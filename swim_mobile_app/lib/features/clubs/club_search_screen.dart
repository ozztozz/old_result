import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_bottom_sheet.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/models/meet.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../meets/meet_search_screen.dart';
import 'relay_simulator_screen.dart';

/// Keşfet — Kulüp Arama ve Takım Seçim Ekranı
class ClubSearchScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;

  const ClubSearchScreen({
    super.key,
    required this.repository,
    this.onMeetSelected,
  });

  /// Seçilen kulüp için hızlı aksiyon penceresini açar.
  static Future<void> showClubActionsSheet(
    BuildContext context, {
    required ClubSearchItem club,
    required SwimRepository repository,
    ValueChanged<MeetSummary>? onMeetSelected,
  }) {
    final palette = context.palette;
    final isSelected =
        SelectedClubService.instance.matches(club.name, club.id);
    final displayName = StringUtils.toTitleCase(club.name);

    return AppBottomSheet.show<void>(
      context,
      builder: (sheetCtx) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    size: 22,
                    color: palette.accent,
                  ),
                ),
                AppSpacing.h12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        club.city != null
                            ? '${StringUtils.toTitleCase(club.city!)} · ${club.athleteCount} Kayıtlı Sporcu'
                            : '${club.athleteCount} Kayıtlı Sporcu',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            AppSpacing.vLg,
            _ClubActionTile(
              icon: isSelected
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              iconColor: isSelected ? palette.statusWarning : palette.accent,
              title: isSelected ? 'Takımımdan Çıkar' : 'Takımım Olarak Seç',
              subtitle: isSelected
                  ? 'Aktif kulüp vurgulaması kaldırılır'
                  : 'Yarış ve canlı akışta sporcuları vurgular',
              onTap: () async {
                if (isSelected) {
                  await SelectedClubService.instance.clearClub();
                } else {
                  await SelectedClubService.instance.setClub(
                    id: club.id,
                    name: club.name,
                  );
                }
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              },
            ),
            AppSpacing.vSm,
            _ClubActionTile(
              icon: Icons.pool_rounded,
              iconColor: palette.infoCyan,
              title: 'Kulübün Müsabakalarını Gör',
              subtitle: 'Katıldığı yarışları listele ve canlı akışta aç',
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MeetSearchScreen(
                      repository: repository,
                      initialClub: club.name,
                      onMeetSelected: onMeetSelected,
                    ),
                  ),
                );
              },
            ),
            AppSpacing.vSm,
            _ClubActionTile(
              icon: Icons.groups_outlined,
              iconColor: palette.primary,
              title: 'Bayrak Simülatöründe Aç',
              subtitle: 'Kulübün en hızlı 4x50 / 4x100 kadrosunu oluştur',
              onTap: () async {
                await SelectedClubService.instance.setClub(
                  id: club.id,
                  name: club.name,
                );
                if (!sheetCtx.mounted) return;
                Navigator.pop(sheetCtx);
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RelaySimulatorScreen(repository: repository),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  State<ClubSearchScreen> createState() => _ClubSearchScreenState();
}

class _ClubSearchScreenState extends State<ClubSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _selectedLetter;
  String _selectedKind = 'Takım';
  String? _errorMessage;
  List<ClubSearchItem> _clubs = [];

  static const int _pageSize = 25;

  static const List<String> _kindOptions = [
    'Takım',
    'Okul',
    'Tümü',
  ];

  String get _kindParam {
    switch (_selectedKind) {
      case 'Okul':
        return 'school';
      case 'Tümü':
        return 'all';
      case 'Takım':
      default:
        return 'club';
    }
  }

  static const List<String> _quickCities = [
    'Tümü',
    'İstanbul',
    'Ankara',
    'İzmir',
    'Bursa',
    'Antalya',
    'Adana',
    'Kocaeli',
  ];

  static const List<String> _alphabet = [
    'Tümü',
    'A',
    'B',
    'C',
    'Ç',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'İ',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'Ö',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'U',
    'Ü',
    'V',
    'Y',
    'Z',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  bool get _hasSearchInput =>
      _queryController.text.trim().length >= 2 ||
      _cityController.text.trim().length >= 2 ||
      _selectedLetter != null;

  void _onFiltersChanged() {
    _debounce?.cancel();
    final q = _queryController.text.trim();
    final city = _cityController.text.trim();
    if (q.length < 2 && city.length < 2 && _selectedLetter == null) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _page = 1;
        _errorMessage = null;
        _clubs = [];
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchClubs(reset: true);
    });
  }

  void _selectQuickCity(String label) {
    if (label == 'Tümü') {
      _cityController.clear();
    } else {
      _cityController.text = label;
    }
    _onFiltersChanged();
  }

  void _selectKind(String kind) {
    if (_selectedKind == kind) return;
    setState(() => _selectedKind = kind);
    if (_hasSearchInput) {
      _debounce?.cancel();
      _fetchClubs(reset: true);
    }
  }

  void _selectLetter(String letter) {
    _debounce?.cancel();
    setState(() {
      if (letter == 'Tümü' || _selectedLetter == letter) {
        _selectedLetter = null;
      } else {
        _selectedLetter = letter;
      }
    });
    if (!_hasSearchInput) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _page = 1;
        _errorMessage = null;
        _clubs = [];
      });
      return;
    }
    _fetchClubs(reset: true);
  }

  Future<void> _fetchClubs({bool reset = false}) async {
    final query = _queryController.text.trim();
    final city = _cityController.text.trim();
    final letter = _selectedLetter;
    final kindLabel = _selectedKind;
    final kindParam = _kindParam;

    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _page = 1;
        _hasMore = false;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    final targetPage = reset ? 1 : _page + 1;
    try {
      final list = await widget.repository.searchClubs(
        page: targetPage,
        q: query.isEmpty ? null : query,
        city: city.isEmpty ? null : city,
        letter: letter,
        kind: kindParam,
      );
      if (!mounted ||
          _queryController.text.trim() != query ||
          _cityController.text.trim() != city ||
          _selectedLetter != letter ||
          _selectedKind != kindLabel) {
        return;
      }
      setState(() {
        if (reset) {
          _clubs = list;
        } else {
          _clubs = [..._clubs, ...list];
          _page = targetPage;
        }
        _hasMore = list.length >= _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted ||
          _queryController.text.trim() != query ||
          _cityController.text.trim() != city ||
          _selectedLetter != letter ||
          _selectedKind != kindLabel) {
        return;
      }
      setState(() {
        if (reset) {
          _errorMessage = 'Kulüpler aranırken bir sorun oluştu.';
        }
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final city = _cityController.text.trim();
    final selectedChip = _quickCities.firstWhere(
      (c) => c != 'Tümü' && c.toLowerCase() == city.toLowerCase(),
      orElse: () => city.isEmpty ? 'Tümü' : '',
    );

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context, palette),
              Expanded(
                child: ListView(
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
                    _buildSearchBar(palette),
                    AppSpacing.vSm,
                    ModernFilterChipBar(
                      chips: _kindOptions
                          .map((k) => FilterChipItem(label: k))
                          .toList(),
                      selectedChip: _selectedKind,
                      onSelected: _selectKind,
                    ),
                    AppSpacing.vSm,
                    _buildCityBar(palette),
                    AppSpacing.vSm,
                    ModernFilterChipBar(
                      chips: _quickCities
                          .map((c) => FilterChipItem(label: c))
                          .toList(),
                      selectedChip: selectedChip,
                      onSelected: _selectQuickCity,
                    ),
                    AppSpacing.vSm,
                    _buildAlphabetBar(palette),
                    AppSpacing.v12,
                    ListenableBuilder(
                      listenable: SelectedClubService.instance,
                      builder: (context, _) => _buildSelectedClubBanner(palette),
                    ),
                    if (!_hasSearchInput)
                      SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: const EmptyStateWidget(
                          title: 'Kulüp Ara',
                          message:
                              'Kulüp adı, il veya alfabetik harf seçerek arayın. Seçtiğiniz kulübün müsabakalarını ve bayrak kadrosunu açabilirsiniz.',
                          icon: Icons.shield_outlined,
                          compact: true,
                        ),
                      )
                    else if (_isLoading)
                      _buildLoadingSkeleton()
                    else if (_errorMessage != null && _clubs.isEmpty)
                      SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Bağlantı Hatası',
                          message: _errorMessage!,
                          icon: Icons.cloud_off_outlined,
                          actionText: 'Tekrar Dene',
                          onAction: () => _fetchClubs(reset: true),
                        ),
                      )
                    else if (_clubs.isEmpty)
                      const SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Kulüp Bulunamadı',
                          message:
                              'Aramanızla eşleşen bir kulüp bulunamadı.',
                          icon: Icons.search_off_rounded,
                          compact: true,
                        ),
                      )
                    else
                      ListenableBuilder(
                        listenable: SelectedClubService.instance,
                        builder: (context, _) => Column(
                          children: [
                            for (final c in _clubs) _buildClubCard(palette, c),
                            if (_hasMore)
                              Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.sm),
                                child: Center(
                                  child: TextButton(
                                    onPressed: _isLoadingMore
                                        ? null
                                        : () => _fetchClubs(reset: false),
                                    child: _isLoadingMore
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: palette.accent,
                                            ),
                                          )
                                        : Text(
                                            'Daha Fazla Yükle',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: palette.accent,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.sm,
        AppSpacing.s20,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          GlassCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Geri',
            onTap: () => Navigator.of(context).pop(),
          ),
          AppSpacing.h12,
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
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  'Kulüp seç, müsabakaları ve sporcuları takip et',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppColorPalette palette) {
    return SoftGlassPanel(
      level: 3,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20,
            color: palette.textSecondary,
          ),
          AppSpacing.hSm,
          Expanded(
            child: TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _onFiltersChanged(),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14.5,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Kulüp adı yazın (örn. Fenerbahçe, Enka)...',
                hintStyle: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: palette.textSecondary.withValues(alpha: 0.75),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (_queryController.text.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
              onPressed: () {
                _queryController.clear();
                _onFiltersChanged();
              },
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildCityBar(AppColorPalette palette) {
    return SoftGlassPanel(
      level: 2,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 18,
            color: palette.textSecondary,
          ),
          AppSpacing.hSm,
          Expanded(
            child: TextField(
              controller: _cityController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _onFiltersChanged(),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'İl (ör. İstanbul, Ankara, İzmir)...',
                hintStyle: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13.5,
                  color: palette.textSecondary.withValues(alpha: 0.75),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (_cityController.text.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
              onPressed: () {
                _cityController.clear();
                _onFiltersChanged();
              },
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildAlphabetBar(AppColorPalette palette) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _alphabet.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final letter = _alphabet[index];
          final isAll = letter == 'Tümü';
          final isSelected = isAll
              ? _selectedLetter == null
              : _selectedLetter == letter;
          return Material(
            color: isSelected
                ? palette.accent
                : palette.surfaceSecondary.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectLetter(letter),
              child: Container(
                constraints: BoxConstraints(minWidth: isAll ? 52 : 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? palette.textOnContrast
                        : palette.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedClubBanner(AppColorPalette palette) {
    final clubService = SelectedClubService.instance;
    if (!clubService.hasSelectedClub) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: SoftGlassPanel(
        level: 2,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () {
          ClubSearchScreen.showClubActionsSheet(
            context,
            club: ClubSearchItem(
              id: clubService.clubId,
              name: clubService.clubName!,
              athleteCount: 0,
            ),
            repository: widget.repository,
            onMeetSelected: widget.onMeetSelected,
          );
        },
        child: Row(
          children: [
            Icon(
              Icons.star_rounded,
              size: 18,
              color: palette.statusWarning,
            ),
            AppSpacing.hSm,
            Expanded(
              child: Text(
                'Seçili Takım: ${StringUtils.toTitleCase(clubService.clubName!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => clubService.clearClub(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Kaldır',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClubCard(AppColorPalette palette, ClubSearchItem club) {
    final isSelected =
        SelectedClubService.instance.matches(club.name, club.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftGlassPanel(
        level: 2,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          ClubSearchScreen.showClubActionsSheet(
            context,
            club: club,
            repository: widget.repository,
            onMeetSelected: widget.onMeetSelected,
          );
        },
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                club.isSchool ? Icons.school_outlined : Icons.shield_outlined,
                size: 20,
                color: palette.accent,
              ),
            ),
            AppSpacing.h12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    StringUtils.toTitleCase(club.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (club.isSchool) 'Okul',
                      if (club.city != null)
                        StringUtils.toTitleCase(club.city!),
                      '${club.athleteCount} Kayıtlı Sporcu',
                    ].join(' · '),
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
            if (isSelected) ...[
              AppSpacing.hSm,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: AppRadius.full,
                ),
                child: Text(
                  'Seçili',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
              ),
            ] else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      children: List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: AppSkeleton.card(height: 68),
        ),
      ),
    );
  }
}

class _ClubActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ClubActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SoftGlassPanel(
      level: 2,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          AppSpacing.h12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
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
            size: 18,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }
}
