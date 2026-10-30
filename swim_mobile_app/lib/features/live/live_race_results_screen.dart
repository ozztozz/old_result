import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../core/theme/swim_theme.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/swim_design_components.dart';
import '../../shared/widgets/swim_result_card.dart';
import '../athletes/athlete_profile_screen.dart';

/// Tek Bir Canlı Yarışın Sonuçları Ekranı (Dereceler, Seriler, Kulvarlar)
/// Başlıkta veya ekranda yarış numarası KESİNLİKLE yer almaz.
class LiveRaceResultsScreen extends StatefulWidget {
  final LiveMeetSummary live;
  final LiveEventProgramItem event;
  final SwimRepository repository;

  const LiveRaceResultsScreen({
    super.key,
    required this.live,
    required this.event,
    required this.repository,
  });

  @override
  State<LiveRaceResultsScreen> createState() => _LiveRaceResultsScreenState();
}

class _LiveRaceResultsScreenState extends State<LiveRaceResultsScreen> {
  bool _isLoading = true;
  bool _isAutoRefresh = false;
  Timer? _refreshTimer;

  List<RaceResult> _allResults = [];
  List<RaceResult> _filteredResults = [];

  String _selectedStatus = 'all'; // 'all', 'finished', 'pending'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAutoRefresh(bool enable) {
    setState(() => _isAutoRefresh = enable);
    _refreshTimer?.cancel();
    if (enable) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _loadResults(silent: true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Otomatik yenileme devrede (15 sn)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadResults({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final feed = await widget.repository.getLiveFeedResponse(
        widget.live.id,
        eventNo: widget.event.eventNo,
        status: _selectedStatus,
      );

      List<RaceResult> results = feed.data;

      // Canlı akış henüz bu yarış için boşsa ancak meetId varsa müsabaka sonuçlarından çek
      if (results.isEmpty && widget.live.meetId != null) {
        try {
          results = await widget.repository.getMeetResults(
            widget.live.meetId!,
            eventNo: widget.event.eventNo,
            status: _selectedStatus != 'all' ? _selectedStatus : null,
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _allResults = results;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    List<RaceResult> list;
    if (_searchQuery.trim().isEmpty) {
      list = List.from(_allResults);
    } else {
      final q = _searchQuery.toLowerCase();
      list = _allResults.where((r) {
        return r.athleteName.toLowerCase().contains(q) ||
            r.clubName.toLowerCase().contains(q);
      }).toList();
    }

    // Sıralama Kuralı:
    // 1. Sonuçlar varsa dereceye göre sırala (en hızlı derece en üstte)
    // 2. Diskalifiyeler (DQ, DNS, DNF) DAİMA EN SONDA
    // 3. Sonuç yoksa (veya derecesizler) seri ve kulvara göre sırala
    final bool hasFinishedResults = list.any((r) => r.timeCs != null && r.timeCs! > 0);

    list.sort((a, b) {
      final bool isDqA = a.resultStatus == 'DQ' ||
          a.resultStatus == 'DNS' ||
          a.resultStatus == 'DNF' ||
          a.rank.toUpperCase().startsWith('DQ') ||
          a.rank.toUpperCase().startsWith('DSQ');
      final bool isDqB = b.resultStatus == 'DQ' ||
          b.resultStatus == 'DNS' ||
          b.resultStatus == 'DNF' ||
          b.rank.toUpperCase().startsWith('DQ') ||
          b.rank.toUpperCase().startsWith('DSQ');

      // 1. Diskalifiyeler EN SONDA
      if (isDqA && !isDqB) return 1;
      if (!isDqA && isDqB) return -1;
      if (isDqA && isDqB) {
        final heatA = int.tryParse(a.heat) ?? 999;
        final heatB = int.tryParse(b.heat) ?? 999;
        if (heatA != heatB) return heatA.compareTo(heatB);
        return (a.lane ?? 999).compareTo(b.lane ?? 999);
      }

      // 2. Sonuçlar varsa: Dereceye göre sırala (küçükten büyüğe)
      if (hasFinishedResults) {
        final bool hasTimeA = a.timeCs != null && a.timeCs! > 0;
        final bool hasTimeB = b.timeCs != null && b.timeCs! > 0;

        if (hasTimeA && !hasTimeB) return -1;
        if (!hasTimeA && hasTimeB) return 1;

        if (hasTimeA && hasTimeB) {
          final cmp = a.timeCs!.compareTo(b.timeCs!);
          if (cmp != 0) return cmp;
          final rankA = int.tryParse(a.rank) ?? 999;
          final rankB = int.tryParse(b.rank) ?? 999;
          if (rankA != rankB) return rankA.compareTo(rankB);
        }
      }

      // 3. Sonuç yoksa: Seri ve kulvara göre sırala
      final heatA = int.tryParse(a.heat) ?? 999;
      final heatB = int.tryParse(b.heat) ?? 999;
      if (heatA != heatB) return heatA.compareTo(heatB);
      return (a.lane ?? 999).compareTo(b.lane ?? 999);
    });

    _filteredResults = list;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.live.status == 'ISLENIYOR';
    final title = widget.event.genderLabel.isNotEmpty
        ? '${widget.event.displayTitle} - ${widget.event.genderLabel}'
        : widget.event.displayTitle;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadResults(silent: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // 1. Üst Bar (RoundIconButton ile Geri, Otomatik Yenileme ve Manuel Yenileme)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundIconButton(
                    Icons.arrow_back,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  Row(
                    children: [
                      RoundIconButton(
                        _isAutoRefresh ? Icons.sync : Icons.sync_disabled,
                        color: _isAutoRefresh ? AppColors.lime : Colors.white,
                        iconColor: AppColors.ink,
                        onTap: () => _toggleAutoRefresh(!_isAutoRefresh),
                      ),
                      const SizedBox(width: 8),
                      RoundIconButton(
                        Icons.refresh,
                        onTap: () => _loadResults(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Yarış Bilgi Başlığı Kartı (24dp radius, dairesel branş ikonu, pastel haplar)
              Container(
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
                        _buildStrokeIcon(widget.event.stroke),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.ink,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.live.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isRunning)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 3.5, backgroundColor: AppColors.ink),
                                SizedBox(width: 5),
                                Text(
                                  'CANLI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.event.gender != null && widget.event.gender!.isNotEmpty)
                          _buildPill(
                            widget.event.gender!,
                            AppColors.lavender,
                          ),
                        if (widget.event.ageGroup != null && widget.event.ageGroup!.isNotEmpty)
                          _buildPill(
                            widget.event.ageGroup!,
                            AppColors.teal,
                          ),
                        _buildPill(
                          '${_allResults.length} Sporcu',
                          AppColors.mint,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Arama Çubuğu
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
                    hintText: 'Sporcu veya kulüp ara...',
                    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AppColors.muted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _applyFilter();
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applyFilter();
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 4. Durum Filtre Hapları (Pastel pill buttons)
              Row(
                children: [
                  _buildStatusChip('all', 'Tümü'),
                  const SizedBox(width: 8),
                  _buildStatusChip('finished', 'Sonuçlananlar'),
                  const SizedBox(width: 8),
                  _buildStatusChip('pending', 'Beklenenler'),
                ],
              ),
              const SizedBox(height: 16),

              // 5. Sonuç Listesi Başlığı
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Yarış Sıralaması (${_filteredResults.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),

              // 6. Sonuç Kartları
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_filteredResults.isEmpty)
                _buildEmptyState()
              else
                ..._filteredResults.map((result) {
                  return SwimResultCard(
                    result: result,
                    onTap: () {
                      if (result.athleteId > 0) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AthleteProfileScreen(
                              athleteId: result.athleteId,
                              athleteName: result.athleteName,
                              repository: widget.repository,
                            ),
                          ),
                        );
                      }
                    },
                  );
                }),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _buildStatusChip(String val, String label) {
    final isSelected = _selectedStatus == val;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedStatus = val);
        _loadResults();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
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
              child: const Icon(Icons.sports_score_rounded, size: 28, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            const Text(
              'Bu yarış için henüz netice bulunmuyor.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Yarış yüzüldükçe sonuçlar buraya anlık olarak gelecektir.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
