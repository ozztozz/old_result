import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/tyf_news.dart';
import '../../shared/widgets/component_gallery_screen.dart';
import '../../shared/widgets/theme_picker_sheet.dart';
import '../clubs/club_search_screen.dart';
import '../clubs/relay_simulator_screen.dart';
import '../live/live_meet_detail_screen.dart';
import '../meets/meet_search_screen.dart';
import '../athletes/athlete_profile_screen.dart';
import '../rankings/rankings_screen.dart';
import '../calendar/event_calendar_screen.dart';
import '../barajlar/barajlar_screen.dart';

/// 1. Ekran: Ana Sayfa & Keşfet (Home Dashboard)
class HomeScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueChanged<int>? onOpenLiveMeet;
  final ValueChanged<MeetSummary>? onOpenMeetInLive;

  const HomeScreen({
    super.key,
    required this.repository,
    this.onOpenLiveMeet,
    this.onOpenMeetInLive,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<MeetSummary> _recentMeets = [];
  List<LiveMeetSummary> _liveMeets = [];
  List<Map<String, dynamic>> _highlights = [];
  List<TyfNewsItem> _newsFeed = [];
  final PageController _newsPageController = PageController(viewportFraction: 0.88);
  int _newsPageIndex = 0;

  @override
  void dispose() {
    _newsPageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final favIds = FavoriteAthletesService.instance.favoriteIds;
      final club = SelectedClubService.instance;
      final Future<List<Map<String, dynamic>>> hlFuture =
          (favIds.isNotEmpty || club.hasSelectedClub)
              ? widget.repository
                  .getHighlightsFeed(
                    athleteIds: favIds,
                    clubId: club.clubId,
                    clubName: club.clubName,
                  )
                  .catchError((_) => <Map<String, dynamic>>[])
              : Future.value(<Map<String, dynamic>>[]);

      final results = await Future.wait([
        widget.repository.getMeets(page: 1),
        widget.repository.getLiveMeets(),
        hlFuture,
        widget.repository
            .getNewsFeed(limit: 15)
            .catchError((_) => <TyfNewsItem>[]),
      ]);
      if (mounted) {
        setState(() {
          _recentMeets = results[0] as List<MeetSummary>;
          _liveMeets = results[1] as List<LiveMeetSummary>;
          _highlights = results[2] as List<Map<String, dynamic>>;
          _newsFeed = results[3] as List<TyfNewsItem>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Müsabakalar yüklenirken bir bağlantı sorunu oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _openSearchModal() {
    showSearch(
      context: context,
      delegate: _SwimSearchDelegate(
        repository: widget.repository,
        onMeetSelected: widget.onOpenMeetInLive,
      ),
    );
  }

  void _openClubSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClubSearchScreen(
          repository: widget.repository,
          onMeetSelected: widget.onOpenMeetInLive,
        ),
      ),
    );
  }

  void _openMeetSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetSearchScreen(
          repository: widget.repository,
          onMeetSelected: widget.onOpenMeetInLive,
        ),
      ),
    );
  }

  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ComponentGalleryScreen()),
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
          child: Column(
            children: [
              // 1. Editoryal Üst Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s20,
                  AppSpacing.s12,
                  AppSpacing.s20,
                  AppSpacing.s12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
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
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Keşfet & Sonuçlar',
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
                    if (kDebugMode) ...[
                      GlassCircleButton(
                        icon: Icons.design_services_outlined,
                        iconSize: 20,
                        iconColor: palette.textTertiary,
                        tooltip: 'SwimDesign Galerisi',
                        onTap: _openGallery,
                      ),
                      AppSpacing.hSm,
                    ],
                    GlassCircleButton(
                      icon: Icons.palette_outlined,
                      iconSize: 20,
                      iconColor: palette.textTertiary,
                      tooltip: 'Tema Seç',
                      onTap: () => ThemePickerSheet.show(context),
                    ),
                    AppSpacing.hSm,
                    GlassCircleButton(
                      icon: Icons.search_outlined,
                      iconSize: 20,
                      iconColor: palette.textTertiary,
                      tooltip: 'Sporcu / Kulüp Ara',
                      onTap: _openSearchModal,
                    ),
                  ],
                ),
              ),

              // 2. İçerik
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: palette.primary,
                        ),
                      )
                    : _errorMessage != null &&
                            _recentMeets.isEmpty &&
                            _liveMeets.isEmpty
                        ? Center(
                            child: EmptyStateWidget(
                              title: 'Veriler Yüklenemedi',
                              message: _errorMessage!,
                              icon: Icons.cloud_off_outlined,
                              actionText: 'Tekrar Dene',
                              onAction: _loadData,
                            ),
                          )
                        : RefreshIndicator(
                            color: palette.primary,
                            onRefresh: _loadData,
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
                                // Hızlı Arama Çubuğu (Level 3, height 48, radius 24, 180ms animasyon)
                                SoftGlassPanel(
                                  level: 3,
                                  height: 48,
                                  borderRadius: BorderRadius.circular(24),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                  ),
                                  animationDuration:
                                      const Duration(milliseconds: 180),
                                  onTap: _openSearchModal,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search_outlined,
                                        size: 20,
                                        color: palette.textSecondary,
                                      ),
                                      AppSpacing.h12,
                                      Expanded(
                                        child: Text(
                                          'Sporcu, kulüp veya müsabaka ara...',
                                          style: TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w400,
                                            color: palette.textSecondary
                                                .withValues(alpha: 0.85),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _openMeetSearch,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: palette.accentSoft,
                                            borderRadius: AppRadius.full,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.tune_rounded,
                                                size: 14,
                                                color: palette.accent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Yarış Ara',
                                                style: TextStyle(
                                                  fontFamily:
                                                      AppTextStyles.fontFamily,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: palette.accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AppSpacing.vLg,

                                // 1. TYF Duyurular & Takvim Haber Bandı
                                if (_newsFeed.isNotEmpty) ...[
                                  _buildNewsFeedBand(palette),
                                  AppSpacing.v20,
                                ],

                                // 2. Öne Çıkan Canlı Havuz Spotlight Kartı
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildUnifiedSpotlightCard(
                                    _liveMeets.first,
                                    palette,
                                  ),
                                  AppSpacing.vMd,
                                ],

                                // 3. 2 Sütunlu Mikro-Rozetli Hızlı Araçlar
                                _buildUnifiedToolGrid(palette),
                                AppSpacing.v20,

                                // 4. Favori Sporcu & Kulüp Canlı Akışı
                                if (_highlights.isNotEmpty) ...[
                                  _buildHighlightsSection(palette),
                                  AppSpacing.v20,
                                ],

                                // 5. Güncel Müsabakalar (25m / 50m Kulvar Şeritleri)
                                _buildUnifiedMeetList(palette),
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

  Widget _buildUnifiedSpotlightCard(
    LiveMeetSummary live,
    AppColorPalette palette,
  ) {
    final isCompleted = live.resultListProgress.total > 0 &&
        live.resultListProgress.processed >= live.resultListProgress.total;
    final statusLower = live.status.toLowerCase();
    final isTrulyLive = !isCompleted &&
        (statusLower.contains('canl') ||
            statusLower.contains('live') ||
            statusLower.contains('devam') ||
            live.resultListProgress.processed > 0);
    final total = live.resultListProgress.total;
    final done = live.resultListProgress.processed;
    final ratio = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).round();

    return _KheloOnTapScale(
      onTap: () {
        if (widget.onOpenLiveMeet != null) {
          widget.onOpenLiveMeet!(live.id);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveMeetDetailScreen(
              live: live,
              repository: widget.repository,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: AppRadius.cardRadius,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.surfaceContrast,
                Color.lerp(palette.surfaceContrast, palette.accent, 0.25)!,
              ],
            ),
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: palette.textOnContrast.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isTrulyLive
                            ? palette.statusLive
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isTrulyLive
                            ? 'CANLI YAYIN'
                            : (isCompleted ? 'SONUÇLANDI' : 'YAKLAŞAN'),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (live.city.isNotEmpty)
                      Text(
                        live.city,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.textOnContrast.withValues(alpha: 0.78),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  StringUtils.toTitleCase(live.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                    color: palette.textOnContrast,
                  ),
                ),
                const SizedBox(height: 14),
                if (total > 0) ...[
                  ClipRRect(
                    borderRadius: AppRadius.full,
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4.5,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted
                            ? palette.statusSuccess
                            : Color.lerp(palette.accent, Colors.white, 0.22)!,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        total > 0
                            ? 'Seri $done/$total  ·  %$pct'
                            : 'Start ${live.startListProgress.processed}/${live.startListProgress.total}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: palette.textOnContrast.withValues(alpha: 0.75),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      'İzle',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.textOnContrast,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: palette.textOnContrast,
                    ),
                  ],
                ),
              ],
            ),
        ),
      ),
    );
  }

  Widget _buildUnifiedToolGrid(AppColorPalette palette) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMicroBadgeToolCard(
                palette,
                title: 'Bayrak Simülatörü',
                subtitle: 'En hızlı 4x50 / 4x100',
                icon: Icons.groups_outlined,
                badgeColor: palette.accent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RelaySimulatorScreen(repository: widget.repository),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMicroBadgeToolCard(
                palette,
                title: 'Top 25 Sıralama',
                subtitle: 'Branş & il en iyileri',
                icon: Icons.leaderboard_outlined,
                badgeColor: palette.infoCyan,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RankingsScreen(repository: widget.repository),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: SelectedClubService.instance,
          builder: (context, _) {
            final clubService = SelectedClubService.instance;
            final subtitle = clubService.hasSelectedClub
                ? 'Seçili: ${StringUtils.toTitleCase(clubService.clubName!)}'
                : 'Kulüp ara, takımını seç veya yarışlarını gör';
            return _KheloOnTapScale(
              onTap: _openClubSearch,
              child: SoftGlassPanel(
                level: 2,
                borderRadius: BorderRadius.circular(18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kulüp Ara',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
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
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: palette.textTertiary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMicroBadgeToolCard(
    AppColorPalette palette, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return _KheloOnTapScale(
      onTap: onTap,
      child: SoftGlassPanel(
        level: 2,
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 17, color: badgeColor),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
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
      ),
    );
  }

  Widget _buildUnifiedMeetList(AppColorPalette palette) {
    final items = _recentMeets.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Güncel Müsabakalar',
          trailing: SoftGlassPanel(
            level: 3,
            height: 28,
            borderRadius: BorderRadius.circular(999),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onTap: _openMeetSearch,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 14, color: palette.accent),
                const SizedBox(width: 4),
                Text(
                  'Tümünü Ara',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final meet in items) _buildUnifiedMeetRow(meet, palette),
      ],
    );
  }

  Widget _buildUnifiedMeetRow(MeetSummary meet, AppColorPalette palette) {
    final is25m = meet.course == 'SC';
    final courseColor = is25m ? palette.infoCyan : palette.accent;
    final cityText = meet.city.isNotEmpty ? meet.city : 'Türkiye';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _KheloOnTapScale(
        onTap: () {
          final matchingLive = _liveMeets
              .where((m) => m.meetId != null && m.meetId == meet.id)
              .firstOrNull;
          if (matchingLive != null && widget.onOpenLiveMeet != null) {
            widget.onOpenLiveMeet!(matchingLive.id);
            return;
          }
          if (widget.onOpenMeetInLive != null) {
            widget.onOpenMeetInLive!(meet);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LiveMeetDetailScreen(
                live: LiveMeetSummary.fromMeetSummary(meet),
                repository: widget.repository,
              ),
            ),
          );
        },
        child: SoftGlassPanel(
          level: 2,
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: courseColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    is25m ? '25m' : '50m',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: courseColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      StringUtils.toTitleCase(meet.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        cityText,
                        if (meet.startDate.isNotEmpty) meet.startDate,
                        '${meet.totalRaces} yarış',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPdfUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildNewsFeedBand(AppColorPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'TYF Duyurular & Takvim',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BarajlarScreen(repository: widget.repository),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.10),
                    borderRadius: AppRadius.full,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: palette.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Barajlar',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventCalendarScreen(repository: widget.repository),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: AppRadius.full,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 13, color: palette.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Takvim',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.v12,
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _newsPageController,
            padEnds: false,
            itemCount: _newsFeed.length,
            onPageChanged: (idx) => setState(() => _newsPageIndex = idx),
            itemBuilder: (context, index) {
              final item = _newsFeed[index];
              final isActive = index == _newsPageIndex;
              final isMilli = item.belgeTuru == 'MILLI_TAKIM';
              final isTakvim = item.belgeTuru == 'TAKVIM';
              final badgeColor = isMilli
                  ? palette.statusWarning
                  : (isTakvim ? palette.statusSuccess : palette.accent);

              return AnimatedScale(
                scale: isActive ? 1.0 : 0.96,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.surface,
                          Color.lerp(palette.surface, badgeColor, 0.06)!,
                        ],
                      ),
                      border: Border.all(
                        color: isActive
                            ? badgeColor.withValues(alpha: 0.35)
                            : palette.border,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isActive ? 0.07 : 0.03,
                          ),
                          blurRadius: isActive ? 14 : 6,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => _openNewsDetailSheet(item, palette),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.turEtiketi,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ),
                                  if (item.revizyonEtiketi.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.primary
                                              .withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          item.revizyonEtiketi,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: palette.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (item.barajSayisi > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.accentSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.timer_outlined,
                                            size: 11,
                                            color: palette.accent,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${item.barajSayisi} Baraj',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: palette.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.baslik,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                  color: palette.textPrimary,
                                ),
                              ),
                              if (item.ozet.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  item.ozet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (item.yasGrubu.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    item.yasGrubu,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 12,
                                    color: palette.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (item.tarihMetni.isNotEmpty)
                                          item.tarihMetni,
                                        if (item.sehirYer.isNotEmpty)
                                          item.sehirYer,
                                      ].isNotEmpty
                                          ? [
                                              if (item.tarihMetni.isNotEmpty)
                                                item.tarihMetni,
                                              if (item.sehirYer.isNotEmpty)
                                                item.sehirYer,
                                            ].join(' • ')
                                          : 'TYF Resmi Belge',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 11.5,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (item.pdfUrl.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _launchPdfUrl(item.pdfUrl),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.primary
                                              .withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(7),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.picture_as_pdf_outlined,
                                              size: 12,
                                              color: palette.primary,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'PDF',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: palette.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_newsFeed.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_newsFeed.length, (i) {
              final active = i == _newsPageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? palette.accent
                      : palette.textTertiary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  void _openNewsDetailSheet(TyfNewsItem item, AppColorPalette palette) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(
                        label: Text(item.turEtiketi),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (item.revizyonEtiketi.isNotEmpty)
                        Chip(
                          label: Text(item.revizyonEtiketi),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.havuz.isNotEmpty)
                        Chip(
                          label: Text(item.havuz),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.barajSayisi > 0)
                        Chip(
                          label: Text('${item.barajSayisi} Baraj Kuralı'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.baslik,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (item.tarihMetni.isNotEmpty || item.sehirYer.isNotEmpty)
                    Text(
                      [
                        if (item.tarihMetni.isNotEmpty) item.tarihMetni,
                        if (item.sehirYer.isNotEmpty) item.sehirYer,
                      ].join(' • '),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: palette.textSecondary,
                      ),
                    ),
                  if (item.yasGrubu.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Yaş Grubu: ${item.yasGrubu}',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ],
                  if (item.ozet.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      item.ozet,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13.5,
                        height: 1.45,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                  if (item.onemliNotlar.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Önemli Notlar',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...item.onemliNotlar.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                note,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (item.pdfUrl.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _launchPdfUrl(item.pdfUrl),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Resmi PDF Belgesini Aç'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightsSection(AppColorPalette palette) {
    final items = _highlights.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Favori & Kulüp Canlı Akışı',
          trailingText: '${items.length} Kayıt',
        ),
        AppSpacing.v12,
        SoftGlassPanel(
          level: 2,
          borderRadius: AppRadius.cardRadius,
          padding: EdgeInsets.zero,
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final h = entry.value;
              final std = h['qualifying_standard'] as Map<String, dynamic>?;
              final bool hasStd = std != null && std['passed'] == true;
              final athId = h['athlete_id'] as int;
              final athleteName = StringUtils.formatAthleteName(
                h['athlete_name'] as String? ?? '',
              );
              final eventLabel =
                  '${h['distance'] ?? ''}m ${h['stroke_label'] ?? ''}'.trim();
              final city = StringUtils.toTitleCase(
                (h['city'] as String?)?.trim() ?? '',
              );
              final subtitleText =
                  city.isNotEmpty ? '$eventLabel • $city' : eventLabel;

              return Column(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AthleteProfileScreen(
                            athleteId: athId,
                            athleteName: h['athlete_name'] as String? ?? '',
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.s12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        athleteName,
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: palette.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                AppSpacing.vXs,
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
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
                                    ),
                                  ],
                                ),
                                if (hasStd) ...[
                                  AppSpacing.vXs,
                                  Text(
                                    (std['badge'] as String?) ?? 'Baraj',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: palette.successText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AppSpacing.h12,
                          Text(
                            h['time'] as String? ?? '',
                            maxLines: 1,
                            softWrap: false,
                            style: AppTextStyles.officialTime.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (idx < items.length - 1)
                    Divider(height: 1, thickness: 1, color: palette.divider),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

}

/// Arama Delegesi
class _SwimSearchDelegate extends SearchDelegate {
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;

  _SwimSearchDelegate({
    required this.repository,
    this.onMeetSelected,
  });

  @override
  String get searchFieldLabel => 'Sporcu veya kulüp ara...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.trim().length < 2) {
      return const Center(child: Text('Aramak için en az 2 harf girin.'));
    }

    return FutureBuilder<GlobalSearchResult>(
      future: repository.searchGlobal(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.hasError) {
          return const Center(child: Text('Sonuç bulunamadı.'));
        }

        final data = snapshot.data!;
        final athletes = data.athletes;
        final clubs = data.clubs;

        if (athletes.isEmpty && clubs.isEmpty) {
          return const Center(child: Text('Eşleşen sonuç bulunamadı.'));
        }

        return ListView(
          children: [
            if (athletes.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sporcular', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              ...athletes.map((a) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(StringUtils.formatAthleteName(a.name)),
                    subtitle: Text(
                      '${a.birthYear ?? '-'} · ${a.clubName}',
                    ),
                    onTap: () {
                      close(context, null);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AthleteProfileScreen(
                            athleteId: a.id,
                            athleteName: a.name,
                            repository: repository,
                          ),
                        ),
                      );
                    },
                  )),
            ],
            if (clubs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Kulüpler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              ...clubs.map((c) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      child: Icon(
                        Icons.shield_outlined,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(c.name),
                    subtitle: Text('${c.athleteCount} Kayıtlı Sporcu'),
                    onTap: () {
                      close(context, null);
                      ClubSearchScreen.showClubActionsSheet(
                        context,
                        club: c,
                        repository: repository,
                        onMeetSelected: onMeetSelected,
                      );
                    },
                  )),
            ],
          ],
        );
      },
    );
  }
}

class _KheloOnTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _KheloOnTapScale({
    required this.child,
    this.onTap,
  });

  @override
  State<_KheloOnTapScale> createState() => _KheloOnTapScaleState();
}

class _KheloOnTapScaleState extends State<_KheloOnTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration:
            disableMotion ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
