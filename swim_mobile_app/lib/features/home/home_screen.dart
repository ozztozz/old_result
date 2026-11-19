import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/live_meet.dart';
import '../../shared/widgets/component_gallery_screen.dart';
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
      artStyle: AmbientArtStyle.orbitalArcs,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Editoryal Üst Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
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
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Keşfet & Sonuçlar',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
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
                        tooltip: 'SwimDesign Galerisi',
                        onTap: _openGallery,
                      ),
                      const SizedBox(width: 8),
                    ],
                    GlassCircleButton(
                      icon: Icons.palette_outlined,
                      iconColor: palette.primary,
                      tooltip: 'Tema Seç',
                      onTap: () => ThemePickerSheet.show(context),
                    ),
                    const SizedBox(width: 8),
                    GlassCircleButton(
                      icon: Icons.search_rounded,
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
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
                              children: [
                                // Hızlı Arama Çubuğu (Frosted Glass yüzey)
                                SoftGlassPanel(
                                  tier: GlassTier.subtle,
                                  borderRadius: BorderRadius.circular(16),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  onTap: _openSearchModal,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        size: 19,
                                        color: palette.textSecondary,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Sporcu, kulüp veya müsabaka ara...',
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          color: palette.textMuted,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Aktif Canlı Yarış Varsa Soft Glass Hero Banner
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildLiveBanner(_liveMeets.first, palette),
                                  const SizedBox(height: 18),
                                ],

                                // Hızlı Araçlar (Bayrak Simülatörü & Top 25 Sıralamalar)
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
                                              builder: (_) => RelaySimulatorScreen(
                                                repository: widget.repository,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
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
                                const SizedBox(height: 22),

                                // Favori Sporcu & Kulüp Canlı Özet Akışı
                                if (_highlights.isNotEmpty) ...[
                                  _buildHighlightsSection(palette),
                                  const SizedBox(height: 22),
                                ],

                                // Güncel Müsabakalar Başlığı
                                SectionHeader(
                                  title: 'Güncel Müsabakalar',
                                  trailingText: '${_recentMeets.length} Müsabaka',
                                ),
                                const SizedBox(height: 14),

                                // Müsabaka Kartları Listesi
                                ..._recentMeets.take(8).map((meet) => _buildMeetCard(meet)),
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
      tier: GlassTier.card,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: palette.primary),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
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
        Row(
          children: [
            Icon(Icons.notifications_active_rounded, size: 17, color: palette.primary),
            const SizedBox(width: 6),
            Text(
              'Favori & Kulüp Canlı Akışı',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final h = entry.value;
              final std = h['qualifying_standard'] as Map<String, dynamic>?;
              final bool hasStd = std != null && std['passed'] == true;
              final athId = h['athlete_id'] as int;

              return Column(
                children: [
                  ListTile(
                    dense: true,
                    title: Text(
                      h['athlete_name'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${h['distance']}m ${h['stroke_label']} • ${h['meet_name']}',
                            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasStd) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: palette.statusSuccess.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (std['badge'] as String?) ?? 'Baraj',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: palette.statusSuccess,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      h['time'] as String? ?? '',
                      style: AppTextStyles.officialTime.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
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
                  ),
                  if (idx < items.length - 1) Divider(height: 1, color: palette.divider),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBanner(LiveMeetSummary live, AppColorPalette palette) {
    return SoftGlassPanel(
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      padding: const EdgeInsets.all(18),
      artStyle: AmbientArtStyle.heroOrbit,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.statusLiveBg,
                  borderRadius: AppRadius.full,
                  border: Border.all(
                    color: palette.statusLive.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.statusLive,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CANLI YARIŞ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: palette.statusLive,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
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
          const SizedBox(height: 12),
          Text(
            live.name,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 11,
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
      tier: GlassTier.card,
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
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
                  meet.name,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    letterSpacing: -0.2,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: courseColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: courseColor.withValues(alpha: 0.25),
                    width: 0.8,
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
          const SizedBox(height: 8),
          Row(
            children: [
              if (meet.city.isNotEmpty) ...[
                Icon(Icons.location_on_outlined, size: 13.5, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  meet.city,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (meet.startDate.isNotEmpty) ...[
                Icon(Icons.calendar_today_outlined, size: 13, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  meet.startDate,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: palette.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${meet.totalRaces} Yarış',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('  ·  ', style: TextStyle(color: palette.textMuted)),
              Text(
                '${meet.totalAthletes} Sporcu',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textMuted,
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
