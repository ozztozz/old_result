import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_bottom_sheet.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/race_result_sorter.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/collapsible_result_group.dart';
import '../../shared/widgets/live_result_row.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/status_badge.dart';
import '../athletes/athlete_profile_screen.dart';

const double _raceActionButtonOffset = (24 * 1.2 - 40) / 2;

/// TYF Yüzme Sonuçları — Canlı Yarış Sonuçları Ekranı (v2.0)
/// Apple Esintili Spor Gösterge Paneli
/// Kulüp seçili olduğunda en başta kulüp sporcularının özet kartı (Pinned Section) gösterilir.
class LiveRaceResultsScreen extends StatefulWidget {
  final LiveMeetSummary live;
  final LiveEventProgramItem event;
  final SwimRepository repository;
  final bool asSheet;
  final ScrollController? sheetScrollController;

  const LiveRaceResultsScreen({
    super.key,
    required this.live,
    required this.event,
    required this.repository,
    this.asSheet = false,
    this.sheetScrollController,
  });

  static Future<void> showSheet(
    BuildContext context, {
    required LiveMeetSummary live,
    required LiveEventProgramItem event,
    required SwimRepository repository,
  }) {
    return AppBottomSheet.show<void>(
      context,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.38,
        maxChildSize: 0.85,
        expand: false,
        builder: (sheetCtx, scrollController) => AppBottomSheet(
          scrollable: false,
          child: LiveRaceResultsScreen(
            live: live,
            event: event,
            repository: repository,
            asSheet: true,
            sheetScrollController: scrollController,
          ),
        ),
      ),
    );
  }

  @override
  State<LiveRaceResultsScreen> createState() => _LiveRaceResultsScreenState();
}

