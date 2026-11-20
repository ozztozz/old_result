import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';

/// İki Sporcuyu Yan Yana Karşılaştırma Ekranı (Head-to-Head).
class AthleteCompareScreen extends StatefulWidget {
  final AthleteDetail athleteA;
  final SwimRepository repository;

  const AthleteCompareScreen({
    super.key,
    required this.athleteA,
    required this.repository,
  });

  @override
  State<AthleteCompareScreen> createState() => _AthleteCompareScreenState();
}

class _AthleteCompareScreenState extends State<AthleteCompareScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  late final FocusNode _searchFocusNode;
  late final TabController _poolTabController;
  bool _isSearchFocused = false;
  Timer? _debounce;
  bool _searching = false;
  List<AthleteSearchItem> _searchResults = [];

  AthleteDetail? _athleteB;
  bool _loadingB = false;
  String? _errorB;
  int? _lastFailedAthleteId;
  String _course = 'LC'; // 'LC' (50m) veya 'SC' (25m)

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocus);
    _poolTabController = TabController(length: 2, vsync: this)
      ..addListener(_handlePoolTabChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.removeListener(_handleSearchFocus);
    _searchFocusNode.dispose();
    _poolTabController.removeListener(_handlePoolTabChange);
    _poolTabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchFocus() {
    if (!mounted) return;
    if (_isSearchFocused != _searchFocusNode.hasFocus) {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _handlePoolTabChange() {
    if (_poolTabController.indexIsChanging) return;
    final nextCourse = _poolTabController.index == 0 ? 'LC' : 'SC';
    if (_course != nextCourse && mounted) {
      setState(() => _course = nextCourse);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await widget.repository.searchGlobal(trimmed);
        if (mounted) {
          setState(() {
            _searchResults =
                res.athletes.where((a) => a.id != widget.athleteA.id).toList();
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectAthleteB(int id) async {
    setState(() {
      _loadingB = true;
      _errorB = null;
      _lastFailedAthleteId = id;
      _searchResults = [];
      _searchCtrl.clear();
    });
    try {
      final detail = await widget.repository.getAthleteDetail(id);
      if (mounted) {
        setState(() {
          _athleteB = detail;
          _loadingB = false;
          _errorB = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingB = false;
          _errorB = 'Sporcu verisi yüklenemedi.';
        });
      }
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
          child: Column(
            children: [
              _buildHeader(context, palette),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.s20,
                    AppSpacing.xs,
                    AppSpacing.s20,
                    64 +
                        AppSpacing.md +
                        MediaQuery.of(context).padding.bottom +
                        AppSpacing.lg,
                  ),
                  children: [
                    // Üst Sporcu Kartları (A vs B)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildAthleteHeaderCard(
                              palette,
                              widget.athleteA,
                            ),
                          ),
                          Padding(
                            padding: AppSpacing.paddingHorizontalSm,
                            child: Center(
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: palette.textSecondary
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _athleteB != null
                                ? _buildAthleteHeaderCard(
                                    palette,
                                    _athleteB!,
                                    onClear: () => setState(() {
                                      _athleteB = null;
                                      _errorB = null;
                                    }),
                                  )
                                : _buildEmptyBCard(palette),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.vMd,

                    // Sporcu B Arama Kutusu
                    if (_athleteB == null) ...[
                      SoftGlassPanel(
                        level: 3,
                        height: 48,
                        borderRadius: AppRadius.full,
                        padding: AppSpacing.paddingHorizontalMd,
                        animationDuration: const Duration(milliseconds: 180),
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
                              Icons.person_search_outlined,
                              size: 20,
                              color: palette.textSecondary,
                            ),
                            AppSpacing.h12,
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                focusNode: _searchFocusNode,
                                onChanged: _onSearchChanged,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14.5,
                                  color: palette.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Karşılaştırılacak 2. sporcuyu ara...',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 14,
                                    color: palette.textSecondary,
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
                            if (_searching)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_searchResults.isNotEmpty) ...[
                        AppSpacing.vSm,
                        SoftGlassPanel(
                          level: 2,
                          borderRadius: AppRadius.cardRadius,
                          padding: AppSpacing.zero,
                          child: Column(
                            children: _searchResults
                                .take(8)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final idx = entry.key;
                              final item = entry.value;
                              final count = _searchResults.take(8).length;
                              return Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    title: Text(
                                      StringUtils.toTitleCase(item.name),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (item.birthYear != null)
                                          '${item.birthYear}',
                                        StringUtils.toTitleCase(item.clubName),
                                      ].join(' • '),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 12,
                                        color: palette.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Icon(
                                      Icons.add_circle_outline_rounded,
                                      color: palette.accent,
                                      size: 20,
                                    ),
                                    onTap: () => _selectAthleteB(item.id),
                                  ),
                                  if (idx < count - 1)
                                    Divider(height: 1, color: palette.divider),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],

                    if (_loadingB) ...[
                      AppSpacing.vMd,
                      _buildLoadingSkeleton(),
                    ] else if (_errorB != null && _athleteB == null) ...[
                      AppSpacing.vLg,
                      EmptyStateWidget(
                        icon: Icons.error_outline_rounded,
                        title: _errorB!,
                        actionText: 'Tekrar dene',
                        onAction: _lastFailedAthleteId != null
                            ? () => _selectAthleteB(_lastFailedAthleteId!)
                            : null,
                      ),
                    ] else if (_athleteB == null && _searchResults.isEmpty) ...[
                      AppSpacing.vLg,
                      EmptyStateWidget(
                        icon: Icons.compare_arrows_rounded,
                        title: 'Karşılaştırmak için ikinci sporcuyu seç',
                        actionText: 'Sporcu Seç',
                        onAction: () => _searchFocusNode.requestFocus(),
                      ),
                    ],

                    // Karşılaştırma İçeriği
                    if (_athleteB != null && !_loadingB) ...[
                      // Kulvar Seçici (50m / 25m)
                      ModernSegmentedTabBar(
                        controller: _poolTabController,
                        tabs: const [
                          TabItemData(title: '50m Uzun Kulvar'),
                          TabItemData(title: '25m Kısa Kulvar'),
                        ],
                      ),
                      AppSpacing.vMd,

                      // Kariyer Özeti Karşılaştırması (ONE level 1 surface)
                      _buildStatsComparisonCard(
                        palette,
                        widget.athleteA,
                        _athleteB!,
                      ),
                      AppSpacing.vMd,

                      // Branş Bazlı PB Karşılaştırma Tablosu (ONE level 2 surface)
                      _buildPbComparisonTable(
                        palette,
                        widget.athleteA,
                        _athleteB!,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GlassCircleButton(
            icon: Icons.arrow_back_outlined,
            iconSize: 20,
            iconColor: palette.textTertiary,
            tooltip: 'Geri',
            onTap: () => Navigator.maybePop(context),
          ),
          AppSpacing.hSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Türkiye Yüzme Federasyonu',
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
                const SizedBox(height: 2),
                Text(
                  'Sporcu Karşılaştırma',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.15,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 140),
        AppSpacing.vMd,
        AppSkeleton.card(height: 260),
      ],
    );
  }

  Widget _buildAthleteHeaderCard(
    AppColorPalette palette,
    AthleteDetail a, {
    VoidCallback? onClear,
  }) {
    return SoftGlassPanel(
      level: 3,
      borderRadius: AppRadius.cardRadius,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.xs,
        AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: onClear == null ? AppSpacing.sm : 0,
                  ),
                  child: Text(
                    StringUtils.toTitleCase(a.name),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (onClear != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    onPressed: onClear,
                    tooltip: 'Kaldır',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          AppSpacing.vXs,
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(
              [
                if (a.birthYear != null) '${a.birthYear}',
                if (a.clubName != null && a.clubName!.isNotEmpty)
                  StringUtils.toTitleCase(a.clubName!),
              ].join(' • '),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: palette.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBCard(AppColorPalette palette) {
    return SoftGlassPanel(
      level: 3,
      borderRadius: AppRadius.cardRadius,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '2. Sporcu Seçin',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.vXs,
          Text(
            'Aşağıdan arayın',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              color: palette.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsComparisonCard(
    AppColorPalette palette,
    AthleteDetail a,
    AthleteDetail b,
  ) {
    Widget statValue(int value, bool isWinner, {required bool alignRight}) {
      return SizedBox(
        width: 78,
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment:
                alignRight ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWinner && alignRight) ...[
                  Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: palette.successText,
                  ),
                  AppSpacing.hXs,
                ],
                Text(
                  '$value',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
                    color:
                        isWinner ? palette.successText : palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (isWinner && !alignRight) ...[
                  AppSpacing.hXs,
                  Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: palette.successText,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    Widget rowItem(String label, int valA, int valB) {
      final total = valA + valB;
      final ratioA = total > 0 ? (valA / total).clamp(0.0, 1.0) : 0.5;
      final ratioB = total > 0 ? (valB / total).clamp(0.0, 1.0) : 0.5;
      final colorA =
          valA > valB ? palette.successText : palette.accent.withValues(alpha: 0.65);
      final colorB =
          valB > valA ? palette.successText : palette.accent.withValues(alpha: 0.65);

      return Padding(
        padding: AppSpacing.paddingVerticalSm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                statValue(valA, valA > valB, alignRight: false),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                statValue(valB, valB > valA, alignRight: true),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.progressTrack,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: ratioA,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorA,
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
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.progressTrack,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ratioB,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorB,
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
      level: 1,
      borderRadius: AppRadius.cardRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        children: [
          rowItem('Toplam Yarış', a.stats.totalRaces, b.stats.totalRaces),
          Divider(height: 1, color: palette.divider),
          rowItem('Kürsü', a.stats.podiumCount, b.stats.podiumCount),
          Divider(height: 1, color: palette.divider),
          rowItem(
            'Geçilen Baraj',
            a.stats.standardsPassed,
            b.stats.standardsPassed,
          ),
        ],
      ),
    );
  }

  Widget _buildPbComparisonTable(
    AppColorPalette palette,
    AthleteDetail a,
    AthleteDetail b,
  ) {
    final pbsA = _course == 'SC' ? a.pbs25m : a.pbs50m;
    final pbsB = _course == 'SC' ? b.pbs25m : b.pbs50m;

    final mapA = <String, PersonalBest>{};
    for (final p in pbsA) {
      mapA['${p.stroke}_${p.distance}'] = p;
    }
    final mapB = <String, PersonalBest>{};
    for (final p in pbsB) {
      mapB['${p.stroke}_${p.distance}'] = p;
    }

    final allKeys = <String>{...mapA.keys, ...mapB.keys}.toList();
    const order = {'free': 1, 'back': 2, 'breast': 3, 'fly': 4, 'medley': 5};
    allKeys.sort((k1, k2) {
      final p1 = mapA[k1] ?? mapB[k1]!;
      final p2 = mapA[k2] ?? mapB[k2]!;
      final o1 = order[p1.stroke] ?? 9;
      final o2 = order[p2.stroke] ?? 9;
      if (o1 != o2) return o1.compareTo(o2);
      return p1.distance.compareTo(p2.distance);
    });

    if (allKeys.isEmpty) {
      return SoftGlassPanel(
        level: 2,
        borderRadius: AppRadius.cardRadius,
        padding: AppSpacing.paddingAllLg,
        child: Text(
          'Seçili kulvarda karşılaştırılacak PB derecesi bulunamadı.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: palette.textSecondary,
          ),
        ),
      );
    }

    Widget timeCell(
      int? timeCs,
      bool isFaster, {
      required bool alignRight,
    }) {
      if (timeCs == null) {
        return Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            '–',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      }

      return Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFaster && alignRight)
                Icon(
                  Icons.arrow_drop_down_outlined,
                  size: 18,
                  color: palette.successText,
                ),
              Text(
                SwimTimeFormatter.formatCs(timeCs),
                maxLines: 1,
                softWrap: false,
                style: AppTextStyles.officialTime.copyWith(
                  fontSize: 16,
                  fontWeight: isFaster ? FontWeight.w700 : FontWeight.w600,
                  color: isFaster ? palette.successText : palette.textPrimary,
                ),
              ),
              if (isFaster && !alignRight)
                Icon(
                  Icons.arrow_drop_down_outlined,
                  size: 18,
                  color: palette.successText,
                ),
            ],
          ),
        ),
      );
    }

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      padding: AppSpacing.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timeColWidth = (constraints.maxWidth - AppSpacing.s12 * 2) * 0.30;

          return Column(
            children: allKeys.asMap().entries.map((entry) {
              final idx = entry.key;
              final key = entry.value;
              final pa = mapA[key];
              final pb = mapB[key];
              final sample = pa ?? pb!;
              final csA = pa?.timeCs;
              final csB = pb?.timeCs;
              final bool bothHave = csA != null && csB != null;
              final bool aFaster = bothHave && csA < csB;
              final bool bFaster = bothHave && csB < csA;

              String diffStr = '';
              if (bothHave) {
                final diff = (csA - csB).abs() / 100.0;
                if (csA == csB) {
                  diffStr = '0.00 s';
                } else {
                  diffStr = '${aFaster ? '-' : '+'}${diff.toStringAsFixed(2)} s';
                }
              }

              return Column(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: timeColWidth,
                            child: timeCell(csA, aFaster, alignRight: false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: AppSpacing.paddingHorizontalSm,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${sample.distance}m ${sample.strokeLabel}',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  if (diffStr.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      diffStr,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: aFaster
                                            ? palette.successText
                                            : (bFaster
                                                ? palette.statusDanger
                                                : palette.textSecondary),
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: timeColWidth,
                            child: timeCell(csB, bFaster, alignRight: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (idx < allKeys.length - 1)
                    Divider(height: 1, color: palette.divider),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
