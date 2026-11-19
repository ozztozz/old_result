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
      animationDuration: const Duration(milliseconds: 200),
      child: AnimatedBuilder(
        animation: controller,
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
                          color: Colors.white.withValues(
                            alpha: palette.isDark ? 0.12 : 0.18,
                          ),
                          borderRadius: AppRadius.chipRadius,
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
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (tabs[index].icon != null) ...[
                                    Icon(
                                      tabs[index].icon,
                                      size: 16,
                                      color: tabs[index].iconColor ??
                                          palette.textSecondary,
                                    ),
                                    AppSpacing.hXs,
                                  ],
                                  Flexible(
                                    child: Text(
                                      tabs[index].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: controller.index == index
                                          ? AppTextStyles.tabSelected.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: palette.textPrimary,
                                            )
                                          : AppTextStyles.tabUnselected
                                              .copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: palette.textSecondary,
                                            ),
                                    ),
                                  ),
                                ],
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
