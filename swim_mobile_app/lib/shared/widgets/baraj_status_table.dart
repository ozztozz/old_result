import 'package:flutter/material.dart';

import '../../core/theme/tokens/tokens.dart';
import 'modern_segmented_tab_bar.dart';

/// Sporcu detay ve kulüp baraj ekranlarında ortak kullanılan
/// baraj tablosu satır verisi.
class BarajStatusRowData {
  final int distance;
  final String strokeLabel;
  final String targetTime;
  final String pbTime;
  final int? diffCs;
  final bool passed;

  const BarajStatusRowData({
    required this.distance,
    required this.strokeLabel,
    required this.targetTime,
    required this.pbTime,
    required this.diffCs,
    required this.passed,
  });
}

/// Geçilen barajların üst özeti + stil sekmeli (ModernSegmentedTabBar) baraj tablosu.
/// Hem Sporcu Detay hem de Kulüp Baraj ekranında ortak kullanılır.
class BarajTabbedStatusView extends StatefulWidget {
  final List<BarajStatusRowData> rows;
  final bool scrollableTable;

  const BarajTabbedStatusView({
    super.key,
    required this.rows,
    this.scrollableTable = false,
  });

  @override
  State<BarajTabbedStatusView> createState() => _BarajTabbedStatusViewState();
}

class _BarajTabbedStatusViewState extends State<BarajTabbedStatusView>
    with TickerProviderStateMixin {
  List<String> _strokes = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _syncTabs();
  }

  @override
  void didUpdateWidget(covariant BarajTabbedStatusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows != widget.rows) {
      _syncTabs();
    }
  }

  void _syncTabs() {
    final nextStrokes = widget.rows
        .map((r) => r.strokeLabel)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) {
        final ia = BarajStatusTable._strokeOrder.indexOf(a);
        final ib = BarajStatusTable._strokeOrder.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    final sameStrokes = _strokes.length == nextStrokes.length &&
        [
          for (var i = 0; i < _strokes.length; i++)
            _strokes[i] == nextStrokes[i],
        ].every((e) => e);

    if (sameStrokes) return;

    final prevIndex = _tabController?.index ?? 0;
    _tabController?.dispose();
    _strokes = nextStrokes;
    if (_strokes.isNotEmpty) {
      final safeIndex = prevIndex.clamp(0, _strokes.length - 1);
      _tabController = TabController(
        length: _strokes.length,
        initialIndex: safeIndex,
        vsync: this,
      )..addListener(() {
          if (mounted) setState(() {});
        });
    } else {
      _tabController = null;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final passedRows = widget.rows.where((r) => r.passed).toList();
    final activeStroke = (_tabController != null && _strokes.isNotEmpty)
        ? _strokes[_tabController!.index]
        : null;

    Widget buildStrokeTable(String? stroke) {
      final strokeRows = stroke == null
          ? widget.rows
          : widget.rows.where((r) => r.strokeLabel == stroke).toList();
      return BarajStatusTable(rows: strokeRows);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (passedRows.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 15, color: palette.gold),
              const SizedBox(width: 6),
              Text(
                'Geçtiği Barajlar (${passedRows.length})',
                style: TextStyle(
                  fontFamily: AppTextStyles.displayFontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: passedRows.map((r) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.statusSuccess.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.statusSuccess.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${r.distance}m ${r.strokeLabel} · ${r.pbTime != '-' ? r.pbTime : r.targetTime}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.statusSuccess,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (_tabController != null && _strokes.isNotEmpty) ...[
          ModernSegmentedTabBar(
            controller: _tabController!,
            height: 40,
            tabs: _strokes.map((s) => TabItemData(title: s)).toList(),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.scrollableTable &&
            _tabController != null &&
            _strokes.isNotEmpty)
          Expanded(
            child: TabBarView(
              controller: _tabController!,
              children: [
                for (final stroke in _strokes)
                  SingleChildScrollView(
                    child: buildStrokeTable(stroke),
                  ),
              ],
            ),
          )
        else if (_tabController != null && _strokes.isNotEmpty)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -250 && _tabController!.index < _strokes.length - 1) {
                _tabController!.animateTo(_tabController!.index + 1);
              } else if (v > 250 && _tabController!.index > 0) {
                _tabController!.animateTo(_tabController!.index - 1);
              }
            },
            child: buildStrokeTable(activeStroke),
          )
        else
          buildStrokeTable(activeStroke),
      ],
    );
  }
}

/// Sporcu detaydaki baraj tablosunu (MESAFE | BARAJ | SPORCU | DURUM)
/// stile göre gruplayarak çizen ortak bileşen.
class BarajStatusTable extends StatelessWidget {
  final List<BarajStatusRowData> rows;
  final EdgeInsetsGeometry padding;

  const BarajStatusTable({
    super.key,
    required this.rows,
    this.padding = EdgeInsets.zero,
  });

  static const _strokeOrder = [
    'Serbest',
    'Sırtüstü',
    'Kurbağalama',
    'Kelebek',
    'Karışık',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final byStroke = <String, List<BarajStatusRowData>>{};
    for (final r in rows) {
      if (r.strokeLabel.isNotEmpty) {
        byStroke.putIfAbsent(r.strokeLabel, () => []).add(r);
      }
    }
    for (final list in byStroke.values) {
      list.sort((a, b) => a.distance.compareTo(b.distance));
    }
    final strokes = byStroke.keys.toList()
      ..sort((a, b) {
        final ia = _strokeOrder.indexOf(a);
        final ib = _strokeOrder.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: Text(
                    'MESAFE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'BARAJ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'SPORCU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    'DURUM',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 6, color: palette.divider),
          if (strokes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Bu etkinlikte seçili tür için baraj bulunamadı.',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: palette.textSecondary,
                ),
              ),
            )
          else
            ...strokes.map((stroke) {
              final list = byStroke[stroke]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          stroke,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 1.2,
                            color: palette.primary.withAlpha(75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...list.map((r) => BarajStatusRow(data: r)),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// Tek bir baraj satırı (Mesafe çipi | Baraj süresi | Sporcu derecesi | Geçti/Fark).
class BarajStatusRow extends StatelessWidget {
  final BarajStatusRowData data;

  const BarajStatusRow({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final passed = data.passed;
    final rawDiffCs = data.diffCs;
    final statusText = rawDiffCs != null
        ? (passed ? 'GEÇTİ' : '+${(rawDiffCs / 100).toStringAsFixed(2)}')
        : '-';
    final hasPb = data.pbTime != '-';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: palette.divider.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: passed
                      ? (palette.isDark
                          ? const Color(0x2610B981)
                          : const Color(0xFFECFDF5))
                      : palette.statusSuccessBg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: (passed
                            ? const Color(0xFF10B981)
                            : palette.statusSuccess)
                        .withAlpha(85),
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${data.distance}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: passed
                        ? (palette.isDark
                            ? const Color(0xFF34D399)
                            : const Color(0xFF059669))
                        : palette.statusSuccess,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              data.targetTime,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: palette.statusSuccess,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              data.pbTime,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: hasPb ? palette.textPrimary : palette.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: rawDiffCs != null && passed
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 13.5,
                        color: palette.gold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: palette.isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  )
                : Text(
                    statusText,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: rawDiffCs != null
                          ? palette.statusWarning
                          : palette.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
