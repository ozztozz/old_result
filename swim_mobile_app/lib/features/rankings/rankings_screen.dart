import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_button.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/brand_header_bar.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../athletes/athlete_profile_screen.dart';

/// Yaş Grubu, Branş ve İl Bazlı Top 25 Sıralamalar Ekranı.
class RankingsScreen extends StatefulWidget {
  final SwimRepository repository;

  const RankingsScreen({super.key, required this.repository});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  late final FocusNode _cityFocusNode;
  late final FocusNode _yearFocusNode;
  bool _isCityFocused = false;
  bool _isYearFocused = false;

  String _gender = 'Erkek';
  String _course = 'LC';
  String _stroke = 'free';
  int _distance = 50;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  static const _strokes = [
    ('free', 'Serbest'),
    ('back', 'Sırtüstü'),
    ('breast', 'Kurbağa'),
    ('fly', 'Kelebek'),
    ('medley', 'Karışık'),
  ];

  static const _distances = [50, 100, 200, 400, 800, 1500];

  @override
  void initState() {
    super.initState();
    _cityFocusNode = FocusNode()..addListener(_handleFocusChange);
    _yearFocusNode = FocusNode()..addListener(_handleFocusChange);
    _loadRankings();
  }

  @override
  void dispose() {
    _cityFocusNode.removeListener(_handleFocusChange);
    _yearFocusNode.removeListener(_handleFocusChange);
    _cityFocusNode.dispose();
    _yearFocusNode.dispose();
    _cityCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    if (_isCityFocused != _cityFocusNode.hasFocus ||
        _isYearFocused != _yearFocusNode.hasFocus) {
      setState(() {
        _isCityFocused = _cityFocusNode.hasFocus;
        _isYearFocused = _yearFocusNode.hasFocus;
      });
    }
  }

