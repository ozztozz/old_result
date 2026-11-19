import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Yüzen Soft Glass Navigasyon Kabuğu (DESIGN_REFINEMENT — Section 1E)
/// Frosted yarı saydam zemin, ince parlak cam kenarlık, kompakt ve rafine aktif gösterge.
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: palette.background,
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          bottomInset > 0 ? bottomInset + 8 : 14,
        ),
        child: SoftGlassPanel(
          tier: GlassTier.dock,
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                _buildNavItem(
                  context,
                  0,
                  'Keşfet',
                  Icons.grid_view_outlined,
                  Icons.grid_view_rounded,
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
    final disableMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigationChanged(index),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: disableMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? (palette.isDark
                      ? palette.primary.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.68))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: isSelected
                  ? Border.all(
                      color: palette.isDark
                          ? palette.primary.withValues(alpha: 0.28)
                          : palette.glassBorderSubtle.withValues(alpha: 0.55),
                      width: 0.85,
                    )
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: palette.softShadow.withValues(alpha: palette.softShadow.a * 0.55),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Zarif üst aktif ışık çizgisi
                AnimatedContainer(
                  duration: disableMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  width: isSelected ? 18 : 0,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? palette.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 19,
                  color: isSelected ? palette.textPrimary : palette.textSecondary,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.15,
                    color: isSelected ? palette.textPrimary : palette.textSecondary,
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
