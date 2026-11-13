import 'package:flutter/material.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/utils/race_result_sorter.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_model.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/hero_race_card.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/modern_race_card.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';
import '../../shared/widgets/club_selection_sheet.dart';
import 'live_race_results_screen.dart';

/// TYF Yüzme Sonuçları — Canlı Müsabaka Detayı: Yarışlar Ekranı (v2.0)
/// Apple Esintili 2 Sekmeli Tasarım & Global Takım Takip Desteği
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
  String? _errorMessage;
  String _selectedFilter = 'Tümü';
  List<RaceModel> _races = [];
  LiveFeedResponse? _lastFeedResponse;
  List<String> _availableClubs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    SelectedClubService.instance.addListener(_onClubChanged);
    _loadFeedData();
  }

  @override
  void dispose() {
    SelectedClubService.instance.removeListener(_onClubChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onClubChanged() {
    if (mounted && _lastFeedResponse != null) {
      _rebuildRacesFromFeed(_lastFeedResponse!);
    }
  }

  Future<void> _loadFeedData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final feed = await widget.repository.getLiveFeedResponse(widget.live.id);
      _lastFeedResponse = feed;

      // Müsabakadaki tüm katılımcı kulüpleri ayıkla
      _availableClubs = feed.results
          .map((r) => r.clubName.trim())
          .where((c) => c.isNotEmpty && !c.toLowerCase().startsWith('ferdi'))
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b));

      _rebuildRacesFromFeed(feed);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Canlı yarış akışı yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _rebuildRacesFromFeed(LiveFeedResponse feed) {
    final rawEvents = feed.events;
    final results = feed.results;

    final converted = rawEvents.map((e) {
      final dist = e.distance != null && e.distance! > 0
          ? '${e.distance}'
          : (RegExp(r'\d+').firstMatch(e.name)?.group(0) ?? '50');

      final stroke = e.strokeLabel.isNotEmpty
          ? e.strokeLabel
          : (e.stroke.isNotEmpty ? e.stroke : 'Serbest');

      final gender = e.gender != null && e.gender!.isNotEmpty
          ? StringUtils.toTitleCase(e.gender!)
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

      bool isMatchEvent(String resEventNo, String progEventNo) {
        final rTrim = resEventNo.trim();
        final eTrim = progEventNo.trim();
        if (rTrim == eTrim) return true;
        final rInt = int.tryParse(rTrim);
        final eInt = int.tryParse(eTrim);
        if (rInt != null && eInt != null && rInt == eInt) return true;
        return false;
      }

      // Kazanan özeti (Tamamlanmışsa)
      String? winner;
      if (isFinished) {
        final matched = results.where((r) => isMatchEvent(r.eventNo, e.eventNo)).toList();
        if (matched.isNotEmpty) {
          RaceResultSorter.sort(matched);
          final top = matched.first;
          final topTime = top.time ??
              (top.timeCs != null ? (top.timeCs! / 100).toStringAsFixed(2) : '');
          if (topTime.isNotEmpty && !RaceResultSorter.isDisqualified(top)) {
            winner = '🥇 1. ${StringUtils.toTitleCase(top.athleteName)} • $topTime';
          }
        }
      }

      // Seçili takımdan bu yarışta kaç sporcu var?
      int myTeamCount = 0;
      if (SelectedClubService.instance.hasSelectedClub) {
        myTeamCount = results.where((r) {
          return isMatchEvent(r.eventNo, e.eventNo) &&
              SelectedClubService.instance.matches(r.clubName, r.clubId);
        }).length;
      }

      return RaceModel(
        id: e.eventNo,
        distance: dist,
        strokeName: StringUtils.toTitleCase(stroke),
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
        myTeamAthleteCount: myTeamCount,
        rawEvent: e,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _races = converted;
        _isLoading = false;
      });
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
    } else if (_selectedFilter.startsWith('🛡️ Takımım')) {
      return list.where((r) => r.myTeamAthleteCount > 0).toList();
    }
    return list;
  }

  // 1. Sekme: Sonuçlananlar (Ters sıralı: Sonuçlanan en üstte)
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

  int get _myTeamTotalInMeet {
    if (!SelectedClubService.instance.hasSelectedClub || _lastFeedResponse == null) return 0;
    final athleteIds = _lastFeedResponse!.results
        .where((r) => SelectedClubService.instance.matches(r.clubName, r.clubId))
        .map((r) => r.athleteId)
        .toSet();
    return athleteIds.length;
  }

  int get _myTeamRaceCount {
    return _races.where((r) => r.myTeamAthleteCount > 0).length;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final completed = _completedRaces;
    final pending = _pendingRaces;
    final heroRace = _firstPendingRace;
    final hasClub = SelectedClubService.instance.hasSelectedClub;

    // Filtre Çipleri
    final List<FilterChipItem> filterChips = [
      const FilterChipItem(label: 'Tümü'),
      const FilterChipItem(label: 'Kadınlar'),
      const FilterChipItem(label: 'Erkekler'),
      const FilterChipItem(label: '★ Favoriler'),
      if (hasClub && _myTeamRaceCount > 0)
        FilterChipItem(label: '🛡️ Takımım ($_myTeamRaceCount)'),
    ];

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: palette.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              StringUtils.toTitleCase(widget.live.name),
              style: AppTextStyles.raceTitle.copyWith(color: palette.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.live.city} • ${widget.live.totalAthletes} Sporcu',
              style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: palette.textSecondary, size: 20),
            tooltip: 'Yenile',
            onPressed: _loadFeedData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: palette.primary),
            )
          : _errorMessage != null && _races.isEmpty
              ? Center(
                  child: EmptyStateWidget(
                    title: 'Bağlantı Hatası',
                    message: _errorMessage!,
                    icon: Icons.cloud_off_rounded,
                    actionText: 'Tekrar Dene',
                    onAction: _loadFeedData,
                  ),
                )
              : RefreshIndicator(
              color: palette.primary,
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

                    // 2. Takım Seçim & Takip Barı (Tüm ekranlarda kalıcı)
                    SliverToBoxAdapter(
                      child: _buildClubSelectorBar(context),
                    ),

                    // 3. Canlı Seans İlerleme Çubuğu
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _buildProgressHeader(palette),
                      ),
                    ),

                    // 4. Cinsiyet, Kategori ve Takım Filtre Çipleri
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 12),
                        child: ModernFilterChipBar(
                          chips: filterChips,
                          selectedChip: _selectedFilter,
                          onSelected: (chip) => setState(() => _selectedFilter = chip),
                        ),
                      ),
                    ),

                    // 5. Sabit 2 Sekmeli Segmented TabBar
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverTabHeaderDelegate(
                        child: Container(
                          color: palette.background,
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

  Widget _buildClubSelectorBar(BuildContext context) {
    final palette = context.palette;
    final hasClub = SelectedClubService.instance.hasSelectedClub;
    final clubName = SelectedClubService.instance.clubName;
    final totalInMeet = _myTeamTotalInMeet;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: hasClub ? palette.primaryContainer : palette.surface,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: hasClub
                ? palette.primary.withValues(alpha: 0.35)
                : palette.border,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: palette.textPrimary.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await ClubSelectionSheet.show(
                context,
                availableClubs: _availableClubs,
              );
            },
            borderRadius: AppRadius.cardRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: hasClub ? palette.primary : palette.surfaceSecondary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      size: 17,
                      color: hasClub ? Colors.white : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasClub ? StringUtils.toTitleCase(clubName!) : 'Takımını Seç',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: hasClub ? palette.primary : palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          hasClub
                              ? (totalInMeet > 0
                                  ? 'Bu müsabakada $totalInMeet kulüp sporcunuz yarışıyor'
                                  : 'Bu müsabakada kayıtlı sporcunuz yok')
                              : 'Yarışlardaki kulüp sporcularınızı otomatik takip edin',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                            color: hasClub
                                ? palette.primary.withValues(alpha: 0.85)
                                : palette.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: hasClub ? palette.surface : palette.surfaceSecondary,
                      borderRadius: AppRadius.chipRadius,
                      border: Border.all(
                        color: hasClub
                            ? palette.primary.withValues(alpha: 0.3)
                            : palette.border,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasClub ? 'Değiştir' : 'Seç',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: hasClub ? palette.primary : palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: hasClub ? palette.primary : palette.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader(AppColorPalette palette) {
    final resTotal = widget.live.resultListProgress.total;
    final resProcessed = widget.live.resultListProgress.processed;
    final resRatio = resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.inputRadius,
        border: Border.all(color: palette.border, width: 1.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'CANLI SEANS',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '$resProcessed / $resTotal Tamamlandı (%$resPercent)',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
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
              backgroundColor: palette.divider,
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
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
    final palette = context.palette;

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
                color: palette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
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
