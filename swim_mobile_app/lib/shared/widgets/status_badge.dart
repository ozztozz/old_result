import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

enum StatusBadgeVariant {
  neutral,
  live,
  success,
  warning,
  error,
  info,
}

/// Unified muted status pill used for race, result, and achievement states.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeVariant variant;
  final Color? bgColor;
  final Color? textColor;
  final Widget? leading;
  final bool hasBorder;

  const StatusBadge({
    super.key,
    required this.label,
    this.variant = StatusBadgeVariant.neutral,
    this.bgColor,
    this.textColor,
    this.leading,
    this.hasBorder = true,
  });

  const StatusBadge.neutral({
    super.key,
    this.label = 'Bekleniyor',
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.neutral,
        bgColor = null,
        textColor = null;

  const StatusBadge.live({
    super.key,
    this.label = 'CANLI',
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.live,
        bgColor = null,
        textColor = null;

  const StatusBadge.success({
    super.key,
    this.label = 'Sonuçlandı',
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.success,
        bgColor = null,
        textColor = null;

  const StatusBadge.warning({
    super.key,
    required this.label,
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.warning,
        bgColor = null,
        textColor = null;

  const StatusBadge.error({
    super.key,
    this.label = 'Hata',
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.error,
        bgColor = null,
        textColor = null;

  const StatusBadge.info({
    super.key,
    this.label = 'Bilgi',
    this.leading,
    this.hasBorder = true,
  })  : variant = StatusBadgeVariant.info,
        bgColor = null,
        textColor = null;

  const StatusBadge.finished({super.key, String? customLabel})
      : label = customLabel ?? 'Sonuçlandı',
        variant = StatusBadgeVariant.success,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  const StatusBadge.waiting({super.key, String? customLabel})
      : label = customLabel ?? 'Bekleniyor',
        variant = StatusBadgeVariant.neutral,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  const StatusBadge.disqualified({super.key, String? customLabel})
      : label = customLabel ?? 'DQ',
        variant = StatusBadgeVariant.error,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  const StatusBadge.pb({super.key, String? customLabel})
      : label = customLabel ?? 'Yeni PB',
        variant = StatusBadgeVariant.info,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  const StatusBadge.standard({super.key, required String badge})
      : label = 'Baraj $badge',
        variant = StatusBadgeVariant.success,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  const StatusBadge.provisional({super.key, String? customLabel})
      : label = customLabel ?? 'Geçici',
        variant = StatusBadgeVariant.neutral,
        bgColor = null,
        textColor = null,
        leading = null,
        hasBorder = true;

  factory StatusBadge.completed({String label = 'Sonuçlandı'}) =>
      StatusBadge.success(label: label);

  factory StatusBadge.pending({String label = 'Bekliyor'}) =>
      StatusBadge.neutral(label: label);

  factory StatusBadge.personalBest({String label = 'PB'}) =>
      StatusBadge.info(label: label);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = switch (variant) {
      StatusBadgeVariant.neutral => palette.textSecondary,
      StatusBadgeVariant.live => palette.statusLive,
      StatusBadgeVariant.success => palette.statusSuccess,
      StatusBadgeVariant.warning => palette.statusWarning,
      StatusBadgeVariant.error => palette.statusDanger,
      StatusBadgeVariant.info => palette.primary,
    };
    final foreground = textColor ?? tint;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor ?? tint.withValues(alpha: 0.14),
        borderRadius: AppRadius.chipRadius,
        border: hasBorder
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null)
            leading!
          else
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: AppTextStyles.badge.copyWith(
              color: foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
