import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/live_meet.dart';
import '../../shared/widgets/component_gallery_screen.dart';
import '../clubs/relay_simulator_screen.dart';
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

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TÜRKİYE YÜZME FEDERASYONU',
              style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Güncel & Canlı Müsabakalar',
              style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              onPressed: _openGallery,
              tooltip: 'SwimDesign Galerisi',
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearchModal,
            tooltip: 'Sporcu / Kulüp Ara',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _recentMeets.isEmpty && _liveMeets.isEmpty
              ? Center(
                  child: EmptyStateWidget(
                    title: 'Veriler Yüklenemedi',
                    message: _errorMessage!,
                    icon: Icons.cloud_off_rounded,
                    actionText: 'Tekrar Dene',
                    onAction: _loadData,
                  ),
                )
              : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Hızlı Arama Barı
                  InkWell(
                    onTap: _openSearchModal,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Theme.of(context).textTheme.bodySmall!.color),
                          const SizedBox(width: 12),
                          Text(
                            'Sporcu, kulüp veya müsabaka ara...',
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall!.color,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hızlı Araçlar (Bayrak Simülatörü & Top 25 Sıralamalar)
                  Row(
                    children: [
                      Expanded(
                        child: _buildToolCard(
                          palette,
                          icon: Icons.groups_rounded,
                          title: 'Bayrak Simülatörü',
                          subtitle: 'En hızlı 4x50 / 4x100',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RelaySimulatorScreen(repository: widget.repository),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildToolCard(
                          palette,
                          icon: Icons.leaderboard_rounded,
                          title: 'Top 25 Sıralama',
                          subtitle: 'Branş & il en iyileri',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RankingsScreen(repository: widget.repository),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Aktif Canlı Yarış Varsa Canlı Banner
                  if (_liveMeets.isNotEmpty) ...[
                    _buildLiveBanner(_liveMeets.first, palette),
                    const SizedBox(height: 20),
                  ],

                  // Favori Sporcu & Kulüp Canlı Özet Akışı
                  if (_highlights.isNotEmpty) ...[
                    _buildHighlightsSection(palette),
                    const SizedBox(height: 20),
                  ],

                  // Güncel Müsabakalar Başlığı
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Güncel Müsabakalar',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_recentMeets.length} Müsabaka',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall!.color,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Müsabaka Kartları Listesi
                  ..._recentMeets.take(8).map((meet) => _buildMeetCard(meet)),
                ],
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
    return Material(
      color: palette.surface,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: palette.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10.5, color: palette.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.statusLive, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.statusLiveBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.statusLive,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CANLI YARIŞ',
                      style: TextStyle(
                        color: palette.statusLive,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (live.city.isNotEmpty)
                Text(
                  live.city,
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall!.color, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            live.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start: ${live.startListProgress.processed}/${live.startListProgress.total} · Sonuç: ${live.resultListProgress.processed}/${live.resultListProgress.total}',
            style: TextStyle(color: Theme.of(context).textTheme.bodySmall!.color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetCard(MeetSummary meet) {
    final is25m = meet.course == 'SC';
    final palette = context.palette;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      meet.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: is25m ? palette.secondary.withValues(alpha: 0.12) : primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: is25m ? palette.secondary.withValues(alpha: 0.4) : primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      is25m ? '25m (Kısa)' : '50m (Uzun)',
                      style: TextStyle(
                        color: is25m ? palette.secondary : primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (meet.city.isNotEmpty) ...[
                    Icon(Icons.location_on_outlined, size: 14, color: Theme.of(context).textTheme.bodySmall!.color),
                    const SizedBox(width: 4),
                    Text(meet.city, style: TextStyle(color: Theme.of(context).textTheme.bodySmall!.color, fontSize: 12)),
                    const SizedBox(width: 12),
                  ],
                  if (meet.startDate.isNotEmpty) ...[
                    Icon(Icons.calendar_today_outlined, size: 14, color: Theme.of(context).textTheme.bodySmall!.color),
                    const SizedBox(width: 4),
                    Text(meet.startDate, style: TextStyle(color: Theme.of(context).textTheme.bodySmall!.color, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${meet.totalRaces} Yarış',
                    style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const Text(' · ', style: TextStyle(color: Colors.grey)),
                  Text(
                    '${meet.totalAthletes} Sporcu',
                    style: TextStyle(color: palette.statusSuccess, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
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
