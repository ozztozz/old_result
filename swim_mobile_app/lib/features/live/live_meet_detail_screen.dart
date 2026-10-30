import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../core/theme/swim_theme.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/swim_design_components.dart';
import '../meets/meet_detail_screen.dart';
import 'live_race_results_screen.dart';

/// Canlı Müsabaka Detayı: Yarışlar Listesi Ekranı
/// Müsabakaya ait yarışları (50m Serbest - Erkekler vb.) resmi yarış sırasına göre listeler.
/// Sayfa açıldığında otomatik olarak ilk "Bekliyor" durumundaki yarışa odaklanır.
class LiveMeetDetailScreen extends StatefulWidget {
  final LiveMeetSummary live;
  final SwimRepository repository;

  const LiveMeetDetailScreen({
    super.key,
    required this.live,
    required this.repository,
  });

  @override
  State<LiveMeetDetailScreen> createState() => _LiveMeetDetailScreenState();
}

class _LiveMeetDetailScreenState extends State<LiveMeetDetailScreen> {
  bool _isLoading = true;
  List<LiveEventProgramItem> _allEvents = [];
  List<LiveEventProgramItem> _filteredEvents = [];

  String _searchQuery = '';
  String _selectedGenderFilter = 'all'; // 'all', 'erkek', 'kadin'
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      // 1. Canlı akış verisini çek
      final feed = await widget.repository.getLiveFeedResponse(widget.live.id);
      List<LiveEventProgramItem> events = feed.events;

      // 2. Canlı akış listesi boşsa ancak meetId varsa müsabaka detayından çek
      if (events.isEmpty && widget.live.meetId != null) {
        try {
          final meetDetail = await widget.repository.getMeetDetail(widget.live.meetId!);
          events = meetDetail.events.map((p) {
            return LiveEventProgramItem(
              eventNo: p.eventNo,
              name: '${p.distance ?? ''}m ${p.strokeLabel}'.trim(),
              distance: p.distance,
              stroke: p.stroke,
              strokeLabel: p.strokeLabel,
              gender: p.gender,
              isPending: p.isPending,
              status: p.status,
            );
          }).toList();
        } catch (_) {}
      } else if (events.isNotEmpty && widget.live.meetId != null) {
        // Cinsiyet bilgisi eksik olan yarış varsa meetDetail ile zenginleştir
        try {
          final meetDetail = await widget.repository.getMeetDetail(widget.live.meetId!);
          final genderMap = {for (var me in meetDetail.events) me.eventNo: me.gender};
          events = events.map((e) {
            final g = (e.gender == null || e.gender!.isEmpty)
                ? (genderMap[e.eventNo] ?? e.gender)
                : e.gender;
            return LiveEventProgramItem(
              eventNo: e.eventNo,
              name: e.name,
              distance: e.distance,
              stroke: e.stroke,
              strokeLabel: e.strokeLabel,
              gender: g,
              ageGroup: e.ageGroup,
              isPending: e.isPending,
              status: e.status,
              totalAthletes: e.totalAthletes,
            );
          }).toList();
        } catch (_) {}
      }

      // 3. Resmi yarış programı sırasına göre sırala (yaris_no)
      events.sort((a, b) {
        final int numA = int.tryParse(a.eventNo) ?? 9999;
        final int numB = int.tryParse(b.eventNo) ?? 9999;
        return numA.compareTo(numB);
      });

