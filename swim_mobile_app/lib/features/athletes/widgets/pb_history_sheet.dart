import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/components/app_bottom_sheet.dart';
import '../../../core/theme/tokens/tokens.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/swim_time_formatter.dart';
import '../../../data/models/athlete.dart';
import '../../../data/repositories/swim_repository.dart';
import '../../../shared/widgets/status_badge.dart';

/// Sporcu En İyi Derece (PB) tıklandığında açılan yarış geçmişi ve gelişim grafiği.
class PbHistorySheet extends StatefulWidget {
  final int athleteId;
  final PersonalBest pb;
  final String strokeLabel;
  final SwimRepository repository;
  final ScrollController? sheetScrollController;

  const PbHistorySheet({
    super.key,
    required this.athleteId,
    required this.pb,
    required this.strokeLabel,
    required this.repository,
    this.sheetScrollController,
  });

  static Future<void> show(
    BuildContext context, {
    required int athleteId,
    required PersonalBest pb,
    required String strokeLabel,
    required SwimRepository repository,
  }) {
    return AppBottomSheet.show<void>(
      context,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.38,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => PbHistorySheet(
          athleteId: athleteId,
          pb: pb,
          strokeLabel: strokeLabel,
          repository: repository,
          sheetScrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<PbHistorySheet> createState() => _PbHistorySheetState();
}

class _PbHistorySheetState extends State<PbHistorySheet> {
  bool _loading = true;
  String? _error;
  List<AthleteRaceHistoryItem> _races = [];
  List<Map<String, dynamic>> _targets = [];
  int? _selectedChartIndex;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final racesFuture = widget.repository.getAthleteRaces(
        widget.athleteId,
        stroke: widget.pb.stroke,
        distance: widget.pb.distance,
      );
      final targetsFuture = widget.repository
          .getAthleteBarajTargets(
            widget.athleteId,
            stroke: widget.pb.stroke,
            distance: widget.pb.distance,
            course: widget.pb.course,
            pbCs: widget.pb.timeCs,
          )
          .catchError((_) => <Map<String, dynamic>>[]);

      final all = await racesFuture;
      final targets = await targetsFuture;
      final targetCourse = widget.pb.course.toUpperCase();
      final now = DateTime.now();
      final cutoff = DateTime(now.year - 3, now.month, now.day);
      final cutoffIso =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

      final filtered = all.where((r) {
        if (targetCourse.isNotEmpty && r.course.toUpperCase() != targetCourse) {
          return false;
        }
        if (r.date.isNotEmpty && r.date.compareTo(cutoffIso) < 0) {
          return false;
        }
        return true;
      }).toList();

      final filteredTargets = targets.where((t) {
        final typeRaw =
            (t['baraj_turu'] ?? t['type'] ?? '').toString().toLowerCase();
        return !typeRaw.contains('harc');
      }).toList();

      if (mounted) {
        setState(() {
          _races = filtered;
          _targets = filteredTargets;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Yarış geçmişi yüklenemedi.';
          _loading = false;
        });
      }
    }
  }

  /// Grafikte soldan sağa (eskiden yeniye) sıralı geçerli dereceler.
  List<AthleteRaceHistoryItem> get _chartPoints {
    final valid = _races
        .where((r) => (r.timeCs ?? 0) > 0 && r.resultStatus != 'DQ' && r.resultStatus != 'DNS' && r.resultStatus != 'DNF')
        .toList();
    valid.sort((a, b) => a.date.compareTo(b.date));
    return valid;
  }

  String _formatShortDate(String iso) {
    final parts = iso.split('-');
    if (parts.length == 3) {
      return '${parts[2]}.${parts[1]}.${parts[0].substring(2)}';
    }
    return iso;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final courseText = widget.pb.course.toUpperCase() == 'SC' ? '25m Kısa Kulvar' : '50m Uzun Kulvar';
    final points = _chartPoints;

    int? minCs;
    int? firstCs;
    if (points.isNotEmpty) {
      firstCs = points.first.timeCs;
      minCs = points.map((e) => e.timeCs!).reduce(math.min);
    }
    final int? improvementCs = (firstCs != null && minCs != null && firstCs > minCs)
        ? (firstCs - minCs)
        : null;

    final int? activeIdx = (_selectedChartIndex != null &&
            _selectedChartIndex! >= 0 &&
            _selectedChartIndex! < points.length)
        ? _selectedChartIndex
        : (points.isNotEmpty ? points.length - 1 : null);

    final cardShadow = [
      BoxShadow(
        color: palette.textPrimary.withValues(alpha: 0.05),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];

    return AppBottomSheet(
      scrollable: false,
      child: Column(
        children: [
          // Üst Başlık
          Row(
            children: [
              if (widget.pb.distance > 0) ...[
                Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        palette.accent.withValues(alpha: 0.2),
                        palette.infoCyan.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.38),
                      width: 1.2,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.surface.withValues(alpha: 0.65),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${widget.pb.distance}',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: palette.accent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.pb.distance}m ${widget.strokeLabel}',
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$courseText • Son 3 Yıl Yarış Geçmişi',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: palette.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.v12,
          Divider(height: 1, color: palette.divider.withValues(alpha: 0.7)),

          // İçerik
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: palette.primary),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: palette.textSecondary),
                            ),
                            AppSpacing.vSm,
                            TextButton(
                              onPressed: _loadHistory,
                              child: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: widget.sheetScrollController,
                        padding: EdgeInsets.only(
                          top: AppSpacing.md,
                          bottom: AppSpacing.lg +
                              MediaQuery.of(context).padding.bottom,
                        ),
                        children: [
                          // Özet KPI Kartları
                          Row(
                            children: [
                              _buildKpiBox(
                                palette,
                                fill: palette.surface,
                                shadow: cardShadow,
                                label: 'En İyi (PB)',
                                value: SwimTimeFormatter.formatCs(
                                  widget.pb.timeCs,
                                ),
                                accent: palette.accent,
                              ),
                              AppSpacing.hSm,
                              _buildKpiBox(
                                palette,
                                fill: palette.surface,
                                shadow: cardShadow,
                                label: 'Gelişim',
                                value: improvementCs != null
                                    ? '-${(improvementCs / 100).toStringAsFixed(2)} sn'
                                    : '—',
                                accent: improvementCs != null
                                    ? palette.successText
                                    : palette.textSecondary,
                              ),
                              if (widget.pb.rudolphPoints != null &&
                                  widget.pb.rudolphPoints! > 0) ...[
                                AppSpacing.hSm,
                                _buildKpiBox(
                                  palette,
                                  fill: palette.surface,
                                  shadow: cardShadow,
                                  label: 'Rudolph',
                                  value: '${widget.pb.rudolphPoints}/20',
                                  accent: palette.primary,
                                ),
                              ],
                              AppSpacing.hSm,
                              _buildKpiBox(
                                palette,
                                fill: palette.surface,
                                shadow: cardShadow,
                                label: 'Yarış',
                                value: '${_races.length}',
                                accent: palette.textPrimary,
                              ),
                            ],
                          ),
                          AppSpacing.v12,

                          // Hedef Reglaman Barajı Kartları
                          if (_targets.isNotEmpty) ...[
                            ..._targets.take(3).map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildTargetBarajCard(palette, t),
                                  ),
                                ),
                            const SizedBox(height: 4),
                          ],

                          // Gelişim Grafiği Kartı
                          if (points.length >= 2) ...[
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.s12,
                                AppSpacing.md,
                                AppSpacing.md,
                                AppSpacing.s12,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: cardShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (activeIdx != null) ...[
                                    _buildSelectedPointBanner(
                                      palette,
                                      points[activeIdx],
                                      isPb: points[activeIdx].timeCs == minCs,
                                    ),
                                    AppSpacing.vSm,
                                  ],
                                  SizedBox(
                                    height: 180,
                                    width: double.infinity,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTapDown: (d) => _selectNearestPoint(
                                            d.localPosition.dx,
                                            constraints.maxWidth,
                                            points.length,
                                            hasRudolph: points.any(
                                              (p) => (p.rudolphPoints ?? 0) > 0,
                                            ),
                                          ),
                                          onHorizontalDragUpdate: (d) =>
                                              _selectNearestPoint(
                                            d.localPosition.dx,
                                            constraints.maxWidth,
                                            points.length,
                                            hasRudolph: points.any(
                                              (p) => (p.rudolphPoints ?? 0) > 0,
                                            ),
                                          ),
                                          child: CustomPaint(
                                            size: Size(
                                              constraints.maxWidth,
                                              180,
                                            ),
                                            painter: _RaceChartPainter(
                                              points: points,
                                              minCs: minCs!,
                                              targetLines: _buildChartTargetLines(
                                                palette,
                                              ),
                                              selectedIndex: activeIdx,
                                              primaryColor: palette.primary,
                                              pbColor: palette.successText,
                                              rudolphColor: palette.secondary,
                                              gridColor: palette.divider,
                                              labelColor: palette.textSecondary,
                                              surfaceColor: palette.surface,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (points.any(
                                    (p) => (p.rudolphPoints ?? 0) > 0,
                                  )) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildChartLegendItem(
                                          palette.primary,
                                          'Süre',
                                          palette.textSecondary,
                                        ),
                                        const SizedBox(width: 14),
                                        _buildChartLegendItem(
                                          palette.secondary,
                                          'Rudolph (1-20)',
                                          palette.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            AppSpacing.vMd,
                          ],

                          // Yarış Geçmişi Listesi
                          Text(
                            'Tüm Yarışlar (${_races.length})',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          AppSpacing.vSm,
                          if (_races.isEmpty)
                            Container(
                              padding: AppSpacing.paddingAllLg,
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: cardShadow,
                              ),
                              child: Text(
                                'Bu branşta geçmiş yarış kaydı bulunamadı.',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: cardShadow,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: _races.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final r = entry.value;
                                  final isPb = minCs != null && r.timeCs == minCs;
                                  final isLast = idx == _races.length - 1;
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.md,
                                          vertical: AppSpacing.s12,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    StringUtils.toTitleCase(
                                                      r.meetName,
                                                    ),
                                                    style: TextStyle(
                                                      fontFamily: AppTextStyles
                                                          .fontFamily,
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          palette.textPrimary,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    [
                                                      _formatShortDate(r.date),
                                                      if (r.rank.isNotEmpty &&
                                                          r.rank != '-')
                                                        '${r.rank}. sıra',
                                                      if (r.rudolphPoints !=
                                                              null &&
                                                          r.rudolphPoints! > 0)
                                                        'Rudolph ${r.rudolphPoints}/20',
                                                      if (r.points != null)
                                                        '${r.points} FINA',
                                                    ].join(' • '),
                                                    style: TextStyle(
                                                      fontFamily: AppTextStyles
                                                          .fontFamily,
                                                      fontSize: 12,
                                                      color:
                                                          palette.textSecondary,
                                                      fontFeatures: const [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            AppSpacing.h12,
                                            _buildRaceTrailing(
                                              palette,
                                              r,
                                              isPb: isPb,
                                            ),
                                          ],
                                        ),
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
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  void _selectNearestPoint(
    double dx,
    double width,
    int count, {
    bool hasRudolph = false,
  }) {
    if (count < 2) return;
    const leftPad = 48.0;
    final rightPad = hasRudolph ? 26.0 : 12.0;
    final chartW = math.max(1.0, width - leftPad - rightPad);
    final ratio = ((dx - leftPad) / chartW).clamp(0.0, 1.0);
    final idx = (ratio * (count - 1)).round();
    if (_selectedChartIndex != idx) {
      setState(() => _selectedChartIndex = idx);
    }
  }

  Widget _buildChartLegendItem(Color color, String label, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildRaceTrailing(
    AppColorPalette palette,
    AthleteRaceHistoryItem r, {
    required bool isPb,
  }) {
    final hasValidTime = r.timeCs != null && r.timeCs! > 0;
    final rawStatus = (r.resultStatus.isNotEmpty
            ? r.resultStatus
            : (r.time ?? ''))
        .trim()
        .toUpperCase();

    if (!hasValidTime) {
      if (rawStatus == 'DNS') {
        return const StatusBadge.neutral(label: 'Başlamadı');
      }
      if (rawStatus == 'WAITING') {
        return const StatusBadge.neutral(label: 'Bekleniyor');
      }
      if (rawStatus == 'DSQ' || rawStatus == 'DQ') {
        return StatusBadge(
          label: 'Diskalifiye',
          variant: StatusBadgeVariant.error,
          leading: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Icon(
              Icons.cancel_outlined,
              size: 13,
              color: palette.statusDanger,
            ),
          ),
        );
      }
      if (rawStatus == 'DNF') {
        return const StatusBadge.neutral(label: 'Tamamlamadı');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          hasValidTime
              ? SwimTimeFormatter.formatCs(r.timeCs)
              : (r.time ?? r.resultStatus),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontFamily: AppTextStyles.displayFontFamily,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: isPb ? palette.successText : palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (isPb) ...[
          AppSpacing.vXs,
          StatusBadge(
            label: 'PB',
            variant: StatusBadgeVariant.success,
            textColor: palette.successText,
          ),
        ],
      ],
    );
  }

  Widget _buildKpiBox(
    AppColorPalette palette, {
    required Color fill,
    required List<BoxShadow> shadow,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                color: palette.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPointBanner(
    AppColorPalette palette,
    AthleteRaceHistoryItem item, {
    required bool isPb,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.textPrimary.withValues(
          alpha: palette.isDark ? 0.08 : 0.05,
        ),
        borderRadius: AppRadius.smallRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StringUtils.toTitleCase(item.meetName),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    _formatShortDate(item.date),
                    if (item.rudolphPoints != null && item.rudolphPoints! > 0)
                      'Rudolph ${item.rudolphPoints}/20',
                    if (item.points != null) '${item.points} FINA',
                  ].join(' • '),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.hSm,
          if (isPb) ...[
            StatusBadge(
              label: 'PB',
              variant: StatusBadgeVariant.success,
              textColor: palette.successText,
            ),
            AppSpacing.hSm,
          ],
          Text(
            SwimTimeFormatter.formatCs(item.timeCs),
            maxLines: 1,
            softWrap: false,
            style: AppTextStyles.officialTime.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPb ? palette.successText : palette.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetBarajCard(
    AppColorPalette palette,
    Map<String, dynamic> t,
  ) {
    final bool passed = t['passed'] == true;
    final int? diffCs = t['diff_cs'] as int?;
    final int? targetCs = t['target_cs'] as int?;
    final String meetName = StringUtils.toTitleCase(
      (t['meet_name'] ?? t['baraj_adi'] ?? 'Katılım Barajı').toString(),
    );
    final Color statusColor = passed ? palette.successText : palette.statusDanger;
    final Color tintColor = passed ? palette.statusSuccess : palette.statusDanger;

    String statusText;
    if (diffCs == null) {
      statusText = 'Baraj: ${SwimTimeFormatter.formatCs(targetCs)}';
    } else if (passed) {
      final margin = (diffCs.abs() / 100).toStringAsFixed(2);
      statusText = diffCs == 0
          ? 'Barajla tam eşit (Geçildi)'
          : 'Geçildi • $margin sn fark';
    } else {
      final rem = (diffCs / 100).toStringAsFixed(2);
      statusText = 'Geçilmedi • $rem sn kaldı';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.12),
        borderRadius: AppRadius.medium,
        border: Border.all(
          color: tintColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_outline : Icons.flag_outlined,
            size: 20,
            color: statusColor,
          ),
          AppSpacing.h12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meetName,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AppSpacing.hSm,
          Text(
            SwimTimeFormatter.formatCs(targetCs),
            maxLines: 1,
            softWrap: false,
            style: AppTextStyles.officialTime.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
  List<({int cs, String label, Color color})> _buildChartTargetLines(
    AppColorPalette palette,
  ) {
    final seenCs = <int>{};
    final lines = <({int cs, String label, Color color})>[];
    for (final t in _targets) {
      final cs = (t['target_cs'] as num?)?.toInt();
      if (cs == null || cs <= 0 || !seenCs.add(cs)) continue;
      lines.add((
        cs: cs,
        label: 'Baraj ${SwimTimeFormatter.formatCs(cs)}',
        color: palette.statusWarning,
      ));
    }
    lines.sort((a, b) => a.cs.compareTo(b.cs));
    return lines;
  }
}

class _RaceChartPainter extends CustomPainter {
  final List<AthleteRaceHistoryItem> points;
  final int minCs;
  final List<({int cs, String label, Color color})> targetLines;
  final int? selectedIndex;
  final Color primaryColor;
  final Color pbColor;
  final Color rudolphColor;
  final Color gridColor;
  final Color labelColor;
  final Color surfaceColor;

  _RaceChartPainter({
    required this.points,
    required this.minCs,
    this.targetLines = const [],
    required this.selectedIndex,
    required this.primaryColor,
    required this.pbColor,
    required this.rudolphColor,
    required this.gridColor,
    required this.labelColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final hasRudolph = points.any((e) => (e.rudolphPoints ?? 0) > 0);
    const leftPad = 48.0;
    final rightPad = hasRudolph ? 26.0 : 12.0;
    const topPad = 14.0;
    const bottomPad = 24.0;

    final chartW = math.max(1.0, size.width - leftPad - rightPad);
    final chartH = math.max(1.0, size.height - topPad - bottomPad);

    final values = points.map((e) => e.timeCs!.toDouble()).toList();
    double rawMin = values.reduce(math.min);
    double rawMax = values.reduce(math.max);
    for (final line in targetLines) {
      if (line.cs > 0) {
        rawMin = math.min(rawMin, line.cs.toDouble());
        rawMax = math.max(rawMax, line.cs.toDouble());
      }
    }
    final span = math.max(10.0, rawMax - rawMin);
    final minVal = rawMin - span * 0.12;
    final maxVal = rawMax + span * 0.12;
    final valSpan = math.max(1.0, maxVal - minVal);

    // Yatay ızgara çizgileri & Y ekseni süre etiketleri
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    for (int i = 0; i <= 3; i++) {
      final t = i / 3.0;
      final y = topPad + t * chartH;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);

      final vCs = (maxVal - t * valSpan).round();
      final tp = TextPainter(
        text: TextSpan(
          text: SwimTimeFormatter.formatCs(vCs),
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11,
            color: labelColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Hedef Baraj kesikli çizgileri
    double? lastLabelY;
    for (final line in targetLines) {
      if (line.cs <= 0) continue;
      final yNormT = (line.cs.toDouble() - minVal) / valSpan;
      final yT = topPad + (1.0 - yNormT) * chartH;
      final dashPaint = Paint()
        ..color = line.color.withValues(alpha: 0.85)
        ..strokeWidth = 1.4;
      double xDash = leftPad;
      while (xDash < size.width - rightPad) {
        final xEnd = math.min(xDash + 5.0, size.width - rightPad);
        canvas.drawLine(Offset(xDash, yT), Offset(xEnd, yT), dashPaint);
        xDash += 9.0;
      }
      final tLabel = TextPainter(
        text: TextSpan(
          text: line.label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: line.color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var labelY = math.max(topPad, yT - tLabel.height - 2);
      if (lastLabelY != null && (labelY - lastLabelY).abs() < tLabel.height + 2) {
        labelY = math.min(topPad + chartH - tLabel.height, yT + 2);
      }
      lastLabelY = labelY;
      tLabel.paint(
        canvas,
        Offset(size.width - rightPad - tLabel.width, labelY),
      );
    }

    // Koordinatları hesapla
    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + (i / (points.length - 1)) * chartW;
      final yNorm = (values[i] - minVal) / valSpan;
      final y = topPad + (1.0 - yNorm) * chartH;
      offsets.add(Offset(x, y));
    }

    // Yumuşak eğri yolu oluştur
    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i];
      final p1 = offsets[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    // Alt alan gradyanı
    final fillPath = Path.from(linePath)
      ..lineTo(offsets.last.dx, topPad + chartH)
      ..lineTo(offsets.first.dx, topPad + chartH)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.22),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH));
    canvas.drawPath(fillPath, fillPaint);

    // Ana çizgi
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // X ekseni başlangıç ve bitiş tarihleri
    for (final idx in [0, points.length - 1]) {
      final d = points[idx].date;
      final parts = d.split('-');
      final shortD = parts.length == 3 ? '${parts[2]}.${parts[1]}.${parts[0].substring(2)}' : d;
      final tp = TextPainter(
        text: TextSpan(
          text: shortD,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11,
            color: labelColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = idx == 0 ? leftPad : (size.width - rightPad - tp.width);
      tp.paint(canvas, Offset(dx, topPad + chartH + 6));
    }

    // Noktalar (Süre)
    for (int i = 0; i < offsets.length; i++) {
      final pt = offsets[i];
      final isPb = points[i].timeCs == minCs;
      final isSel = selectedIndex == i;
      final dotColor = isPb ? pbColor : primaryColor;

      if (isSel) {
        canvas.drawCircle(
          pt,
          8,
          Paint()..color = dotColor.withValues(alpha: 0.20),
        );
      }
      canvas.drawCircle(pt, isSel ? 5.0 : 3.6, Paint()..color = surfaceColor);
      canvas.drawCircle(
        pt,
        isSel ? 4.2 : 3.0,
        Paint()..color = dotColor,
      );
    }

    // İkinci çizgi: Rudolph Puanı (1-20)
    final rudolphOffsets = <({int idx, Offset pt, int val})>[];
    final rudolphVals = points
        .map((e) => e.rudolphPoints)
        .whereType<int>()
        .where((v) => v > 0)
        .toList();
    if (rudolphVals.isNotEmpty) {
      final rMinRaw = rudolphVals.reduce(math.min).toDouble();
      final rMaxRaw = rudolphVals.reduce(math.max).toDouble();
      final rMin = math.max(0.0, rMinRaw - 2.0);
      final rMax = math.min(20.0, rMaxRaw + 2.0);
      final rSpan = math.max(2.0, rMax - rMin);

      // Sağ Y ekseni Rudolph ölçeği
      for (final rTick in [rMax.round(), rMin.round()]) {
        final yNormR = (rTick - rMin) / rSpan;
        final yR = topPad + (1.0 - yNormR) * chartH;
        final rTp = TextPainter(
          text: TextSpan(
            text: '${rTick}R',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: rudolphColor.withValues(alpha: 0.85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        rTp.paint(
          canvas,
          Offset(size.width - rightPad + 4, yR - rTp.height / 2),
        );
      }

      for (int i = 0; i < points.length; i++) {
        final r = points[i].rudolphPoints;
        if (r == null || r <= 0) continue;
        final x = leftPad + (i / (points.length - 1)) * chartW;
        final yNormR = (r - rMin) / rSpan;
        final yR = topPad + (1.0 - yNormR) * chartH;
        rudolphOffsets.add((idx: i, pt: Offset(x, yR), val: r));
      }

      if (rudolphOffsets.length >= 2) {
        final rPath = Path()
          ..moveTo(rudolphOffsets.first.pt.dx, rudolphOffsets.first.pt.dy);
        for (int i = 0; i < rudolphOffsets.length - 1; i++) {
          final p0 = rudolphOffsets[i].pt;
          final p1 = rudolphOffsets[i + 1].pt;
          final midX = (p0.dx + p1.dx) / 2;
          rPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        }
        canvas.drawPath(
          rPath,
          Paint()
            ..color = rudolphColor
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }

      for (final ro in rudolphOffsets) {
        final isSel = selectedIndex == ro.idx;
        if (isSel) {
          canvas.drawCircle(
            ro.pt,
            7,
            Paint()..color = rudolphColor.withValues(alpha: 0.22),
          );
        }
        canvas.drawCircle(
          ro.pt,
          isSel ? 4.4 : 3.2,
          Paint()..color = surfaceColor,
        );
        canvas.drawCircle(
          ro.pt,
          isSel ? 3.5 : 2.5,
          Paint()..color = rudolphColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RaceChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.minCs != minCs ||
        oldDelegate.targetLines.length != targetLines.length;
  }
}
