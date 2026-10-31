import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_decorations.dart';

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
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: AppDecorations.tabContainer,
      child: TabBar(
        controller: controller,
        indicator: AppDecorations.tabIndicator,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
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
                  Icon(t.icon, size: 16, color: t.iconColor ?? AppColors.textSecondary),
                  const SizedBox(width: 6),
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

