import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
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

const double _liveMeetTabBarHeight = 46;
const double _liveMeetActionButtonOffset = (24 * 1.2 - 40) / 2;

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

      final ageGroup =
          e.ageGroup != null && e.ageGroup!.isNotEmpty ? e.ageGroup! : '';

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
        final matched =
            results.where((r) => isMatchEvent(r.eventNo, e.eventNo)).toList();
        if (matched.isNotEmpty) {
          RaceResultSorter.sort(matched);
          final top = matched.first;
          final topTime = top.time ??
              (top.timeCs != null
                  ? (top.timeCs! / 100).toStringAsFixed(2)
                  : '');
          if (topTime.isNotEmpty && !RaceResultSorter.isDisqualified(top)) {
            winner =
                '🥇 1. ${StringUtils.toTitleCase(top.athleteName)} • $topTime';
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

    LiveRaceResultsScreen.showSheet(
      context,
      live: widget.live,
      event: eventItem,
      repository: widget.repository,
    );
  }

  List<RaceModel> _applyGenderFilter(List<RaceModel> list) {
    if (_selectedFilter == 'Kadınlar') {
      return list
          .where((r) => r.gender.toLowerCase().contains('kadın'))
          .toList();
    } else if (_selectedFilter == 'Erkekler') {
      return list
          .where((r) => r.gender.toLowerCase().contains('erkek'))
          .toList();
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
    final pending =
        _races.where((r) => r.status != RaceStatus.completed).toList();
    return pending.isNotEmpty ? pending.first : null;
  }

  int get _myTeamTotalInMeet {
    if (!SelectedClubService.instance.hasSelectedClub ||
        _lastFeedResponse == null) {
      return 0;
    }
    final athleteIds = _lastFeedResponse!.results
        .where(
            (r) => SelectedClubService.instance.matches(r.clubName, r.clubId))
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

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context, palette),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: palette.primary,
                        ),
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
                              headerSliverBuilder:
                                  (context, innerBoxIsScrolled) {
                                return [
                                  if (heroRace != null)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.s20,
                                          AppSpacing.sm,
                                          AppSpacing.s20,
                                          AppSpacing.md,
                                        ),
                                        child: HeroRaceCard(
                                          race: heroRace,
                                          onTap: () =>
                                              _openRaceResults(heroRace),
                                        ),
                                      ),
                                    ),
                                  SliverToBoxAdapter(
                                    child: _buildClubSelectorBar(context),
                                  ),
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.s20,
                                        0,
                                        AppSpacing.s20,
                                        AppSpacing.s12,
                                      ),
                                      child: _buildProgressHeader(palette),
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.s20,
                                        0,
                                        AppSpacing.s20,
                                        AppSpacing.s12,
                                      ),
                                      child: ModernFilterChipBar(
                                        chips: filterChips,
                                        selectedChip: _selectedFilter,
                                        onSelected: (chip) => setState(
                                          () => _selectedFilter = chip,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _SliverTabHeaderDelegate(
                                      extent: _liveMeetTabBarHeight +
                                          AppSpacing.xs * 2,
                                      child: Container(
                                        color: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.s20,
                                          vertical: AppSpacing.xs,
                                        ),
                                        child: ModernSegmentedTabBar(
                                          controller: _tabController,
                                          tabs: [
                                            TabItemData(
                                              title:
                                                  'Sonuçlananlar (${completed.length})',
                                              icon: Icons
                                                  .check_circle_outline_rounded,
                                            ),
                                            TabItemData(
                                              title:
                                                  'Bekleyenler (${pending.length})',
                                              icon: Icons.schedule_rounded,
                                            ),
                                          ],
                                          height: _liveMeetTabBarHeight,
                                        ),
                                      ),
                                    ),
                                  ),
                                ];
                              },
                              body: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildRaceListView(
                                    races: completed,
                                    isCompletedTab: true,
                                    emptyMessage:
                                        'Henüz sonuçlanmış bir yarış bulunmuyor.',
                                    heroRace: heroRace,
                                  ),
                                  _buildRaceListView(
                                    races: pending,
                                    isCompletedTab: false,
                                    emptyMessage:
                                        'Bekleyen yarış bulunmuyor, tüm program tamamlandı.',
                                    heroRace: heroRace,
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    final athleteCount =
        NumberFormat('#,###', 'tr_TR').format(widget.live.totalAthletes);
    final title = StringUtils.toTitleCase(widget.live.name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 40 + AppSpacing.sm),
              Expanded(
                child: Text(
                  '${widget.live.city} • $athleteCount sporcu',
                  style: AppTextStyles.filterChip.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 40 + AppSpacing.sm),
            ],
          ),
          AppSpacing.vXs,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, _liveMeetActionButtonOffset),
                child: GlassCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  iconColor: palette.textTertiary,
                  tooltip: 'Geri',
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
              AppSpacing.hSm,
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.2,
                    color: palette.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppSpacing.hSm,
              Transform.translate(
                offset: const Offset(0, _liveMeetActionButtonOffset),
                child: GlassCircleButton(
                  icon: Icons.refresh_rounded,
                  iconColor: palette.textTertiary,
                  tooltip: 'Yenile',
                  onTap: _loadFeedData,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClubSelectorBar(BuildContext context) {
    final palette = context.palette;
    final hasClub = SelectedClubService.instance.hasSelectedClub;
    final clubName = SelectedClubService.instance.clubName;
    final totalInMeet = _myTeamTotalInMeet;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        0,
        AppSpacing.s20,
        AppSpacing.s12,
      ),
      child: SoftGlassPanel(
        level: 3,
        borderRadius: AppRadius.cardRadius,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.sm,
        ),
        onTap: () async {
          await ClubSelectionSheet.show(
            context,
            availableClubs: _availableClubs,
          );
        },
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_rounded,
                size: 17,
                color: palette.primary,
              ),
            ),
            AppSpacing.hSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasClub
                        ? StringUtils.toTitleCase(clubName!)
                        : 'Takımını Seç',
                    style: AppTextStyles.categorySeries.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.vXs,
                  Text(
                    hasClub
                        ? (totalInMeet > 0
                            ? 'Bu müsabakada $totalInMeet kulüp sporcunuz yarışıyor'
                            : 'Bu müsabakada kayıtlı sporcunuz yok')
                        : 'Yarışlardaki kulüp sporcularınızı otomatik takip edin',
                    style: AppTextStyles.labelMuted.copyWith(
                      fontWeight: FontWeight.w400,
                      color: palette.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppSpacing.hSm,
            Text(
              hasClub ? 'Değiştir' : 'Seç',
              style: AppTextStyles.labelMuted.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            AppSpacing.hXs,
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(AppColorPalette palette) {
    final resTotal = widget.live.resultListProgress.total;
    final resProcessed = widget.live.resultListProgress.processed;
    final resRatio =
        resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: palette.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              AppSpacing.hXs,
              Text(
                'CANLI SEANS',
                style: AppTextStyles.labelMuted.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '$resProcessed / $resTotal Tamamlandı (%$resPercent)',
                style: AppTextStyles.categorySeries.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          AppSpacing.vSm,
          ClipRRect(
            borderRadius: AppRadius.full,
            child: LinearProgressIndicator(
              value: resRatio,
              backgroundColor: palette.divider,
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
              minHeight: AppSpacing.xs,
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
    required RaceModel? heroRace,
  }) {
    if (races.isEmpty) {
      return EmptyStateWidget(
        title: isCompletedTab ? 'Sonuçlanan yarış yok' : 'Bekleyen yarış yok',
        message: emptyMessage,
        icon: isCompletedTab
            ? Icons.emoji_events_outlined
            : Icons.schedule_outlined,
        compact: true,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.sm,
        AppSpacing.s20,
        64 +
            AppSpacing.md +
            MediaQuery.of(context).padding.bottom +
            AppSpacing.lg,
      ),
      itemCount: races.length,
      itemBuilder: (context, index) {
        final race = races[index];
        final highlight = !isCompletedTab &&
            index == 0 &&
            (heroRace == null || race.id == heroRace.id);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (highlight)
                Positioned(
                  top: -AppSpacing.md,
                  right: -AppSpacing.md,
                  width: 200,
                  height: 150,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            context.palette.glowLight.withValues(
                              alpha: context.palette.isDark ? 0.10 : 0.22,
                            ),
                            context.palette.glowLight.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ModernRaceCard(
                race: race,
                onTap: () => _openRaceResults(race),
                onFavoriteToggle: () {
                  setState(() {
                    race.isFavorite = !race.isFavorite;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliverTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;

  _SliverTabHeaderDelegate({required this.child, required this.extent});

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SliverTabHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
