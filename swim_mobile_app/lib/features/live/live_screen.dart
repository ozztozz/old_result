import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/live_meet.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/theme_picker_sheet.dart';
import 'live_meet_detail_screen.dart';

/// TYF Yüzme Sonuçları — Canlı Müsabakalar Ekranı
/// SECOND DESIGN REFINEMENT: Sakin atmosferik derinlik, gerçek frosted cam malzeme,
/// editoryal tipografi ve güçlü sayısal hiyerarşi.
class LiveScreen extends StatefulWidget {
  final SwimRepository repository;

  const LiveScreen({super.key, required this.repository});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LiveMeetSummary> _liveMeets = [];
  String _searchQuery = '';
  String? _selectedCity;
  late final FocusNode _searchFocusNode;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
    _loadLiveMeets();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted && _isSearchFocused != _searchFocusNode.hasFocus) {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    }
  }

  Future<void> _loadLiveMeets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await widget.repository.getLiveMeets();
      if (mounted) {
        setState(() {
          _liveMeets = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Canlı müsabakalar yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _openLiveDetail(LiveMeetSummary live) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMeetDetailScreen(
          live: live,
          repository: widget.repository,
        ),
      ),
    );
  }

  List<String> get _availableCities {
    final cities = <String>{};
    for (final m in _liveMeets) {
      final c = m.city.trim();
      if (c.isNotEmpty && c != '-') {
        cities.add(c);
      }
    }
    final sorted = cities.toList()..sort();
    return sorted;
  }

  List<LiveMeetSummary> get _filteredMeets {
    return _liveMeets.where((m) {
      if (_selectedCity != null && m.city.trim() != _selectedCity) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return m.name.toLowerCase().contains(q) ||
            m.city.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  int get _totalAthletesAcrossLive {
    int sum = 0;
    for (final m in _liveMeets) {
      sum += m.totalAthletes;
    }
    return sum;
  }

  static String _formatTurkishInt(int value) {
    final s = value.toString();
    return s.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
  }

  /// Türkçe karakter duyarlı Title Case dönüştürücüsü.
  /// Sadece boşluklardan böler; Ş/ş, Ç/ç, Ğ/ğ, Ü/ü, Ö/ö, İ/i, I/ı karakterlerini korur.
  static String _toTurkishTitleCase(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    return StringUtils.toTitleCase(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final meets = _filteredMeets;
    final palette = context.palette;

    return AmbientBackground(
      artStyle: AmbientArtStyle.flowLines,
      artHeight: 165,
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
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Canlı Müsabakalar',
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
                    GlassCircleButton(
                      icon: Icons.palette_outlined,
                      iconSize: 20,
                      iconColor: palette.textTertiary,
                      tooltip: 'Tema Seç',
                      onTap: () => ThemePickerSheet.show(context),
                    ),
                    const SizedBox(width: 8),
                    GlassCircleButton(
                      icon: Icons.refresh_rounded,
                      iconSize: 20,
                      iconColor: palette.textTertiary,
                      tooltip: 'Yenile',
                      onTap: _loadLiveMeets,
                    ),
                  ],
                ),
              ),

              // 2. İçerik Alanı
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: palette.primary,
                        ),
                      )
                    : _errorMessage != null && _liveMeets.isEmpty
                        ? Center(
                            child: EmptyStateWidget(
                              title: 'Bağlantı Hatası',
                              message: _errorMessage!,
                              icon: Icons.cloud_off_outlined,
                              actionText: 'Tekrar Dene',
                              onAction: _loadLiveMeets,
                            ),
                          )
                        : RefreshIndicator(
                            color: palette.primary,
                            onRefresh: _loadLiveMeets,
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(
                                22,
                                8,
                                22,
                                64 +
                                    16 +
                                    MediaQuery.of(context).padding.bottom +
                                    24,
                              ),
                              children: [
                                // Premium İstatistik Hero Paneli
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildLiveOverviewHero(palette),
                                  const SizedBox(height: 20),
                                ],

                                // Frosted Glass Arama Yüzeyi (Level 3, 180ms focus animasyonlu)
                                SoftGlassPanel(
                                  level: 3,
                                  height: 48,
                                  borderRadius: BorderRadius.circular(24),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
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
                                        Icons.search_rounded,
                                        color: palette.textSecondary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
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
                                                'Müsabaka veya şehir ara...',
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
                                const SizedBox(height: 16),

                                // İl Filtresi (Sağ kenar yumuşak fade-out)
                                if (_availableCities.isNotEmpty) ...[
                                  ModernFilterChipBar(
                                    chips: [
                                      const FilterChipItem(label: 'Tüm İller'),
                                      ..._availableCities.map(
                                        (city) => FilterChipItem(label: city),
                                      ),
                                    ],
                                    selectedChip: _selectedCity ?? 'Tüm İller',
                                    onSelected: (label) {
                                      setState(() {
                                        _selectedCity = label == 'Tüm İller' ||
                                                label == _selectedCity
                                            ? null
                                            : label;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                ],

                                // Bölüm Başlığı
                                SectionHeader(
                                  title: _selectedCity == null
                                      ? 'Aktif Müsabakalar'
                                      : '$_selectedCity Müsabakaları',
                                  trailingText: '${meets.length} yarış',
                                ),
                                const SizedBox(height: 14),

                                // Müsabaka Listesi (Gerçek Frosted Glass Kartlar)
                                if (meets.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: EmptyStateWidget(
                                      title: 'Aktif Müsabaka Bulunamadı',
                                      message:
                                          'Filtre kriterlerinize uyan canlı yarış şu anda bulunmuyor.',
                                      icon: Icons.pool_outlined,
                                    ),
                                  )
                                else
                                  for (int i = 0; i < meets.length; i++)
                                    _buildLiveMeetCard(
                                      meets[i],
                                      palette,
                                      isFirst: i == 0,
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

  /// Premium Frosted İstatistik Hero Paneli
  Widget _buildLiveOverviewHero(AppColorPalette palette) {
    final cityCount = _availableCities.length;
    final primaryTextColor = palette.textPrimary;
    final labelTextColor = palette.textSecondary;

    return SoftGlassPanel(
      level: 1,
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      artStyle: AmbientArtStyle.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulsingLiveDot(color: palette.statusLive),
              const SizedBox(width: 8),
              Text(
                'Canlı akış',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
              const Spacer(),
              Text(
                'Anlık havuz verisi',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: labelTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Güçlü sayısal hiyerarşi ve eşit hizalanmış 3 sütun
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 1,
                child: _buildHeroMetric(
                  value: _formatTurkishInt(_liveMeets.length),
                  label: 'Müsabaka',
                  numberColor: primaryTextColor,
                  labelColor: labelTextColor,
                ),
              ),
              _buildHeroDivider(),
              Expanded(
                flex: 1,
                child: _buildHeroMetric(
                  value: _formatTurkishInt(_totalAthletesAcrossLive),
                  label: 'Sporcu',
                  numberColor: primaryTextColor,
                  labelColor: labelTextColor,
                ),
              ),
              _buildHeroDivider(),
              Expanded(
                flex: 1,
                child: _buildHeroMetric(
                  value: _formatTurkishInt(cityCount),
                  label: 'Şehir',
                  numberColor: primaryTextColor,
                  labelColor: labelTextColor,
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
    required Color numberColor,
    required Color labelColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 50,
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
                    fontSize: 42,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.0,
                    color: numberColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDivider() {
    return Container(
      width: 1,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  /// Rafine Frosted Glass Müsabaka Kartı
  Widget _buildLiveMeetCard(
    LiveMeetSummary meet,
    AppColorPalette palette, {
    bool isFirst = false,
  }) {
    final resTotal = meet.resultListProgress.total;
    final resProcessed = meet.resultListProgress.processed;
    final hasNoRaces = resProcessed == 0 && resTotal == 0;
    final resRatio =
        resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();
    final isCompleted = !hasNoRaces && resTotal > 0 && resPercent >= 100;

    final isDark = palette.isDark;
    final titleColor = palette.textPrimary;
    final chipTextColor = palette.textTertiary;
    final mutedTextColor = palette.textSecondary;

    final cardBody = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Üst Durum & Katılımcı Satırı (Kırmızı yok; Steel tonlu sakin cam rozetler)
          Row(
            children: [
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.25),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Canlı',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: chipTextColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.25),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 14,
                      color: chipTextColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_formatTurkishInt(meet.totalAthletes)} sporcu',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: chipTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Müsabaka Başlığı (Türkçe duyarlı Title Case)
          Text(
            _toTurkishTitleCase(meet.name),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.2,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),

          // 3. Şehir ve Tarih Satırı
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14.5,
                color: mutedTextColor,
              ),
              const SizedBox(width: 4),
              Text(
                meet.city.isNotEmpty ? meet.city : 'Türkiye',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: mutedTextColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (meet.date.isNotEmpty) ...[
                Text(
                  '  ·  ',
                  style: TextStyle(color: mutedTextColor, fontSize: 13.5),
                ),
                Text(
                  meet.date,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: mutedTextColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // 4. İlerleme Bölümü
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tamamlanan yarışlar',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: mutedTextColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$resProcessed / $resTotal',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: mutedTextColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isCompleted) ...[
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: palette.progressCompletedIcon,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    hasNoRaces ? '–' : '%$resPercent',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: titleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // İlerleme Çubuğu (Tamamlandıysa sakin yumuşak dolgu)
          LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth = (constraints.maxWidth * resRatio)
                  .clamp(0.0, constraints.maxWidth);
              return Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.progressTrack,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: fillWidth,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: isCompleted ? palette.progressCompletedFill : null,
                    gradient: isCompleted
                        ? null
                        : LinearGradient(
                            colors: [
                              palette.progressGradientStart,
                              palette.progressGradientEnd,
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    return SoftGlassPanel(
      level: 2,
      tier: GlassTier.card,
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      onTap: () => _openLiveDetail(meet),
      child: isFirst
          ? Stack(
              children: [
                Positioned(
                  top: -70,
                  right: -70,
                  width: 220,
                  height: 220,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            palette.glowLight
                                .withValues(alpha: isDark ? 0.12 : 0.35),
                            palette.glowLight.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                cardBody,
              ],
            )
          : cardBody,
    );
  }
}

/// Canlı akış için yumuşak nabız animasyonlu kırmızı gösterge noktası.
/// Arkadaki kırmızı ışık halkası 1800ms döngüyle scale 1.0 → 1.6, opacity 0.5 → 0.0 geçişi yapar.
class _PulsingLiveDot extends StatefulWidget {
  final Color color;

  const _PulsingLiveDot({required this.color});

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.6).animate(curved);
    _opacity = Tween<double>(begin: 0.5, end: 0.0).animate(curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!disableMotion)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(alpha: _opacity.value),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 6.5,
            height: 6.5,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
