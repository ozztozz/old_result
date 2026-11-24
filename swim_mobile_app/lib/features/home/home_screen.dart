import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../../shared/widgets/component_gallery_screen.dart';
import '../../shared/widgets/theme_picker_sheet.dart';
import '../clubs/club_search_screen.dart';
import '../clubs/relay_simulator_screen.dart';
import '../live/live_meet_detail_screen.dart';
import '../meets/meet_search_screen.dart';
import '../athletes/athlete_profile_screen.dart';
import '../rankings/rankings_screen.dart';

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
      ]);
      if (mounted) {
        setState(() {
          _recentMeets = results[0] as List<MeetSummary>;
          _liveMeets = results[1] as List<LiveMeetSummary>;
          _highlights = results[2] as List<Map<String, dynamic>>;
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

                                // 1. Öne Çıkan Canlı Havuz Spotlight Kartı
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildUnifiedSpotlightCard(
                                    _liveMeets.first,
                                    palette,
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // 2. 2 Sütunlu Mikro-Rozetli Hızlı Araçlar
                                _buildUnifiedToolGrid(palette),
                                const SizedBox(height: 18),

                                // 3. Favori Sporcu & Kulüp Canlı Akışı
                                if (_highlights.isNotEmpty) ...[
                                  _buildHighlightsSection(palette),
                                  const SizedBox(height: 18),
                                ],

                                // 4. Güncel Müsabakalar (25m / 50m Kulvar Şeritleri)
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
        borderRadius: BorderRadius.circular(22),
        child: CustomPaint(
          painter: _HomePoolLanesPainter(
            laneColor: Colors.white.withValues(alpha: 0.06),
          ),
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
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(18),
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
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
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
                      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
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

class _HomePoolLanesPainter extends CustomPainter {
  final Color laneColor;

  const _HomePoolLanesPainter({required this.laneColor});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = laneColor
      ..strokeWidth = 1.2;
    const laneCount = 5;
    for (int i = 1; i < laneCount; i++) {
      final y = size.height * (i / laneCount);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_HomePoolLanesPainter oldDelegate) =>
      laneColor != oldDelegate.laneColor;
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
