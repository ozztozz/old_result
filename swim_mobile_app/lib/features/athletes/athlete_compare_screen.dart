import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';

/// İki Sporcuyu Yan Yana Karşılaştırma Ekranı (Head-to-Head).
class AthleteCompareScreen extends StatefulWidget {
  final AthleteDetail athleteA;
  final SwimRepository repository;

  const AthleteCompareScreen({
    super.key,
    required this.athleteA,
    required this.repository,
  });

  @override
  State<AthleteCompareScreen> createState() => _AthleteCompareScreenState();
}

class _AthleteCompareScreenState extends State<AthleteCompareScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<AthleteSearchItem> _searchResults = [];

  AthleteDetail? _athleteB;
  bool _loadingB = false;
  String _course = 'LC'; // 'LC' (50m) veya 'SC' (25m)

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await widget.repository.searchGlobal(trimmed);
        if (mounted) {
          setState(() {
            _searchResults = res.athletes.where((a) => a.id != widget.athleteA.id).toList();
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectAthleteB(int id) async {
    setState(() {
      _loadingB = true;
      _searchResults = [];
      _searchCtrl.clear();
    });
    try {
      final detail = await widget.repository.getAthleteDetail(id);
      if (mounted) {
        setState(() {
          _athleteB = detail;
          _loadingB = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingB = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sporcu verisi yüklenemedi.')),
        );
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
        title: Text(
          'Sporcu Karşılaştırma',
          style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // Üst Sporcu Kartları (A vs B)
          Row(
            children: [
              Expanded(child: _buildAthleteHeaderCard(palette, widget.athleteA, isA: true)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: palette.primary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _athleteB != null
                    ? _buildAthleteHeaderCard(
                        palette,
                        _athleteB!,
                        isA: false,
                        onClear: () => setState(() => _athleteB = null),
                      )
                    : _buildEmptyBCard(palette),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sporcu B Arama Kutusu
          if (_athleteB == null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.inputRadius,
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_search_rounded, size: 18, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: TextStyle(fontSize: 14, color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Karşılaştırılacak 2. sporcuyu ara...',
                        hintStyle: TextStyle(fontSize: 13.5, color: palette.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searching)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                    ),
                ],
              ),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: _searchResults.take(8).map((item) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (item.birthYear != null) '${item.birthYear}',
                          item.clubName,
                        ].join(' • '),
                        style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                      ),
                      trailing: Icon(Icons.add_circle_outline_rounded, color: palette.primary, size: 20),
                      onTap: () => _selectAthleteB(item.id),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],

          if (_loadingB)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: palette.primary)),
            ),

          // Karşılaştırma İçeriği
          if (_athleteB != null && !_loadingB) ...[
            // Kulvar Seçici (50m / 25m)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: palette.surfaceSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildCourseButton(palette, 'LC', '50m Uzun Kulvar'),
                  _buildCourseButton(palette, 'SC', '25m Kısa Kulvar'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Kariyer Özeti Karşılaştırması
            _buildStatsComparisonCard(palette, widget.athleteA, _athleteB!),
            const SizedBox(height: 14),

            // Branş Bazlı PB Karşılaştırma Tablosu
            _buildPbComparisonTable(palette, widget.athleteA, _athleteB!),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseButton(AppColorPalette palette, String code, String label) {
    final active = _course == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _course = code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? palette.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [BoxShadow(color: palette.textPrimary.withValues(alpha: 0.05), blurRadius: 3)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? palette.textPrimary : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAthleteHeaderCard(
    AppColorPalette palette,
    AthleteDetail a, {
    required bool isA,
    VoidCallback? onClear,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: isA ? palette.primary.withValues(alpha: 0.45) : palette.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a.name,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded, size: 16, color: palette.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (a.birthYear != null) '${a.birthYear}',
              a.clubName,
            ].join(' • '),
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 10.5,
              color: palette.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBCard(AppColorPalette palette) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.5),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: palette.border, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2. Sporcu Seçin',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Aşağıdan arayın',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 10.5,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsComparisonCard(AppColorPalette palette, AthleteDetail a, AthleteDetail b) {
    Widget rowItem(String label, int valA, int valB) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                '$valA',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13.5,
                  fontWeight: valA > valB ? FontWeight.w700 : FontWeight.w500,
                  color: valA > valB ? palette.statusSuccess : palette.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$valB',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13.5,
                  fontWeight: valB > valA ? FontWeight.w700 : FontWeight.w500,
                  color: valB > valA ? palette.statusSuccess : palette.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          rowItem('Toplam Yarış', a.stats.totalRaces, b.stats.totalRaces),
          Divider(height: 1, color: palette.divider),
          rowItem('Kürsü', a.stats.podiumCount, b.stats.podiumCount),
          Divider(height: 1, color: palette.divider),
          rowItem('Geçilen Baraj', a.stats.standardsPassed, b.stats.standardsPassed),
        ],
      ),
    );
  }

  Widget _buildPbComparisonTable(AppColorPalette palette, AthleteDetail a, AthleteDetail b) {
    final pbsA = _course == 'SC' ? a.pbs25m : a.pbs50m;
    final pbsB = _course == 'SC' ? b.pbs25m : b.pbs50m;

    final mapA = <String, PersonalBest>{};
    for (final p in pbsA) {
      mapA['${p.stroke}_${p.distance}'] = p;
    }
    final mapB = <String, PersonalBest>{};
    for (final p in pbsB) {
      mapB['${p.stroke}_${p.distance}'] = p;
    }

    final allKeys = <String>{...mapA.keys, ...mapB.keys}.toList();
    const order = {'free': 1, 'back': 2, 'breast': 3, 'fly': 4, 'medley': 5};
    allKeys.sort((k1, k2) {
      final p1 = mapA[k1] ?? mapB[k1]!;
      final p2 = mapA[k2] ?? mapB[k2]!;
      final o1 = order[p1.stroke] ?? 9;
      final o2 = order[p2.stroke] ?? 9;
      if (o1 != o2) return o1.compareTo(o2);
      return p1.distance.compareTo(p2.distance);
    });

    if (allKeys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: palette.border),
        ),
        child: Text(
          'Seçili kulvarda karşılaştırılacak PB derecesi bulunamadı.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: palette.textSecondary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: allKeys.asMap().entries.map((entry) {
          final idx = entry.key;
          final key = entry.value;
          final pa = mapA[key];
          final pb = mapB[key];
          final sample = pa ?? pb!;
          final csA = pa?.timeCs;
          final csB = pb?.timeCs;
          final bool bothHave = csA != null && csB != null;
          final bool aFaster = bothHave && csA < csB;
          final bool bFaster = bothHave && csB < csA;

          String diffStr = '';
          if (bothHave) {
            final diff = (csA - csB).abs() / 100.0;
            diffStr = csA == csB ? '0.00' : '${aFaster ? '-' : '+'}${diff.toStringAsFixed(2)}s';
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 78,
                      child: Text(
                        csA != null ? SwimTimeFormatter.formatCs(csA) : '-',
                        style: AppTextStyles.officialTime.copyWith(
                          fontSize: 13.5,
                          fontWeight: aFaster ? FontWeight.w700 : FontWeight.w500,
                          color: aFaster ? palette.statusSuccess : palette.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${sample.distance}m ${sample.strokeLabel}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          if (diffStr.isNotEmpty)
                            Text(
                              diffStr,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: aFaster
                                    ? palette.statusSuccess
                                    : (bFaster ? palette.statusDanger : palette.textSecondary),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 78,
                      child: Text(
                        csB != null ? SwimTimeFormatter.formatCs(csB) : '-',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.officialTime.copyWith(
                          fontSize: 13.5,
                          fontWeight: bFaster ? FontWeight.w700 : FontWeight.w500,
                          color: bFaster ? palette.statusSuccess : palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (idx < allKeys.length - 1) Divider(height: 1, color: palette.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}
