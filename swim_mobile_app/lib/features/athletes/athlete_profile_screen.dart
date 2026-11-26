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
import '../../data/models/baraj_rule.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/baraj_event_selector.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';
import 'athlete_compare_screen.dart';
import 'widgets/pb_history_sheet.dart';

const double _profileTabBarHeight = 46;

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
  List<Map<String, dynamic>> _barajTargets = [];
  List<BarajEventOption> _barajEventCatalog = [];
  String _selectedBarajMeet = '';
  String _selectedBarajCity = '';
  String _selectedBarajMonth = '';
  String _selectedBarajType = 'Katılım Barajı';
  bool _isFavorite = false;
  late TabController _tabController;
  int _selectedCourseIndex = 0; // 0: 50m Uzun Kulvar, 1: 25m Kısa Kulvar

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final results = await Future.wait([
        widget.repository.getAthleteDetail(widget.athleteId),
        widget.repository
            .getAthleteBarajTargets(widget.athleteId)
            .catchError((_) => <Map<String, dynamic>>[]),
        widget.repository
            .getBarajlar()
            .then((r) => r.events)
            .catchError((_) => <BarajEventOption>[]),
      ]);
      if (mounted) {
        setState(() {
          _athlete = results[0] as AthleteDetail;
          _barajTargets = results[1] as List<Map<String, dynamic>>;
          _barajEventCatalog = results[2] as List<BarajEventOption>;
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
                                    title: 'Barajlar',
                                    icon: Icons.flag_outlined,
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
                          _buildBarajlarTab(context, palette),
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

  /// Editoryal Üst Başlık (Geri, SPORCU PROFİLİ etiketi, aksiyon butonları)
  Widget _buildHeader(AppColorPalette palette, AthleteDetail a) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GlassCircleButton(
          icon: Icons.arrow_back_outlined,
          iconSize: 20,
          iconColor: palette.textPrimary,
          tooltip: 'Geri',
          onTap: () => Navigator.maybePop(context),
        ),
        AppSpacing.hMd,
        Expanded(
          child: Text(
            'SPORCU PROFİLİ',
            style: TextStyle(
              fontFamily: AppTextStyles.displayFontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppSpacing.hSm,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassCircleButton(
              icon: Icons.compare_arrows_outlined,
              iconSize: 20,
              iconColor: palette.textPrimary,
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
              iconColor: _isFavorite ? palette.statusWarning : palette.textPrimary,
              iconSize: 20,
              tooltip: _isFavorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
              onTap: _toggleFavorite,
            ),
          ],
        ),
      ],
    );
  }

  /// Level 1 Profil Hero Paneli
  Widget _buildProfileHero(AppColorPalette palette, AthleteDetail a) {
    final athleteName = StringUtils.formatAthleteName(a.name);
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

    final hasPodium = a.stats.podiumCount > 0;
    final onContrast = palette.textOnContrast;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContrast,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: AppSpacing.cardPadding,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.primary.withAlpha(42),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.primary,
                    width: 1.6,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.isEmpty ? 'SP' : initials,
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: onContrast,
                  ),
                ),
              ),
              AppSpacing.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athleteName,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontFamilyFallback: AppTextStyles.fontFamilyFallback,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.18,
                        color: onContrast,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (metaText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metaText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: onContrast.withAlpha(200),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      clubName,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: palette.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasPodium) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Kürsü Oranı %${a.stats.podiumRate.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: onContrast.withAlpha(170),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
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
              if (hasPodium) ...[
                _buildHeroDivider(palette),
                Expanded(
                  child: _buildHeroMetric(
                    palette: palette,
                    label: 'Kürsü',
                    value: '${a.stats.podiumCount}',
                  ),
                ),
              ],
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
    final onContrast = palette.textOnContrast;
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
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.0,
                    color: onContrast,
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
              fontWeight: FontWeight.w500,
              color: onContrast.withAlpha(180),
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
      color: palette.textOnContrast.withAlpha(36),
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

  int? _parseBarajTimeToCs(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty || cleaned == '-') return null;
    final parts = cleaned.split(':');
    if (parts.length == 2) {
      final min = int.tryParse(parts[0]);
      final sec = double.tryParse(parts[1]);
      if (min != null && sec != null) {
        return (min * 6000) + (sec * 100).round();
      }
    } else if (parts.length == 1) {
      final sec = double.tryParse(parts[0]);
      if (sec != null) return (sec * 100).round();
    }
    return null;
  }

  /// 2. SEKME: Barajlar (Sezon Baraj Tablosu - 50m / 25m Kulvar)
  Widget _buildBarajlarTab(
    BuildContext context,
    AppColorPalette palette,
  ) {
    final havuzFilter = _selectedCourseIndex == 0 ? '50m' : '25m';
    final hasMatching = _barajTargets
        .any((t) => (t['havuz'] ?? '').toString() == havuzFilter);

    const chip50 = '50m Uzun Kulvar';
    const chip25 = '25m Kısa Kulvar';
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
            chips: const [
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
          child: !hasMatching
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
                      title: 'Baraj Bilgisi Bulunamadı',
                      message:
                          '$havuzFilter kulvar için tanımlı baraj hedefi bulunmuyor.',
                      icon: Icons.flag_outlined,
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
                    _buildSeasonBarajCard(palette, havuzFilter),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSeasonBarajCard(AppColorPalette palette, String havuzFilter) {
    final matching = _barajTargets
        .where((t) => (t['havuz'] ?? '').toString() == havuzFilter)
        .toList();
    if (matching.isEmpty) return const SizedBox.shrink();

    String eventKeyForRow(Map<String, dynamic> t) {
      final evId = t['event_id'];
      if (evId != null) return 'ev_$evId';
      final title = (t['meet_name'] ?? t['baraj_adi'] ?? 'Baraj').toString();
      final dt = (t['meet_date'] ?? '').toString().trim();
      return '${title}_$dt';
    }

    BarajEventOption? findCatalogMatch(
      int? eventId,
      String barajAdi,
      String title,
    ) {
      for (final c in _barajEventCatalog) {
        if (eventId != null && c.eventId == eventId) return c;
      }
      for (final c in _barajEventCatalog) {
        if (barajAdi.isNotEmpty && c.barajAdi == barajAdi) return c;
        if (title.isNotEmpty && c.title == title) return c;
      }
      return null;
    }

    final eventsMap = <String, BarajEventOption>{};
    for (final t in matching) {
      final key = eventKeyForRow(t);
      if (!eventsMap.containsKey(key)) {
        final evId = (t['event_id'] as num?)?.toInt();
        final title = (t['meet_name'] ?? t['baraj_adi'] ?? 'Baraj').toString();
        final barajAdi = (t['baraj_adi'] ?? title).toString();
        final catalog = findCatalogMatch(evId, barajAdi, title);

        final rawCity = (t['city'] ?? '').toString().trim();
        final rawDateText = (t['meet_date'] ?? '').toString().trim();
        final rawStartDate = (t['start_date'] ?? '').toString().trim();
        final rawValidity =
            (t['baraj_gecerlilik_metni'] ?? '').toString().trim();

        eventsMap[key] = BarajEventOption(
          eventId: evId ?? catalog?.eventId,
          barajAdi: barajAdi,
          title: title,
          city: rawCity.isNotEmpty ? rawCity : (catalog?.city ?? ''),
          dateText:
              rawDateText.isNotEmpty ? rawDateText : (catalog?.dateText ?? ''),
          startDate: rawStartDate.isNotEmpty
              ? rawStartDate
              : (catalog?.startDate ?? ''),
          validityText: rawValidity.isNotEmpty
              ? rawValidity
              : (catalog?.validityText ?? ''),
        );
      }
    }

    final allEvents = eventsMap.values.toList();
    final cities = BarajEventSelector.extractCities(allEvents);
    final months = BarajEventSelector.extractMonths(allEvents);
    final filteredEvents = BarajEventSelector.filterEvents(
      allEvents,
      city: _selectedBarajCity,
      month: _selectedBarajMonth,
    );
    final eventsToShow = filteredEvents.isNotEmpty ? filteredEvents : allEvents;

    String eventSelectionId(BarajEventOption ev) =>
        ev.eventId != null ? 'ev_${ev.eventId}' : '${ev.title}_${ev.dateText}';

    final activeEv = eventsToShow.firstWhere(
      (ev) => eventSelectionId(ev) == _selectedBarajMeet,
      orElse: () => eventsToShow.first,
    );
    final activeKey = eventSelectionId(activeEv);

    final meetRowsRaw = matching
        .where((t) =>
            eventKeyForRow(t) == activeKey &&
            (t['baraj_turu'] ?? 'Katılım Barajı').toString() ==
                _selectedBarajType)
        .toList();

    final seenEvents = <String>{};
    final meetRows = <Map<String, dynamic>>[];
    for (final t in meetRowsRaw) {
      final k = '${t['mesafe']}_${t['stil']}';
      if (seenEvents.add(k)) {
        meetRows.add(t);
      }
    }

    final withPb = meetRows.where((t) => t['passed'] != null).toList();
    final passedCount = withPb.where((t) => t['passed'] == true).length;

    const strokeOrder = [
      'Serbest',
      'Sırtüstü',
      'Kurbağalama',
      'Kelebek',
      'Karışık',
    ];
    final byStroke = <String, List<Map<String, dynamic>>>{};
    for (final t in meetRows) {
      final s = (t['stil'] ?? '').toString();
      if (s.isNotEmpty) byStroke.putIfAbsent(s, () => []).add(t);
    }
    for (final list in byStroke.values) {
      list.sort((a, b) => ((a['mesafe'] as num?)?.toInt() ?? 0)
          .compareTo((b['mesafe'] as num?)?.toInt() ?? 0));
    }
    final strokes = byStroke.keys.toList()
      ..sort((a, b) {
        final ia = strokeOrder.indexOf(a);
        final ib = strokeOrder.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

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
                  color: palette.statusSuccess,
                  borderRadius: AppRadius.full,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Sezon Baraj Tablosu ($havuzFilter)',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: passedCount > 0
                      ? palette.statusSuccessBg
                      : palette.accentSoft,
                  borderRadius: AppRadius.full,
                ),
                child: Text(
                  '$passedCount/${meetRows.length} Geçti',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: passedCount > 0
                        ? palette.statusSuccess
                        : palette.accent,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.vSm,
          // Barajlar sayfasıyla ortak Yer / Tarih filtreli Etkinlik Seçici
          BarajEventSelector(
            events: eventsToShow,
            activeEvent: activeEv,
            cities: cities,
            months: months,
            selectedCity: _selectedBarajCity,
            selectedMonth: _selectedBarajMonth,
            onCityChanged: (val) {
              setState(() {
                _selectedBarajCity = val;
                final next = BarajEventSelector.filterEvents(
                  allEvents,
                  city: val,
                  month: _selectedBarajMonth,
                );
                if (next.isNotEmpty) {
                  _selectedBarajMeet = eventSelectionId(next.first);
                }
              });
            },
            onMonthChanged: (val) {
              setState(() {
                _selectedBarajMonth = val;
                final next = BarajEventSelector.filterEvents(
                  allEvents,
                  city: _selectedBarajCity,
                  month: val,
                );
                if (next.isNotEmpty) {
                  _selectedBarajMeet = eventSelectionId(next.first);
                }
              });
            },
            onEventSelected: (ev) {
              setState(() => _selectedBarajMeet = eventSelectionId(ev));
            },
          ),
          AppSpacing.vSm,
          Row(
            children: [
              ModernFilterChip(
                label: 'Katılım',
                isSelected: _selectedBarajType == 'Katılım Barajı',
                onTap: () =>
                    setState(() => _selectedBarajType = 'Katılım Barajı'),
              ),
              ModernFilterChip(
                label: 'Harcırah',
                isSelected: _selectedBarajType == 'Harcırah Barajı',
                onTap: () =>
                    setState(() => _selectedBarajType = 'Harcırah Barajı'),
              ),
            ],
          ),
          if (meetRows.any((t) =>
              (t['pb_cs'] as num?) == null &&
              (t['overall_pb_cs'] as num?) != null)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: palette.statusWarningBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: palette.statusWarning.withAlpha(65),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: palette.statusWarning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Geçerlilik dönemi dışında — PB dereceleri ile karşılaştırılıyor',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Kompakt tablo başlığı
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: Text('MESAFE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Text(
                    'BARAJ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'SPORCU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    'DURUM',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 6, color: palette.divider),
          if (strokes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Bu etkinlikte seçili tür için baraj bulunamadı.',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: palette.textSecondary,
                ),
              ),
            )
          else
            ...strokes.map((stroke) {
              final list = byStroke[stroke]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          stroke,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 1.2,
                            color: palette.primary.withAlpha(75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...list.map((t) {
                    final mesafe = t['mesafe'];
                    final rawTargetTime = (t['target_time'] ?? '-').toString();
                    final targetCs = _parseBarajTimeToCs(rawTargetTime);
                    final targetText = targetCs != null
                        ? SwimTimeFormatter.formatCs(targetCs)
                        : rawTargetTime;
                    final pbCs = (t['pb_cs'] as num?)?.toInt();
                    final overallPbCs = (t['overall_pb_cs'] as num?)?.toInt();
                    final shownPbCs = pbCs ?? overallPbCs;
                    final pbText = shownPbCs == null
                        ? '-'
                        : SwimTimeFormatter.formatCs(shownPbCs);

                    final rawDiffCs = (t['diff_cs'] as num?)?.toInt() ??
                        (shownPbCs != null && targetCs != null
                            ? shownPbCs - targetCs
                            : null);
                    final passed = t['passed'] == true ||
                        (rawDiffCs != null && rawDiffCs <= 0);
                    final statusText = rawDiffCs != null
                        ? (passed
                            ? 'GEÇTİ'
                            : '+${(rawDiffCs / 100).toStringAsFixed(2)}')
                        : '-';

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: palette.divider.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 42,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: passed
                                      ? (palette.isDark
                                          ? const Color(0x2610B981)
                                          : const Color(0xFFECFDF5))
                                      : palette.statusSuccessBg,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: (passed
                                            ? const Color(0xFF10B981)
                                            : palette.statusSuccess)
                                        .withAlpha(85),
                                    width: 1.0,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${mesafe ?? "-"}',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.displayFontFamily,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: passed
                                        ? (palette.isDark
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFF059669))
                                        : palette.statusSuccess,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              targetText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: palette.statusSuccess,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              pbText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: shownPbCs != null
                                    ? palette.textPrimary
                                    : palette.textTertiary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: rawDiffCs != null && passed
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.emoji_events_rounded,
                                        size: 13.5,
                                        color: palette.gold,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: palette.isDark
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    statusText,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: rawDiffCs != null
                                          ? palette.statusWarning
                                          : palette.textTertiary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            }),
        ],
      ),
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
    final tileFill = palette.isCrispCardTheme
        ? palette.surfaceSecondary
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : palette.textPrimary.withValues(alpha: 0.05));
    final tileBorderColor = palette.isCrispCardTheme
        ? palette.border
        : Colors.white.withValues(alpha: isDark ? 0.10 : 0.25);

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
                          constraints: const BoxConstraints(minHeight: 44),
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
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: palette.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.sm,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${pb.distance}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: AppTextStyles
                                                .displayFontFamily,
                                            fontFamilyFallback:
                                                AppTextStyles.fontFamilyFallback,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                            color: palette.statusSuccess,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
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
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
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
                    StringUtils.cleanMaskedText(a.scoutNote),
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
