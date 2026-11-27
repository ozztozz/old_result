import 'package:flutter/material.dart';

import '../../core/theme/tokens/tokens.dart';
import '../../data/models/live_meet.dart';

/// Canlı yarış akışı ve kulüp yarış bazlı listesinde ortak kullanılan
/// yarış başlık bileşeni (Mesafe dairesi, stil, cinsiyet, Yarış No, durum ve gün/saat/yaş çipleri).
class LiveEventHeader extends StatelessWidget {
  final LiveEventProgramItem event;
  final bool? isDoneOverride;
  final int? athleteCountBadge;
  final bool showStatusIcon;
  final bool showChevron;

  const LiveEventHeader({
    super.key,
    required this.event,
    this.isDoneOverride,
    this.athleteCountBadge,
    this.showStatusIcon = true,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasDistance = event.distance != null && event.distance! > 0;
    final strokeText = (hasDistance && event.strokeLabel.isNotEmpty)
        ? event.strokeLabel
        : event.displayTitle;
    final genderText = event.genderLabel;
    final isFemale = genderText == 'Kadınlar';
    final isMale = genderText == 'Erkekler';
    final isDone = isDoneOverride ??
        (!event.isPending || event.status.toLowerCase().contains('sonu'));
    final ageText = (event.ageGroup ?? '').trim();
    final dayText =
        (event.day != null && event.day! > 0) ? '${event.day}. Gün' : '';
    final timeText = (event.estimatedTime ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (hasDistance) ...[
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
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                        '${event.distance}',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppTextStyles.displayFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: palette.accent,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      strokeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (genderText.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Tooltip(
                      message: genderText,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: (isFemale
                                  ? palette.statusLive
                                  : (isMale
                                      ? palette.accent
                                      : palette.infoCyan))
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (isFemale
                                    ? palette.statusLive
                                    : (isMale
                                        ? palette.accent
                                        : palette.infoCyan))
                                .withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          isFemale
                              ? Icons.female_rounded
                              : (isMale
                                  ? Icons.male_rounded
                                  : Icons.wc_rounded),
                          size: 16,
                          color: isFemale
                              ? palette.statusLive
                              : (isMale ? palette.accent : palette.infoCyan),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (event.eventNo.trim().isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceContrast,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Yarış ${event.eventNo.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textOnContrast,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
            if (showStatusIcon) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: event.status,
                child: Icon(
                  isDone ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 17,
                  color: isDone ? palette.statusSuccess : palette.statusWarning,
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.accent,
                ),
              ),
            ],
          ],
        ),
        if (dayText.isNotEmpty ||
            timeText.isNotEmpty ||
            ageText.isNotEmpty ||
            athleteCountBadge != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (dayText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    dayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                ),
              if (timeText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.7),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 11.5,
                        color: palette.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (ageText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.7),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    ageText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              if (athleteCountBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 12,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$athleteCountBadge',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
