import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';
import '../../shared/widgets/status_badge.dart';
import 'athlete_compare_screen.dart';
import 'widgets/pb_history_sheet.dart';

const double _profileTabBarHeight = 46;
const double _profileActionButtonOffset = (28 * 1.15 - 40) / 2;

/// Sporcu Profili, Kişisel En İyi Dereceler (PB) ve Scout Analizi Ekranı
class AthleteProfileScreen extends StatefulWidget {
  final int athleteId;
  final String athleteName;
  final SwimRepository repository;

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.repository,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  AthleteDetail? _athlete;
  bool _isFavorite = false;
  late TabController _tabController;
  int _selectedCourseIndex = 0; // 0: 50m Uzun Kulvar, 1: 25m Kısa Kulvar

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isFavorite = FavoriteAthletesService.instance.isFavorite(widget.athleteId);
    FavoriteAthletesService.instance.addListener(_onFavoritesChanged);
    _loadAthleteData();
  }

  @override
  void dispose() {
    FavoriteAthletesService.instance.removeListener(_onFavoritesChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    final fav = FavoriteAthletesService.instance.isFavorite(widget.athleteId);
    if (mounted && fav != _isFavorite) {
      setState(() => _isFavorite = fav);
    }
  }

  Future<void> _loadAthleteData() async {
    setState(() => _isLoading = true);
    try {
      final athlete = await widget.repository.getAthleteDetail(widget.athleteId);
      if (mounted) {
        setState(() {
          _athlete = athlete;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final added =
        await FavoriteAthletesService.instance.toggleFavorite(widget.athleteId);
    if (!mounted) return;
    setState(() => _isFavorite = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Sporcu favorilere eklendi.'
              : 'Sporcu favorilerden çıkarıldı.',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
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
              ? _buildLoadingSkeleton(context)
              : _athlete == null
                  ? Center(
                      child: EmptyStateWidget(
                        title: 'Sporcu bilgileri yüklenemedi',
                        message:
                            'Lütfen bağlantınızı kontrol edip tekrar deneyin.',
                        icon: Icons.error_outline,
                        actionText: 'Tekrar Dene',
                        onAction: _loadAthleteData,
                      ),
                    )
                  : NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.s20,
                              AppSpacing.s12,
                              AppSpacing.s20,
                              AppSpacing.md,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(palette, _athlete!),
                                AppSpacing.vLg,
                                _buildProfileHero(palette, _athlete!),
                              ],
                            ),
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _PinnedTabBarDelegate(
                            extent: _profileTabBarHeight + AppSpacing.xs * 2,
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s20,
                                vertical: AppSpacing.xs,
                              ),
                              child: ModernSegmentedTabBar(
                                controller: _tabController,
                                height: _profileTabBarHeight,
                                tabs: const [
                                  TabItemData(
                                    title: 'Best Time',
                                    icon: Icons.timer_outlined,
                                  ),
                                  TabItemData(
                                    title: 'Scout Analizi',
                                    icon: Icons.insights_outlined,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBestTimesTab(context, palette, _athlete!),
                          _buildScoutAnalysisTab(context, palette, _athlete!),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
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
        const AppSkeleton.line(width: 240, height: 28),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 164),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 46, borderRadius: AppRadius.chipRadius),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 120),
        AppSpacing.v12,
        const AppSkeleton.card(height: 120),
      ],
    );
  }

  /// Editoryal Üst Başlık (Kulüp etiketi, 28 w700 sporcu adı, Level 3 aksiyon butonları)
  Widget _buildHeader(AppColorPalette palette, AthleteDetail a) {
    final rawClub = a.clubName?.trim() ?? '';
    final clubName = rawClub.isNotEmpty
        ? (rawClub == rawClub.toUpperCase()
            ? StringUtils.toTitleCase(rawClub)
            : rawClub)
        : 'Ferdi Sporcu';
    final athleteName = StringUtils.toTitleCase(a.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 40 + AppSpacing.sm),
            Expanded(
              child: Text(
                clubName,
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
              offset: const Offset(0, _profileActionButtonOffset),
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
                athleteName,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: palette.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppSpacing.hSm,
            Transform.translate(
              offset: const Offset(0, _profileActionButtonOffset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassCircleButton(
                    icon: Icons.compare_arrows_outlined,
                    iconSize: 20,
                    iconColor: palette.textTertiary,
                    tooltip: 'Karşılaştır',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AthleteCompareScreen(
                            athleteA: a,
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                  ),
                  AppSpacing.hSm,
                  GlassCircleButton(
                    icon: _isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    iconColor:
                        _isFavorite ? palette.accent : palette.textTertiary,
                    iconSize: 20,
                    tooltip: _isFavorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
                    onTap: _toggleFavorite,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Level 1 Profil Hero Paneli
  Widget _buildProfileHero(AppColorPalette palette, AthleteDetail a) {
    final athleteName = StringUtils.toTitleCase(a.name);
    final initials = athleteName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final clubName = (a.clubName != null && a.clubName!.trim().isNotEmpty)
        ? StringUtils.toTitleCase(a.clubName!)
        : 'Ferdi Sporcu';

    final metaItems = <String>[];
    if (a.birthYear != null) metaItems.add('${a.birthYear}');
    if (a.age != null) metaItems.add('${a.age} Yaş');
    if (a.gender.isNotEmpty) {
      metaItems.add(
        a.gender == 'M'
            ? 'Erkek'
            : a.gender == 'F'
                ? 'Kadın'
                : StringUtils.toTitleCase(a.gender),
      );
    }
    final metaText = metaItems.join(' · ');

    final allPbs = [...a.pbs50m, ...a.pbs25m];
    int bestFina = 0;
    for (final pb in allPbs) {
      if ((pb.points ?? 0) > bestFina) {
        bestFina = pb.points!;
      }
    }

    return SoftGlassPanel(
      level: 1,
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: AppRadius.rounded,
      padding: AppSpacing.cardPadding,
      artStyle: AmbientArtStyle.none,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.isEmpty ? 'SP' : initials,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
              ),
              AppSpacing.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metaText.isNotEmpty ? metaText : clubName,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AppSpacing.vXs,
                    Text(
                      'Kürsü Oranı %${a.stats.podiumRate.toStringAsFixed(0)}',
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
                ),
              ),
              if (bestFina > 0) ...[
                AppSpacing.hSm,
                StatusBadge(
                  label: '$bestFina FINA',
                  variant: StatusBadgeVariant.info,
                ),
              ],
            ],
          ),
          AppSpacing.v20,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _buildHeroMetric(
                  palette: palette,
                  label: 'Toplam Yarış',
                  value: '${a.stats.totalRaces}',
                ),
              ),
              _buildHeroDivider(palette),
              Expanded(
                child: _buildHeroMetric(
                  palette: palette,
                  label: 'Kürsü',
                  value: '${a.stats.podiumCount}',
                ),
              ),
              _buildHeroDivider(palette),
              Expanded(
                child: _buildHeroMetric(
                  palette: palette,
                  label: 'Baraj',
                  value: '${a.stats.standardsPassed}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required AppColorPalette palette,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 46,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.0,
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          AppSpacing.vXs,
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w400,
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
      height: 36,
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

  /// 1. SEKME: Best Times (Kişisel En İyi Dereceler - Stile Göre Gruplanmış Tablo)
  Widget _buildBestTimesTab(
    BuildContext context,
    AppColorPalette palette,
    AthleteDetail a,
  ) {
    final pbs = _selectedCourseIndex == 0 ? a.pbs50m : a.pbs25m;
    final courseLabel =
        _selectedCourseIndex == 0 ? '50m Uzun Kulvar' : '25m Kısa Kulvar';
    final groupedPbs = _groupPbsByStroke(pbs);
    final chip50 = '50m Uzun Kulvar (${a.pbs50m.length})';
    final chip25 = '25m Kısa Kulvar (${a.pbs25m.length})';
    final selectedChip = _selectedCourseIndex == 0 ? chip50 : chip25;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s20,
            AppSpacing.s12,
            AppSpacing.s20,
            AppSpacing.s12,
          ),
          child: ModernFilterChipBar(
            chips: [
              FilterChipItem(label: chip50),
              FilterChipItem(label: chip25),
            ],
            selectedChip: selectedChip,
            onSelected: (label) {
              setState(() {
                _selectedCourseIndex = label == chip50 ? 0 : 1;
              });
            },
          ),
        ),
        Expanded(
          child: groupedPbs.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.s20,
                      AppSpacing.sm,
                      AppSpacing.s20,
                      64 +
                          AppSpacing.md +
                          MediaQuery.of(context).padding.bottom +
                          AppSpacing.lg,
                    ),
                    child: EmptyStateWidget(
                      title: 'Kayıtlı PB Bulunamadı',
                      message:
                          '$courseLabel için henüz onaylanmış kişisel en iyi derece bulunmuyor.',
                      icon: Icons.timer_outlined,
                      compact: true,
                    ),
                  ),
                )
              : ListView(
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
                    for (int i = 0; i < groupedPbs.length; i++) ...[
                      if (i > 0) AppSpacing.v12,
                      _buildStrokeSection(
                        palette,
                        groupedPbs.keys.elementAt(i),
                        groupedPbs.values.elementAt(i),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// PBs listesini yüzme stiline (Serbest, Sırtüstü, Kurbağalama vb.) göre gruplar ve mesafeye göre sıralar
  Map<String, List<PersonalBest>> _groupPbsByStroke(List<PersonalBest> pbs) {
    final Map<String, List<PersonalBest>> grouped = {};
    for (final pb in pbs) {
      final key = pb.strokeLabel.isNotEmpty
          ? pb.strokeLabel
          : (pb.stroke.isNotEmpty ? pb.stroke : 'Diğer');
      grouped.putIfAbsent(key, () => []).add(pb);
    }

    // Her stil içindeki mesafeleri küçükten büyüğe sırala (50, 100, 200, 400...)
    for (final list in grouped.values) {
      list.sort((x, y) => x.distance.compareTo(y.distance));
    }

    // Geleneksel yüzme branş sırası
    const preferredOrder = [
      'Serbest',
      'Sırtüstü',
      'Kurbağalama',
      'Kelebek',
      'Karışık',
      'Freestyle',
      'Backstroke',
      'Breaststroke',
      'Butterfly',
      'Medley',
      'Individual Medley',
    ];

    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        int indexA = preferredOrder.indexOf(a.key);
        int indexB = preferredOrder.indexOf(b.key);
        if (indexA == -1) indexA = 999;
        if (indexB == -1) indexB = 999;
        final comp = indexA.compareTo(indexB);
        return comp != 0 ? comp : a.key.compareTo(b.key);
      });

    return Map.fromEntries(sortedEntries);
  }

  /// Belirli bir stil altındaki mesafeleri Level 2 cam kart içinde saran kutucuklar olarak gösterir
  Widget _buildStrokeSection(
    AppColorPalette palette,
    String strokeName,
    List<PersonalBest> strokePbs,
  ) {
    final isDark = palette.isDark;
    final tileFill = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : palette.textPrimary.withValues(alpha: 0.05);
    final tileBorderColor =
        Colors.white.withValues(alpha: isDark ? 0.10 : 0.25);
    final chipFill = Colors.white.withValues(alpha: isDark ? 0.09 : 0.14);
    final chipBorder = Colors.white.withValues(alpha: isDark ? 0.16 : 0.25);

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: AppRadius.full,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  strokeName,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppSpacing.hSm,
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: chipFill,
                  borderRadius: AppRadius.full,
                  border: Border.all(color: chipBorder, width: 1.0),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${strokePbs.length} Derece',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.v12,
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = AppSpacing.sm;
              final columns = ((constraints.maxWidth + spacing) / 100)
                  .floor()
                  .clamp(3, 6);
              final tileWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: strokePbs.map((pb) {
                  return SizedBox(
                    width: tileWidth,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: AppRadius.medium,
                        onTap: () => PbHistorySheet.show(
                          context,
                          athleteId: widget.athleteId,
                          pb: pb,
                          strokeLabel: strokeName,
                          repository: widget.repository,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Container(
                            decoration: BoxDecoration(
                              color: tileFill,
                              borderRadius: AppRadius.medium,
                              border: Border.all(
                                color: tileBorderColor,
                                width: 1.0,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: palette.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.s12,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${pb.distance}m',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: palette.textSecondary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        AppSpacing.vXs,
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            SwimTimeFormatter.formatCs(
                                              pb.timeCs,
                                            ),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (pb.points != null) ...[
                                          AppSpacing.vXs,
                                          Text(
                                            '${pb.points} FINA',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: palette.accent,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 2. SEKME: Scout Analizi (Teknik Gözlem, Podyum Dönüşümü, Zirve Performans)
  Widget _buildScoutAnalysisTab(
    BuildContext context,
    AppColorPalette palette,
    AthleteDetail a,
  ) {
    final allPbs = [...a.pbs50m, ...a.pbs25m];
    allPbs.sort((x, y) => (y.points ?? 0).compareTo(x.points ?? 0));
    final peakPb = allPbs.isNotEmpty && (allPbs.first.points ?? 0) > 0
        ? allPbs.first
        : null;

    final podiumRatio = (a.stats.podiumRate / 100.0).clamp(0.0, 1.0);

    return ListView(
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
        // 1. Scout Teknik Değerlendirme Raporu
        const SectionHeader(
          title: 'Scout Analiz Raporu',
          trailingText: 'Teknik Rapor',
        ),
        AppSpacing.v12,
        SoftGlassPanel(
          level: 2,
          borderRadius: AppRadius.cardRadius,
          padding: AppSpacing.cardPadding,
          child: a.scoutNote.isNotEmpty
              ? Container(
                  width: double.infinity,
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: palette.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: AppRadius.medium,
                    border: Border(
                      left: BorderSide(
                        color: palette.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    a.scoutNote,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      height: 1.5,
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                )
              : Text(
                  'Bu sporcu için henüz kayıtlı bir scout analiz veya teknik gözlem raporu bulunmuyor.',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
        ),
        AppSpacing.vLg,

        // 2. Kariyer Verimliliği & Kürsü Dönüşüm Analizi
        const SectionHeader(title: 'Kariyer Verimliliği'),
        AppSpacing.v12,
        SoftGlassPanel(
          level: 2,
          borderRadius: AppRadius.cardRadius,
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kürsüye Çıkma Oranı',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13.5,
                        color: palette.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppSpacing.hSm,
                  Text(
                    '%${a.stats.podiumRate.toStringAsFixed(1)}',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: palette.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              AppSpacing.vSm,
              ClipRRect(
                borderRadius: AppRadius.full,
                child: LinearProgressIndicator(
                  value: podiumRatio,
                  minHeight: 8,
                  backgroundColor: palette.progressTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                ),
              ),
              AppSpacing.vMd,
              Divider(color: palette.divider, height: 1),
              AppSpacing.v12,
              Row(
                children: [
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Yarış / Start',
                    value: '${a.stats.totalRaces}',
                  ),
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Madalya / Kürsü',
                    value: '${a.stats.podiumCount}',
                  ),
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Geçilen Baraj',
                    value: '${a.stats.standardsPassed}',
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Zirve Performans (En Yüksek FINA Puanı)
        if (peakPb != null) ...[
          AppSpacing.vLg,
          SectionHeader(
            title: 'Zirve Performans',
            trailingText: '${peakPb.points} FINA',
          ),
          AppSpacing.v12,
          SoftGlassPanel(
            level: 2,
            borderRadius: AppRadius.cardRadius,
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${peakPb.distance}m ${peakPb.strokeLabel}',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: palette.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppSpacing.h12,
                    Text(
                      SwimTimeFormatter.formatCs(peakPb.timeCs),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: palette.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                AppSpacing.vXs,
                Text(
                  '${peakPb.course == 'SC' ? '25m Kısa Kulvar' : '50m Uzun Kulvar'} · ${StringUtils.toTitleCase(peakPb.meetName)} (${peakPb.date})',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricDetail({
    required AppColorPalette palette,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sabit TabBar için SliverPersistentHeaderDelegate
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;

  _PinnedTabBarDelegate({
    required this.child,
    required this.extent,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) {
    return child != oldDelegate.child || extent != oldDelegate.extent;
  }
}
