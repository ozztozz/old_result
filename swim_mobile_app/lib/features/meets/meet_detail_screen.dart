import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/race_result_sorter.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/collapsible_result_group.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/status_badge.dart';
import '../athletes/athlete_profile_screen.dart';

const double _meetDetailActionButtonOffset = (22 * 1.2 - 40) / 2;

/// 2. Ekran: Müsabaka Detayı, Filtreler ve Yarış Sonuçları
class MeetDetailScreen extends StatefulWidget {
  final int meetId;
  final String meetTitle;
  final SwimRepository repository;

  const MeetDetailScreen({
    super.key,
    required this.meetId,
    required this.meetTitle,
    required this.repository,
  });

  @override
  State<MeetDetailScreen> createState() => _MeetDetailScreenState();
}

class _MeetDetailScreenState extends State<MeetDetailScreen> {
  bool _isLoading = true;
  bool _isLoadingResults = false;
  String? _errorMessage;

  MeetDetail? _meetDetail;
  MeetParticipants? _participants;
  List<RaceResult> _results = [];

  // Filtre Değerleri
  String? _selectedEventNo;
  int? _selectedClubId;
  int? _selectedAthleteId;
  String _selectedStatus = 'all';
  final Set<String> _collapsedGroupKeys = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.getMeetDetail(widget.meetId),
        widget.repository.getMeetParticipants(widget.meetId),
        widget.repository.getMeetResults(widget.meetId, page: 1),
      ]);

      if (mounted) {
        final list = results[2] as List<RaceResult>;
        RaceResultSorter.sort(list, preferRankFirst: false);
        setState(() {
          _meetDetail = results[0] as MeetDetail;
          _participants = results[1] as MeetParticipants;
          _results = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Müsabaka detayları yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _filterResults() async {
    setState(() => _isLoadingResults = true);
    try {
      final res = await widget.repository.getMeetResults(
        widget.meetId,
        eventNo: _selectedEventNo,
        clubId: _selectedClubId,
        athleteId: _selectedAthleteId,
        status: _selectedStatus,
        page: 1,
      );
      if (mounted) {
        RaceResultSorter.sort(res, preferRankFirst: false);
        setState(() {
          _results = res;
          _isLoadingResults = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: _isLoading
              ? _buildInitialLoadingSkeleton(context)
              : _errorMessage != null && _meetDetail == null
                  ? Center(
                      child: EmptyStateWidget(
                        title: 'Bağlantı Hatası',
                        message: _errorMessage!,
                        icon: Icons.cloud_off_outlined,
                        actionText: 'Tekrar Dene',
                        onAction: _loadInitialData,
                      ),
                    )
                  : Column(
                      children: [
                        _buildHeader(context, palette),
                        Expanded(
                          child: RefreshIndicator(
                            color: palette.primary,
                            onRefresh: _loadInitialData,
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(
                                AppSpacing.s20,
                                AppSpacing.sm,
                                AppSpacing.s20,
                                64 +
                                    AppSpacing.md +
                                    MediaQuery.of(context).padding.bottom +
                                    AppSpacing.lg,
                              ),
                              children: [
                                if (_meetDetail != null) ...[
                                  _buildMeetSummaryHero(palette, _meetDetail!),
                                  AppSpacing.vLg,
                                ],
                                _buildFiltersSection(palette),
                                AppSpacing.vLg,
                                SectionHeader(
                                  title: 'Yarış Sonuçları',
                                  trailingText: '${_results.length} Sonuç',
                                ),
                                AppSpacing.v12,
                                if (_isLoadingResults)
                                  _buildResultsSkeleton()
                                else if (_results.isEmpty)
                                  const SoftGlassPanel(
                                    level: 2,
                                    borderRadius: AppRadius.cardRadius,
                                    padding: AppSpacing.paddingAllLg,
                                    child: EmptyStateWidget(
                                      title: 'Sonuç bulunamadı',
                                      message:
                                          'Kriterlere uygun sonuç bulunamadı.',
                                      icon: Icons.search_off_outlined,
                                      compact: true,
                                    ),
                                  )
                                else
                                  ..._buildGroupedMeetResultsPanels(
                                    context,
                                    palette,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedMeetResultsPanels(
    BuildContext context,
    AppColorPalette palette,
  ) {
    final groups = RaceResultSorter.splitMultipleRankings(
      _results,
      preferRankFirst: false,
    );
    final isMultiGroup = groups.length > 1;
    final widgets = <Widget>[];

    for (var gIdx = 0; gIdx < groups.length; gIdx++) {
      final group = groups[gIdx];
      final panel = SoftGlassPanel(
        level: 2,
        borderRadius: AppRadius.cardRadius,
        padding: EdgeInsets.zero,
        child: Column(
          children: group.results.asMap().entries.map((entry) {
            final index = entry.key;
            final r = entry.value;
            final isLast = index == group.results.length - 1;
            return _buildResultRow(
              context,
              palette,
              result: r,
              rankIndex: index + 1,
              showDivider: !isLast,
            );
          }).toList(),
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

  Widget _buildInitialLoadingSkeleton(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        64 + AppSpacing.md + MediaQuery.of(context).padding.bottom + AppSpacing.lg,
      ),
      children: [
        const AppSkeleton.line(width: 140, height: 14),
        AppSpacing.vSm,
        const AppSkeleton.line(width: 240, height: 24),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 132),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 44, borderRadius: AppRadius.chipRadius),
        AppSpacing.vLg,
        _buildResultsSkeleton(),
      ],
    );
  }

  Widget _buildResultsSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    final detail = _meetDetail;
    final city = detail?.city.trim() ?? '';
    final raceCount =
        (detail?.totalRaces ?? 0) > 0 ? detail!.totalRaces : (detail?.events.length ?? 0);
    final topLabel = city.isNotEmpty
        ? (raceCount > 0 ? '$city • $raceCount yarış' : city)
        : (raceCount > 0 ? '$raceCount yarış' : 'Müsabaka Detayı');

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
                  topLabel,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
                offset: const Offset(0, _meetDetailActionButtonOffset),
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
              const SizedBox(width: 40 + AppSpacing.sm),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeetSummaryHero(AppColorPalette palette, MeetDetail detail) {
    final is25m = detail.course.toUpperCase() == 'SC';
    final poolLabel = is25m ? '25m Kısa Kulvar' : '50m Uzun Kulvar';
    final dateText = (detail.endDate.isNotEmpty && detail.endDate != detail.startDate)
        ? '${detail.startDate} – ${detail.endDate}'
        : detail.startDate;

    final effectiveRaces =
        detail.totalRaces > 0 ? detail.totalRaces : detail.events.length;
    final int effectiveAthletes;
    if (detail.totalAthletes > 0) {
      effectiveAthletes = detail.totalAthletes;
    } else if (_participants != null && _participants!.athletes.isNotEmpty) {
      effectiveAthletes = _participants!.athletes.length;
    } else {
      effectiveAthletes = _results
          .map((r) => r.athleteId > 0 ? '${r.athleteId}' : r.athleteName.trim())
          .where((k) => k.isNotEmpty)
          .toSet()
          .length;
    }

    final athleteFormatted = (_isLoading || (_isLoadingResults && effectiveAthletes == 0))
        ? '–'
        : NumberFormat('#,###', 'tr_TR').format(effectiveAthletes);
    final raceFormatted = _isLoading
        ? '–'
        : NumberFormat('#,###', 'tr_TR').format(effectiveRaces);

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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                label: poolLabel,
                variant: StatusBadgeVariant.info,
              ),
              if (dateText.isNotEmpty)
                Text(
                  dateText,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          AppSpacing.vMd,
          Row(
            children: [
              Expanded(
                child: _buildSummaryMetric(
                  palette,
                  value: athleteFormatted,
                  label: 'Sporcu',
                ),
              ),
              _buildHeroDivider(palette),
              Expanded(
                child: _buildSummaryMetric(
                  palette,
                  value: raceFormatted,
                  label: 'Yarış',
                ),
              ),
              if (detail.city.isNotEmpty) ...[
                _buildHeroDivider(palette),
                Expanded(
                  child: _buildSummaryMetric(
                    palette,
                    value: StringUtils.toTitleCase(detail.city),
                    label: 'Şehir',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    AppColorPalette palette, {
    required String value,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDivider(AppColorPalette palette) {
    return Container(
      width: 1,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.divider.withValues(alpha: 0.0),
            palette.textSecondary.withValues(alpha: 0.35),
            palette.divider.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersSection(AppColorPalette palette) {
    final events = _meetDetail?.events ?? [];
    final clubs = _participants?.clubs ?? [];

    final allAthletes = _participants?.athletes ?? [];
    final filteredAthletes = _selectedClubId == null
        ? allAthletes
        : allAthletes.where((a) => a.clubId == _selectedClubId).toList();

    final eventChips = <FilterChipItem>[
      const FilterChipItem(label: 'Tüm Yarışlar'),
      ...events.map((ev) {
        final dist = ev.distance != null ? '${ev.distance}m ' : '';
        return FilterChipItem(
          label: '$dist${StringUtils.toTitleCase(ev.strokeLabel)}',
        );
      }),
    ];

    String selectedEventLabel = 'Tüm Yarışlar';
    if (_selectedEventNo != null) {
      for (final ev in events) {
        if (ev.eventNo == _selectedEventNo) {
          final dist = ev.distance != null ? '${ev.distance}m ' : '';
          selectedEventLabel =
              '$dist${StringUtils.toTitleCase(ev.strokeLabel)}';
          break;
        }
      }
    }

    final statusChips = const <FilterChipItem>[
      FilterChipItem(label: 'Tümü'),
      FilterChipItem(label: 'Sonuçlanan'),
      FilterChipItem(label: 'Bekleyen'),
    ];
    final selectedStatusLabel = switch (_selectedStatus) {
      'finished' => 'Sonuçlanan',
      'pending' => 'Bekleyen',
      _ => 'Tümü',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (events.isNotEmpty) ...[
          ModernFilterChipBar(
            chips: eventChips,
            selectedChip: selectedEventLabel,
            onSelected: (label) {
              if (label == 'Tüm Yarışlar') {
                setState(() => _selectedEventNo = null);
              } else {
                final match = events.where((ev) {
                  final dist = ev.distance != null ? '${ev.distance}m ' : '';
                  return '$dist${StringUtils.toTitleCase(ev.strokeLabel)}' ==
                      label;
                });
                setState(() {
                  _selectedEventNo = match.isNotEmpty
                      ? (_selectedEventNo == match.first.eventNo
                          ? null
                          : match.first.eventNo)
                      : null;
                });
              }
              _filterResults();
            },
          ),
          AppSpacing.v12,
        ],

        // Bağımlı Kulüp ve Sporcu Seçici Dropdown'lar (Level 3)
        Row(
          children: [
            Expanded(
              child: SoftGlassPanel(
                level: 3,
                height: 44,
                borderRadius: AppRadius.medium,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedClubId,
                    isExpanded: true,
                    dropdownColor: palette.surfaceElevated,
                    icon: Icon(
                      Icons.keyboard_arrow_down_outlined,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    hint: Text(
                      'Tüm Takımlar',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Tüm Takımlar',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...clubs.map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            StringUtils.toTitleCase(c.name),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: palette.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedClubId = val;
                        if (_selectedAthleteId != null) {
                          final nextAthletes = val == null
                              ? allAthletes
                              : allAthletes.where((a) => a.clubId == val);
                          final match =
                              nextAthletes.any((a) => a.id == _selectedAthleteId);
                          if (!match) _selectedAthleteId = null;
                        }
                      });
                      _filterResults();
                    },
                  ),
                ),
              ),
            ),
            AppSpacing.hSm,
            Expanded(
              child: SoftGlassPanel(
                level: 3,
                height: 44,
                borderRadius: AppRadius.medium,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedAthleteId,
                    isExpanded: true,
                    dropdownColor: palette.surfaceElevated,
                    icon: Icon(
                      Icons.keyboard_arrow_down_outlined,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    hint: Text(
                      'Tüm Sporcular',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Tüm Sporcular',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...filteredAthletes.map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${StringUtils.toTitleCase(a.name)}${a.birthYear != null ? " (${a.birthYear})" : ""}',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: palette.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedAthleteId = val);
                      _filterResults();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        AppSpacing.v12,

        // Durum Filtresi
        ModernFilterChipBar(
          chips: statusChips,
          selectedChip: selectedStatusLabel,
          onSelected: (label) {
            setState(() {
              _selectedStatus = switch (label) {
                'Sonuçlanan' => 'finished',
                'Bekleyen' => 'pending',
                _ => 'all',
              };
            });
            _filterResults();
          },
        ),
      ],
    );
  }

  String? _getDisplaySeedTime(RaceResult result) {
    if (result.seedTime != null &&
        result.seedTime!.isNotEmpty &&
        result.seedTime != '0' &&
        result.seedTime != '00:00.00' &&
        result.seedTime != '-') {
      var s = result.seedTime!.trim();
      if (s.startsWith('00:')) s = s.substring(3);
      return s;
    }
    if (result.seedTimeCs != null && result.seedTimeCs! > 0) {
      return SwimTimeFormatter.formatCs(result.seedTimeCs);
    }
    return null;
  }

  int? _parseTimeToCs(String? s) {
    if (s == null) return null;
    final clean = s.trim();
    if (clean.isEmpty || clean == '-' || clean == '0' || clean == '00:00.00') {
      return null;
    }
    try {
      final parts = clean.split(':');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final sec = int.parse(secParts[0]);
        final cs = secParts.length > 1
            ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
            : 0;
        return (m * 60 + sec) * 100 + cs;
      } else if (parts.length == 1) {
        final secParts = parts[0].split('.');
        final sec = int.parse(secParts[0]);
        final cs = secParts.length > 1
            ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
            : 0;
        return sec * 100 + cs;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Widget _buildResultRow(
    BuildContext context,
    AppColorPalette palette, {
    required RaceResult result,
    required int? rankIndex,
    required bool showDivider,
  }) {
    final rawStatus = result.resultStatus.trim().toUpperCase();
    final isWaiting = rawStatus == 'WAITING';
    final isDns = rawStatus == 'DNS';
    final isDnf = rawStatus == 'DNF';
    final isDsq = rawStatus == 'DQ' ||
        rawStatus == 'DSQ' ||
        result.rank.toUpperCase().startsWith('DQ') ||
        result.rank.toUpperCase().startsWith('DSQ');
    final isNonFinish = isDns || isDnf || isDsq;
    final isSwimming = rawStatus == 'SWIMMING' || rawStatus == 'HAVUZDA';

    final hasValidTime = (result.timeCs ?? 0) > 0 ||
        (result.time != null &&
            result.time!.trim().isNotEmpty &&
            result.time!.trim() != '-' &&
            result.time!.trim().toUpperCase() != 'DNS' &&
            result.time!.trim().toUpperCase() != 'DNF' &&
            result.time!.trim().toUpperCase() != 'DQ' &&
            result.time!.trim().toUpperCase() != 'DSQ' &&
            result.time!.trim().toUpperCase() != 'WAITING');

    final isCompleted =
        !isWaiting && !isNonFinish && !isSwimming && hasValidTime;

    final rawRank = result.rank.replaceAll('.', '').trim();
    final parsedRank = int.tryParse(rawRank);
    final effectiveRank = (parsedRank != null && parsedRank > 0)
        ? parsedRank
        : (rankIndex != null && rankIndex > 0 ? rankIndex : null);

    final isPodium = isCompleted && effectiveRank != null && effectiveRank <= 3;

    final heatMatch = RegExp(r'\d+').firstMatch(result.heat);
    final cleanHeat = heatMatch?.group(0) ?? '';
    final heatStr = cleanHeat.isNotEmpty
        ? cleanHeat
        : (result.heat.isNotEmpty ? result.heat : '-');
    final laneStr =
        result.lane != null && result.lane! > 0 ? '${result.lane}' : '-';

    final String rankOrLaneText = isCompleted && effectiveRank != null
        ? '$effectiveRank.'
        : '$heatStr/$laneStr';

    final isFollowed =
        SelectedClubService.instance.matches(result.clubName, result.clubId) ||
            FavoriteAthletesService.instance.isFavorite(result.athleteId);

    final athleteName = StringUtils.formatAthleteName(result.athleteName);
    final clubName = result.clubName.trim().isNotEmpty
        ? StringUtils.toTitleCase(result.clubName)
        : 'Ferdi Sporcu';

    final Color? podiumBadgeColor;
    if (isCompleted && effectiveRank == 1) {
      podiumBadgeColor = palette.statusWarning;
    } else if (isCompleted && effectiveRank == 2) {
      podiumBadgeColor = palette.textSecondary;
    } else if (isCompleted && effectiveRank == 3) {
      podiumBadgeColor = palette.accent;
    } else {
      podiumBadgeColor = null;
    }

    final chipFill = podiumBadgeColor != null
        ? podiumBadgeColor.withValues(alpha: 0.15)
        : palette.surfaceSecondary;
    final chipBorder = podiumBadgeColor != null
        ? podiumBadgeColor.withValues(alpha: 0.28)
        : palette.border.withValues(alpha: 0.6);

    final String formattedTime;
    if (result.timeCs != null && result.timeCs! > 0) {
      formattedTime = SwimTimeFormatter.formatCs(result.timeCs);
    } else if (result.time != null && result.time!.trim().isNotEmpty) {
      var t = result.time!.trim();
      if (t.startsWith('00:')) t = t.substring(3);
      formattedTime = t;
    } else {
      formattedTime = '-';
    }

    final String? qualifyingText = (isCompleted &&
            result.qualifyingStandard != null &&
            result.qualifyingStandard!.passed &&
            result.qualifyingStandard!.badge.trim().isNotEmpty)
        ? StringUtils.toTitleCase(result.qualifyingStandard!.badge)
        : null;

    final seedDisplay = isCompleted ? _getDisplaySeedTime(result) : null;
    final finishCs = result.timeCs ?? _parseTimeToCs(result.time);
    final seedCs = (result.seedTimeCs != null && result.seedTimeCs! > 0)
        ? result.seedTimeCs
        : _parseTimeToCs(result.seedTime);
    final isFasterThanSeed = isCompleted &&
        finishCs != null &&
        seedCs != null &&
        finishCs > 0 &&
        seedCs > 0 &&
        finishCs < seedCs;
    final isSlowerThanSeed = isCompleted &&
        finishCs != null &&
        seedCs != null &&
        finishCs > 0 &&
        seedCs > 0 &&
        finishCs > seedCs;

    Widget trailingWidget;
    if (isDns) {
      trailingWidget = const StatusBadge.neutral(label: 'Başlamadı');
    } else if (isDnf) {
      trailingWidget = const StatusBadge.neutral(label: 'Tamamlamadı');
    } else if (isDsq) {
      trailingWidget = StatusBadge(
        label: 'Diskalifiye',
        variant: StatusBadgeVariant.error,
        leading: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Icon(
            Icons.cancel_outlined,
            size: 13,
            color: palette.statusDanger,
          ),
        ),
      );
    } else if (isWaiting) {
      trailingWidget = const StatusBadge.neutral(label: 'Bekleniyor');
    } else if (isSwimming) {
      trailingWidget = const StatusBadge.live(label: 'Havuzda');
    } else {
      trailingWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formattedTime,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.displayFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isFasterThanSeed)
                  Icon(
                    Icons.arrow_drop_down_outlined,
                    size: 16,
                    color: palette.successText,
                  )
                else if (isSlowerThanSeed)
                  Icon(
                    Icons.arrow_drop_up_outlined,
                    size: 16,
                    color: palette.statusDanger,
                  ),
                Text(
                  seedDisplay,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    fontWeight: (isFasterThanSeed || isSlowerThanSeed)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: isFasterThanSeed
                        ? palette.successText
                        : (isSlowerThanSeed
                            ? palette.statusDanger
                            : palette.textSecondary),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isFollowed
              ? palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.12)
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AthleteProfileScreen(
                    athleteId: result.athleteId,
                    athleteName: result.athleteName,
                    repository: widget.repository,
                  ),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.s12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: chipFill,
                        borderRadius: AppRadius.smallRadius,
                        border: Border.all(color: chipBorder, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        rankOrLaneText,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight:
                              isPodium ? FontWeight.w700 : FontWeight.w600,
                          color: podiumBadgeColor ?? palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    AppSpacing.h12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (isFollowed)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.xs,
                                  ),
                                  child: Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: palette.accent,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  athleteName,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: palette.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            clubName,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              color: palette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (qualifyingText != null) ...[
                            AppSpacing.vXs,
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 14,
                                    color: palette.successText,
                                  ),
                                ),
                                AppSpacing.hXs,
                                Expanded(
                                  child: Text(
                                    qualifyingText,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: palette.successText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppSpacing.h12,
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: trailingWidget,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: palette.divider),
      ],
    );
  }
}
