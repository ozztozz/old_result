import 'package:flutter/material.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: height,
      padding: AppSpacing.paddingAllXs,
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: AppRadius.chipRadius,
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.chipRadius,
          boxShadow: [
            BoxShadow(
              color: palette.textPrimary.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        labelColor: palette.textPrimary,
        unselectedLabelColor: palette.textSecondary,
        labelStyle: AppTextStyles.tabSelected,
        unselectedLabelStyle: AppTextStyles.tabUnselected,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: tabs.map((t) {
          return Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (t.icon != null) ...[
                  Icon(t.icon, size: 16, color: t.iconColor ?? palette.textSecondary),
                  AppSpacing.hXs,
                ],
                Text(t.title),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
