import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/theme_picker_sheet.dart';
import '../athletes/athlete_profile_screen.dart';

/// 5. Ekran: Favorilerim & Hızlı Takip (Soft Glass + Ambient Glass)
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
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hızlı takip',
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
                            'Favori Sporcular',
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
                    if (_favoritesData.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceGlassStrong,
                          borderRadius: AppRadius.full,
                          border: Border.all(
                            color: palette.isDark
                                ? palette.border
                                : palette.glassBorder,
                          ),
                        ),
                        child: Text(
                          '${_favoritesData.length} Sporcu',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: palette.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GlassCircleButton(
                      icon: Icons.palette_outlined,
                      iconColor: palette.primary,
                      tooltip: 'Tema Seç',
                      onTap: () => ThemePickerSheet.show(context),
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
                            ? const Padding(
                                padding: EdgeInsets.only(bottom: 72),
                                child: EmptyStateWidget(
                                  title: 'Henüz favori sporcu eklemediniz',
                                  message:
                                      'Sporcu profilindeki yıldız simgesine dokunarak takip etmek istediğiniz sporcuları buraya ekleyebilirsiniz.',
                                  icon: Icons.star_outline_rounded,
                                ),
                              )
                            : RefreshIndicator(
                                color: palette.primary,
                                onRefresh: _loadFavorites,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    112,
                                  ),
                                  itemCount: _favoritesData.length,
                                  itemBuilder: (context, index) {
                                    return _buildFavoriteCard(
                                      context,
                                      palette,
                                      _favoritesData[index],
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    BuildContext context,
    AppColorPalette palette,
    AthleteSummaryItem fav,
  ) {
    final latest = fav.latestRace;
    final topPerf = fav.topPerformance;
    final initials = fav.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    return SoftGlassPanel(
      tier: GlassTier.card,
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.primaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials.isEmpty ? 'SP' : initials,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fav.name,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 15.5,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fav.birthYear ?? "-"}  ·  ${fav.clubName}',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.star_rounded, color: palette.gold, size: 22),
                      tooltip: 'Favorilerden çıkar',
                      onPressed: () =>
                          FavoriteAthletesService.instance.removeFavorite(fav.id),
                    ),
                    Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: palette.divider),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son Yarışı',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            latest != null
                                ? '${latest.distance}m ${latest.stroke} · ${latest.time}'
                                : '-',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'En Yüksek FINA',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            topPerf?.points != null
                                ? '${topPerf!.points} Puan'
                                : '-',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.primary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
  }
}
