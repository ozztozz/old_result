import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/race_result_sorter.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
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
  String? _errorMessage;
  bool _isAutoRefresh = false;
  Timer? _refreshTimer;

  List<RaceResult> _allResults = [];
  List<RaceResult> _filteredResults = [];

  String _selectedStatus = 'all'; // 'all', 'finished', 'pending'
  String _searchQuery = '';
  final Set<String> _expandedSplitKeys = {};
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
      final feed = await widget.repository.getLiveFeedResponse(
        widget.live.id,
        eventNo: widget.event.eventNo,
      );

      final list = feed.results;
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

  void _applyFilter() {
    var filtered = List<RaceResult>.from(_allResults);

    // Durum filtresi
    if (_selectedStatus == 'finished') {
      filtered = filtered.where((r) {
        final isWait = r.resultStatus == 'WAITING';
        final isDq = r.resultStatus == 'DQ' ||
            r.resultStatus == 'DNS' ||
            r.resultStatus == 'DNF' ||
            r.rank.toUpperCase().startsWith('DQ');
        final hasTime = (r.timeCs != null && r.timeCs! > 0) ||
            (r.time != null && r.time!.isNotEmpty);
        return !isWait && !isDq && hasTime;
      }).toList();
    } else if (_selectedStatus == 'pending') {
      filtered = filtered.where((r) {
        final isWait = r.resultStatus == 'WAITING';
        final hasNoTime = (r.timeCs == null || r.timeCs == 0) &&
            (r.time == null || r.time!.isEmpty);
        return isWait || hasNoTime;
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

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context, palette, title),
              Expanded(
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
                    : RefreshIndicator(
                        color: palette.primary,
                        onRefresh: () => _loadResults(),
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
                            // 1. Level 1 Yarış Özet Kartı
                            _buildRaceSummaryHero(palette, title),
                            AppSpacing.vLg,

                            // 2. Level 3 Arama Çubuğu
                            SoftGlassPanel(
                              level: 3,
                              height: 48,
                              borderRadius: BorderRadius.circular(24),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              animationDuration:
                                  const Duration(milliseconds: 180),
                              fillAlphaOverride: palette.isDark
                                  ? (_isSearchFocused ? 0.15 : 0.09)
                                  : (_isSearchFocused ? 0.20 : 0.14),
                              borderAlphaOverride: palette.isDark
                                  ? (_isSearchFocused ? 0.34 : 0.16)
                                  : (_isSearchFocused ? 0.50 : 0.25),
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
                              SoftGlassPanel(
                                level: 2,
                                borderRadius: AppRadius.cardRadius,
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: _filteredResults
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    final index = entry.key;
                                    final result = entry.value;
                                    final isLast =
                                        index == _filteredResults.length - 1;

                                    return _buildResultRow(
                                      context,
                                      palette,
                                      result: result,
                                      rankIndex: index + 1,
                                      showDivider: !isLast,
                                    );
                                  }).toList(),
                                ),
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
              Expanded(
                child: Text(
                  StringUtils.toTitleCase(title),
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
    final palette = context.palette;
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

              return _buildResultRow(
                context,
                palette,
                result: result,
                rankIndex: overallRank,
                showDivider: !isLast,
                isPinnedClubRow: true,
              );
            }).toList(),
          ),
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

  List<({String label, String lapTime, String? cumulativeTime})> _buildSplitLegs(
    RaceResult result, {
    required bool isCompleted,
    required int? finishCs,
    required String formattedTime,
  }) {
    final splits = result.splitTimes;
    if (splits == null || splits.isEmpty) return const [];
    final entries = splits.entries.toList();
    int parseDist(String key) =>
        int.tryParse(key.replaceAll(RegExp(r'[^\d]'), '')) ?? 999999;
    entries.sort((a, b) => parseDist(a.key).compareTo(parseDist(b.key)));

    final legs = <({String label, String lapTime, String? cumulativeTime})>[];
    int? prevCs;
    int prevDist = 0;

    for (final entry in entries) {
      final rawVal = entry.value.trim();
      final currCs = _parseTimeToCs(rawVal);
      final dist = int.tryParse(entry.key.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

      final String lapTime;
      final String? cumulativeTime;
      if (prevCs == null) {
        lapTime = currCs != null ? SwimTimeFormatter.formatCs(currCs) : rawVal;
        cumulativeTime = null;
      } else if (currCs != null && currCs > prevCs) {
        lapTime = SwimTimeFormatter.formatCs(currCs - prevCs);
        cumulativeTime = rawVal;
      } else {
        lapTime = rawVal;
        cumulativeTime = null;
      }

      legs.add((
        label: entry.key,
        lapTime: lapTime,
        cumulativeTime: cumulativeTime,
      ));
      prevCs = currCs;
      if (dist > prevDist) prevDist = dist;
    }

    final totalDistance = result.distance ?? widget.event.distance ?? 0;
    if (isCompleted &&
        finishCs != null &&
        finishCs > 0 &&
        totalDistance > prevDist &&
        prevCs != null &&
        finishCs > prevCs) {
      legs.add((
        label: '${totalDistance}m',
        lapTime: SwimTimeFormatter.formatCs(finishCs - prevCs),
        cumulativeTime: formattedTime,
      ));
    }

    return legs;
  }

  Widget _buildResultRow(
    BuildContext context,
    AppColorPalette palette, {
    required RaceResult result,
    required int? rankIndex,
    required bool showDivider,
    bool isPinnedClubRow = false,
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

    final isCompleted = !isWaiting && !isNonFinish && !isSwimming && hasValidTime;

    final rawRank = result.rank.replaceAll('.', '').trim();
    final parsedRank = int.tryParse(rawRank);
    final effectiveRank = (parsedRank != null && parsedRank > 0)
        ? parsedRank
        : (rankIndex != null && rankIndex > 0 ? rankIndex : null);

    final isPodium = isCompleted && effectiveRank != null && effectiveRank <= 3;

    final cleanHeat = result.heat.replaceAll(RegExp(r'[^\d]'), '').trim();
    final heatStr = cleanHeat.isNotEmpty
        ? cleanHeat
        : (result.heat.isNotEmpty ? result.heat : '-');
    final laneStr =
        result.lane != null && result.lane! > 0 ? '${result.lane}' : '-';

    final String rankOrLaneText =
        isCompleted && effectiveRank != null ? '$effectiveRank.' : 'S$heatStr/$laneStr';

    final bool isMyTeam =
        SelectedClubService.instance.matches(result.clubName, result.clubId);

    final athleteName = StringUtils.toTitleCase(result.athleteName);
    final clubName = result.clubName.trim().isNotEmpty
        ? StringUtils.toTitleCase(result.clubName)
        : 'Ferdi Sporcu';

    final String? subtitleText;
    if (isPinnedClubRow) {
      final hasHeat = cleanHeat.isNotEmpty || result.heat.trim().isNotEmpty;
      final heatDisplay = cleanHeat.isNotEmpty ? cleanHeat : result.heat.trim();
      final hasLane = result.lane != null && result.lane! > 0;
      if (hasHeat && hasLane) {
        subtitleText = 'Seri $heatDisplay • Kulvar ${result.lane}';
      } else if (hasHeat) {
        subtitleText = 'Seri $heatDisplay';
      } else if (hasLane) {
        subtitleText = 'Kulvar ${result.lane}';
      } else {
        subtitleText = null;
      }
    } else {
      subtitleText = clubName;
    }

    final chipFill = isPodium
        ? palette.successText.withValues(alpha: 0.14)
        : palette.textPrimary.withValues(alpha: palette.isDark ? 0.08 : 0.05);
    final chipBorder = isPodium
        ? palette.successText.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: palette.isDark ? 0.12 : 0.25);

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

    final seedDisplay = _getDisplaySeedTime(result);
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

    Widget buildSeedRow({required bool compare}) {
      final faster = compare && isFasterThanSeed;
      final slower = compare && isSlowerThanSeed;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (faster)
            Icon(
              Icons.arrow_drop_down_outlined,
              size: 16,
              color: palette.successText,
            )
          else if (slower)
            Icon(
              Icons.arrow_drop_up_outlined,
              size: 16,
              color: palette.statusDanger,
            ),
          Text(
            seedDisplay!,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
              fontWeight: (faster || slower) ? FontWeight.w600 : FontWeight.w400,
              color: faster
                  ? palette.successText
                  : (slower ? palette.statusDanger : palette.textSecondary),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

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
      trailingWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusBadge.neutral(label: 'Bekleniyor'),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            buildSeedRow(compare: false),
          ],
        ],
      );
    } else if (isSwimming) {
      trailingWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusBadge.live(label: 'Havuzda'),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            buildSeedRow(compare: false),
          ],
        ],
      );
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
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            buildSeedRow(compare: true),
          ],
        ],
      );
    }

    final splits = _buildSplitLegs(
      result,
      isCompleted: isCompleted,
      finishCs: finishCs,
      formattedTime: formattedTime,
    );
    final splitKey =
        '${isPinnedClubRow ? 'pinned' : 'heat'}_${result.id}_${result.heat}_${result.lane}_${result.athleteName}';
    final isExpanded =
        splits.isNotEmpty && _expandedSplitKeys.contains(splitKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isMyTeam
              ? palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.12)
              : Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _openAthleteProfile(result),
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
                        // 1. Sıra / Kulvar Çipi
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
                              color: isPodium
                                  ? palette.successText
                                  : palette.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        AppSpacing.h12,

                        // 2. Sporcu Adı & Kulüp
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (isMyTeam) ...[
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(
                                        right: AppSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
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
                              if (subtitleText != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitleText,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12.5,
                                    color: palette.textSecondary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        AppSpacing.h12,

                        // 3. Derece veya Durum Rozeti
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 136),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: trailingWidget,
                          ),
                        ),
                        if (splits.isNotEmpty) ...[
                          AppSpacing.hXs,
                          SizedBox(
                            width: 36,
                            height: 40,
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedSplitKeys.remove(splitKey);
                                  } else {
                                    _expandedSplitKeys.add(splitKey);
                                  }
                                });
                              },
                              tooltip: 'Ara dereceler',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 40,
                              ),
                              icon: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.s12,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s12,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: palette.textPrimary.withValues(
                              alpha: palette.isDark ? 0.05 : 0.03,
                            ),
                            borderRadius: AppRadius.smallRadius,
                            border: Border.all(color: palette.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ara Dereceler',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textSecondary,
                                ),
                              ),
                              AppSpacing.vXs,
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                children: splits.map((e) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.textPrimary.withValues(
                                        alpha: palette.isDark ? 0.06 : 0.04,
                                      ),
                                      borderRadius: AppRadius.smallRadius,
                                      border: Border.all(
                                        color: palette.divider,
                                      ),
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${e.label} ',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                              color: palette.textSecondary,
                                            ),
                                          ),
                                          TextSpan(
                                            text: e.lapTime,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          if (e.cumulativeTime != null)
                                            TextSpan(
                                              text: ' (${e.cumulativeTime})',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                                color: palette.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: palette.divider),
      ],
    );
  }
}
