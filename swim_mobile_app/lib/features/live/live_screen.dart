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
/// Soft Glass + Ambient Glass + Cool Sophisticated tasarım dili.
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
      artHeight: 260,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Editoryal Üst Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TÜRKİYE YÜZME FEDERASYONU',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Canlı Müsabakalar',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
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
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 112),
                              children: [
                                // Seçici Soft Glass Hero Özet Paneli
                                if (_liveMeets.isNotEmpty) ...[
                                  _buildLiveOverviewHero(palette),
                                  const SizedBox(height: 18),
                                ],

                                // Minimalist Arama Girişi
                                Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.surfaceGlassStrong,
                                    borderRadius: AppRadius.inputRadius,
                                    border: Border.all(
                                      color: palette.isDark
                                          ? palette.border
                                          : palette.glassBorder,
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.softShadow,
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                        spreadRadius: -4,
                                      ),
                                    ],
                                  ),
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
                                    height: 38,
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

                                        return ChoiceChip(
                                          label: Text(label),
                                          selected: isSelected,
                                          onSelected: (_) {
                                            setState(() {
                                              _selectedCity =
                                                  isSelected && !isAll
                                                      ? null
                                                      : city;
                                            });
                                          },
                                          labelStyle: TextStyle(
                                            fontFamily: AppTextStyles.fontFamily,
                                            fontSize: 12.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onPrimary
                                                : palette.textSecondary,
                                          ),
                                          selectedColor: palette.primary,
                                          backgroundColor: palette.surface
                                              .withValues(alpha: 0.85),
                                          side: BorderSide(
                                            color: isSelected
                                                ? palette.primary
                                                : palette.border,
                                            width: 1.0,
                                          ),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: AppRadius.medium,
                                          ),
                                          showCheckmark: false,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],

                                // Bölüm Başlığı
                                SectionHeader(
                                  title: _selectedCity == null
                                      ? 'Aktif Müsabakalar'
                                      : '$_selectedCity Müsabakaları',
                                  trailingText: '${meets.length} Yarış',
                                ),
                                const SizedBox(height: 14),

                                // Müsabaka Listesi
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

  /// Üst Soft Glass Özet Paneli (Distinctive hero composition)
  Widget _buildLiveOverviewHero(AppColorPalette palette) {
    final cityCount = _availableCities.length;

    return SoftGlassPanel(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      artStyle: AmbientArtStyle.contourWaves,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.statusLiveBg,
                  borderRadius: AppRadius.full,
                  border: Border.all(
                    color: palette.statusLive.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.statusLive,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CANLI AKIŞ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: palette.statusLive,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Anlık Havuz Verisi',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
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
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: palette.divider,
    );
  }

  Widget _buildLiveMeetCard(LiveMeetSummary meet, AppColorPalette palette) {
    final resTotal = meet.resultListProgress.total;
    final resProcessed = meet.resultListProgress.processed;
    final resRatio =
        resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: palette.border,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.softShadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: () => _openLiveDetail(meet),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Üst Rozet Satırı
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.statusLiveBg,
                        borderRadius: AppRadius.full,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: palette.statusLive,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'CANLI',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: palette.statusLive,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.people_outline_rounded,
                      size: 14,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${meet.totalAthletes} Sporcu',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Müsabaka Başlığı
                Text(
                  meet.name,
                  style: AppTextStyles.raceTitle.copyWith(
                    fontSize: 16.5,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),

                // 3. Şehir ve Tarih
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13.5,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      meet.city.isNotEmpty ? meet.city : 'Türkiye',
                      style: AppTextStyles.categorySeries.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    if (meet.date.isNotEmpty) ...[
                      Text(
                        '  ·  ',
                        style: TextStyle(color: palette.textMuted),
                      ),
                      Text(
                        meet.date,
                        style: AppTextStyles.categorySeries.copyWith(
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // 4. İnce 1px Ayırıcı & İlerleme
                Divider(height: 1, thickness: 1, color: palette.divider),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sonuçlanan Yarışlar',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      '$resProcessed / $resTotal  (%$resPercent)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: palette.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: resRatio,
                    backgroundColor: palette.surfaceSecondary,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                    minHeight: 4.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
