import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/tokens/tokens.dart';
import '../../../core/utils/swim_time_formatter.dart';
import '../../../data/models/athlete.dart';
import '../../../data/repositories/swim_repository.dart';

/// Sporcu En İyi Derece (PB) tıklandığında açılan yarış geçmişi ve gelişim grafiği.
class PbHistorySheet extends StatefulWidget {
  final int athleteId;
  final PersonalBest pb;
  final String strokeLabel;
  final SwimRepository repository;

  const PbHistorySheet({
    super.key,
    required this.athleteId,
    required this.pb,
    required this.strokeLabel,
    required this.repository,
  });

  static Future<void> show(
    BuildContext context, {
    required int athleteId,
    required PersonalBest pb,
    required String strokeLabel,
    required SwimRepository repository,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PbHistorySheet(
        athleteId: athleteId,
        pb: pb,
        strokeLabel: strokeLabel,
        repository: repository,
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
      final all = await widget.repository.getAthleteRaces(
        widget.athleteId,
        stroke: widget.pb.stroke,
        distance: widget.pb.distance,
      );
      final targetCourse = widget.pb.course.toUpperCase();
      final filtered = all.where((r) {
        if (targetCourse.isEmpty) return true;
        return r.course.toUpperCase() == targetCourse;
      }).toList();

      if (mounted) {
        setState(() {
          _races = filtered;
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

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.50,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Column(
            children: [
              // Tutamaç
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Üst Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.pb.distance}m ${widget.strokeLabel}',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$courseText • Yarış Gelişim Geçmişi',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.divider),

              // İçerik
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: palette.primary))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: TextStyle(color: palette.textSecondary)),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _loadHistory,
                                  child: const Text('Tekrar Dene'),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                            children: [
                              // Özet KPI Kartları
                              Row(
                                children: [
                                  _buildKpiBox(
                                    palette,
                                    label: 'En İyi (PB)',
                                    value: SwimTimeFormatter.formatCs(widget.pb.timeCs),
                                    accent: palette.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildKpiBox(
                                    palette,
                                    label: 'Gelişim',
                                    value: improvementCs != null
                                        ? '-${(improvementCs / 100).toStringAsFixed(2)} sn'
                                        : '—',
                                    accent: improvementCs != null
                                        ? palette.statusSuccess
                                        : palette.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildKpiBox(
                                    palette,
                                    label: 'Yarış',
                                    value: '${_races.length}',
                                    accent: palette.textPrimary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Gelişim Grafiği Kartı
                              if (points.length >= 2) ...[
                                Container(
                                  padding: const EdgeInsets.fromLTRB(12, 14, 14, 12),
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: AppRadius.cardRadius,
                                    border: Border.all(color: palette.border, width: 1),
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
                                        const SizedBox(height: 10),
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
                                              ),
                                              onHorizontalDragUpdate: (d) => _selectNearestPoint(
                                                d.localPosition.dx,
                                                constraints.maxWidth,
                                                points.length,
                                              ),
                                              child: CustomPaint(
                                                size: Size(constraints.maxWidth, 180),
                                                painter: _RaceChartPainter(
                                                  points: points,
                                                  minCs: minCs!,
                                                  selectedIndex: activeIdx,
                                                  primaryColor: palette.primary,
                                                  pbColor: palette.statusSuccess,
                                                  gridColor: palette.divider,
                                                  labelColor: palette.textSecondary,
                                                  surfaceColor: palette.surface,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Yarış Geçmişi Listesi
                              Text(
                                'Tüm Yarışlar (${_races.length})',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_races.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: AppRadius.cardRadius,
                                    border: Border.all(color: palette.border),
                                  ),
                                  child: Text(
                                    'Bu branşta geçmiş yarış kaydı bulunamadı.',
                                    style: TextStyle(color: palette.textSecondary, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              else
                                Container(
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: AppRadius.cardRadius,
                                    border: Border.all(color: palette.border, width: 1),
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
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        r.meetName,
                                                        style: TextStyle(
                                                          fontFamily: AppTextStyles.fontFamily,
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600,
                                                          color: palette.textPrimary,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        [
                                                          _formatShortDate(r.date),
                                                          if (r.rank.isNotEmpty && r.rank != '-') '${r.rank}. sıra',
                                                          if (r.points != null) '${r.points} FINA',
                                                        ].join(' • '),
                                                        style: TextStyle(
                                                          fontFamily: AppTextStyles.fontFamily,
                                                          fontSize: 11.5,
                                                          color: palette.textSecondary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      r.timeCs != null && r.timeCs! > 0
                                                          ? SwimTimeFormatter.formatCs(r.timeCs)
                                                          : (r.time ?? r.resultStatus),
                                                      style: AppTextStyles.officialTime.copyWith(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        color: isPb ? palette.statusSuccess : palette.textPrimary,
                                                      ),
                                                    ),
                                                    if (isPb)
                                                      Container(
                                                        margin: const EdgeInsets.only(top: 2),
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: palette.statusSuccess.withValues(alpha: 0.14),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          'PB',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: palette.statusSuccess,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast) Divider(height: 1, color: palette.divider),
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
      },
    );
  }

  void _selectNearestPoint(double dx, double width, int count) {
    if (count < 2) return;
    const leftPad = 48.0;
    const rightPad = 12.0;
    final chartW = math.max(1.0, width - leftPad - rightPad);
    final ratio = ((dx - leftPad) / chartW).clamp(0.0, 1.0);
    final idx = (ratio * (count - 1)).round();
    if (_selectedChartIndex != idx) {
      setState(() => _selectedChartIndex = idx);
    }
  }

  Widget _buildKpiBox(
    AppColorPalette palette, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.smallRadius,
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10.5,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.meetName,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatShortDate(item.date),
                  style: TextStyle(fontSize: 10.5, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            SwimTimeFormatter.formatCs(item.timeCs),
            style: AppTextStyles.officialTime.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isPb ? palette.statusSuccess : palette.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceChartPainter extends CustomPainter {
  final List<AthleteRaceHistoryItem> points;
  final int minCs;
  final int? selectedIndex;
  final Color primaryColor;
  final Color pbColor;
  final Color gridColor;
  final Color labelColor;
  final Color surfaceColor;

  _RaceChartPainter({
    required this.points,
    required this.minCs,
    required this.selectedIndex,
    required this.primaryColor,
    required this.pbColor,
    required this.gridColor,
    required this.labelColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const leftPad = 48.0;
    const rightPad = 12.0;
    const topPad = 12.0;
    const bottomPad = 24.0;

    final chartW = math.max(1.0, size.width - leftPad - rightPad);
    final chartH = math.max(1.0, size.height - topPad - bottomPad);

    final values = points.map((e) => e.timeCs!.toDouble()).toList();
    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
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
            fontSize: 10,
            color: labelColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
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
        text: TextSpan(text: shortD, style: TextStyle(fontSize: 9.5, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = idx == 0 ? leftPad : (size.width - rightPad - tp.width);
      tp.paint(canvas, Offset(dx, topPad + chartH + 6));
    }

    // Noktalar
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
  }

  @override
  bool shouldRepaint(covariant _RaceChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.minCs != minCs;
  }
}
