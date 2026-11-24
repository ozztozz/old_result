import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Yüzen Koyu Yarı Saydam Cam Navigasyon Kabuğu
/// Doğrudan [SoftGlassPanel] (`GlassTier.dock`) kullanır.
class AppScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<Widget> screens;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.screens,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(
            top: BorderSide(
              color: palette.border,
              width: 1.0,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _buildNavItem(
                  context,
                  0,
                  'Ana Sayfa',
                  Icons.home_outlined,
                  Icons.home_rounded,
                ),
                _buildNavItem(
                  context,
                  1,
                  'Canlı Takip',
                  Icons.sensors_outlined,
                  Icons.sensors_rounded,
                ),
                _buildNavItem(
                  context,
                  2,
                  'Favorilerim',
                  Icons.star_outline_rounded,
                  Icons.star_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData activeIcon,
  ) {
    final palette = context.palette;
    final isSelected = currentIndex == index;
    final activeColor = palette.accent;
    final inactiveColor = palette.textSecondary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigationChanged(index),
          splashColor: palette.accent.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 22,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.1,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
