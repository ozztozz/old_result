import 'package:flutter/material.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';

/// 5. Ekran: Favorilerim & Hızlı Takip (Mobil Özel)
class FavoritesScreen extends StatefulWidget {
  final SwimRepository repository;

  const FavoritesScreen({super.key, required this.repository});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<AthleteSummaryItem> _favoritesData = [];

  @override
  void initState() {
    super.initState();
    FavoriteAthletesService.instance.addListener(_onFavoritesChanged);
    _loadFavorites();
  }

  @override
  void dispose() {
    FavoriteAthletesService.instance.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) {
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    final favoriteIds = FavoriteAthletesService.instance.favoriteIds;
    if (favoriteIds.isEmpty) {
      if (mounted) {
        setState(() {
          _favoritesData = [];
          _errorMessage = null;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await widget.repository.getAthletesSummary(favoriteIds);
      if (mounted) {
        setState(() {
          _favoritesData = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Favori sporcular yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
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
              'TAKİP ETTİĞİM SPORCULAR',
              style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              '${_favoritesData.length} Favori Sporcu',
              style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: palette.primary))
          : _errorMessage != null
              ? Center(
                  child: EmptyStateWidget(
                    title: 'Bağlantı Hatası',
                    message: _errorMessage!,
                    icon: Icons.error_outline_rounded,
                    actionText: 'Tekrar Dene',
                    onAction: _loadFavorites,
                  ),
                )
              : _favoritesData.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_border,
                              size: 64, color: palette.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz favori sporcu eklemediniz.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sporcu profilindeki yıldız simgesine dokunarak\nçocuğunuzu veya öğrencilerinizi buraya ekleyebilirsiniz.',
                            style: TextStyle(
                                color: palette.textSecondary, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadFavorites,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _favoritesData.length,
                        itemBuilder: (context, index) {
                          final fav = _favoritesData[index];
                          final latest = fav.latestRace;
                          final topPerf = fav.topPerformance;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AthleteProfileScreen(
                                      athleteId: fav.id,
                                      athleteName: fav.name,
                                      repository: widget.repository,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          child: const Icon(Icons.person,
                                              color: Colors.white),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fav.name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15),
                                              ),
                                              Text(
                                                '${fav.birthYear ?? "-"} · ${fav.clubName}',
                                                style: TextStyle(
                                                    color: palette.textSecondary,
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.star,
                                              color: palette.gold, size: 22),
                                          tooltip: 'Favorilerden çıkar',
                                          onPressed: () =>
                                              FavoriteAthletesService.instance
                                                  .removeFavorite(fav.id),
                                        ),
                                        Icon(Icons.chevron_right,
                                            color: palette.textMuted),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Son Yarışı',
                                                style: TextStyle(
                                                    color: palette.textSecondary,
                                                    fontSize: 11),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                latest != null
                                                    ? '${latest.distance}m ${latest.stroke} (${latest.time})'
                                                    : '-',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'En Yüksek FINA',
                                                style: TextStyle(
                                                    color: palette.textSecondary,
                                                    fontSize: 11),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                topPerf?.points != null
                                                    ? '${topPerf!.points} Puan'
                                                    : '-',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: palette.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
