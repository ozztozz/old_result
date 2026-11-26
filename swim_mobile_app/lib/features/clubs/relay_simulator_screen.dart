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
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../athletes/athlete_profile_screen.dart';

/// Kulüp Bayrak Takımı Simülatörü (4x50 / 4x100 Serbest & Karışık).
class RelaySimulatorScreen extends StatefulWidget {
  final SwimRepository repository;

  const RelaySimulatorScreen({super.key, required this.repository});

  @override
  State<RelaySimulatorScreen> createState() => _RelaySimulatorScreenState();
}

class _RelaySimulatorScreenState extends State<RelaySimulatorScreen> {
  final TextEditingController _clubSearchCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  late final FocusNode _clubSearchFocusNode;
  late final FocusNode _yearFocusNode;
  bool _isClubSearchFocused = false;
  bool _isYearFocused = false;
  Timer? _debounce;

  int? _clubId;
  String? _clubName;
  bool _searchingClubs = false;
  List<ClubSearchItem> _clubResults = [];

  String _relayType = '4x50_free';
  String _gender = 'Erkek';
  String _course = 'LC';

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _simData;

  @override
  void initState() {
    super.initState();
    _clubSearchFocusNode = FocusNode()..addListener(_handleFocusChange);
    _yearFocusNode = FocusNode()..addListener(_handleFocusChange);
    final sel = SelectedClubService.instance;
    if (sel.hasSelectedClub) {
      _clubId = sel.clubId;
      _clubName = sel.clubName;
      _runSimulation();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clubSearchFocusNode.removeListener(_handleFocusChange);
    _yearFocusNode.removeListener(_handleFocusChange);
    _clubSearchFocusNode.dispose();
    _yearFocusNode.dispose();
    _clubSearchCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    if (_isClubSearchFocused != _clubSearchFocusNode.hasFocus ||
        _isYearFocused != _yearFocusNode.hasFocus) {
      setState(() {
        _isClubSearchFocused = _clubSearchFocusNode.hasFocus;
        _isYearFocused = _yearFocusNode.hasFocus;
      });
    }
  }

  void _onClubSearchChanged(String q) {
    _debounce?.cancel();
    final t = q.trim();
    if (t.length < 2) {
      setState(() {
        _clubResults = [];
        _searchingClubs = false;
      });
      return;
    }
    setState(() => _searchingClubs = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await widget.repository.searchGlobal(t);
        if (mounted) {
          setState(() {
            _clubResults = res.clubs;
            _searchingClubs = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingClubs = false);
      }
    });
  }

  Future<void> _runSimulation() async {
    if (_clubId == null && (_clubName == null || _clubName!.isEmpty)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final y = int.tryParse(_yearCtrl.text.trim());
      final data = await widget.repository.getRelaySimulator(
        clubId: _clubId,
        clubName: _clubName,
        relayType: _relayType,
        gender: _gender,
        course: _course,
        birthYear: y,
      );
      if (mounted) {
        setState(() {
          _simData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Bayrak simülasyonu hesaplanamadı.';
          _loading = false;
        });
      }
    }
  }

  static const _relayOptions = [
    ('4x50_free', '4x50 Serbest'),
    ('4x100_free', '4x100 Serbest'),
    ('4x50_medley', '4x50 Karışık'),
    ('4x100_medley', '4x100 Karışık'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final legs = (_simData?['legs'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final totalTime = _simData?['total_time'] as String?;
    final complete = _simData?['complete'] == true;

    final relayChips = _relayOptions
        .map((r) => FilterChipItem(label: r.$2))
        .toList();
    final selectedRelayLabel = _relayOptions
        .firstWhere((r) => r.$1 == _relayType, orElse: () => _relayOptions.first)
        .$2;

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
                    // 1. Kulüp Seçimi
                    if (_clubName != null) ...[
                      SoftGlassPanel(
                        level: 3,
                        borderRadius: AppRadius.cardRadius,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.s12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: palette.primary,
                              size: 20,
                            ),
                            AppSpacing.hSm,
                            Expanded(
                              child: Text(
                                StringUtils.toTitleCase(_clubName!),
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            AppSpacing.hSm,
                            TextButton(
                              onPressed: () => setState(() {
                                _clubId = null;
                                _clubName = null;
                                _simData = null;
                              }),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                'Değiştir',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vMd,
                    ] else ...[
                      SoftGlassPanel(
                        level: 3,
                        height: 48,
                        borderRadius: BorderRadius.circular(24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        animationDuration: const Duration(milliseconds: 180),
                        fillAlphaOverride: palette.isDark
                            ? (_isClubSearchFocused ? 0.15 : 0.09)
                            : (_isClubSearchFocused ? 0.20 : 0.14),
                        borderAlphaOverride: palette.isDark
                            ? (_isClubSearchFocused ? 0.34 : 0.16)
                            : (_isClubSearchFocused ? 0.50 : 0.25),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_outlined,
                              color: palette.textSecondary,
                              size: 20,
                            ),
                            AppSpacing.h12,
                            Expanded(
                              child: TextField(
                                controller: _clubSearchCtrl,
                                focusNode: _clubSearchFocusNode,
                                onChanged: _onClubSearchChanged,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14.5,
                                  color: palette.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Kulüp ara (ör. Enka, Fenerbahçe)...',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 14,
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
                            if (_searchingClubs)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_clubResults.isNotEmpty) ...[
                        AppSpacing.vSm,
                        SoftGlassPanel(
                          level: 2,
                          borderRadius: AppRadius.cardRadius,
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: _clubResults
                                .take(8)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final idx = entry.key;
                              final c = entry.value;
                              final isLast =
                                  idx == (_clubResults.take(8).length - 1);
                              return Column(
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                      Icons.shield_outlined,
                                      color: palette.primary,
                                      size: 20,
                                    ),
                                    title: Text(
                                      StringUtils.toTitleCase(c.name),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _clubId = c.id;
                                        _clubName = c.name;
                                        _clubResults = [];
                                        _clubSearchCtrl.clear();
                                      });
                                      _runSimulation();
                                    },
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      color: palette.divider,
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ] else if (!_searchingClubs) ...[
                        AppSpacing.vLg,
                        SoftGlassPanel(
                          level: 2,
                          borderRadius: AppRadius.cardRadius,
                          padding: AppSpacing.paddingAllLg,
                          child: EmptyStateWidget(
                            title: 'Kulüp seçilmedi',
                            message:
                                'Bayrak kadrosu simüle etmek için yukarıdan bir kulüp arayın veya seçin.',
                            icon: Icons.shield_outlined,
                            actionText: 'Kulüp Seç',
                            onAction: () => _clubSearchFocusNode.requestFocus(),
                            compact: true,
                          ),
                        ),
                      ],
                      AppSpacing.vMd,
                    ],

                    // 2. Filtreler
                    if (_clubName != null) ...[
                      ModernFilterChipBar(
                        chips: relayChips,
                        selectedChip: selectedRelayLabel,
                        onSelected: (label) {
                          final match = _relayOptions.firstWhere(
                            (r) => r.$2 == label,
                            orElse: () => _relayOptions.first,
                          );
                          setState(() => _relayType = match.$1);
                          _runSimulation();
                        },
                      ),
                      AppSpacing.vSm,
                      _buildGenderPoolYearRow(context, palette),
                      AppSpacing.vMd,
                    ],

                    // 3. Simülasyon Durumları & Sonuçlar
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
                          onAction: _runSimulation,
                          compact: true,
                        ),
                      )
                    else if (_simData != null) ...[
                      // Tahmini Toplam Süre Kartı (Level 1 Hero cam yüzey)
                      SoftGlassPanel(
                        level: 1,
                        tier: GlassTier.hero,
                        ambientGlowBehind: true,
                        borderRadius: AppRadius.rounded,
                        padding: const EdgeInsets.all(AppSpacing.s20),
                        artStyle: AmbientArtStyle.none,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    complete
                                        ? 'Tahmini En Hızlı Bayrak'
                                        : 'Yeterli Sporcu Bulunamadı',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: complete
                                                  ? palette.accent
                                                  : palette.statusWarning,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          AppSpacing.vXs,
                                          Text(
                                            'Son 2 yıl PB derecelerine göre otomatik kadro',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 12.5,
                                              color: palette.textSecondary,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppSpacing.h12,
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 148,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          totalTime ?? '--:--.--',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.5,
                                            color: complete
                                                ? palette.textPrimary
                                                : palette.textSecondary,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      AppSpacing.vMd,

                      // 4 Ayak Kadro Listesi (Level 2)
                      if (legs.isEmpty)
                        const SoftGlassPanel(
                          level: 2,
                          borderRadius: AppRadius.cardRadius,
                          padding: AppSpacing.paddingAllLg,
                          child: EmptyStateWidget(
                            title: 'Yeterli sporcu bulunamadı',
                            message:
                                'Seçilen bayrak türü ve yaş kriteri için uygun 4 sporcu bulunamadı.',
                            icon: Icons.groups_outlined,
                            compact: true,
                          ),
                        )
                      else
                        SoftGlassPanel(
                          level: 2,
                          borderRadius: AppRadius.cardRadius,
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: legs.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final leg = entry.value;
                              final isLast = idx == legs.length - 1;
                              return _buildLegRow(
                                context,
                                palette,
                                leg: leg,
                                showDivider: !isLast,
                              );
                            }).toList(),
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

  Widget _buildGenderPoolYearRow(
    BuildContext context,
    AppColorPalette palette,
  ) {
    final chips = [
      _buildCompactChip(
        palette,
        label: 'Erkek',
        isSelected: _gender == 'Erkek',
        onTap: () {
          setState(() => _gender = 'Erkek');
          _runSimulation();
        },
      ),
      _buildCompactChip(
        palette,
        label: 'Kadın',
        isSelected: _gender == 'Kadın',
        onTap: () {
          setState(() => _gender = 'Kadın');
          _runSimulation();
        },
      ),
      _buildCompactChip(
        palette,
        label: '50m',
        isSelected: _course == 'LC',
        onTap: () {
          setState(() => _course = 'LC');
          _runSimulation();
        },
      ),
      _buildCompactChip(
        palette,
        label: '25m',
        isSelected: _course == 'SC',
        onTap: () {
          setState(() => _course = 'SC');
          _runSimulation();
        },
      ),
    ];

    final yearField = SoftGlassPanel(
      level: 3,
      height: 40,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
      animationDuration: const Duration(milliseconds: 180),
      fillAlphaOverride: palette.isDark
          ? (_isYearFocused ? 0.14 : 0.08)
          : (_isYearFocused ? 0.20 : 0.14),
      borderAlphaOverride: palette.isDark
          ? (_isYearFocused ? 0.24 : 0.12)
          : (_isYearFocused ? 0.40 : 0.25),
      child: Center(
        child: TextField(
          controller: _yearCtrl,
          focusNode: _yearFocusNode,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _runSimulation(),
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13.5,
            color: palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: 'D.Yılı',
            hintStyle: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13,
              color: palette.textSecondary,
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

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (textScale <= 1.1 && constraints.maxWidth >= 320) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                chips[i],
                const SizedBox(width: 6),
              ],
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 96),
                  child: yearField,
                ),
              ),
            ],
          );
        }

        return Wrap(
          spacing: 6,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...chips,
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, maxWidth: 120),
              child: yearField,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactChip(
    AppColorPalette palette, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return SoftGlassPanel(
      level: 3,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
      borderRadius: AppRadius.chipRadius,
      animationDuration: const Duration(milliseconds: 180),
      fillColorOverride: isSelected ? palette.activeChipFill : null,
      borderAlphaOverride: isSelected ? palette.activeChipBorderAlpha : null,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? palette.activeChipText : palette.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColorPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s12,
        AppSpacing.s20,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GlassCircleButton(
            icon: Icons.arrow_back_outlined,
            iconSize: 20,
            iconColor: palette.textTertiary,
            tooltip: 'Geri',
            onTap: () => Navigator.maybePop(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      children: [
        AppSkeleton.card(height: 88),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
        AppSpacing.v12,
        AppSkeleton.card(height: 60),
      ],
    );
  }

  Widget _buildLegRow(
    BuildContext context,
    AppColorPalette palette, {
    required Map<String, dynamic> leg,
    required bool showDivider,
  }) {
    final athId = leg['athlete_id'] as int;
    final rawName = leg['athlete_name'] as String? ?? '';
    final athleteName = StringUtils.formatAthleteName(rawName);
    final strokeLabel = StringUtils.toTitleCase(
      leg['stroke_label'] as String? ?? '',
    );
    final detailText =
        '${leg['distance']}m $strokeLabel${leg['birth_year'] != null ? ' • ${leg['birth_year']}' : ''}';

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
                    // Col 1: Ayak numarası (sessiz düz çip)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.textPrimary.withValues(
                          alpha: palette.isDark ? 0.08 : 0.05,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: palette.isDark ? 0.12 : 0.25,
                          ),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${leg['leg']}',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    AppSpacing.h12,

                    // Col 2: Sporcu adı & branş/doğum yılı
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
                            detailText,
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
                        ],
                      ),
                    ),
                    AppSpacing.h12,

                    // Col 3: Ayak derecesi
                    Text(
                      leg['time'] as String? ?? '',
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
