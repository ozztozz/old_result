import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'app_button.dart';
import 'soft_glass_panel.dart';

/// Shared Level 1 Soft Glass modal dialog.
/// Radius 26, max width 360, title w600 18, body 14.5 textSecondary,
/// scale 0.96 -> 1 + fade 200ms (fade only when disableAnimations is true).
class AppDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel = 'Tamam',
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required String body,
    String confirmLabel = 'Tamam',
    String? cancelLabel,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    bool barrierDismissible = true,
  }) {
    final palette = context.palette;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: palette.shadowTint.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, _, __) => AppDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm ?? () => Navigator.of(dialogContext).pop(true),
        onCancel: onCancel ?? () => Navigator.of(dialogContext).pop(false),
      ),
      transitionBuilder: (dialogContext, animation, _, child) {
        final disableAnimations =
            MediaQuery.maybeOf(dialogContext)?.disableAnimations ?? false;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        if (disableAnimations) {
          return FadeTransition(opacity: curved, child: child);
        }
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: AppSpacing.paddingAllLg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SoftGlassPanel(
          level: 1,
          borderRadius: AppRadius.rounded,
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              AppSpacing.vSm,
              Text(
                body,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14.5,
                  height: 1.45,
                  color: palette.textSecondary,
                ),
              ),
              AppSpacing.vLg,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (cancelLabel != null) ...[
                    TextButton(
                      onPressed: onCancel ?? () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                      ),
                      child: Text(cancelLabel!),
                    ),
                    AppSpacing.hSm,
                  ],
                  AppButton(
                    text: confirmLabel,
                    size: AppButtonSize.small,
                    onPressed: onConfirm ?? () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
