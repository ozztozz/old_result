import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../core/theme/swim_theme.dart';

enum SwimBadgeType {
  finished,
  waiting,
  disqualified,
  pb,
  standard,
  provisional,
}

/// Yüzme Durum Rozeti (SwimStatusBadge)
/// Minimalist pastel tasarım sistemiyle uyumlu hap (pill) rozet.
class SwimStatusBadge extends StatelessWidget {
  final SwimBadgeType type;
  final String? customLabel;

  const SwimStatusBadge({
    super.key,
    required this.type,
    this.customLabel,
  });

  const SwimStatusBadge.finished({super.key, this.customLabel})
      : type = SwimBadgeType.finished;

  const SwimStatusBadge.waiting({super.key, this.customLabel})
      : type = SwimBadgeType.waiting;

  const SwimStatusBadge.disqualified({super.key, this.customLabel})
      : type = SwimBadgeType.disqualified;

  const SwimStatusBadge.pb({super.key, this.customLabel})
      : type = SwimBadgeType.pb;

  const SwimStatusBadge.standard({super.key, required String badge})
      : type = SwimBadgeType.standard,
        customLabel = badge;

  const SwimStatusBadge.provisional({super.key, this.customLabel})
      : type = SwimBadgeType.provisional;

  @override
  Widget build(BuildContext context) {
    final colors = context.swimColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (type) {
      case SwimBadgeType.finished:
        bg = isDark ? colors.success.withValues(alpha: 0.2) : AppColors.mint;
        fg = isDark ? colors.success : AppColors.ink;
        icon = Icons.check_circle_rounded;
        label = customLabel ?? 'Sonuçlandı';
        break;

      case SwimBadgeType.waiting:
        bg = isDark ? colors.pendingBg : AppColors.lavender;
        fg = isDark ? colors.pending : AppColors.ink;
        icon = Icons.schedule_rounded;
        label = customLabel ?? 'Bekleniyor';
        break;

      case SwimBadgeType.disqualified:
        bg = isDark ? colors.danger.withValues(alpha: 0.2) : const Color(0xFFFFEBEE);
        fg = isDark ? colors.danger : const Color(0xFFD32F2F);
        icon = Icons.cancel_rounded;
        label = customLabel ?? 'DQ';
        break;

      case SwimBadgeType.pb:
        bg = isDark ? colors.pb.withValues(alpha: 0.25) : AppColors.lime;
        fg = isDark ? colors.pb : AppColors.ink;
        icon = Icons.star_rounded;
        label = customLabel ?? 'Yeni PB';
        break;

      case SwimBadgeType.standard:
        bg = isDark ? colors.success.withValues(alpha: 0.2) : AppColors.teal;
        fg = isDark ? colors.success : AppColors.ink;
        icon = Icons.verified_rounded;
        label = customLabel != null ? 'Baraj $customLabel' : 'Baraj';
        break;

      case SwimBadgeType.provisional:
        bg = isDark ? Theme.of(context).cardTheme.color! : Colors.white;
        fg = isDark ? Theme.of(context).textTheme.bodySmall!.color! : AppColors.ink;
        icon = Icons.info_outline_rounded;
        label = customLabel ?? 'Geçici';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}


