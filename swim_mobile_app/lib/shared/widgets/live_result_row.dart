import 'package:flutter/material.dart';

import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/race_result.dart';
import 'status_badge.dart';

/// Canlı yarış sonuçları ve kulüp takip ekranlarında ortak kullanılan
/// sonuç/beklenen yarış satırı bileşeni.
class LiveResultRow extends StatefulWidget {
  final RaceResult result;
  final int? rankIndex;
  final bool showDivider;
  final bool isPinnedClubRow;
  final bool highlightMyTeam;
  final int? eventDistance;
  final String? titleOverride;
  final String? subtitleOverride;
  final String? leadingBadgeText;
  final VoidCallback? onTap;
  final Future<Map<String, String>?> Function()? onLoadSplits;

  const LiveResultRow({
    super.key,
    required this.result,
    this.rankIndex,
    this.showDivider = false,
    this.isPinnedClubRow = false,
    this.highlightMyTeam = true,
    this.eventDistance,
    this.titleOverride,
    this.subtitleOverride,
    this.leadingBadgeText,
    this.onTap,
    this.onLoadSplits,
  });

  /// Verilen sonucun geçerli bir yarış derecesi içerip içermediğini döndürür.
  static bool hasValidRaceTime(RaceResult r) {
    if ((r.timeCs ?? 0) > 0) return true;
    final trimmed = r.time?.trim() ?? '';
    if (trimmed.isEmpty ||
        trimmed == '-' ||
        trimmed == '0' ||
        trimmed == '00:00.00') {
      return false;
    }
    final upper = trimmed.toUpperCase();
    return upper != 'DNS' &&
        upper != 'DNF' &&
        upper != 'DQ' &&
        upper != 'DSQ' &&
        upper != 'WAITING' &&
        upper != 'BEKLENİYOR' &&
        upper != 'BEKLENIYOR';
  }

  @override
  State<LiveResultRow> createState() => _LiveResultRowState();
}

class _LiveResultRowState extends State<LiveResultRow> {
  bool _isExpanded = false;
  bool _isLoadingSplits = false;
  bool _didAttemptLoadSplits = false;
  Map<String, String>? _loadedSplits;

