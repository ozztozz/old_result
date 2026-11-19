import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'soft_glass_panel.dart';

/// Shared Level 1 Soft Glass modal bottom sheet shell.
/// Top radius 26, drag handle 36x4, padding 20, max height 85%, SafeArea bottom.
class AppBottomSheet extends StatelessWidget {
  final Widget child;
  final bool scrollable;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.scrollable = true,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool useRootNavigator = true,
  }) {
    final palette = context.palette;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: useRootNavigator,
      backgroundColor: Colors.transparent,
      barrierColor: palette.shadowTint.withValues(alpha: 0.35),
      sheetAnimationStyle: AnimationStyle(
        duration: Duration(milliseconds: disableAnimations ? 150 : 260),
        reverseDuration: Duration(milliseconds: disableAnimations ? 120 : 200),
      ),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    final bodyContent = scrollable
        ? Flexible(
            child: SingleChildScrollView(
              child: child,
            ),
          )
        : Expanded(child: child);

    final sheetFill = palette.isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.12),
            palette.background.withValues(alpha: 0.88),
          )
        : Colors.white.withValues(alpha: 0.60);

    final sheet = Padding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SoftGlassPanel(
          level: 1,
          fillColorOverride: sheetFill,
          borderRadius: AppRadius.sheetRadius,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.s20,
            AppSpacing.s12,
            AppSpacing.s20,
            AppSpacing.lg + bottomInset,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textSecondary.withValues(alpha: 0.4),
                      borderRadius: AppRadius.full,
                    ),
                  ),
                ),
                AppSpacing.vMd,
                bodyContent,
              ],
            ),
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, childWidget) {
        if (disableAnimations) {
          return Opacity(opacity: value, child: childWidget);
        }
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: childWidget,
          ),
        );
      },
      child: sheet,
    );
  }
}
