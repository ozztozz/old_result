import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/athlete.dart';
import '../../data/models/baraj_rule.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/baraj_event_selector.dart';
import '../../shared/widgets/baraj_status_table.dart';
import '../../shared/widgets/brand_header_bar.dart';
import '../../shared/widgets/formatted_summary_view.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/modern_segmented_tab_bar.dart';
import '../calendar/event_calendar_screen.dart';
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
  final String _selectedBarajType = 'Katılım Barajı';
  bool _isFavorite = false;
  late TabController _tabController;
  int _selectedCourseIndex = 0; // 0: 50m Uzun Kulvar, 1: 25m Kısa Kulvar

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          child: ResponsiveCenter(
            maxWidth: 1040,
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
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.s20,
                              AppSpacing.s12,
                              AppSpacing.s20,
                              AppSpacing.sm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const BrandHeaderBar(
                                  subtitle: 'Sporcu Profili',
                                  padding: EdgeInsets.zero,
                                ),
                                const SizedBox(height: 10),
                                _buildProfileHero(palette, _athlete!),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s20,
                              vertical: AppSpacing.xs,
                            ),
                            child: ModernSegmentedTabBar(
                              controller: _tabController,
                              height: _profileTabBarHeight,
                              tabs: const [
                                TabItemData(
                                  title: 'Takvim',
                                  icon: Icons.calendar_month_outlined,
                                ),
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
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                EventCalendarScreen(
                                  repository: widget.repository,
                                  initialAge: (_athlete!.birthYear != null &&
                                          _athlete!.birthYear! > 1900)
                                      ? DateTime.now().year - _athlete!.birthYear!
                                      : null,
                                  embedded: true,
                                ),
                                _buildBestTimesTab(context, palette, _athlete!),
                                _buildBarajlarTab(context, palette),
                                _buildScoutAnalysisTab(context, palette, _athlete!),
                              ],
                            ),
                          ),
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
        const AppSkeleton.card(height: 84),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 46, borderRadius: AppRadius.chipRadius),
        AppSpacing.vLg,
        const AppSkeleton.card(height: 120),
        AppSpacing.v12,
        const AppSkeleton.card(height: 120),
      ],
    );
  }

  /// Koyu Kart İçi Yuvarlak Aksiyon Butonu
  Widget _buildHeroCircleButton({
    required IconData icon,
    required Color iconColor,
    required Color onContrast,
    required String tooltip,
    required VoidCallback onTap,
    double size = 34,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onContrast.withAlpha(24),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: onContrast.withAlpha(55),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: iconColor),
          ),
        ),
      ),
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

    final onContrast = palette.textOnContrast;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContrast,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.primary.withAlpha(42),
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.primary,
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials.isEmpty ? 'SP' : initials,
              style: TextStyle(
                fontFamily: AppTextStyles.displayFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: onContrast,
              ),
            ),
          ),
          AppSpacing.h12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  athleteName,
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontFamilyFallback: AppTextStyles.fontFamilyFallback,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                    color: onContrast,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (metaText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metaText,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: onContrast.withAlpha(200),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  clubName,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AppSpacing.hSm,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeroCircleButton(
                icon: Icons.compare_arrows_outlined,
                iconColor: onContrast,
                onContrast: onContrast,
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
              const SizedBox(width: 6),
              _buildHeroCircleButton(
                icon: _isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                iconColor:
                    _isFavorite ? palette.statusWarning : onContrast,
                onContrast: onContrast,
                tooltip:
                    _isFavorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
                onTap: _toggleFavorite,
              ),
            ],
          ),
        ],
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
        final rawOzet = (t['ozet'] ?? '').toString().trim();
        final rawNotes = t['onemli_notlar'] is List
            ? (t['onemli_notlar'] as List).map((e) => e.toString()).toList()
            : <String>[];

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
          ozet: rawOzet.isNotEmpty ? rawOzet : (catalog?.ozet ?? ''),
          onemliNotlar: rawNotes.isNotEmpty
              ? rawNotes
              : (catalog?.onemliNotlar ?? const []),
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
    final activePdfUrl = matching
        .where((t) => eventKeyForRow(t) == activeKey)
        .map((t) => (t['pdf_url'] ?? '').toString().trim())
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');

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
            onOpenPdf: activePdfUrl.isNotEmpty
                ? () async {
                    final uri = Uri.tryParse(activePdfUrl);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                : null,
            onOpenSummary: (activeEv.ozet.isNotEmpty ||
                    activeEv.onemliNotlar.isNotEmpty)
                ? () => showAnnouncementDetailSheet(
                      context,
                      title: activeEv.title,
                      subtitle: [
                        if (activeEv.dateText.isNotEmpty) activeEv.dateText,
                        if (activeEv.city.isNotEmpty) activeEv.city,
                      ].join(' • '),
                      tags: [
                        if (activeEv.validityText.isNotEmpty)
                          'Geçerlilik: ${activeEv.validityText}',
                      ],
                      summary: activeEv.ozet,
                      notes: activeEv.onemliNotlar,
                      onOpenPdf: activePdfUrl.isNotEmpty
                          ? () async {
                              final uri = Uri.tryParse(activePdfUrl);
                              if (uri != null) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            }
                          : null,
                    )
                : null,
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
          BarajTabbedStatusView(
            rows: [
              for (final stroke in strokes)
                for (final t in byStroke[stroke]!)
                  (() {
                    final mesafe = (t['mesafe'] as num?)?.toInt() ?? 0;
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
                    return BarajStatusRowData(
                      distance: mesafe,
                      strokeLabel: stroke,
                      targetTime: targetText,
                      pbTime: pbText,
                      diffCs: rawDiffCs,
                      passed: passed,
                    );
                  })(),
            ],
          ),
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
  String _formatPbDate(String raw) {
    final s = raw.trim();
    if (s.length >= 10 && s[4] == '-' && s[7] == '-') {
      final y = s.substring(0, 4);
      final m = s.substring(5, 7);
      final d = s.substring(8, 10);
      return '$d.$m.$y';
    }
    return s;
  }

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
                                            color: palette.accent,
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
                                        if (pb.date.trim().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              _formatPbDate(pb.date),
                                              maxLines: 1,
                                              softWrap: false,
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                                color: palette.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (pb.rudolphPoints != null &&
                                            pb.rudolphPoints! > 0) ...[
                                          const SizedBox(height: 3),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.primary
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Rudolph ${pb.rudolphPoints}',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: palette.primary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
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
    final rudolphPbs = allPbs
        .where((e) => (e.rudolphPoints ?? 0) > 0)
        .toList()
      ..sort(
        (x, y) => (y.rudolphPoints ?? 0).compareTo(x.rudolphPoints ?? 0),
      );
    final peakRudolphPb = rudolphPbs.isNotEmpty ? rudolphPbs.first : null;

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

        // 2. Kariyer Verimliliği & Pozitif Metrikler
        if (a.stats.totalRaces > 0 ||
            a.stats.podiumCount > 0 ||
            a.stats.standardsPassed > 0 ||
            allPbs.isNotEmpty) ...[
          const SectionHeader(title: 'Kariyer Verimliliği'),
          AppSpacing.v12,
          SoftGlassPanel(
            level: 2,
            borderRadius: AppRadius.cardRadius,
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.stats.podiumCount > 0) ...[
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
                ],
                Row(
                  children: [
                    if (a.stats.totalRaces > 0)
                      _buildMetricDetail(
                        palette: palette,
                        label: 'Toplam Yarış',
                        value: '${a.stats.totalRaces}',
                      ),
                    if (a.stats.podiumCount > 0)
                      _buildMetricDetail(
                        palette: palette,
                        label: 'Madalya / Kürsü',
                        value: '${a.stats.podiumCount}',
                      ),
                    if (a.stats.standardsPassed > 0)
                      _buildMetricDetail(
                        palette: palette,
                        label: 'Geçilen Baraj',
                        value: '${a.stats.standardsPassed}',
                      )
                    else if (allPbs.isNotEmpty)
                      _buildMetricDetail(
                        palette: palette,
                        label: 'Kayıtlı PB',
                        value: '${allPbs.length}',
                      ),
                    if (peakRudolphPb != null)
                      _buildMetricDetail(
                        palette: palette,
                        label: 'En İyi Rudolph',
                        value: '${peakRudolphPb.rudolphPoints}/20',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // 3. Zirve Performans (Yaş Grubu Rudolph & FINA)
        if (peakRudolphPb != null || peakPb != null) ...[
          AppSpacing.vLg,
          SectionHeader(
            title: 'Zirve Performans',
            trailingText: peakRudolphPb != null
                ? '${peakRudolphPb.rudolphPoints}/20 Rudolph'
                : '${peakPb!.points} FINA',
          ),
          AppSpacing.v12,
          SoftGlassPanel(
            level: 2,
            borderRadius: AppRadius.cardRadius,
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (peakRudolphPb != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${peakRudolphPb.distance}m ${peakRudolphPb.strokeLabel}',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${peakRudolphPb.rudolphPoints}/20 Rudolph',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: palette.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(
                        SwimTimeFormatter.formatCs(peakRudolphPb.timeCs),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.vXs,
                  Text(
                    '${peakRudolphPb.course == 'SC' ? '25m Kısa Kulvar' : '50m Uzun Kulvar'} · ${StringUtils.toTitleCase(peakRudolphPb.meetName)} (${_formatPbDate(peakRudolphPb.date)})',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (peakPb != null &&
                    (peakRudolphPb == null ||
                        peakPb.distance != peakRudolphPb.distance ||
                        peakPb.stroke != peakRudolphPb.stroke ||
                        peakPb.course != peakRudolphPb.course)) ...[
                  if (peakRudolphPb != null) ...[
                    AppSpacing.vMd,
                    Divider(color: palette.divider, height: 1),
                    AppSpacing.v12,
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${peakPb.distance}m ${peakPb.strokeLabel}',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${peakPb.points} FINA',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(
                        SwimTimeFormatter.formatCs(peakPb.timeCs),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.vXs,
                  Text(
                    '${peakPb.course == 'SC' ? '25m Kısa Kulvar' : '50m Uzun Kulvar'} · ${StringUtils.toTitleCase(peakPb.meetName)} (${_formatPbDate(peakPb.date)})',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: palette.textSecondary,
                      fontSize: 12,
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

        // 4. Güçlü Stiller & Mesafe Profili
        if (allPbs.isNotEmpty) ..._buildStrengthProfileSection(palette, allPbs),

        // 5. Hedefe Yakın Branşlar (Sadece pozitif fırsatlar)
        ..._buildCloseBarajSection(palette),

        // 6. Son Dönem Form & PB Özeti
        ..._buildRecentFormSection(palette, allPbs),
      ],
    );
  }

  DateTime? _parsePbDateTime(String raw) {
    final s = raw.trim();
    if (s.length >= 10 && s[4] == '-' && s[7] == '-') {
      return DateTime.tryParse(s.substring(0, 10));
    }
    final dot = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})').firstMatch(s);
    if (dot != null) {
      final d = int.tryParse(dot.group(1)!);
      final m = int.tryParse(dot.group(2)!);
      final y = int.tryParse(dot.group(3)!);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  List<Widget> _buildStrengthProfileSection(
    AppColorPalette palette,
    List<PersonalBest> allPbs,
  ) {
    final strokeBestScore = <String, int>{};
    final hasAnyRudolph = allPbs.any((pb) => (pb.rudolphPoints ?? 0) > 0);
    final hasAnyFina =
        !hasAnyRudolph && allPbs.any((pb) => (pb.points ?? 0) > 0);
    for (final pb in allPbs) {
      final key = pb.strokeLabel.isNotEmpty ? pb.strokeLabel : pb.stroke;
      if (key.isEmpty) continue;
      if (hasAnyRudolph) {
        final r = pb.rudolphPoints ?? 0;
        if (r > 0) {
          strokeBestScore[key] =
              (strokeBestScore[key] ?? 0) > r ? strokeBestScore[key]! : r;
        }
      } else if (hasAnyFina) {
        final pts = pb.points ?? 0;
        if (pts > 0) {
          strokeBestScore[key] =
              (strokeBestScore[key] ?? 0) > pts ? strokeBestScore[key]! : pts;
        }
      } else {
        strokeBestScore[key] = (strokeBestScore[key] ?? 0) + 1;
      }
    }
    if (strokeBestScore.isEmpty) return const [];

    final sortedStrokes = strokeBestScore.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final maxScore = hasAnyRudolph ? 20 : sortedStrokes.first.value;

    // Mesafe profili: Sprint (50-100), Orta (200), Uzun (400+)
    final tierScores = <String, int>{};
    for (final pb in allPbs) {
      final tier = pb.distance <= 100
          ? 'Sprint (50-100m)'
          : pb.distance == 200
              ? 'Orta Mesafe (200m)'
              : 'Uzun Mesafe (400m+)';
      final val = hasAnyRudolph
          ? (pb.rudolphPoints ?? 0)
          : hasAnyFina
              ? (pb.points ?? 0)
              : 1;
      if ((hasAnyRudolph || hasAnyFina) && val == 0) continue;
      if (hasAnyRudolph || hasAnyFina) {
        tierScores[tier] =
            (tierScores[tier] ?? 0) > val ? tierScores[tier]! : val;
      } else {
        tierScores[tier] = (tierScores[tier] ?? 0) + 1;
      }
    }
    final sortedTiers = tierScores.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));

    return [
      AppSpacing.vLg,
      SectionHeader(
        title: 'Branş Güç Profili',
        trailingText: 'Ana Stil: ${sortedStrokes.first.key}',
      ),
      AppSpacing.v12,
      SoftGlassPanel(
        level: 2,
        borderRadius: AppRadius.cardRadius,
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sortedStrokes.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sortedStrokes[i].key,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (i == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'En Güçlü',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: palette.primary,
                        ),
                      ),
                    ),
                  Text(
                    hasAnyRudolph
                        ? '${sortedStrokes[i].value}/20 Rudolph'
                        : hasAnyFina
                            ? '${sortedStrokes[i].value} FINA'
                            : '${sortedStrokes[i].value} Branş',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == 0 ? palette.primary : palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: AppRadius.full,
                child: LinearProgressIndicator(
                  value: maxScore > 0
                      ? (sortedStrokes[i].value / maxScore).clamp(0.15, 1.0)
                      : 0.5,
                  minHeight: 6,
                  backgroundColor: palette.progressTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    i == 0 ? palette.primary : palette.accent,
                  ),
                ),
              ),
            ],
            if (sortedTiers.isNotEmpty) ...[
              AppSpacing.vMd,
              Divider(color: palette.divider, height: 1),
              AppSpacing.v12,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: sortedTiers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final t = entry.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: idx == 0
                          ? palette.primary.withValues(alpha: 0.12)
                          : palette.surfaceSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: idx == 0
                            ? palette.primary.withValues(alpha: 0.45)
                            : palette.border,
                      ),
                    ),
                    child: Text(
                      hasAnyRudolph
                          ? '${t.key} · ${t.value}/20 R'
                          : hasAnyFina
                              ? '${t.key} · ${t.value} FINA'
                              : '${t.key} (${t.value})',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: idx == 0 ? FontWeight.w700 : FontWeight.w500,
                        color: idx == 0 ? palette.primary : palette.textPrimary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildCloseBarajSection(AppColorPalette palette) {
    final seen = <String>{};
    final candidates = <Map<String, dynamic>>[];
    for (final t in _barajTargets) {
      if (t['passed'] != false) continue;
      final pbCs = (t['pb_cs'] as num?)?.toInt();
      final barajCs = (t['baraj_cs'] as num?)?.toInt();
      if (pbCs == null || barajCs == null) continue;
      final diffCs = pbCs - barajCs;
      if (diffCs <= 0 || diffCs > 500) continue; // 5 saniye içinde hedefe yakınlar
      final key = '${t['havuz']}_${t['mesafe']}_${t['stil']}';
      if (!seen.add(key)) continue;
      candidates.add({...t, '_diff_cs': diffCs});
    }
    if (candidates.isEmpty) return const [];

    candidates.sort(
      (x, y) => (x['_diff_cs'] as int).compareTo(y['_diff_cs'] as int),
    );
    final top = candidates.take(3).toList();

    return [
      AppSpacing.vLg,
      const SectionHeader(
        title: 'Baraja Çok Yakın Branşlar',
        trailingText: 'Hedef Fırsatı',
      ),
      AppSpacing.v12,
      SoftGlassPanel(
        level: 2,
        borderRadius: AppRadius.cardRadius,
        padding: AppSpacing.cardPadding,
        child: Column(
          children: [
            for (int i = 0; i < top.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: 8),
                Divider(color: palette.divider, height: 1),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${top[i]['mesafe']}m ${top[i]['stil']} (${top[i]['havuz'] ?? ''})',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hedef: ${SwimTimeFormatter.formatCs((top[i]['baraj_cs'] as num).toInt())} · PB: ${SwimTimeFormatter.formatCs((top[i]['pb_cs'] as num).toInt())}',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            color: palette.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Sadece ${((top[i]['_diff_cs'] as int) / 100.0).toStringAsFixed(2)} sn',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildRecentFormSection(
    AppColorPalette palette,
    List<PersonalBest> allPbs,
  ) {
    if (allPbs.isEmpty) return const [];
    final cutoff = DateTime.now().subtract(const Duration(days: 180));
    final recentPbs = <PersonalBest>[];
    PersonalBest? latestPb;
    DateTime? latestDt;

    for (final pb in allPbs) {
      final dt = _parsePbDateTime(pb.date);
      if (dt != null) {
        if (!dt.isBefore(cutoff)) {
          recentPbs.add(pb);
        }
        if (latestDt == null || dt.isAfter(latestDt)) {
          latestDt = dt;
          latestPb = pb;
        }
      }
    }

    final finaPoints =
        allPbs.map((e) => e.points ?? 0).where((p) => p > 0).toList();
    final avgFina = finaPoints.isNotEmpty
        ? (finaPoints.reduce((a, b) => a + b) / finaPoints.length).round()
        : 0;
    final rudolphList = allPbs
        .map((e) => e.rudolphPoints ?? 0)
        .where((p) => p > 0)
        .toList();
    final avgRudolph = rudolphList.isNotEmpty
        ? (rudolphList.reduce((a, b) => a + b) / rudolphList.length)
        : 0.0;

    if (recentPbs.isEmpty &&
        avgFina == 0 &&
        avgRudolph == 0 &&
        latestPb == null) {
      return const [];
    }

    return [
      AppSpacing.vLg,
      const SectionHeader(title: 'Son Dönem Form & Gelişim'),
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
                if (recentPbs.isNotEmpty)
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Son 6 Ayda PB',
                    value: '${recentPbs.length}',
                  ),
                if (avgRudolph > 0)
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Ort. Rudolph',
                    value: '${avgRudolph.toStringAsFixed(1)}/20',
                  )
                else if (avgFina > 0)
                  _buildMetricDetail(
                    palette: palette,
                    label: 'Ort. En İyi FINA',
                    value: '$avgFina',
                  ),
                _buildMetricDetail(
                  palette: palette,
                  label: 'Toplam PB Branşı',
                  value: '${allPbs.length}',
                ),
              ],
            ),
            if (latestPb != null) ...[
              AppSpacing.vMd,
              Divider(color: palette.divider, height: 1),
              AppSpacing.v12,
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En Güncel PB: ${latestPb.distance}m ${latestPb.strokeLabel} (${SwimTimeFormatter.formatCs(latestPb.timeCs)})'
                      '${(latestPb.rudolphPoints ?? 0) > 0 ? ' · Rudolph ${latestPb.rudolphPoints}/20' : ''}'
                      ' · ${_formatPbDate(latestPb.date)}',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
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
    ];
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


