import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

class TabItemData {
  final String title;
  final IconData? icon;
  final Color? iconColor;

  const TabItemData({
    required this.title,
    this.icon,
    this.iconColor,
  });
}

/// TYF Yüzme Sonuçları — Modern Segmented (Hap Şekilli) TabBar Bileşeni (v2.0)
class ModernSegmentedTabBar extends StatelessWidget {
  final TabController controller;
  final List<TabItemData> tabs;
  final double height;

  const ModernSegmentedTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.height = 46,
  }) : assert(controller.length == tabs.length);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SoftGlassPanel(
      level: 3,
      height: height,
      padding: AppSpacing.paddingAllXs,
      borderRadius: AppRadius.chipRadius,
      animationDuration: const Duration(milliseconds: 240),
      child: AnimatedBuilder(
        animation: controller.animation ?? controller,
        builder: (context, _) {
          final tabCount = tabs.length;
          final animatedIndex = tabCount == 0
              ? 0.0
              : (controller.animation?.value ?? controller.index.toDouble())
                  .clamp(0.0, (tabCount - 1).toDouble());
          final indicatorX =
              tabCount <= 1 ? 0.0 : (animatedIndex * 2 / (tabCount - 1)) - 1;
          final isRtl = Directionality.of(context) == TextDirection.rtl;

          return Stack(
            children: [
              if (tabCount > 0)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(isRtl ? -indicatorX : indicatorX, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / tabCount,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : palette.surface.withValues(alpha: 0.92),
                          borderRadius: AppRadius.chipRadius,
                          border: Border.all(
                            color: palette.isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : palette.border.withValues(alpha: 0.7),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.shadowTint.withValues(
                                alpha: palette.isDark ? 0.24 : 0.08,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var index = 0; index < tabCount; index++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: controller.index == index,
                          inMutuallyExclusiveGroup: true,
                          child: InkWell(
                            borderRadius: AppRadius.chipRadius,
                            onTap: () => controller.animateTo(
                              index,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            ),
                            child: Center(
                              child: AnimatedScale(
                                scale: controller.index == index ? 1.02 : 0.98,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (tabs[index].icon != null) ...[
                                      Icon(
                                        tabs[index].icon,
                                        size: 16,
                                        color: tabs[index].iconColor ??
                                            (controller.index == index
                                                ? palette.accent
                                                : palette.textSecondary),
                                      ),
                                      AppSpacing.hXs,
                                    ],
                                    Flexible(
                                      child: AnimatedDefaultTextStyle(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        style: controller.index == index
                                            ? AppTextStyles.tabSelected
                                                .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: palette.textPrimary,
                                              )
                                            : AppTextStyles.tabUnselected
                                                .copyWith(
                                                fontWeight: FontWeight.w500,
                                                color: palette.textSecondary,
                                              ),
                                        child: Text(
                                          tabs[index].title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