class _LiveRaceResultsScreenState extends State<LiveRaceResultsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _isAutoRefresh = false;
  Timer? _refreshTimer;

  List<RaceResult> _allResults = [];
  List<RaceResult> _filteredResults = [];

  String _selectedStatus = 'all'; // 'all', 'finished', 'pending'
  String _searchQuery = '';
  int _detailTabIndex = 0; // 0: Seriler, 1: İstatistik
  final Set<String> _collapsedGroupKeys = {};
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
    SelectedClubService.instance.addListener(_onClubChanged);
    _loadResults();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    SelectedClubService.instance.removeListener(_onClubChanged);
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted && _isSearchFocused != _searchFocusNode.hasFocus) {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _onClubChanged() {
    if (mounted) setState(() {});
  }

  void _toggleAutoRefresh(bool enable) {
    setState(() => _isAutoRefresh = enable);
    _refreshTimer?.cancel();
    if (enable) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _loadResults(silent: true);
      });
    }
  }

  Future<void> _loadResults({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<RaceResult> list;
      if (widget.live.id > 0) {
        final feed = await widget.repository.getLiveFeedResponse(
          widget.live.id,
          eventNo: widget.event.eventNo,
        );
        list = List<RaceResult>.from(feed.results);
      } else if (widget.live.meetId != null) {
        final collected = <RaceResult>[];
        for (var page = 1; page <= 5; page++) {
          final batch = await widget.repository.getMeetResults(
            widget.live.meetId!,
            eventNo: widget.event.eventNo,
            page: page,
          );
          collected.addAll(batch);
          if (batch.length < 50) break;
        }
        list = collected;
      } else {
        list = [];
      }
      RaceResultSorter.sort(list);

      if (mounted) {
        setState(() {
          _allResults = list;
          _errorMessage = null;
          _isLoading = false;
        });
        _applyFilter();
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _errorMessage = 'Yarış sonuçları yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  bool _hasValidRaceTime(RaceResult r) => LiveResultRow.hasValidRaceTime(r);

  void _applyFilter() {
    var filtered = List<RaceResult>.from(_allResults);

    // Durum filtresi
    if (_selectedStatus == 'finished') {
      filtered = filtered.where((r) {
        final rawStatus = r.resultStatus.trim().toUpperCase();
        final isWait = rawStatus == 'WAITING';
        final isDq = rawStatus == 'DQ' ||
            rawStatus == 'DSQ' ||
            rawStatus == 'DNS' ||
            rawStatus == 'DNF' ||
            r.rank.toUpperCase().startsWith('DQ') ||
            r.rank.toUpperCase().startsWith('DSQ');
        return !isWait && !isDq && _hasValidRaceTime(r);
      }).toList();
    } else if (_selectedStatus == 'pending') {
      filtered = filtered.where((r) {
        final isWait = r.resultStatus.trim().toUpperCase() == 'WAITING';
        return isWait || !_hasValidRaceTime(r);
      }).toList();
    }

    // Arama filtresi
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        return r.athleteName.toLowerCase().contains(q) ||
            r.clubName.toLowerCase().contains(q);
      }).toList();
    }

    setState(() {
      _filteredResults = filtered;
    });
  }

  /// Seçili kulübe ait sporcuların bu yarıştaki sonuçları
  List<RaceResult> get _myClubResults {
    if (!SelectedClubService.instance.hasSelectedClub) return [];
    return _allResults.where((r) {
      return SelectedClubService.instance.matches(r.clubName, r.clubId);
    }).toList();
  }

  /// Sporcunun genel yarış sıralamasındaki kesin sırası
  int? _getOverallRank(RaceResult result) {
    final parsed = int.tryParse(result.rank.replaceAll('.', '').trim());
    if (parsed != null && parsed > 0) return parsed;
    final idx = _allResults.indexOf(result);
    return idx >= 0 ? idx + 1 : null;
  }

  void _openAthleteProfile(RaceResult result) {
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
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = widget.event.name.isNotEmpty
        ? widget.event.name
        : '${widget.event.distance ?? ''} ${widget.event.strokeLabel}'.trim();

    final myClubResults = _myClubResults;
    final hasClubAthletes = myClubResults.isNotEmpty;

    final statusChips = <FilterChipItem>[
      const FilterChipItem(label: 'Tümü'),
      const FilterChipItem(label: 'Sonuçlananlar'),
      const FilterChipItem(label: 'Beklenenler'),
    ];
    final selectedChipLabel = switch (_selectedStatus) {
      'finished' => 'Sonuçlananlar',
      'pending' => 'Beklenenler',
      _ => 'Tümü',
    };

    final resultsListView = ListView(
      controller: widget.sheetScrollController,
      padding: EdgeInsets.fromLTRB(
        widget.asSheet ? 0 : AppSpacing.s20,
        AppSpacing.sm,
        widget.asSheet ? 0 : AppSpacing.s20,
        widget.asSheet
            ? AppSpacing.lg
            : (64 +
                AppSpacing.md +
                MediaQuery.of(context).padding.bottom +
                AppSpacing.lg),
      ),
      children: [
        if (!widget.asSheet) ...[
          // 1. Level 1 Yarış Özet Kartı
          _buildRaceSummaryHero(palette, title),
          AppSpacing.vMd,
        ],

                            // 1.5. Seriler / İstatistik Sekme Hapları
                            _buildDetailTabPills(palette),
                            AppSpacing.vMd,

                            if (_detailTabIndex == 1)
                              _buildRaceStatsSection(palette)
                            else ...[
                              // 2. Arama Çubuğu
                              Container(
                                height: 46,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _isSearchFocused
                                        ? palette.accent.withValues(alpha: 0.45)
                                        : palette.border.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.textPrimary
                                          .withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_outlined,
                                    color: palette.textSecondary,
                                    size: 20,
                                  ),
                                  AppSpacing.h12,
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      onChanged: (val) {
                                        _searchQuery = val;
                                        _applyFilter();
                                      },
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 15,
                                        color: palette.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Sporcu veya kulüp ara...',
                                        hintStyle: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w400,
                                          color: palette.textSecondary
                                              .withValues(alpha: 0.85),
                                        ),
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        _searchQuery = '';
                                        _applyFilter();
                                      },
                                      child: Icon(
                                        Icons.close_outlined,
                                        size: 18,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            AppSpacing.v12,

                            // 3. Level 3 Durum Filtre Çipleri
                            ModernFilterChipBar(
                              chips: statusChips,
                              selectedChip: selectedChipLabel,
                              onSelected: (label) {
                                setState(() {
                                  _selectedStatus = switch (label) {
                                    'Sonuçlananlar' => 'finished',
                                    'Beklenenler' => 'pending',
                                    _ => 'all',
                                  };
                                });
                                _applyFilter();
                              },
                            ),
                            AppSpacing.vLg,

                            // 4. Kulüp Öne Çıkarılan Bölüm (Level 2)
                            if (!_isLoading && hasClubAthletes) ...[
                              _buildClubPinnedSection(context, myClubResults),
                              AppSpacing.vLg,
                            ],

                            // 5. Genel Sonuç Listesi Başlığı
                            SectionHeader(
                              title: hasClubAthletes
                                  ? 'Tüm Yarış Sıralaması'
                                  : 'Yarış Sıralaması',
                              trailingText: '${_filteredResults.length} Sporcu',
                            ),
                            AppSpacing.v12,

                            // 6. Genel Sonuç Listesi Paneli (Level 2)
                            if (_isLoading)
                              _buildLoadingSkeleton()
                            else if (_filteredResults.isEmpty)
                              const SoftGlassPanel(
                                level: 2,
                                borderRadius: AppRadius.cardRadius,
                                padding: AppSpacing.paddingAllLg,
                                child: EmptyStateWidget(
                                  title: 'Sonuç bulunamadı',
                                  message:
                                      'Kriterlere uygun yarış sonucu bulunamadı.',
                                  icon: Icons.person_search_outlined,
                                  compact: true,
                                ),
                              )
                            else
                              ..._buildGroupedResultsPanels(palette),
                            ],
                          ],
    );

    final bodyContent = Expanded(
      child: _errorMessage != null && _allResults.isEmpty
          ? Center(
              child: EmptyStateWidget(
                title: 'Bağlantı Hatası',
                message: _errorMessage!,
                icon: Icons.cloud_off_outlined,
                actionText: 'Tekrar Dene',
                onAction: () => _loadResults(),
              ),
            )
          : (widget.asSheet
              ? resultsListView
              : RefreshIndicator(
                  color: palette.primary,
                  onRefresh: () => _loadResults(),
                  child: resultsListView,
                )),
    );

    if (widget.asSheet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSheetHeader(context, palette, title),
          bodyContent,
        ],
      );
    }

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ResponsiveCenter(
          maxWidth: 1040,
          child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context, palette, title),
              bodyContent,
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildSheetHeader(
    BuildContext context,
    AppColorPalette palette,
    String title,
  ) {
    final subtitleParts = <String>[
      if (widget.event.genderLabel.isNotEmpty) widget.event.genderLabel,
      if ((widget.event.ageGroup ?? '').trim().isNotEmpty)
        widget.event.ageGroup!.trim(),
      if (widget.event.day != null && widget.event.day! > 0)
        '${widget.event.day}. Gün',
      if ((widget.event.estimatedTime ?? '').trim().isNotEmpty)
        widget.event.estimatedTime!.trim(),
    ];
    final distance = widget.event.distance;
    final hasDistance = distance != null && distance > 0;
    final sheetTitle = (hasDistance && widget.event.strokeLabel.isNotEmpty)
        ? StringUtils.toTitleCase(widget.event.strokeLabel)
        : StringUtils.toTitleCase(title);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          if (hasDistance) ...[
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.accent.withValues(alpha: 0.2),
                    palette.infoCyan.withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.38),
                  width: 1.2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface.withValues(alpha: 0.65),
                ),
                padding: const EdgeInsets.all(2),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$distance',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: palette.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggleAutoRefresh(!_isAutoRefresh),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _isAutoRefresh
                    ? palette.accent.withValues(alpha: 0.14)
                    : palette.surfaceSecondary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.autorenew_rounded,
                size: 17,
                color: _isAutoRefresh ? palette.accent : palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.surfaceSecondary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTabPills(AppColorPalette palette) {
    const tabs = [(0, 'Seriler'), (1, 'İstatistik')];
    return Row(
      children: [
        for (final tab in tabs)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: tab.$1 == 0 ? 8 : 0),
              child: GestureDetector(
                onTap: () {
                  if (_detailTabIndex != tab.$1) {
                    setState(() => _detailTabIndex = tab.$1);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _detailTabIndex == tab.$1
                        ? palette.accent
                        : palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (_detailTabIndex == tab.$1
                                ? palette.accent
                                : palette.textPrimary)
                            .withValues(
                          alpha: _detailTabIndex == tab.$1 ? 0.24 : 0.04,
                        ),
                        blurRadius: _detailTabIndex == tab.$1 ? 10 : 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tab.$2,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _detailTabIndex == tab.$1
                              ? Theme.of(context).colorScheme.onPrimary
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRaceStatsSection(AppColorPalette palette) {
    if (_isLoading) return _buildLoadingSkeleton();
    if (_allResults.isEmpty) {
      return const SoftGlassPanel(
        level: 2,
        borderRadius: AppRadius.cardRadius,
        padding: AppSpacing.paddingAllLg,
        child: EmptyStateWidget(
          title: 'İstatistik verisi yok',
          message: 'Bu yarış için henüz sporcu veya seri verisi bulunmuyor.',
          icon: Icons.bar_chart_rounded,
        ),
      );
    }

    int finished = 0;
    int pending = 0;
    int passedStandard = 0;
    final clubCounts = <String, int>{};

    for (final r in _allResults) {
      final isDone = r.resultStatus != 'WAITING' &&
          ((r.time != null && r.time!.trim().isNotEmpty) ||
              r.resultStatus == 'DQ' ||
              r.resultStatus == 'DNS' ||
              r.resultStatus == 'DNF');
      if (isDone) {
        finished++;
      } else {
        pending++;
      }
      if (r.qualifyingStandard?.passed == true) {
        passedStandard++;
      }
      final club = r.clubName.trim().isNotEmpty
          ? StringUtils.toTitleCase(r.clubName)
          : 'Ferdi Sporcu';
      clubCounts[club] = (clubCounts[club] ?? 0) + 1;
    }

    final total = _allResults.length;
    final topClubs = clubCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget buildDualStatRow({
      required String title,
      required String leftLabel,
      required int leftVal,
      required String rightLabel,
      required int rightVal,
      required Color leftColor,
      required Color rightColor,
    }) {
      final sum = leftVal + rightVal;
      final leftRatio = sum > 0 ? (leftVal / sum).clamp(0.0, 1.0) : 0.5;
      final rightRatio = sum > 0 ? (rightVal / sum).clamp(0.0, 1.0) : 0.5;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '$leftVal',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: leftColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$rightVal',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: rightColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  leftLabel,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
                Text(
                  rightLabel,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.progressTrack,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: leftRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            color: leftColor,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.progressTrack,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: rightRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            color: rightColor,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      padding: AppSpacing.paddingAllMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildDualStatRow(
            title: 'Yarış İlerlemesi',
            leftLabel: 'Tamamlanan',
            leftVal: finished,
            rightLabel: 'Beklenen',
            rightVal: pending,
            leftColor: palette.statusSuccess,
            rightColor: palette.statusWarning,
          ),
          Divider(height: 1, color: palette.divider),
          buildDualStatRow(
            title: 'Baraj Durumu',
            leftLabel: 'Barajı Geçen',
            leftVal: passedStandard,
            rightLabel: 'Diğer',
            rightVal: (total - passedStandard).clamp(0, total),
            leftColor: palette.accent,
            rightColor: palette.textSecondary,
          ),
          if (topClubs.isNotEmpty) ...[
            Divider(height: 1, color: palette.divider),
            const SizedBox(height: 12),
            Text(
              'Katılım Sağlayan Kulüpler',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in topClubs.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value} sporcu',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (entry.value / total).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: palette.progressTrack,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(palette.accent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppColorPalette palette,
    String title,
  ) {
    final raceCount = widget.live.resultListProgress.total > 0
        ? widget.live.resultListProgress.total
        : widget.live.startListProgress.total;
    final cityText = widget.live.city.trim();
    final meetLabel = cityText.isNotEmpty
        ? (raceCount > 0 ? '$cityText • $raceCount yarış' : cityText)
        : (raceCount > 0
            ? '$raceCount yarış'
            : StringUtils.toTitleCase(widget.live.name));

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
                  meetLabel,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 88 + AppSpacing.sm),
            ],
          ),
          AppSpacing.vXs,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, _raceActionButtonOffset),
                child: GlassCircleButton(
                  icon: Icons.arrow_back_outlined,
                  iconSize: 20,
                  iconColor: palette.textTertiary,
                  tooltip: 'Geri',
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
              AppSpacing.hSm,
              const Spacer(),
              AppSpacing.hSm,
              Transform.translate(
                offset: const Offset(0, _raceActionButtonOffset),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassCircleButton(
                      icon: _isAutoRefresh
                          ? Icons.sync_outlined
                          : Icons.sync_disabled_outlined,
                      iconSize: 20,
                      iconColor: _isAutoRefresh
                          ? palette.accent
                          : palette.textTertiary,
                      tooltip: _isAutoRefresh
                          ? 'Otomatik Yenileme Açık'
                          : 'Otomatik Yenileme Kapalı',
                      onTap: () => _toggleAutoRefresh(!_isAutoRefresh),
                    ),
                    AppSpacing.hSm,
                    GlassCircleButton(
                      icon: Icons.refresh_outlined,
                      iconSize: 20,
                      iconColor: palette.textTertiary,
                      tooltip: 'Yenile',
                      onTap: () => _loadResults(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRaceSummaryHero(AppColorPalette palette, String title) {
    final statusLower = widget.event.status.toLowerCase();
    final isCompleted = !widget.event.isPending ||
        statusLower.contains('tamam') ||
        statusLower.contains('sonuc');
    final isTrulyLive = !isCompleted &&
        (statusLower.contains('canl') ||
            statusLower.contains('isleniyor') ||
            statusLower.contains('live'));

    final StatusBadge statusBadge;
    if (isTrulyLive) {
      statusBadge = const StatusBadge.live(label: 'Canlı');
    } else if (isCompleted) {
      statusBadge = StatusBadge(
        label: 'Sonuçlandı',
        variant: StatusBadgeVariant.success,
        textColor: palette.successText,
      );
    } else {
      statusBadge = const StatusBadge.neutral(label: 'Bekleniyor');
    }

    final metaParts = <String>[
      if (widget.event.distance != null && widget.event.distance! > 0)
        '${widget.event.distance}m',
      if (widget.event.strokeLabel.isNotEmpty)
        StringUtils.toTitleCase(widget.event.strokeLabel),
      if (widget.event.gender != null && widget.event.gender!.isNotEmpty)
        StringUtils.toTitleCase(widget.event.gender!),
      if (widget.event.ageGroup != null && widget.event.ageGroup!.isNotEmpty)
        StringUtils.toTitleCase(widget.event.ageGroup!),
    ];

    return SoftGlassPanel(
      level: 1,
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: AppRadius.rounded,
      padding: AppSpacing.cardPadding,
      artStyle: AmbientArtStyle.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                statusBadge,
                Text(
                  '${_allResults.length} Sporcu',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.v12,
          Text(
            StringUtils.toTitleCase(title),
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (metaParts.isNotEmpty) ...[
            AppSpacing.vXs,
            Text(
              metaParts.join(' • '),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: palette.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildGroupedResultsPanels(AppColorPalette palette) {
    final groups = RaceResultSorter.splitMultipleRankings(_filteredResults);
    final isMultiGroup = groups.length > 1;
    final widgets = <Widget>[];

    for (var gIdx = 0; gIdx < groups.length; gIdx++) {
      final group = groups[gIdx];
      final panel = Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: palette.textPrimary.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: group.results.asMap().entries.map((entry) {
              final index = entry.key;
              final result = entry.value;
              final isLast = index == group.results.length - 1;
              return LiveResultRow(
                result: result,
                rankIndex:
                    isMultiGroup ? (index + 1) : _getOverallRank(result),
                showDivider: !isLast,
                eventDistance: widget.event.distance,
                onTap: () => _openAthleteProfile(result),
              );
            }).toList(),
          ),
        ),
      );

      if (isMultiGroup && group.title != null) {
        if (gIdx > 0) widgets.add(AppSpacing.vMd);
        final groupKey = '${gIdx}_${group.title}';
        final isExpanded = !_collapsedGroupKeys.contains(groupKey);
        widgets.add(
          CollapsibleResultGroup(
            title: group.title!,
            count: group.results.length,
            isExpanded: isExpanded,
            onToggle: () {
              setState(() {
                if (isExpanded) {
                  _collapsedGroupKeys.add(groupKey);
                } else {
                  _collapsedGroupKeys.remove(groupKey);
                }
              });
            },
            child: panel,
          ),
        );
      } else {
        widgets.add(panel);
      }
    }
    return widgets;
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 64),
        AppSpacing.v12,
        AppSkeleton.card(height: 64),
        AppSpacing.v12,
        AppSkeleton.card(height: 64),
      ],
    );
  }

  /// Kulüp Sporcularının Listenin Başında Ayrı ve Vurgulu Gösterildiği Vitrin Paneli
  Widget _buildClubPinnedSection(
    BuildContext context,
    List<RaceResult> clubResults,
  ) {
    final clubName = SelectedClubService.instance.clubName ?? 'Kulübünüz';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: StringUtils.toTitleCase(clubName),
          trailingText: '${clubResults.length} Sporcu',
        ),
        AppSpacing.v12,
        SoftGlassPanel(
          level: 2,
          borderRadius: AppRadius.cardRadius,
          padding: EdgeInsets.zero,
          child: Column(
            children: clubResults.asMap().entries.map((entry) {
              final idx = entry.key;
              final result = entry.value;
              final isLast = idx == clubResults.length - 1;
              final overallRank = _getOverallRank(result);

              return LiveResultRow(
                result: result,
                rankIndex: overallRank,
                showDivider: !isLast,
                isPinnedClubRow: true,
                eventDistance: widget.event.distance,
                onTap: () => _openAthleteProfile(result),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
