import 'package:flutter/material.dart';
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
/// Renk tek başına anlam taşımaz; her duruma ikon ve etiket eşlik eder (WCAG AA).
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
    Color border;
    IconData icon;
    String label;

    switch (type) {
      case SwimBadgeType.finished:
        bg = colors.success.withOpacity(isDark ? 0.2 : 0.1);
        fg = colors.success;
        border = colors.success.withOpacity(0.3);
        icon = Icons.check_circle_outline;
        label = customLabel ?? 'Sonuçlandı';
        break;

      case SwimBadgeType.waiting:
        bg = colors.pendingBg;
        fg = colors.pending;
        border = colors.pending.withOpacity(0.4);
        icon = Icons.schedule;
        label = customLabel ?? 'Bekleniyor';
        break;

      case SwimBadgeType.disqualified:
        bg = colors.danger.withOpacity(isDark ? 0.2 : 0.1);
        fg = colors.danger;
        border = colors.danger.withOpacity(0.4);
        icon = Icons.cancel_outlined;
        label = customLabel ?? 'DQ';
        break;

      case SwimBadgeType.pb:
        bg = colors.pb.withOpacity(isDark ? 0.25 : 0.1);
        fg = colors.pb;
        border = colors.pb.withOpacity(0.5);
        icon = Icons.star;
        label = customLabel ?? 'Yeni PB';
        break;

      case SwimBadgeType.standard:
        bg = colors.success.withOpacity(isDark ? 0.2 : 0.1);
        fg = colors.success;
        border = colors.success.withOpacity(0.3);
        icon = Icons.verified_outlined;
        label = customLabel != null ? 'Baraj $customLabel' : 'Baraj';
        break;

      case SwimBadgeType.provisional:
        bg = Theme.of(context).cardTheme.color!;
        fg = Theme.of(context).textTheme.bodySmall!.color!;
        border = Theme.of(context).colorScheme.outline;
        icon = Icons.info_outline;
        label = customLabel ?? 'Geçici (Canlı)';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
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
