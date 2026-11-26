import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';
import '../home/home_screen.dart';

/// 5. Ekran: Favorilerim & Hızlı Takip (Soft Glass + Ambient Glass)
class FavoritesScreen extends StatefulWidget {
  final SwimRepository repository;
  final VoidCallback? onGoToDiscover;

  const FavoritesScreen({
    super.key,
    required this.repository,
    this.onGoToDiscover,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<AthleteSummaryItem> _favoritesData = [];
  String _searchQuery = '';
  late final FocusNode _searchFocusNode;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
    FavoriteAthletesService.instance.addListener(_onFavoritesChanged);
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    FavoriteAthletesService.instance.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted && _isSearchFocused != _searchFocusNode.hasFocus) {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    }
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

  void _goToDiscover() {
    if (widget.onGoToDiscover != null) {
      widget.onGoToDiscover!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HomeScreen(repository: widget.repository),
        ),
      );
    }
  }

  List<AthleteSummaryItem> get _filteredFavorites {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _favoritesData;
    return _favoritesData.where((fav) {
      return fav.name.toLowerCase().contains(q) ||
          fav.clubName.toLowerCase().contains(q);
    }).toList();
  }

  int get _distinctClubsCount {
    return _favoritesData
        .map((f) => f.clubName.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .length;
  }

  int get _highestFina {
    int best = 0;
    for (final f in _favoritesData) {
      final pts = f.topPerformance?.points ?? 0;
      if (pts > best) best = pts;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filtered = _filteredFavorites;

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Editoryal Üst Başlık (LiveScreen ile aynı yapı)
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
                            'HIZLI TAKİP',
                            style: TextStyle(
                              fontFamily: AppTextStyles.displayFontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: palette.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Favori Sporcular',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.displayFontFamily,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.hSm,
                    GlassCircleButton(
                      icon: Icons.refresh_outlined,
                      iconSize: 20,
                      iconColor: palette.textPrimary,
                      tooltip: 'Yenile',
                      onTap: _loadFavorites,
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
                              icon: Icons.error_outline,
                              actionText: 'Tekrar Dene',
                              onAction: _loadFavorites,
                            ),
                          )
                        : _favoritesData.isEmpty
                            ? _buildEmptyState(context, palette)
                            : RefreshIndicator(
                                color: palette.primary,
                                onRefresh: _loadFavorites,
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
                                    // Level 1 Hero Özet Paneli
                                    _buildOverviewHero(palette),
                                    AppSpacing.vLg,

                                    // Level 3 Arama Çubuğu
                                    SoftGlassPanel(
                                      level: 3,
                                      height: 48,
                                      borderRadius: BorderRadius.circular(24),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      animationDuration:
                                          const Duration(milliseconds: 180),
                                      fillAlphaOverride: palette.isDark
                                          ? (_isSearchFocused ? 0.15 : 0.09)
                                          : (_isSearchFocused ? 0.20 : 0.14),
                                      borderAlphaOverride: palette.isDark
                                          ? (_isSearchFocused ? 0.34 : 0.16)
                                          : (_isSearchFocused ? 0.50 : 0.25),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_outlined,
                                            color: palette.textSecondary,
                                            size: 20,
                                          ),
                                          AppSpacing.h12,
                                          Expanded(
                                            child: TextField(
                                              focusNode: _searchFocusNode,
                                              onChanged: (val) => setState(
                                                () => _searchQuery = val,
                                              ),
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 15,
                                                color: palette.textPrimary,
                                              ),
                                              decoration: InputDecoration(
                                                hintText:
                                                    'Sporcu veya kulüp ara...',
                                                hintStyle: TextStyle(
                                                  fontFamily:
                                                      AppTextStyles.fontFamily,
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w400,
                                                  color: palette.textSecondary
                                                      .withValues(alpha: 0.85),
                                                ),
                                                filled: false,
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppSpacing.vLg,

                                    // Level 2 Favori Sporcu Kartları
                                    if (filtered.isEmpty)
                                      const EmptyStateWidget(
                                        title: 'Sonuç bulunamadı',
                                        message:
                                            'Arama kriterlerinize uygun favori sporcu bulunamadı.',
                                        icon: Icons.search_off_outlined,
                                        compact: true,
                                      )
                                    else
                                      ...filtered.map(
                                        (fav) => _buildFavoriteCard(
                                          context,
                                          palette,
                                          fav,
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
    );
  }

  /// Koyu Lacivert Hero İstatistik Paneli
  Widget _buildOverviewHero(AppColorPalette palette) {
    final onContrast = palette.textOnContrast;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceContrast,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TAKİP ÖZETİ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: palette.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppSpacing.hSm,
              Text(
                'Güncel veriler',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: onContrast.withAlpha(170),
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
                  value: '${_favoritesData.length}',
                  label: 'Sporcu',
                  palette: palette,
                ),
              ),
              _buildHeroDivider(palette),
              Expanded(
                child: _buildHeroMetric(
                  value: '$_distinctClubsCount',
                  label: 'Kulüp',
                  palette: palette,
                ),
              ),
              _buildHeroDivider(palette),
              Expanded(
                child: _buildHeroMetric(
                  value: _highestFina > 0 ? '$_highestFina' : '-',
                  label: 'En İyi FINA',
                  palette: palette,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required String value,
    required String label,
    required AppColorPalette palette,
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

  Widget _buildFavoriteCard(
    BuildContext context,
    AppColorPalette palette,
    AthleteSummaryItem fav,
  ) {
    final latest = fav.latestRace;
    final athleteName = StringUtils.formatAthleteName(fav.name);
    final clubName = StringUtils.toTitleCase(fav.clubName);
    final branchInfo = latest != null
        ? '${latest.distance}m ${StringUtils.toTitleCase(latest.stroke)}'
        : (fav.birthYear != null ? '${fav.birthYear}' : '');
    final subtitleText =
        branchInfo.isNotEmpty ? '$clubName · $branchInfo' : clubName;

    final initials = athleteName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      margin: const EdgeInsets.only(bottom: AppSpacing.s12),
      padding: AppSpacing.cardPadding,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
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
              AppSpacing.h12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athleteName,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        letterSpacing: -0.2,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: palette.textSecondary,
                        fontSize: 13.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
                  IconButton(
                    icon: Icon(
                      Icons.star_rounded,
                      color: palette.accent,
                      size: 22,
                    ),
                    tooltip: 'Favorilerden çıkar',
                    onPressed: () =>
                        FavoriteAthletesService.instance.removeFavorite(fav.id),
                  ),
                  Icon(
                    Icons.chevron_right_outlined,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppColorPalette palette) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s20,
          AppSpacing.lg,
          AppSpacing.s20,
          64 + AppSpacing.md + MediaQuery.of(context).padding.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.textSecondary.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                    ),
                  ),
                  SoftGlassPanel(
                    level: 3,
                    shape: BoxShape.circle,
                    width: 58,
                    height: 58,
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Icon(
                        Icons.star_outline_rounded,
                        size: 26,
                        color: palette.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.vMd,
            Text(
              'Henüz favori sporcu eklemediniz',
              textAlign: TextAlign.center,
              style: AppTextStyles.raceTitle.copyWith(
                color: palette.textPrimary,
              ),
            ),
            AppSpacing.vXs,
            Text(
              'Sporcu profilindeki yıldız simgesine dokunarak takip etmek istediğiniz sporcuları buraya ekleyebilirsiniz.',
              textAlign: TextAlign.center,
              style: AppTextStyles.categorySeries.copyWith(
                color: palette.textSecondary,
              ),
            ),
            AppSpacing.vMd,
            SoftGlassPanel(
              level: 3,
              borderRadius: AppRadius.full,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.s12,
              ),
              onTap: _goToDiscover,
              child: Text(
                "Keşfet'e Git",
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