      if (mounted) {
        setState(() {
          _allEvents = events;
          _applyFilter(shouldScrollToPending: true);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter({bool shouldScrollToPending = false}) {
    List<LiveEventProgramItem> list = List.from(_allEvents);

    // Cinsiyet Filtresi
    if (_selectedGenderFilter == 'erkek') {
      list = list.where((e) {
        final g = (e.gender ?? '').toLowerCase();
        return g.contains('erkek');
      }).toList();
    } else if (_selectedGenderFilter == 'kadin') {
      list = list.where((e) {
        final g = (e.gender ?? '').toLowerCase();
        return g.contains('kad') || g.contains('bayan');
      }).toList();
    }

    // Arama Filtresi (Yarış adı, stili, cinsiyet)
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) {
        return e.displayTitle.toLowerCase().contains(q) ||
            e.strokeLabel.toLowerCase().contains(q) ||
            e.genderLabel.toLowerCase().contains(q) ||
            (e.ageGroup ?? '').toLowerCase().contains(q);
      }).toList();
    }

    // Resmi yarış sırasını koru
    list.sort((a, b) {
      final int numA = int.tryParse(a.eventNo) ?? 9999;
      final int numB = int.tryParse(b.eventNo) ?? 9999;
      return numA.compareTo(numB);
    });

    setState(() {
      _filteredEvents = list;
    });

    if (shouldScrollToPending) {
      _scrollToFirstPending();
    }
  }

