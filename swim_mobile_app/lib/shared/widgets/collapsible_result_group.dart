import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

/// Çoklu sıralama / yaş kategorisi grupları için varsayılan olarak açık gelen
/// açılır-kapanır bölüm başlığı ve içerik konteyneri.
class CollapsibleResultGroup extends StatelessWidget {
  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  const CollapsibleResultGroup({
    super.key,
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: AppRadius.smallRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  AppSpacing.hSm,
                  Text(
                    '$count Sporcu',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  AppSpacing.hXs,
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
