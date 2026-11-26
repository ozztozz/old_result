import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/brand_header_bar.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../live/live_meet_detail_screen.dart';

/// Keşfet — Gelişmiş Müsabaka / Yarış Arama ve Filtreleme Ekranı
class MeetSearchScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;
  final String? initialClub;

  const MeetSearchScreen({
    super.key,
    required this.repository,
    this.onMeetSelected,
    this.initialClub,
  });

  @override
  State<MeetSearchScreen> createState() => _MeetSearchScreenState();
}

class _MeetSearchScreenState extends State<MeetSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _clubController = TextEditingController();
  final TextEditingController _athleteController = TextEditingController();

  String _selectedYear = 'Tümü';
  String _selectedGender = 'Tümü';
  bool _filtersExpanded = true;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  int _page = 1;
  List<MeetSummary> _meets = [];

  Timer? _debounce;

  static const List<String> _yearOptions = [
    'Tümü',
    '2026',
    '2025',
    '2024',
    '2023',
  ];

  static const List<String> _genderOptions = [
    'Tümü',
    'Erkek',
    'Kadın',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialClub != null && widget.initialClub!.trim().isNotEmpty) {
      _clubController.text = widget.initialClub!.trim();
    }
    _fetchMeets(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _cityController.dispose();
    _clubController.dispose();
    _athleteController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _queryController.text.trim().isNotEmpty ||
      _cityController.text.trim().isNotEmpty ||
      _clubController.text.trim().isNotEmpty ||
      _athleteController.text.trim().isNotEmpty ||
      _selectedYear != 'Tümü' ||
      _selectedGender != 'Tümü';

  void _onFilterTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchMeets(reset: true);
    });
    setState(() {});
  }

  void _clearFilters() {
    _debounce?.cancel();
    _queryController.clear();
    _cityController.clear();
    _clubController.clear();
    _athleteController.clear();
    setState(() {
      _selectedYear = 'Tümü';
      _selectedGender = 'Tümü';
    });
    _fetchMeets(reset: true);
  }

  Future<void> _fetchMeets({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    final targetPage = reset ? 1 : _page + 1;
    try {
      final list = await widget.repository.searchMeets(
        page: targetPage,
        year: _selectedYear == 'Tümü' ? null : _selectedYear,
        city: _cityController.text.trim(),
        q: _queryController.text.trim(),
        club: _clubController.text.trim(),
        athlete: _athleteController.text.trim(),
        gender: _selectedGender == 'Tümü' ? null : _selectedGender,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _meets = list;
        } else {
          _meets = [..._meets, ...list];
          _page = targetPage;
        }
        _hasMore = list.length >= 20;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          _errorMessage = 'Müsabakalar aranırken bir sorun oluştu.';
        }
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _openMeetDetail(MeetSummary meet) {
    if (widget.onMeetSelected != null) {
      widget.onMeetSelected!(meet);
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
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ResponsiveCenter(
          maxWidth: 1040,
          child: SafeArea(
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
                    AppSpacing.v12,
                    _buildFilterPanel(palette),
                    AppSpacing.vLg,
                    if (_isLoading)
                      _buildLoadingSkeleton()
                    else if (_errorMessage != null && _meets.isEmpty)
                      SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Bağlantı Hatası',
                          message: _errorMessage!,
                          icon: Icons.cloud_off_outlined,
                          actionText: 'Tekrar Dene',
                          onAction: () => _fetchMeets(reset: true),
                        ),
                      )
                    else if (_meets.isEmpty)
                      const SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Müsabaka Bulunamadı',
                          message:
                              'Seçilen filtrelere uygun yarış veya müsabaka bulunamadı.',
                          icon: Icons.search_off_rounded,
                          compact: true,
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Sonuçlar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            AppSpacing.hSm,
                            Flexible(
                              child: Text(
                                '${_meets.length} Müsabaka',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: palette.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final meet in _meets) _buildMeetRow(meet, palette),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Center(
                            child: TextButton(
                              onPressed: _isLoadingMore
                                  ? null
                                  : () => _fetchMeets(reset: false),
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
                                      'Daha Fazla Göster',
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: palette.accent,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                    ],
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

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    return BrandHeaderBar(
      subtitle: 'Müsabaka Arama',
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.sm,
      ),
      actions: [
        if (_hasActiveFilters)
          TextButton(
            onPressed: _clearFilters,
            child: Text(
              'Temizle',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ),
        GlassCircleButton(
          icon: _filtersExpanded
              ? Icons.filter_list_off_rounded
              : Icons.filter_list_rounded,
          iconSize: 20,
          iconColor: _hasActiveFilters ? palette.accent : palette.textTertiary,
          tooltip: _filtersExpanded ? 'Filtreleri Gizle' : 'Filtreleri Göster',
          onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
        ),
      ],
    );
  }

  Widget _buildSearchBar(AppColorPalette palette) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.border.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.textPrimary.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_outlined, size: 20, color: palette.textSecondary),
          AppSpacing.h12,
          Expanded(
            child: TextField(
              controller: _queryController,
              onChanged: (_) => _onFilterTextChanged(),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14.5,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Müsabaka adı ara...',
                hintStyle: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: palette.textSecondary.withValues(alpha: 0.85),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_queryController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _queryController.clear();
                _onFilterTextChanged();
              },
              child: Icon(
                Icons.close_outlined,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(AppColorPalette palette) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _filtersExpanded
          ? SoftGlassPanel(
              level: 2,
              borderRadius: AppRadius.cardRadius,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yıl',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  AppSpacing.vXs,
                  ModernFilterChipBar(
                    chips: _yearOptions
                        .map((y) => FilterChipItem(label: y))
                        .toList(),
                    selectedChip: _selectedYear,
                    onSelected: (val) {
                      setState(() => _selectedYear = val);
                      _fetchMeets(reset: true);
                    },
                  ),
                  AppSpacing.v12,
                  Text(
                    'Cinsiyet',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  AppSpacing.vXs,
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: _genderOptions.map((g) {
                      return ModernFilterChip(
                        label: g,
                        isSelected: _selectedGender == g,
                        onTap: () {
                          setState(() => _selectedGender = g);
                          _fetchMeets(reset: true);
                        },
                      );
                    }).toList(),
                  ),
                  AppSpacing.v12,
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactFilterField(
                          palette,
                          controller: _cityController,
                          hint: 'İl (ör. Ankara)',
                          icon: Icons.location_on_outlined,
                        ),
                      ),
                      AppSpacing.hSm,
                      Expanded(
                        child: _buildCompactFilterField(
                          palette,
                          controller: _clubController,
                          hint: 'Takım / Kulüp',
                          icon: Icons.shield_outlined,
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.vSm,
                  _buildCompactFilterField(
                    palette,
                    controller: _athleteController,
                    hint: 'Sporcu adı',
                    icon: Icons.person_outline_rounded,
                  ),
                  if (SelectedClubService.instance.hasSelectedClub &&
                      _clubController.text.trim().isEmpty) ...[
                    AppSpacing.vSm,
                    GestureDetector(
                      onTap: () {
                        _clubController.text =
                            SelectedClubService.instance.clubName ?? '';
                        _onFilterTextChanged();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            size: 14,
                            color: palette.accent,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Takımımı uygula: ${StringUtils.toTitleCase(SelectedClubService.instance.clubName ?? '')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildCompactFilterField(
    AppColorPalette palette, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.border.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => _onFilterTextChanged(),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12.5,
                  color: palette.textSecondary.withValues(alpha: 0.85),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                _onFilterTextChanged();
              },
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMeetRow(MeetSummary meet, AppColorPalette palette) {
    final is25m = meet.course == 'SC';
    final courseColor = is25m ? palette.infoCyan : palette.accent;
    final cityText = meet.city.isNotEmpty ? meet.city : 'Türkiye';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftGlassPanel(
        level: 2,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _openMeetDetail(meet),
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
                    '$cityText · ${meet.startDate}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 68),
        AppSpacing.v12,
        AppSkeleton.card(height: 68),
        AppSpacing.v12,
        AppSkeleton.card(height: 68),
      ],
    );
  }
}
