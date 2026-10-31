import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_model.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/hero_race_card.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/modern_race_card.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';
import 'live_race_results_screen.dart';

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

/// TYF Yüzme Sonuçları — Canlı Müsabaka Detayı: Yarışlar Ekranı (v2.0)
/// Apple Esintili 2 Sekmeli Tasarım:
/// 1. Sekme: Sonuçlananlar (Ters sıralı: Son sonuçlanan en üstte)
/// 2. Sekme: Bekleyenler (Resmi yarış sırasına göre)
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

class _LiveMeetDetailScreenState extends State<LiveMeetDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  String _selectedFilter = 'Tümü';
  List<RaceModel> _races = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFeedData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedData() async {
    setState(() => _isLoading = true);
    try {
      final feed = await widget.repository.getLiveFeedResponse(widget.live.id);
      final rawEvents = feed.events;
      final results = feed.results;

      // Program etkinliklerini RaceModel'e dönüştür
      final converted = rawEvents.map((e) {
        final dist = e.distance != null && e.distance! > 0
            ? '${e.distance}'
            : (RegExp(r'\d+').firstMatch(e.name)?.group(0) ?? '50');

        final stroke = e.strokeLabel.isNotEmpty
            ? e.strokeLabel
            : (e.stroke.isNotEmpty ? e.stroke : 'Serbest');

        final gender = e.gender != null && e.gender!.isNotEmpty
            ? _toTitleCase(e.gender!)
            : (e.name.toLowerCase().contains('bayan') ||
                    e.name.toLowerCase().contains('kadin') ||
                    e.name.toLowerCase().contains('kız')
                ? 'Kadınlar'
                : 'Erkekler');

        final ageGroup = e.ageGroup != null && e.ageGroup!.isNotEmpty
            ? e.ageGroup!
            : '';

        final isFinished = !e.isPending ||
            e.status.toLowerCase().contains('tamam') ||
            e.status.toLowerCase().contains('sonuc');

        // Kazanan özeti (Tamamlanmışsa)
        String? winner;
        if (isFinished) {
          final matched = results.where((r) => r.eventNo == e.eventNo).toList();
          if (matched.isNotEmpty) {
            matched.sort((a, b) => (a.timeCs ?? 999999).compareTo(b.timeCs ?? 999999));
            final top = matched.first;
            final topTime = top.time ?? (top.timeCs != null ? '${(top.timeCs! / 100).toStringAsFixed(2)}' : '');
            if (topTime.isNotEmpty) {
              winner = '🥇 1. ${_toTitleCase(top.athleteName)} • $topTime';
            }
          }
        }

        return RaceModel(
          id: e.eventNo,
          distance: dist,
          strokeName: _toTitleCase(stroke),
          gender: gender,
          ageCategory: ageGroup,
          status: isFinished
              ? RaceStatus.completed
              : (e.status.toLowerCase().contains('canli') ||
                      e.status.toLowerCase().contains('isleniyor')
                  ? RaceStatus.live
                  : RaceStatus.upcoming),
          startTime: e.status,
          heatLaneInfo: isFinished ? null : 'Havuzda • Sonuç Bekleniyor',
          winnerSummary: winner,
          rawEvent: e,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _races = converted;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openRaceResults(RaceModel race) {
    final eventItem = race.rawEvent is LiveEventProgramItem
        ? race.rawEvent as LiveEventProgramItem
        : LiveEventProgramItem(
            eventNo: race.id,
            name: '${race.distance} ${race.strokeName}',
            stroke: race.strokeName,
            strokeLabel: race.strokeName,
            distance: int.tryParse(race.distance),
            gender: race.gender,
            ageGroup: race.ageCategory,
          );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRaceResultsScreen(
          live: widget.live,
          event: eventItem,
          repository: widget.repository,
        ),
      ),
    );
  }

  List<RaceModel> _applyGenderFilter(List<RaceModel> list) {
    if (_selectedFilter == 'Kadınlar') {
      return list.where((r) => r.gender.toLowerCase().contains('kadın')).toList();
    } else if (_selectedFilter == 'Erkekler') {
      return list.where((r) => r.gender.toLowerCase().contains('erkek')).toList();
    } else if (_selectedFilter == '★ Favoriler') {
      return list.where((r) => r.isFavorite).toList();
    }
    return list;
  }

  // 1. Sekme: Sonuçlananlar (Ters sıralı: Son sonuçlanan en üstte)
  List<RaceModel> get _completedRaces {
    final list = _races.where((r) => r.status == RaceStatus.completed).toList();
    return _applyGenderFilter(list.reversed.toList());
  }

  // 2. Sekme: Bekleyenler (Sıradaki ve Gelecek Yarışlar)
  List<RaceModel> get _pendingRaces {
    final list = _races.where((r) => r.status != RaceStatus.completed).toList();
    return _applyGenderFilter(list);
  }

  RaceModel? get _firstPendingRace {
    final pending = _races.where((r) => r.status != RaceStatus.completed).toList();
    return pending.isNotEmpty ? pending.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completedRaces;
    final pending = _pendingRaces;
    final heroRace = _firstPendingRace;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _toTitleCase(widget.live.name),
              style: AppTextStyles.raceTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.live.city} • ${widget.live.totalAthletes} Sporcu',
              style: AppTextStyles.categorySeries,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
            tooltip: 'Yenile',
            onPressed: _loadFeedData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _loadFeedData,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    // 1. Vitrin Canlı Yarış Kartı
                    if (heroRace != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: HeroRaceCard(
                            race: heroRace,
                            onTap: () => _openRaceResults(heroRace),
                          ),
                        ),
                      ),

                    // 2. İlerleme Çubuğu
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _buildProgressHeader(),
                      ),
                    ),

                    // 3. Cinsiyet ve Kategori Filtre Çipleri
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 12),
                        child: ModernFilterChipBar(
                          chips: const [
                            FilterChipItem(label: 'Tümü'),
                            FilterChipItem(label: 'Kadınlar'),
                            FilterChipItem(label: 'Erkekler'),
                            FilterChipItem(label: '★ Favoriler'),
                          ],
                          selectedChip: _selectedFilter,
                          onSelected: (chip) => setState(() => _selectedFilter = chip),
                        ),
                      ),
                    ),

                    // 4. Sabit 2 Sekmeli Segmented TabBar
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabHeaderDelegate(
                        child: Container(
                          color: AppColors.background,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ModernSegmentedTabBar(
                            controller: _tabController,
                            tabs: [
                              TabItemData(
                                title: 'Sonuçlananlar (${completed.length})',
                                icon: Icons.check_circle_outline_rounded,
                              ),
                              TabItemData(
                                title: 'Bekleyenler (${pending.length})',
                                icon: Icons.schedule_rounded,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    // Sekme 1: Sonuçlananlar (Ters sıralı: Sonuçlanan ilk sırada)
                    _buildRaceListView(
                      races: completed,
                      isCompletedTab: true,
                      emptyMessage: 'Henüz sonuçlanmış bir yarış bulunmuyor.',
                    ),

                    // Sekme 2: Bekleyenler
                    _buildRaceListView(
                      races: pending,
                      isCompletedTab: false,
                      emptyMessage: 'Bekleyen yarış bulunmuyor, tüm program tamamlandı.',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProgressHeader() {
    final resTotal = widget.live.resultListProgress.total;
    final resProcessed = widget.live.resultListProgress.processed;
    final resRatio = resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'CANLI SEANS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '$resProcessed / $resTotal Tamamlandı (%$resPercent)',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: resRatio,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRaceListView({
    required List<RaceModel> races,
    required bool isCompletedTab,
    required String emptyMessage,
  }) {
    if (races.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCompletedTab ? Icons.emoji_events_outlined : Icons.schedule_outlined,
                size: 40,
                color: AppColors.laneNeutral,
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: races.length,
      itemBuilder: (context, index) {
        final race = races[index];
        return ModernRaceCard(
          race: race,
          onTap: () => _openRaceResults(race),
          onFavoriteToggle: () {
            setState(() {
              race.isFavorite = !race.isFavorite;
            });
          },
        );
      },
    );
  }
}

class _SliverTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _SliverTabHeaderDelegate({required this.child});

  @override
  double get minExtent => 52.0;

  @override
  double get maxExtent => 52.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SliverTabHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
