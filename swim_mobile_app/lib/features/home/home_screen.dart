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
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/theme_picker_sheet.dart';
import '../clubs/relay_simulator_screen.dart';
import '../live/live_meet_detail_screen.dart';
import '../meets/meet_detail_screen.dart';
import '../athletes/athlete_profile_screen.dart';
import '../rankings/rankings_screen.dart';

/// 1. Ekran: Ana Sayfa & Keşfet (Home Dashboard)
class HomeScreen extends StatefulWidget {
  final SwimRepository repository;

  const HomeScreen({super.key, required this.repository});

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
      delegate: _SwimSearchDelegate(repository: widget.repository),
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
                                    ],
                                  ),
                                ),
                                AppSpacing.vLg,

                                // Aktif Canlı Yarış Varsa Soft Glass Level 1 Hero Banner
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildLiveBanner(_liveMeets.first, palette),
                                  AppSpacing.vLg,
                                ],

                                // Hızlı Araçlar (Sakin 2 sütunlu Level 3 ızgara)
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildToolCard(
                                        palette,
                                        icon: Icons.groups_outlined,
                                        title: 'Bayrak Simülatörü',
                                        subtitle: 'En hızlı 4x50 / 4x100',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RelaySimulatorScreen(
                                                repository: widget.repository,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    AppSpacing.h12,
                                    Expanded(
                                      child: _buildToolCard(
                                        palette,
                                        icon: Icons.leaderboard_outlined,
                                        title: 'Top 25 Sıralama',
                                        subtitle: 'Branş & il en iyileri',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => RankingsScreen(
                                                repository: widget.repository,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                AppSpacing.vLg,

                                // Favori Sporcu & Kulüp Canlı Özet Akışı
                                if (_highlights.isNotEmpty) ...[
                                  _buildHighlightsSection(palette),
                                  AppSpacing.vLg,
                                ],

                                // Güncel Müsabakalar Başlığı
                                SectionHeader(
                                  title: 'Güncel Müsabakalar',
                                  trailingText: '${_recentMeets.length} Müsabaka',
                                ),
                                AppSpacing.v12,

                                // Müsabaka Kartları Listesi (Level 2)
                                ..._recentMeets
                                    .take(8)
                                    .map((meet) => _buildMeetCard(meet)),
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

  Widget _buildToolCard(
    AppColorPalette palette, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SoftGlassPanel(
      level: 3,
      borderRadius: AppRadius.cardRadius,
      padding: AppSpacing.cardPadding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: palette.primary),
          AppSpacing.v12,
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AppSpacing.vXs,
          Text(
            subtitle,
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
              final athleteName =
                  StringUtils.toTitleCase(h['athlete_name'] as String? ?? '');
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

  Widget _buildLiveBanner(LiveMeetSummary live, AppColorPalette palette) {
    final statusLower = live.status.toLowerCase();
    final isCompleted = live.resultListProgress.total > 0 &&
        live.resultListProgress.processed >= live.resultListProgress.total;
    final isTrulyLive = !isCompleted &&
        (statusLower.contains('canl') ||
            statusLower.contains('live') ||
            statusLower.contains('devam') ||
            live.resultListProgress.processed > 0);

    final StatusBadge statusBadge;
    if (isTrulyLive) {
      statusBadge = const StatusBadge.live(label: 'CANLI YARIŞ');
    } else if (isCompleted) {
      statusBadge = StatusBadge(
        label: 'Sonuçlandı',
        variant: StatusBadgeVariant.success,
        textColor: palette.successText,
      );
    } else {
      statusBadge = StatusBadge.neutral(
        label: live.status.isNotEmpty
            ? StringUtils.toTitleCase(live.status)
            : 'Bekleniyor',
      );
    }

    return SoftGlassPanel(
      level: 1,
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: AppRadius.rounded,
      padding: AppSpacing.cardPadding,
      artStyle: AmbientArtStyle.none,
      onTap: () {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              statusBadge,
              const Spacer(),
              if (live.city.isNotEmpty)
                Text(
                  live.city,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          AppSpacing.v12,
          Text(
            StringUtils.toTitleCase(live.name),
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
          AppSpacing.vSm,
          Row(
            children: [
              Expanded(
                child: Text(
                  'Start ${live.startListProgress.processed}/${live.startListProgress.total}  ·  Sonuç ${live.resultListProgress.processed}/${live.resultListProgress.total}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                'Aç',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppSpacing.hXs,
              Icon(
                Icons.chevron_right_outlined,
                size: 14,
                color: palette.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeetCard(MeetSummary meet) {
    final is25m = meet.course == 'SC';
    final palette = context.palette;
    final courseColor = is25m ? palette.secondary : palette.primary;

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      margin: const EdgeInsets.only(bottom: AppSpacing.s12),
      padding: AppSpacing.cardPadding,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MeetDetailScreen(
              meetId: meet.id,
              meetTitle: meet.name,
              repository: widget.repository,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  StringUtils.toTitleCase(meet.name),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              AppSpacing.h12,
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: courseColor.withValues(alpha: 0.14),
                  borderRadius: AppRadius.badgeRadius,
                  border: Border.all(
                    color: courseColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  is25m ? '25m' : '50m',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: courseColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.vSm,
          Row(
            children: [
              if (meet.city.isNotEmpty) ...[
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: palette.textSecondary,
                ),
                AppSpacing.hXs,
                Text(
                  meet.city,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                AppSpacing.h12,
              ],
              if (meet.startDate.isNotEmpty) ...[
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: palette.textSecondary,
                ),
                AppSpacing.hXs,
                Text(
                  meet.startDate,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          AppSpacing.v12,
          Divider(height: 1, thickness: 1, color: palette.divider),
          AppSpacing.v12,
          Row(
            children: [
              Text(
                '${meet.totalRaces} Yarış',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('  ·  ', style: TextStyle(color: palette.textSecondary)),
              Text(
                '${meet.totalAthletes} Sporcu',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_outlined,
                size: 20,
                color: palette.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Arama Delegesi
class _SwimSearchDelegate extends SearchDelegate {
  final SwimRepository repository;

  _SwimSearchDelegate({required this.repository});

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
                    title: Text(a.name),
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
                      // Kulüp detay Faz 4
                    },
                  )),
            ],
          ],
        );
      },
    );
  }
}
