import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/live_meet.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLiveMeets();
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
              // 1. Editoryal Üst Başlık (Sakin, nefes alan tipografi)
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
                            'Canlı Müsabakalar',
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
                    GlassCircleButton(
                      icon: Icons.palette_outlined,
                      iconColor: palette.primary,
                      tooltip: 'Tema Seç',
                      onTap: () => ThemePickerSheet.show(context),
                    ),
                    const SizedBox(width: 8),
                    GlassCircleButton(
                      icon: Icons.refresh_rounded,
                      iconColor: palette.textPrimary,
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
                              padding: const EdgeInsets.fromLTRB(22, 8, 22, 118),
                              children: [
                                // Premium İstatistik Hero Paneli
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildLiveOverviewHero(palette),
                                  const SizedBox(height: 20),
                                ],

                                // Frosted Glass Arama Yüzeyi (Level 3)
                                SoftGlassPanel(
                                  level: 3,
                                  tier: GlassTier.subtle,
                                  borderRadius: BorderRadius.circular(16),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 3,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        color: palette.textSecondary,
                                        size: 19,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          onChanged: (val) =>
                                              setState(() => _searchQuery = val),
                                          style: TextStyle(
                                            fontFamily: AppTextStyles.fontFamily,
                                            fontSize: 14,
                                            color: palette.textPrimary,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Müsabaka veya şehir ara...',
                                            hintStyle: TextStyle(
                                              fontFamily: AppTextStyles.fontFamily,
                                              fontSize: 13.5,
                                              color: palette.textMuted,
                                            ),
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              vertical: 11,
                                            ),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // İl Filtresi
                                if (_availableCities.isNotEmpty) ...[
                                  SizedBox(
                                    height: 36,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _availableCities.length + 1,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (context, idx) {
                                        final isAll = idx == 0;
                                        final city = isAll
                                            ? null
                                            : _availableCities[idx - 1];
                                        final label = isAll ? 'Tüm İller' : city!;
                                        final isSelected = _selectedCity == city;

                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedCity =
                                                  isSelected && !isAll
                                                      ? null
                                                      : city;
                                            });
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(
                                                sigmaX: 10,
                                                sigmaY: 10,
                                              ),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 180),
                                                curve: Curves.easeOutCubic,
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? const Color(0xFF657D91)
                                                          .withValues(alpha: 0.85)
                                                      : Colors.white.withValues(
                                                          alpha: palette.isDark
                                                              ? 0.09
                                                              : 0.14,
                                                        ),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.white.withValues(
                                                      alpha: palette.isDark
                                                          ? 0.16
                                                          : 0.25,
                                                    ),
                                                    width: 1.0,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontFamily: AppTextStyles.fontFamily,
                                                    fontSize: 12.5,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                    color: isSelected
                                                        ? Colors.white
                                                        : palette.textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 22),
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
                                  ...meets.map(
                                    (m) => _buildLiveMeetCard(m, palette),
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

  /// Premium Frosted İstatistik Hero Paneli (SECOND DESIGN REFINEMENT — Section 4)
  /// Rakamların üzerinde geometrik daire yok; panel arkasında yumuşak ambient ışık,
  /// güçlü sayısal tipografi ve sakin editoryal etiketler.
  Widget _buildLiveOverviewHero(AppColorPalette palette) {
    final cityCount = _availableCities.length;

    return SoftGlassPanel(
      level: 1,
      tier: GlassTier.hero,
      ambientGlowBehind: true,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      artStyle: AmbientArtStyle.heroOrbit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Ölçülü canlı akış noktası (abartılı kırmızı rozet yerine sakin nokta)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: palette.statusLive.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 5.5,
                  height: 5.5,
                  decoration: BoxDecoration(
                    color: palette.statusLive,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Canlı akış',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Anlık havuz verisi',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Zarif yatay ayırıcı
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.divider.withValues(alpha: 0.05),
                  palette.primary.withValues(alpha: 0.22),
                  palette.divider.withValues(alpha: 0.05),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Güçlü sayısal hiyerarşi ve ferah aralıklar
          Row(
            children: [
              _buildHeroMetric(
                palette,
                value: '${_liveMeets.length}',
                label: 'Müsabaka',
              ),
              _buildHeroDivider(palette),
              _buildHeroMetric(
                palette,
                value: '$_totalAthletesAcrossLive',
                label: 'Sporcu',
              ),
              _buildHeroDivider(palette),
              _buildHeroMetric(
                palette,
                value: '$cityCount',
                label: 'Şehir',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric(
    AppColorPalette palette, {
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.9,
              height: 1.05,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDivider(AppColorPalette palette) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.divider.withValues(alpha: 0.0),
            palette.primary.withValues(alpha: 0.24),
            palette.divider.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  /// Rafine Frosted Glass Müsabaka Kartı (SECOND DESIGN REFINEMENT — Section 5)
  /// Dekoratif grafik kalabalığı olmadan saf cam malzeme, tipografi ve boşluk dengesi.
  Widget _buildLiveMeetCard(LiveMeetSummary meet, AppColorPalette palette) {
    final resTotal = meet.resultListProgress.total;
    final resProcessed = meet.resultListProgress.processed;
    final resRatio =
        resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return SoftGlassPanel(
      level: 2,
      tier: GlassTier.card,
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      onTap: () => _openLiveDetail(meet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Üst Durum & Katılım Satırı (Ölçülü canlı nokta + sade katılımcı metni)
          Row(
            children: [
              Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: palette.statusLive,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Canlı',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.statusLive,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.people_outline_rounded,
                size: 14.5,
                color: palette.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                '${meet.totalAthletes} sporcu',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Müsabaka Başlığı (Daha güçlü görsel öncelik)
          Text(
            meet.name,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 17.5,
              fontWeight: FontWeight.w600,
              height: 1.28,
              letterSpacing: -0.3,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 7),

          // 3. Şehir ve Tarih (Daha rahat okunabilir destekleyici metin)
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: palette.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                meet.city.isNotEmpty ? meet.city : 'Türkiye',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (meet.date.isNotEmpty) ...[
                Text(
                  '  ·  ',
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
                Text(
                  meet.date,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // 4. Rafine İlerleme Bölümü
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tamamlanan yarışlar',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Row(
                children: [
                  Text(
                    '$resProcessed / $resTotal',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '%$resPercent',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Sakin, rafine ilerleme çubuğu
          LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth =
                  (constraints.maxWidth * resRatio).clamp(0.0, constraints.maxWidth);
              return Container(
                height: 4.5,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: palette.isDark
                      ? palette.background.withValues(alpha: 0.50)
                      : palette.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: fillWidth,
                  height: 4.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        palette.primary,
                        palette.textPrimary,
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
  }
}
