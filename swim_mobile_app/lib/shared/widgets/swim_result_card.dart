import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../core/theme/swim_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/race_result.dart';
import 'swim_status_badge.dart';

/// Yüzme Yarış Sonucu Kartı (SwimResultCard)
/// Minimalist İskandinav Pastel Tasarım Mantığı (AppColors, 20dp radius, dairesel rozet, soft gölge)
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
    final isWaiting = result.resultStatus == 'WAITING';
    final isDq = result.resultStatus == 'DQ' ||
        result.resultStatus == 'DNS' ||
        result.resultStatus == 'DNF' ||
        result.rank.toUpperCase().startsWith('DQ') ||
        result.rank.toUpperCase().startsWith('DSQ');
    final rank = result.rank.trim();

    // Dairesel rozet arka planı ve metni
    Color badgeBg;
    Color badgeTextColor;
    Widget badgeContent;

    if (isWaiting) {
      badgeBg = Colors.white;
      badgeTextColor = AppColors.muted;
      badgeContent = const Icon(
        Icons.schedule_rounded,
        size: 18,
        color: AppColors.muted,
      );
    } else if (isDq) {
      badgeBg = const Color(0xFFFFEBEE);
      badgeTextColor = const Color(0xFFD32F2F);
      badgeContent = Text(
        result.resultStatus.isNotEmpty ? result.resultStatus : 'DQ',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: badgeTextColor,
        ),
      );
    } else if (rank == '1') {
      badgeBg = AppColors.lime;
      badgeTextColor = AppColors.ink;
      badgeContent = Text(
        '1',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: badgeTextColor,
        ),
      );
    } else if (rank == '2') {
      badgeBg = AppColors.teal;
      badgeTextColor = AppColors.ink;
      badgeContent = Text(
        '2',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: badgeTextColor,
        ),
      );
    } else if (rank == '3') {
      badgeBg = AppColors.lavender;
      badgeTextColor = AppColors.ink;
      badgeContent = Text(
        '3',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: badgeTextColor,
        ),
      );
    } else {
      badgeBg = Colors.white;
      badgeTextColor = AppColors.ink;
      badgeContent = Text(
        rank.isNotEmpty ? '#$rank' : '-',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: badgeTextColor,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Sıralama / Madalya Dairesel Rozeti
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: badgeContent,
                ),
                const SizedBox(width: 14),

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
                          color: AppColors.ink,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        result.clubName.isNotEmpty ? result.clubName : 'Ferdi',
                        style: const TextStyle(
                          color: AppColors.muted,
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
                              result.heat.startsWith('Seri')
                                  ? result.heat
                                  : 'Seri: ${result.heat}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (result.lane != null && result.lane! > 0)
                            Text(
                              'Kulvar ${result.lane}',
                              style: const TextStyle(
                                color: AppColors.muted,
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

                // 3. Süre & Baraj Rozeti
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWaiting)
                        const SwimStatusBadge.waiting()
                      else if (isDq)
                        SwimStatusBadge.disqualified(
                          customLabel: result.resultStatus.isNotEmpty
                              ? result.resultStatus
                              : 'DQ',
                        )
                      else
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            SwimTimeFormatter.formatCs(result.timeCs),
                            style: SwimTheme.timeDisplay.copyWith(
                              color: AppColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),
                      if (result.points != null && result.points! > 0)
                        Text(
                          '${result.points} Puan',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (result.qualifyingStandard != null &&
                          result.qualifyingStandard!.passed)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SwimStatusBadge.standard(
                            badge: result.qualifyingStandard!.badge,
                          ),
                        ),
                    ],
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