  void _scrollToFirstPending() {
    final firstPendingIndex = _filteredEvents.indexWhere((e) => e.isPending);
    if (firstPendingIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final viewportHeight = _scrollController.position.viewportDimension;
          const double headerAreaHeight = 310.0;
          const double cardHeight = 88.0;

          final double itemCenter = headerAreaHeight + (firstPendingIndex * cardHeight) + (cardHeight / 2.0);
          final double targetOffset = (itemCenter - (viewportHeight / 2.0))
              .clamp(0.0, _scrollController.position.maxScrollExtent);

          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeInOutCubic,
          );
        }
      });
    }
  }

  void _openRaceResults(LiveEventProgramItem event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRaceResultsScreen(
          live: widget.live,
          event: event,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.live.status == 'ISLENIYOR';
    final firstPendingEventNo = _filteredEvents.firstWhere(
      (e) => e.isPending,
      orElse: () => LiveEventProgramItem(eventNo: '', name: '', stroke: '', strokeLabel: ''),
    ).eventNo;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadEvents,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // 1. Üst Bar (RoundIconButton ile Geri ve Yenileme Butonları)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundIconButton(
                    Icons.arrow_back,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  RoundIconButton(
                    Icons.refresh,
                    onTap: _loadEvents,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Müsabaka Genel Durum Kartı (24dp radius, yumuşak gölge)
              _buildMeetHeaderCard(isRunning),
              const SizedBox(height: 16),

              // 3. Yarış Arama Çubuğu
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Yarış ara (örn: 50m Serbest, Sırtüstü)...',
                    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AppColors.muted),
                            onPressed: () {
                              _searchController.clear();
                              _searchQuery = '';
                              _applyFilter();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (val) {
                    _searchQuery = val;
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 4. Cinsiyet Filtre Butonları (Pastel hap butonlar)
              Row(
                children: [
                  _buildGenderChip('all', 'Tüm Yarışlar'),
                  const SizedBox(width: 8),
                  _buildGenderChip('erkek', 'Erkekler'),
                  const SizedBox(width: 8),
                  _buildGenderChip('kadin', 'Kadınlar'),
                  const Spacer(),
                  Text(
                    '${_filteredEvents.length} yarış',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 5. Yarış Programı Başlığı & "Sıradaki Yarışa Git" Hapı
              Row(
                children: [
                  const Text(
                    'Yarış Programı',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (firstPendingEventNo.isNotEmpty)
                    GestureDetector(
                      onTap: _scrollToFirstPending,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.lime,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_downward_rounded, size: 13, color: AppColors.ink),
                            SizedBox(width: 4),
                            Text(
                              'Sıradaki Yarış',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // 6. Yarışlar Listesi
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_filteredEvents.isEmpty)
                _buildEmptyState()
              else
                ..._filteredEvents.map((ev) {
                  final isFirstPending = ev.isPending && ev.eventNo == firstPendingEventNo;
                  return _buildRaceCard(ev, isFirstPending: isFirstPending);
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeetHeaderCard(bool isRunning) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isRunning ? AppColors.mint : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: isRunning ? AppColors.ink : AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? 'CANLI TAKİP' : widget.live.status,
                      style: TextStyle(
                        color: isRunning ? AppColors.ink : AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (widget.live.city.isNotEmpty)
                Text(
                  widget.live.city,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.live.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          if (widget.live.date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.live.date,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),

          // Start & Sonuç Listesi İlerleme Çubukları
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Listesi: ${widget.live.startListProgress.processed} / ${widget.live.startListProgress.total}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: widget.live.startListProgress.total > 0
                            ? widget.live.startListProgress.processed / widget.live.startListProgress.total
                            : 0,
                        backgroundColor: AppColors.bg,
                        color: AppColors.teal,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sonuç Listesi: ${widget.live.resultListProgress.processed} / ${widget.live.resultListProgress.total}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: widget.live.resultListProgress.total > 0
                            ? widget.live.resultListProgress.processed / widget.live.resultListProgress.total
                            : 0,
                        backgroundColor: AppColors.bg,
                        color: AppColors.mint,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.live.meetId != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.ink),
                label: const Text(
                  'Tüm Resmi Sonuçları Görüntüle',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetDetailScreen(
                        meetId: widget.live.meetId!,
                        meetTitle: widget.live.name,
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRaceCard(LiveEventProgramItem ev, {bool isFirstPending = false}) {
    final genderText = ev.genderLabel;
    final fullTitle = genderText.isNotEmpty
        ? '${ev.displayTitle} - $genderText'
        : ev.displayTitle;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: isFirstPending
            ? Border.all(color: AppColors.ink, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRaceResults(ev),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 1. Branş Dairesel İkonu
                _buildStrokeIcon(ev.stroke),
                const SizedBox(width: 14),

                // 2. Yarış Başlığı (Numarasız) ve Rozetler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (genderText.isNotEmpty)
                            _buildPill(
                              genderText,
                              genderText.toLowerCase().contains('kad')
                                  ? AppColors.lavender
                                  : AppColors.teal,
                            ),
                          if (ev.ageGroup != null && ev.ageGroup!.isNotEmpty)
                            _buildPill(ev.ageGroup!, Colors.white),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 3. Durum Rozeti (Sonuçlandı vs Bekliyor)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ev.isPending
                        ? (isFirstPending ? AppColors.lime : Colors.white)
                        : AppColors.mint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    ev.isPending
                        ? (isFirstPending ? '⚡ Sıradaki' : '⏱ Bekliyor')
                        : '✓ Sonuçlandı',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ev.isPending && !isFirstPending
                          ? AppColors.muted
                          : AppColors.ink,
                    ),
                  ),
                ),

                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrokeIcon(String stroke) {
    IconData iconData = Icons.pool_rounded;
    Color iconBg = AppColors.mint;

    switch (stroke.toUpperCase()) {
      case 'FREE':
        iconData = Icons.waves_rounded;
        iconBg = AppColors.teal;
        break;
      case 'BACK':
        iconData = Icons.water_rounded;
        iconBg = AppColors.lavender;
        break;
      case 'BREAST':
        iconData = Icons.arrow_downward_rounded;
        iconBg = AppColors.mint;
        break;
      case 'FLY':
        iconData = Icons.air_rounded;
        iconBg = AppColors.lime;
        break;
      case 'MEDLEY':
        iconData = Icons.auto_awesome_rounded;
        iconBg = AppColors.lavender;
        break;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconBg,
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: AppColors.ink, size: 20),
    );
  }

  Widget _buildPill(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _buildGenderChip(String val, String label) {
    final isSelected = _selectedGenderFilter == val;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedGenderFilter = val);
        _applyFilter();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.lime : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pool_rounded, size: 28, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aramanıza uygun bir yarış bulunamadı.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Farklı bir arama terimi deneyebilir veya filtreyi temizleyebilirsiniz.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
