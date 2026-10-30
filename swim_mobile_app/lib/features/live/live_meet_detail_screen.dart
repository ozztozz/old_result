import 'package:flutter/material.dart';
import '../../core/theme/swim_theme.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
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

      // 2. Müsabaka detayını (program ve cinsiyetler) ve sonuçları çek
      MeetDetail? meetDetail;
      List<RaceResult> allResults = List.from(feed.data);

      if (widget.live.meetId != null) {
        try {
          final res = await Future.wait([
            widget.repository.getMeetDetail(widget.live.meetId!),
            if (allResults.isEmpty)
              widget.repository.getMeetResults(widget.live.meetId!, page: 1),
          ]);
          meetDetail = res[0] as MeetDetail;
          if (res.length > 1) {
            allResults = res[1] as List<RaceResult>;
          }
        } catch (_) {}
      }

      // 3. Hangi yarışların sonuçlandığını (derecesi olduğunu) belirle
      // 3. Hangi yarışların sonuçlandığını belirle:
      // Kullanıcı kuralı: "Bekliyor" statüsü SONUCU OLMAYAN yarış demektir.
      // Yarışa girmemiş tekil sporcular 'Bekleniyor' görünse dahi,
      // yarışta en az 1 sporcunun derecesi varsa o yarış "Sonuçlandı" kabul edilir!
      final Set<String> finishedEventNos = {};
      for (final r in allResults) {
        final eno = r.eventNo.trim();
        final hasTime = r.time != null &&
            r.time!.isNotEmpty &&
            r.time != 'Bekleniyor' &&
            r.time != '-';
        final hasTimeCs = (r.timeCs != null && r.timeCs! > 0);
        final isOk = (r.resultStatus == 'OK' && hasTime);

        if (hasTime || hasTimeCs || isOk) {
          finishedEventNos.add(eno);
        }
      }

      // Canlı yarış sonuç ilerleme sayacı (eğer backend'den geliyorsa)
      final processedCount = widget.live.resultListProgress.processed;

      // 4. Müsabaka programındaki tüm yarışları (hem sonuçlananları hem bekleyenleri) eksiksiz birleştir
      List<LiveEventProgramItem> events = [];

      if (meetDetail != null && meetDetail.events.isNotEmpty) {
        // Resmi müsabaka programı tüm yarışları ve cinsiyetleri kesin olarak içerir
        events = meetDetail.events.map((p) {
          final int? eventIdx = int.tryParse(p.eventNo);
          final bool isFin = finishedEventNos.contains(p.eventNo) ||
              p.status == 'Sonuçlandı' ||
              !p.isPending ||
              (processedCount > 0 && eventIdx != null && eventIdx <= processedCount);

          return LiveEventProgramItem(
            eventNo: p.eventNo,
            name: '${p.distance ?? ''}m ${p.strokeLabel}'.trim(),
            distance: p.distance,
            stroke: p.stroke,
            strokeLabel: p.strokeLabel,
            gender: p.gender,
            isPending: !isFin,
            status: isFin ? 'Sonuçlandı' : 'Bekliyor',
          );
        }).toList();
      } else {
        // Canlı akış listesinden al ve sonuç durumunu hesapla
        events = feed.events.map((e) {
          final int? eventIdx = int.tryParse(e.eventNo);
          final bool isFin = finishedEventNos.contains(e.eventNo) ||
              e.status == 'Sonuçlandı' ||
              !e.isPending ||
              (processedCount > 0 && eventIdx != null && eventIdx <= processedCount);

          return LiveEventProgramItem(
            eventNo: e.eventNo,
            name: e.name,
            distance: e.distance,
            stroke: e.stroke,
            strokeLabel: e.strokeLabel,
            gender: e.gender,
            ageGroup: e.ageGroup,
            isPending: !isFin,
            status: isFin ? 'Sonuçlandı' : 'Bekliyor',
            totalAthletes: e.totalAthletes,
          );
        }).toList();
      }

      // 5. Resmi yarış programı sırasına göre sırala
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

    // 1. Kural: Filtrelenmiş liste de resmi yarış sırasını korur
    list.sort((a, b) {
      final int numA = int.tryParse(a.eventNo) ?? 9999;
      final int numB = int.tryParse(b.eventNo) ?? 9999;
      return numA.compareTo(numB);
    });

    setState(() {
      _filteredEvents = list;
    });

    // 3. Kural: Liste ilk bekliyor olanda odaklanmalı
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
          // Üst bilgi kartı + arama + filtre alanının yüksekliği
          const double headerAreaHeight = 310.0;
          // Her bir yarış kartının yaklaşık yüksekliği (kart + margin)
          const double cardHeight = 88.0;

          // İlk sonucu olmayan yarışın dikey merkez koordinatı:
          final double itemCenter = headerAreaHeight + (firstPendingIndex * cardHeight) + (cardHeight / 2.0);

          // Bu yarışın merkezini ekranın tam ortasına (viewportHeight / 2) getirecek scroll ofseti:
          // Böylece yukarısında sonuçlanan yarışlar, ortasında bu yarış, altında ise sonraki yarışlar görünür.
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
    final colors = context.swimColors;
    final isRunning = widget.live.status == 'ISLENIYOR';
    final firstPendingEventNo = _filteredEvents.firstWhere(
      (e) => e.isPending,
      orElse: () => LiveEventProgramItem(eventNo: '', name: '', stroke: '', strokeLabel: ''),
    ).eventNo;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.live.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Müsabaka Genel Durum Kartı
            _buildMeetHeaderCard(isRunning),
            const SizedBox(height: 14),

            // 2. Yarış Arama Çubuğu
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Yarış ara (örn: 50m Serbest, Sırtüstü, Kadınlar)...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _searchQuery = '';
                          _applyFilter();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (val) {
                _searchQuery = val;
                _applyFilter();
              },
            ),
            const SizedBox(height: 10),

            // 3. Cinsiyet Filtre Butonları
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 4. Yarışlar Listesi Başlığı
            Row(
              children: [
                const Icon(Icons.pool, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Yarış Programı',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (firstPendingEventNo.isNotEmpty)
                  GestureDetector(
                    onTap: _scrollToFirstPending,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_downward, size: 12, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Text(
                            'Sıradaki Yarışa Git',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 5. Yarışlar Listesi / Yükleniyor / Boş Durum
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
    );
  }

  Widget _buildMeetHeaderCard(bool isRunning) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isRunning ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRunning ? 'CANLI TAKİP' : widget.live.status,
                        style: TextStyle(
                          color: isRunning ? Colors.green.shade900 : Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.live.city.isNotEmpty)
                  Text(
                    widget.live.city,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.live.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (widget.live.date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.live.date,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),

            // Start & Sonuç Listesi İlerleme Çubukları
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start: ${widget.live.startListProgress.processed} / ${widget.live.startListProgress.total}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: widget.live.startListProgress.total > 0
                            ? widget.live.startListProgress.processed / widget.live.startListProgress.total
                            : 0,
                        backgroundColor: Colors.blue.shade100,
                        color: Theme.of(context).colorScheme.primary,
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
                        'Sonuç: ${widget.live.resultListProgress.processed} / ${widget.live.resultListProgress.total}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: widget.live.resultListProgress.total > 0
                            ? widget.live.resultListProgress.processed / widget.live.resultListProgress.total
                            : 0,
                        backgroundColor: Colors.green.shade100,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (widget.live.meetId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.emoji_events_outlined, size: 18),
                  label: const Text('Müsabakanın Tüm Resmi Sonuçları'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
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
      ),
    );
  }

  Widget _buildRaceCard(LiveEventProgramItem ev, {bool isFirstPending = false}) {
    final genderText = ev.genderLabel;
    final isFemale = genderText.toLowerCase().contains('kad') ||
        genderText.toLowerCase().contains('bayan');
    final isMale = genderText.toLowerCase().contains('erkek');

    // Başlıkta branş ve cinsiyet net olarak yer alır
    final fullTitle = genderText.isNotEmpty
        ? '${ev.displayTitle} - $genderText'
        : ev.displayTitle;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isFirstPending ? 1.5 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFirstPending
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          width: isFirstPending ? 1.8 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openRaceResults(ev),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 1. Branş İkonu
              _buildStrokeIcon(ev.stroke),
              const SizedBox(width: 12),

              // 2. Yarış Başlığı (Numarasız!) ve Cinsiyet Rozeti
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fullTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.2,
                              color: isFirstPending
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Cinsiyet Rozeti (2. Kural: Cinsiyet listede belirgin olmalı)
                        if (genderText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isFemale
                                  ? Colors.purple.shade50
                                  : isMale
                                      ? Colors.blue.shade50
                                      : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isFemale
                                    ? Colors.purple.shade200
                                    : isMale
                                        ? Colors.blue.shade200
                                        : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isFemale ? Icons.female : (isMale ? Icons.male : Icons.person),
                                  size: 13,
                                  color: isFemale
                                      ? Colors.purple.shade800
                                      : isMale
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade800,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  genderText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isFemale
                                        ? Colors.purple.shade900
                                        : isMale
                                            ? Colors.blue.shade900
                                            : Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Durum Rozeti (Sonuçlandı vs Bekliyor)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ev.isPending
                                ? (isFirstPending ? Colors.amber.shade100 : Colors.amber.shade50)
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: ev.isPending
                                  ? (isFirstPending ? Colors.amber.shade700 : Colors.amber.shade300)
                                  : Colors.green.shade300,
                            ),
                          ),
                          child: Text(
                            ev.isPending ? (isFirstPending ? '⚡ Sıradaki (Bekliyor)' : '⏱ Bekliyor') : '✓ Sonuçlandı',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: ev.isPending
                                  ? Colors.amber.shade900
                                  : Colors.green.shade900,
                            ),
                          ),
                        ),

                        if (ev.ageGroup != null && ev.ageGroup!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              ev.ageGroup!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Sağ Ok İkonu
              Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStrokeIcon(String stroke) {
    IconData iconData = Icons.pool;
    Color iconColor = Colors.blue;

    switch (stroke.toUpperCase()) {
      case 'FREE':
        iconData = Icons.waves;
        iconColor = Colors.blue;
        break;
      case 'BACK':
        iconData = Icons.water;
        iconColor = Colors.indigo;
        break;
      case 'BREAST':
        iconData = Icons.arrow_downward;
        iconColor = Colors.teal;
        break;
      case 'FLY':
        iconData = Icons.air;
        iconColor = Colors.deepOrange;
        break;
      case 'MEDLEY':
        iconData = Icons.auto_awesome;
        iconColor = Colors.purple;
        break;
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  Widget _buildGenderChip(String val, String label) {
    final isSelected = _selectedGenderFilter == val;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        setState(() => _selectedGenderFilter = val);
        _applyFilter();
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.pool_outlined, size: 50, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Aramanıza uygun bir yarış bulunamadı.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Farklı bir arama terimi deneyebilir veya filtreyi temizleyebilirsiniz.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
