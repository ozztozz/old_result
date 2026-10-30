import 'package:flutter/material.dart';
import '../../core/theme/swim_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/race_result.dart';
import 'swim_status_badge.dart';

/// Yüzme Yarış Sonucu Kartı (SwimResultCard)
/// Sade, gölgesiz, 1dp kenarlıklı ve FittedBox ile taşma korumalı imza bileşen.
class SwimResultCard extends StatelessWidget {
  final RaceResult result;
  final VoidCallback? onTap;

  const SwimResultCard({
    super.key,
    required this.result,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.swimColors;
    final isWaiting = result.resultStatus == 'WAITING';
    final isDq = result.resultStatus == 'DQ' || result.resultStatus == 'DNS';
    final rank = result.rank.trim();

    // Kürsü madalya rengi (1, 2, 3)
    Color? medalColor;
    if (rank == '1') medalColor = colors.medalGold;
    if (rank == '2') medalColor = colors.medalSilver;
    if (rank == '3') medalColor = colors.medalBronze;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Sıralama / Madalya Rozeti
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: medalColor != null
                      ? medalColor.withOpacity(0.15)
                      : isWaiting
                          ? colors.pendingBg
                          : isDq
                              ? colors.danger.withOpacity(0.12)
                              : Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: medalColor ??
                        (isWaiting
                            ? colors.pending.withOpacity(0.4)
                            : isDq
                                ? colors.danger.withOpacity(0.4)
                                : Theme.of(context).colorScheme.outline),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  isWaiting ? '⏱' : (isDq ? result.resultStatus : (rank.isNotEmpty ? '#$rank' : '-')),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: medalColor ??
                        (isWaiting
                            ? colors.pending
                            : isDq
                                ? colors.danger
                                : Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 2. Sporcu ve Kulüp Detayı
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.athleteName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.clubName,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall!.color,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (result.heat.isNotEmpty) ...[
                          Text(
                            result.heat,
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall!.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (result.lane != null)
                          Text(
                            'Kulvar ${result.lane}',
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodySmall!.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 3. Süre (FittedBox ile taşma korumalı) & Baraj Rozeti
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isWaiting)
                      const SwimStatusBadge.waiting()
                    else if (isDq)
                      SwimStatusBadge.disqualified(customLabel: result.resultStatus)
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          SwimTimeFormatter.formatCs(result.timeCs),
                          style: SwimTheme.timeDisplay.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 3),
                    if (result.points != null && result.points! > 0)
                      Text(
                        '${result.points} Puan',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall!.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (result.qualifyingStandard != null && result.qualifyingStandard!.passed)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SwimStatusBadge.standard(badge: result.qualifyingStandard!.badge),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