  Future<void> _handleToggleExpand() async {
    if (_isLoadingSplits) return;
    final hasExisting =
        (widget.result.splitTimes?.isNotEmpty ?? false) ||
        (_loadedSplits?.isNotEmpty ?? false);
    if (hasExisting) {
      setState(() => _isExpanded = !_isExpanded);
      return;
    }
    if (widget.onLoadSplits == null || _didAttemptLoadSplits) return;
    setState(() => _isLoadingSplits = true);
    try {
      final fetched = await widget.onLoadSplits!();
      if (!mounted) return;
      setState(() {
        _loadedSplits = fetched;
        _didAttemptLoadSplits = true;
        _isLoadingSplits = false;
        if (fetched != null && fetched.isNotEmpty) {
          _isExpanded = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _didAttemptLoadSplits = true;
        _isLoadingSplits = false;
      });
    }
  }

  String? _getDisplaySeedTime(RaceResult result) {
    if (result.seedTime != null &&
        result.seedTime!.isNotEmpty &&
        result.seedTime != '0' &&
        result.seedTime != '00:00.00' &&
        result.seedTime != '-') {
      var s = result.seedTime!.trim();
      if (s.startsWith('00:')) s = s.substring(3);
      return s;
    }
    if (result.seedTimeCs != null && result.seedTimeCs! > 0) {
      return SwimTimeFormatter.formatCs(result.seedTimeCs);
    }
    return null;
  }

  int? _parseTimeToCs(String? s) {
    if (s == null) return null;
    final clean = s.trim();
    if (clean.isEmpty || clean == '-' || clean == '0' || clean == '00:00.00') {
      return null;
    }
    try {
      final parts = clean.split(':');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final sec = int.parse(secParts[0]);
        final cs = secParts.length > 1
            ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
            : 0;
        return (m * 60 + sec) * 100 + cs;
      } else if (parts.length == 1) {
        final secParts = parts[0].split('.');
        final sec = int.parse(secParts[0]);
        final cs = secParts.length > 1
            ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
            : 0;
        return sec * 100 + cs;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  List<({String label, String lapTime, String? cumulativeTime})>
      _buildSplitLegs(
    RaceResult result, {
    required bool isCompleted,
    required int? finishCs,
    required String formattedTime,
  }) {
    final splits =
        (result.splitTimes != null && result.splitTimes!.isNotEmpty)
            ? result.splitTimes
            : _loadedSplits;
    if (splits == null || splits.isEmpty) return const [];

    int parseDist(String key) =>
        int.tryParse(key.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

    final checkpoints = <({int dist, int cs, String? rawVal, String label})>[];
    for (final entry in splits.entries) {
      final dist = parseDist(entry.key);
      final rawVal = entry.value.trim();
      final cs = _parseTimeToCs(rawVal);
      if (dist > 0 && cs != null && cs > 0) {
        checkpoints.add((dist: dist, cs: cs, rawVal: rawVal, label: entry.key));
      }
    }

    if (checkpoints.isEmpty) {
      return splits.entries
          .map(
            (e) => (
              label: e.key,
              lapTime: e.value.trim(),
              cumulativeTime: null,
            ),
          )
          .toList();
    }

    checkpoints.sort((a, b) => a.dist.compareTo(b.dist));

    final totalDistance = result.distance ?? widget.eventDistance ?? 0;
    if (isCompleted &&
        finishCs != null &&
        finishCs > 0 &&
        totalDistance > checkpoints.last.dist &&
        finishCs > checkpoints.last.cs) {
      checkpoints.add((
        dist: totalDistance,
        cs: finishCs,
        rawVal: formattedTime,
        label: '${totalDistance}m',
      ));
    }

    final legs = <({String label, String lapTime, String? cumulativeTime})>[];
    int prevDist = 0;
    int prevCs = 0;

    for (final cp in checkpoints) {
      if (cp.dist <= prevDist || cp.cs <= prevCs) continue;
      final gap = cp.dist - prevDist;
      final deltaCs = cp.cs - prevCs;

      if (gap > 50 && gap % 50 == 0) {
        final steps = gap ~/ 50;
        var runningPrevCs = prevCs;
        for (int s = 1; s <= steps; s++) {
          final stepDist = prevDist + s * 50;
          final isMeasuredEnd = s == steps;
          final stepCumulCs = isMeasuredEnd
              ? cp.cs
              : prevCs + (deltaCs * s / steps).round();
          final stepLapCs = stepCumulCs - runningPrevCs;
          final isFirstEver = legs.isEmpty;

          legs.add((
            label: isMeasuredEnd ? cp.label : '~${stepDist}m',
            lapTime: SwimTimeFormatter.formatCs(stepLapCs),
            cumulativeTime: isFirstEver
                ? null
                : (isMeasuredEnd
                    ? (cp.rawVal ?? SwimTimeFormatter.formatCs(stepCumulCs))
                    : SwimTimeFormatter.formatCs(stepCumulCs)),
          ));
          runningPrevCs = stepCumulCs;
        }
      } else {
        final isFirstEver = legs.isEmpty;
        legs.add((
          label: cp.label,
          lapTime: SwimTimeFormatter.formatCs(deltaCs),
          cumulativeTime: isFirstEver
              ? null
              : (cp.rawVal ?? SwimTimeFormatter.formatCs(cp.cs)),
        ));
      }

      prevDist = cp.dist;
      prevCs = cp.cs;
    }

    return legs;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final result = widget.result;

    final rawStatus = result.resultStatus.trim().toUpperCase();
    final isWaiting = rawStatus == 'WAITING';
    final isDns = rawStatus == 'DNS';
    final isDnf = rawStatus == 'DNF';
    final isDsq = rawStatus == 'DQ' ||
        rawStatus == 'DSQ' ||
        result.rank.toUpperCase().startsWith('DQ') ||
        result.rank.toUpperCase().startsWith('DSQ');
    final isNonFinish = isDns || isDnf || isDsq;
    final isSwimming = rawStatus == 'SWIMMING' || rawStatus == 'HAVUZDA';

    final hasValidTime = LiveResultRow.hasValidRaceTime(result);
    final isCompleted = !isWaiting && !isNonFinish && !isSwimming && hasValidTime;

    final rawRank = result.rank.replaceAll('.', '').trim();
    final parsedRank = int.tryParse(rawRank);
    final effectiveRank = (parsedRank != null && parsedRank > 0)
        ? parsedRank
        : (widget.rankIndex != null && widget.rankIndex! > 0
            ? widget.rankIndex
            : null);

    final isPodium = isCompleted && effectiveRank != null && effectiveRank <= 3;

    final heatMatch = RegExp(r'\d+').firstMatch(result.heat);
    final cleanHeat = heatMatch?.group(0) ?? '';
    final heatStr = cleanHeat.isNotEmpty
        ? cleanHeat
        : (result.heat.isNotEmpty ? result.heat : '-');
    final laneStr =
        result.lane != null && result.lane! > 0 ? '${result.lane}' : '-';

    final String rankOrLaneText = isCompleted && effectiveRank != null
        ? '$effectiveRank.'
        : '$heatStr/$laneStr';

    final bool isMyTeam = widget.highlightMyTeam &&
        SelectedClubService.instance.matches(result.clubName, result.clubId);

    final primaryTitle = widget.titleOverride ??
        StringUtils.formatAthleteName(result.athleteName);
    final clubName = result.clubName.trim().isNotEmpty
        ? StringUtils.toTitleCase(result.clubName)
        : 'Ferdi Sporcu';

    final String? subtitleText;
    if (widget.subtitleOverride != null) {
      subtitleText =
          widget.subtitleOverride!.trim().isNotEmpty ? widget.subtitleOverride : null;
    } else if (widget.isPinnedClubRow) {
      final hasHeat = cleanHeat.isNotEmpty || result.heat.trim().isNotEmpty;
      final heatDisplay = cleanHeat.isNotEmpty ? cleanHeat : result.heat.trim();
      final hasLane = result.lane != null && result.lane! > 0;
      final estTime = (result.estimatedTime ?? '').trim();
      final baseParts = <String>[
        if (hasHeat) 'Seri $heatDisplay',
        if (hasLane) 'Kulvar ${result.lane}',
        if (estTime.isNotEmpty) estTime,
      ];
      subtitleText = baseParts.isNotEmpty ? baseParts.join(' • ') : null;
    } else {
      subtitleText = clubName;
    }

    final Color? podiumBadgeColor;
    if (isCompleted && effectiveRank == 1) {
      podiumBadgeColor = palette.statusWarning;
    } else if (isCompleted && effectiveRank == 2) {
      podiumBadgeColor = palette.textSecondary;
    } else if (isCompleted && effectiveRank == 3) {
      podiumBadgeColor = palette.accent;
    } else {
      podiumBadgeColor = null;
    }

    final chipFill = podiumBadgeColor != null
        ? podiumBadgeColor.withValues(alpha: 0.15)
        : palette.surfaceSecondary;
    final chipBorder = podiumBadgeColor != null
        ? podiumBadgeColor.withValues(alpha: 0.28)
        : palette.border.withValues(alpha: 0.6);

    final String formattedTime;
    if (result.timeCs != null && result.timeCs! > 0) {
      formattedTime = SwimTimeFormatter.formatCs(result.timeCs);
    } else if (result.time != null && result.time!.trim().isNotEmpty) {
      var t = result.time!.trim();
      if (t.startsWith('00:')) t = t.substring(3);
      formattedTime = t;
    } else {
      formattedTime = '-';
    }

    final seedDisplay = _getDisplaySeedTime(result);
    final finishCs = result.timeCs ?? _parseTimeToCs(result.time);
    final seedCs = (result.seedTimeCs != null && result.seedTimeCs! > 0)
        ? result.seedTimeCs
        : _parseTimeToCs(result.seedTime);
    final isFasterThanSeed = isCompleted &&
        finishCs != null &&
        seedCs != null &&
        finishCs > 0 &&
        seedCs > 0 &&
        finishCs < seedCs;
    final isSlowerThanSeed = isCompleted &&
        finishCs != null &&
        seedCs != null &&
        finishCs > 0 &&
        seedCs > 0 &&
        finishCs > seedCs;

    Widget buildSeedRow({required bool compare}) {
      final faster = compare && isFasterThanSeed;
      final slower = compare && isSlowerThanSeed;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (faster)
            Icon(
              Icons.arrow_drop_down_outlined,
              size: 16,
              color: palette.successText,
            )
          else if (slower)
            Icon(
              Icons.arrow_drop_up_outlined,
              size: 16,
              color: palette.statusDanger,
            ),
          Text(
            seedDisplay!,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
              fontWeight: (faster || slower) ? FontWeight.w600 : FontWeight.w400,
              color: faster
                  ? palette.successText
                  : (slower ? palette.statusDanger : palette.textSecondary),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    Widget trailingWidget;
    if (isDns) {
      trailingWidget = const StatusBadge.neutral(label: 'Başlamadı');
    } else if (isDnf) {
      trailingWidget = const StatusBadge.neutral(label: 'Tamamlamadı');
    } else if (isDsq) {
      trailingWidget = StatusBadge(
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
    } else if (isSwimming) {
      trailingWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusBadge.live(label: 'Havuzda'),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            buildSeedRow(compare: false),
          ],
        ],
      );
    } else if (!isCompleted) {
      if (seedDisplay != null && seedDisplay.isNotEmpty) {
        trailingWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              seedDisplay,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: AppTextStyles.displayFontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Giriş derecesi',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: palette.textSecondary,
              ),
            ),
          ],
        );
      } else {
        trailingWidget = const StatusBadge.neutral(label: 'Bekleniyor');
      }
    } else {
      trailingWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formattedTime,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.displayFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (seedDisplay != null && seedDisplay.isNotEmpty) ...[
            const SizedBox(height: 2),
            buildSeedRow(compare: true),
          ],
        ],
      );
    }

    final splits = _buildSplitLegs(
      result,
      isCompleted: isCompleted,
      finishCs: finishCs,
      formattedTime: formattedTime,
    );
    final totalDist = result.distance ?? widget.eventDistance ?? 0;
    final canLazyLoadSplits = isCompleted &&
        totalDist >= 100 &&
        widget.onLoadSplits != null &&
        !_didAttemptLoadSplits;
    final showExpandButton = splits.isNotEmpty || canLazyLoadSplits;
    final isExpanded = splits.isNotEmpty && _isExpanded;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isMyTeam
              ? palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.12)
              : Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: widget.onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.s12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          constraints: const BoxConstraints(minWidth: 44),
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
                            rankOrLaneText,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              fontWeight:
                                  isPodium ? FontWeight.w700 : FontWeight.w600,
                              color: podiumBadgeColor ?? palette.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        AppSpacing.h12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (isMyTeam) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: AppSpacing.xs,
                                      ),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: palette.accent,
                                      ),
                                    ),
                                  ],
                                  if (widget.leadingBadgeText != null &&
                                      widget.leadingBadgeText!
                                          .trim()
                                          .isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.surfaceContrast,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        widget.leadingBadgeText!.trim(),
                                        style: TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: palette.textOnContrast,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Expanded(
                                    child: Text(
                                      primaryTitle,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (subtitleText != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitleText,
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
                            ],
                          ),
                        ),
                        if (showExpandButton) ...[
                          AppSpacing.hSm,
                          Tooltip(
                            message: 'Ara dereceler',
                            child: InkWell(
                              onTap: _handleToggleExpand,
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isExpanded
                                      ? palette.accent.withValues(alpha: 0.14)
                                      : palette.surfaceSecondary,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isExpanded
                                        ? palette.accent.withValues(alpha: 0.35)
                                        : palette.border.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: _isLoadingSplits
                                    ? Center(
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                            color: palette.accent,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.timer_outlined,
                                        size: 16,
                                        color: isExpanded
                                            ? palette.accent
                                            : palette.textSecondary,
                                      ),
                              ),
                            ),
                          ),
                        ],
                        AppSpacing.h12,
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 136),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: trailingWidget,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isDsq && (result.warningNote ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.s12,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: palette.statusDanger.withValues(alpha: 0.08),
                      borderRadius: AppRadius.smallRadius,
                      border: Border.all(
                        color: palette.statusDanger.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1.5),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: palette.statusDanger,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result.warningNote!
                                .trim()
                                .replaceFirst(
                                  RegExp(r'^(?:DSQ|DQ)\s*-\s*',
                                      caseSensitive: false),
                                  '',
                                )
                                .trim(),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: palette.statusDanger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: isExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.s12,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s12,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: palette.textPrimary.withValues(
                              alpha: palette.isDark ? 0.05 : 0.03,
                            ),
                            borderRadius: AppRadius.smallRadius,
                            border: Border.all(color: palette.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ara Dereceler',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textSecondary,
                                ),
                              ),
                              AppSpacing.vXs,
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                children: splits.map((e) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.textPrimary.withValues(
                                        alpha: palette.isDark ? 0.06 : 0.04,
                                      ),
                                      borderRadius: AppRadius.smallRadius,
                                      border: Border.all(
                                        color: palette.divider,
                                      ),
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${e.label} ',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                              color: palette.textSecondary,
                                            ),
                                          ),
                                          TextSpan(
                                            text: e.lapTime,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          if (e.cumulativeTime != null)
                                            TextSpan(
                                              text: ' (${e.cumulativeTime})',
                                              style: TextStyle(
                                                fontFamily:
                                                    AppTextStyles.fontFamily,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                                color: palette.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (widget.showDivider)
          Divider(height: 1, thickness: 1, color: palette.divider),
      ],
    );
  }
}