  Future<void> _loadRankings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final y = int.tryParse(_yearCtrl.text.trim());
      final c = _cityCtrl.text.trim();
      final list = await widget.repository.getRankings(
        stroke: _stroke,
        distance: _distance,
        gender: _gender,
        course: _course,
        birthYear: y,
        city: c.isNotEmpty ? c : null,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Sıralama verileri yüklenemedi.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final strokeChips = _strokes
        .map((s) => FilterChipItem(label: s.$2))
        .toList();
    final selectedStrokeLabel = _strokes
        .firstWhere((s) => s.$1 == _stroke, orElse: () => _strokes.first)
        .$2;

    final distanceChips = _distances
        .map((d) => FilterChipItem(label: '${d}m'))
        .toList();
    final selectedDistanceLabel = '${_distance}m';

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
                    // 1. Cinsiyet & Kulvar (Tek satır, overflow korumalı)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ModernFilterChip(
                                      label: 'Erkek',
                                      isSelected: _gender == 'Erkek',
                                      onTap: () {
                                        setState(() => _gender = 'Erkek');
                                        _loadRankings();
                                      },
                                    ),
                                    ModernFilterChip(
                                      label: 'Kadın',
                                      isSelected: _gender == 'Kadın',
                                      onTap: () {
                                        setState(() => _gender = 'Kadın');
                                        _loadRankings();
                                      },
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ModernFilterChip(
                                      label: '50m',
                                      isSelected: _course == 'LC',
                                      onTap: () {
                                        setState(() => _course = 'LC');
                                        _loadRankings();
                                      },
                                    ),
                                    ModernFilterChip(
                                      label: '25m',
                                      isSelected: _course == 'SC',
                                      onTap: () {
                                        setState(() => _course = 'SC');
                                        _loadRankings();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    AppSpacing.vSm,

                    // 2. Stil Çipleri (ModernFilterChipBar)
                    ModernFilterChipBar(
                      chips: strokeChips,
                      selectedChip: selectedStrokeLabel,
                      onSelected: (label) {
                        final match = _strokes.firstWhere(
                          (s) => s.$2 == label,
                          orElse: () => _strokes.first,
                        );
                        setState(() => _stroke = match.$1);
                        _loadRankings();
                      },
                    ),
                    AppSpacing.vSm,

                    // 3. Mesafe Çipleri (ModernFilterChipBar)
                    ModernFilterChipBar(
                      chips: distanceChips,
                      selectedChip: selectedDistanceLabel,
                      onSelected: (label) {
                        final parsed = int.tryParse(label.replaceAll('m', ''));
                        if (parsed != null) {
                          setState(() => _distance = parsed);
                          _loadRankings();
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // 4. İl ve Doğum Yılı Girişleri + Getir Butonu
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildGlassField(
                            palette: palette,
                            controller: _cityCtrl,
                            focusNode: _cityFocusNode,
                            isFocused: _isCityFocused,
                            hint: 'İl (ör. Ankara)',
                          ),
                        ),
                        AppSpacing.hSm,
                        Expanded(
                          flex: 2,
                          child: _buildGlassField(
                            palette: palette,
                            controller: _yearCtrl,
                            focusNode: _yearFocusNode,
                            isFocused: _isYearFocused,
                            hint: 'D.Yılı (2014)',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        AppSpacing.hSm,
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 88,
                            minHeight: 48,
                          ),
                          child: SizedBox(
                            height: 48,
                            child: AppButton(
                              text: 'Getir',
                              size: AppButtonSize.small,
                              onPressed: _loadRankings,
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.vMd,

                    // 5. Sonuç Tablosu / Durumlar
                    if (_loading)
                      _buildLoadingSkeleton()
                    else if (_error != null)
                      SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Bağlantı Hatası',
                          message: _error!,
                          icon: Icons.cloud_off_outlined,
                          actionText: 'Tekrar dene',
                          onAction: _loadRankings,
                          compact: true,
                        ),
                      )
                    else if (_items.isEmpty)
                      const SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: AppSpacing.paddingAllLg,
                        child: EmptyStateWidget(
                          title: 'Sonuç bulunamadı',
                          message: 'Seçilen kriterlerde sonuç bulunamadı.',
                          icon: Icons.leaderboard_outlined,
                          compact: true,
                        ),
                      )
                    else
                      SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.cardRadius,
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: _items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            final isLast = idx == _items.length - 1;
                            return _buildRankingRow(
                              context,
                              palette,
                              idx: idx,
                              item: item,
                              showDivider: !isLast,
                            );
                          }).toList(),
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
    return const BrandHeaderBar(
      subtitle: 'Top 25 Sıralama',
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.md,
      ),
    );
  }

  Widget _buildGlassField({
    required AppColorPalette palette,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isFocused,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return SoftGlassPanel(
      level: 3,
      height: 48,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      animationDuration: const Duration(milliseconds: 180),
      fillAlphaOverride: palette.isDark
          ? (isFocused ? 0.15 : 0.09)
          : (isFocused ? 0.20 : 0.14),
      borderAlphaOverride: palette.isDark
          ? (isFocused ? 0.34 : 0.16)
          : (isFocused ? 0.50 : 0.25),
      child: Center(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          onSubmitted: (_) => _loadRankings(),
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            color: palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13.5,
              color: palette.textSecondary.withValues(alpha: 0.85),
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
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
      ],
    );
  }

  Widget _buildRankingRow(
    BuildContext context,
    AppColorPalette palette, {
    required int idx,
    required Map<String, dynamic> item,
    required bool showDivider,
  }) {
    final rank = item['rank'] as int? ?? (idx + 1);
    final isPodium = rank <= 3;
    final athId = item['athlete_id'] as int;
    final rawName = item['athlete_name'] as String? ?? '';
    final athleteName = StringUtils.formatAthleteName(rawName);

    final rawClub = (item['club_name'] as String? ?? '').trim();
    final clubName = rawClub.isNotEmpty
        ? StringUtils.toTitleCase(rawClub)
        : 'Ferdi';
    final rawCity = (item['city'] as String? ?? '').trim();
    final cityName = rawCity.isNotEmpty ? StringUtils.toTitleCase(rawCity) : '';

    final yearClub = item['birth_year'] != null
        ? '${item['birth_year']} • $clubName'
        : clubName;
    final detailLine = cityName.isNotEmpty ? '$yearClub • $cityName' : yearClub;

    final chipFill = isPodium
        ? palette.accent.withValues(alpha: 0.18)
        : palette.textPrimary.withValues(alpha: palette.isDark ? 0.08 : 0.05);
    final chipBorder = isPodium
        ? palette.accent
        : (palette.isCrispCardTheme
            ? palette.border
            : Colors.white.withValues(alpha: palette.isDark ? 0.12 : 0.25));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AthleteProfileScreen(
                    athleteId: athId,
                    athleteName: rawName,
                    repository: widget.repository,
                  ),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.s12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Col 1: Sıra çipi
                    Container(
                      constraints: const BoxConstraints(minWidth: 38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: chipFill,
                        borderRadius: AppRadius.smallRadius,
                        border: Border.all(color: chipBorder, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$rank.',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight:
                              isPodium ? FontWeight.w700 : FontWeight.w600,
                          color: isPodium
                              ? palette.accent
                              : palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    AppSpacing.h12,

                    // Col 2: Sporcu adı & detay satırı
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            athleteName,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detailLine,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              color: palette.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.h12,

                    // Col 3: Derece & FINA
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item['time'] as String? ?? '',
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (item['points'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${item['points']} FINA',
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: palette.accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: palette.divider),
      ],
    );
  }
}
