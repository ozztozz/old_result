import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/components/app_card.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/athlete.dart';

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
    _loadAthleteData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFavorite
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

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: palette.primary,
                ),
              )
            : _athlete == null
                ? Center(
                    child: EmptyStateWidget(
                      title: 'Sporcu bilgileri yüklenemedi',
                      message: 'Lütfen bağlantınızı kontrol edip tekrar deneyin.',
                      icon: Icons.error_outline_rounded,
                      actionText: 'Tekrar Dene',
                      onAction: _loadAthleteData,
                    ),
                  )
                : NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.sm,
                            AppSpacing.md,
                            AppSpacing.xs,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTopBar(palette),
                              AppSpacing.vSm,
                              _buildProfileCard(palette, _athlete!),
                              AppSpacing.vSm,
                            ],
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedTabBarDelegate(
                          tabBar: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicator: BoxDecoration(
                              color: palette.surface,
                              borderRadius: AppRadius.full,
                              boxShadow: [
                                BoxShadow(
                                  color: palette.textPrimary.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            labelColor: palette.textPrimary,
                            unselectedLabelColor: palette.textSecondary,
                            labelStyle: AppTextStyles.tabSelected.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle: AppTextStyles.tabUnselected,
                            tabs: const [
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.timer_outlined, size: 16),
                                    SizedBox(width: 6),
                                    Text('Best Time'),
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.insights_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('Scout Analizi'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: palette.background,
                          borderColor: palette.border,
                          surfaceSecondary: palette.surfaceSecondary,
                        ),
                      ),
                    ],
                    body: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBestTimesTab(palette, _athlete!),
                        _buildScoutAnalysisTab(palette, _athlete!),
                      ],
                    ),
                  ),
      ),
    );
  }

  /// Üst Navigasyon Çubuğu (Geri Dön ve Favori Butonları)
  Widget _buildTopBar(AppColorPalette palette) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCircleButton(
          palette: palette,
          icon: Icons.arrow_back_ios_new_rounded,
          iconSize: 16,
          onTap: () => Navigator.maybePop(context),
        ),
        _buildCircleButton(
          palette: palette,
          icon: _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          iconColor: _isFavorite ? palette.gold : palette.textPrimary,
          iconSize: 20,
          onTap: _toggleFavorite,
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required AppColorPalette palette,
    required IconData icon,
    required VoidCallback onTap,
    double iconSize = 18,
    Color? iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: palette.surface,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: palette.textPrimary.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? palette.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Sporcu Başlık ve Hızlı Kariyer Kartı
  Widget _buildProfileCard(AppColorPalette palette, AthleteDetail a) {
    final initials = a.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final clubName = (a.clubName != null && a.clubName!.isNotEmpty)
        ? a.clubName!
        : 'Ferdi Sporcu';

    final metaItems = <String>[];
    if (a.birthYear != null) metaItems.add('${a.birthYear}');
    if (a.age != null) metaItems.add('${a.age} Yaş');
    if (a.gender.isNotEmpty) {
      metaItems.add(a.gender == 'M' ? 'Erkek' : a.gender == 'F' ? 'Kadın' : a.gender);
    }
    final metaText = metaItems.join(' · ');

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
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
                      a.name,
                      style: AppTextStyles.raceTitle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      clubName,
                      style: AppTextStyles.clubName.copyWith(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (metaText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        metaText,
                        style: AppTextStyles.labelMuted.copyWith(
                          fontSize: 11,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vSm,
          Divider(color: palette.divider, height: 1),
          AppSpacing.vSm,
          // Hızlı Metrik Özeti
          Row(
            children: [
              _buildMiniMetric(
                palette: palette,
                label: 'Toplam Yarış',
                value: '${a.stats.totalRaces}',
              ),
              Container(
                width: 1,
                height: 24,
                color: palette.divider,
              ),
              _buildMiniMetric(
                palette: palette,
                label: 'Kürsü',
                value: '${a.stats.podiumCount}',
                subValue: '(%${a.stats.podiumRate.toStringAsFixed(0)})',
              ),
              Container(
                width: 1,
                height: 24,
                color: palette.divider,
              ),
              _buildMiniMetric(
                palette: palette,
                label: 'Baraj',
                value: '${a.stats.standardsPassed}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required AppColorPalette palette,
    required String label,
    required String value,
    String? subValue,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTextStyles.metricHero.copyWith(
                  fontSize: 16,
                  color: palette.textPrimary,
                ),
              ),
              if (subValue != null) ...[
                const SizedBox(width: 3),
                Text(
                  subValue,
                  style: AppTextStyles.labelMuted.copyWith(
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelMuted.copyWith(
              fontSize: 11,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 1. SEKME: Best Times (Kişisel En İyi Dereceler - Stile Göre Gruplanmış Compact Görünüm)
  Widget _buildBestTimesTab(AppColorPalette palette, AthleteDetail a) {
    final pbs = _selectedCourseIndex == 0 ? a.pbs50m : a.pbs25m;
    final courseLabel = _selectedCourseIndex == 0 ? '50m Uzun Kulvar' : '25m Kısa Kulvar';
    final groupedPbs = _groupPbsByStroke(pbs);

    return Column(
      children: [
        // Kulvar Seçici Segmented Pill
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: AppRadius.full,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildCourseFilterButton(
                    palette: palette,
                    title: '50m Uzun Kulvar',
                    count: a.pbs50m.length,
                    isSelected: _selectedCourseIndex == 0,
                    onTap: () => setState(() => _selectedCourseIndex = 0),
                  ),
                ),
                Expanded(
                  child: _buildCourseFilterButton(
                    palette: palette,
                    title: '25m Kısa Kulvar',
                    count: a.pbs25m.length,
                    isSelected: _selectedCourseIndex == 1,
                    onTap: () => setState(() => _selectedCourseIndex = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Stile Göre Gruplanmış Compact PB Kartı
        Expanded(
          child: groupedPbs.isEmpty
              ? Center(
                  child: EmptyStateWidget(
                    title: 'Kayıtlı PB Bulunamadı',
                    message: '$courseLabel için henüz onaylanmış kişisel en iyi derece bulunmuyor.',
                    icon: Icons.timer_outlined,
                    compact: true,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < groupedPbs.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Divider(color: palette.divider, height: 1),
                            ),
                          _buildStrokeSection(
                            palette,
                            groupedPbs.keys.elementAt(i),
                            groupedPbs.values.elementAt(i),
                          ),
                        ],
                      ],
                    ),
                  ),
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

  /// Belirli bir stil altındaki mesafeleri kompakt yan yana hücreler halinde gösterir
  Widget _buildStrokeSection(
    AppColorPalette palette,
    String strokeName,
    List<PersonalBest> strokePbs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getStrokeIcon(strokeName),
              size: 14,
              color: palette.primary,
            ),
            const SizedBox(width: 6),
            Text(
              strokeName,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${strokePbs.length} Derece',
              style: AppTextStyles.labelMuted.copyWith(
                color: palette.textSecondary,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: strokePbs.map((pb) {
              return Container(
                constraints: const BoxConstraints(minWidth: 72),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary.withValues(alpha: 0.6),
                  borderRadius: AppRadius.smallRadius,
                  border: Border.all(
                    color: palette.border,
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mesafe (50m, 100m, 400m vb.)
                    Text(
                      '${pb.distance}m',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Derece (24.95 vb.)
                    Text(
                      SwimTimeFormatter.formatCs(pb.timeCs),
                      style: AppTextStyles.officialTime.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (pb.points != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${pb.points} FINA',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: palette.gold,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  IconData _getStrokeIcon(String stroke) {
    final lower = stroke.toLowerCase();
    if (lower.contains('serbest') || lower.contains('freestyle')) {
      return Icons.waves_rounded;
    } else if (lower.contains('sırt') || lower.contains('back')) {
      return Icons.water_rounded;
    } else if (lower.contains('kurbağa') || lower.contains('breast')) {
      return Icons.sports_rounded;
    } else if (lower.contains('kelebek') || lower.contains('fly') || lower.contains('butterfly')) {
      return Icons.speed_rounded;
    } else if (lower.contains('karışık') || lower.contains('medley') || lower.contains('im')) {
      return Icons.auto_awesome_rounded;
    }
    return Icons.pool_rounded;
  }

  Widget _buildCourseFilterButton({
    required AppColorPalette palette,
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? palette.surface : Colors.transparent,
          borderRadius: AppRadius.full,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.textPrimary.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          '$title ($count)',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? palette.textPrimary : palette.textSecondary,
          ),
        ),
      ),
    );
  }

  /// 2. SEKME: Scout Analizi (Teknik Gözlem, Podyum Dönüşümü, Zirve Performans)
  Widget _buildScoutAnalysisTab(AppColorPalette palette, AthleteDetail a) {
    // Tüm PB'ler arasından en yüksek FINA puanlı zirve dereceyi bul
    final allPbs = [...a.pbs50m, ...a.pbs25m];
    allPbs.sort((x, y) => (y.points ?? 0).compareTo(x.points ?? 0));
    final peakPb = allPbs.isNotEmpty && (allPbs.first.points ?? 0) > 0
        ? allPbs.first
        : null;

    final podiumRatio = (a.stats.podiumRate / 100.0).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Scout Teknik Değerlendirme Raporu
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.primaryContainer,
                        borderRadius: AppRadius.smallRadius,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.rate_review_outlined,
                        size: 18,
                        color: palette.primary,
                      ),
                    ),
                    AppSpacing.hSm,
                    Text(
                      'Scout Analiz Raporu',
                      style: AppTextStyles.raceTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.primaryContainer,
                        borderRadius: AppRadius.badgeRadius,
                      ),
                      child: Text(
                        'Teknik Rapor',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: palette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.vMd,
                if (a.scoutNote.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.surfaceSecondary.withValues(alpha: 0.5),
                      borderRadius: AppRadius.medium,
                      border: Border(
                        left: BorderSide(
                          color: palette.primary,
                          width: 3.5,
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
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(
                      'Bu sporcu için henüz kayıtlı bir scout analiz veya teknik gözlem raporu bulunmuyor.',
                      style: AppTextStyles.labelMuted.copyWith(
                        color: palette.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          AppSpacing.vMd,

          // 2. Kariyer Verimliliği & Kürsü Dönüşüm Analizi
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.primaryContainer,
                        borderRadius: AppRadius.smallRadius,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.insights_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                    ),
                    AppSpacing.hSm,
                    Text(
                      'Kariyer Verimliliği',
                      style: AppTextStyles.raceTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                AppSpacing.vMd,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Kürsüye Çıkma Oranı',
                      style: AppTextStyles.athleteName.copyWith(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    Text(
                      '%${a.stats.podiumRate.toStringAsFixed(1)}',
                      style: AppTextStyles.officialTime.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: AppRadius.full,
                  child: LinearProgressIndicator(
                    value: podiumRatio,
                    minHeight: 8,
                    backgroundColor: palette.surfaceSecondary,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                  ),
                ),
                AppSpacing.vMd,
                Divider(color: palette.divider, height: 1),
                AppSpacing.vSm,
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
            AppSpacing.vMd,
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: palette.goldBg,
                          borderRadius: AppRadius.smallRadius,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.military_tech_rounded,
                          size: 18,
                          color: palette.gold,
                        ),
                      ),
                      AppSpacing.hSm,
                      Text(
                        'Zirve Performans',
                        style: AppTextStyles.raceTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.goldBg,
                          borderRadius: AppRadius.badgeRadius,
                        ),
                        child: Text(
                          '${peakPb.points} FINA',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: palette.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.vSm,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${peakPb.distance}m ${peakPb.strokeLabel}',
                        style: AppTextStyles.athleteName.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        SwimTimeFormatter.formatCs(peakPb.timeCs),
                        style: AppTextStyles.officialTime.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${peakPb.course == 'SC' ? '25m Kısa Kulvar' : '50m Uzun Kulvar'} · ${peakPb.meetName} (${peakPb.date})',
                    style: AppTextStyles.labelMuted.copyWith(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
            style: AppTextStyles.metricHero.copyWith(
              fontSize: 15,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTextStyles.labelMuted.copyWith(
              fontSize: 10.5,
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
  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;
  final Color surfaceSecondary;

  _PinnedTabBarDelegate({
    required this.tabBar,
    required this.backgroundColor,
    required this.borderColor,
    required this.surfaceSecondary,
  });

  @override
  double get minExtent => tabBar.preferredSize.height + 16.0;

  @override
  double get maxExtent => tabBar.preferredSize.height + 16.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        height: tabBar.preferredSize.height + 8.0,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: surfaceSecondary,
          borderRadius: AppRadius.full,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor ||
        borderColor != oldDelegate.borderColor ||
        surfaceSecondary != oldDelegate.surfaceSecondary;
  }
}
