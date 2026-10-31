import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'app_button.dart';

/// Katman 3: Atomik UI Bileşeni — EmptyStateWidget
/// Boş durum şablonları, hata veya veri bulunamadı ekranları için standart bileşen.
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String? message;
  final IconData? icon;
  final String? actionText;
  final VoidCallback? onAction;
  final Widget? customAction;
  final bool compact;

  const EmptyStateWidget({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionText,
    this.onAction,
    this.customAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final iconWidget = icon != null
        ? Container(
            width: compact ? 44.0 : 64.0,
            height: compact ? 44.0 : 64.0,
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: compact ? 22.0 : 32.0,
              color: palette.textMuted,
            ),
          )
        : null;

    final titleWidget = Text(
      title,
      textAlign: TextAlign.center,
      style: (compact ? AppTextStyles.tabSelected : AppTextStyles.raceTitle).copyWith(
        color: palette.textPrimary,
      ),
    );

    final messageWidget = message != null
        ? Text(
            message!,
            textAlign: TextAlign.center,
            style: AppTextStyles.categorySeries.copyWith(
              color: palette.textSecondary,
            ),
          )
        : null;

    Widget? actionWidget = customAction;
    if (actionWidget == null && actionText != null && onAction != null) {
      actionWidget = AppButton.secondary(
        text: actionText!,
        onPressed: onAction,
        size: compact ? AppButtonSize.small : AppButtonSize.medium,
      );
    }

    return Center(
      child: Padding(
        padding: compact ? AppSpacing.paddingAllMd : AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (iconWidget != null) ...[
              iconWidget,
              compact ? AppSpacing.vSm : AppSpacing.vMd,
            ],
            titleWidget,
            if (messageWidget != null) ...[
              AppSpacing.vXs,
              messageWidget,
            ],
            if (actionWidget != null) ...[
              compact ? AppSpacing.vSm : AppSpacing.vMd,
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}

