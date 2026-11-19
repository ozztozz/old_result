import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Yüzen Frosted Glass Navigasyon Katmanı
/// SECOND DESIGN REFINEMENT — Section 7:
/// Çerçevesiz, hafif ve zarif aktif durum; kenarlıklı araç çubuğu yerine yüzen cam hissi.
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
          22,
          0,
          22,
          bottomInset > 0 ? bottomInset + 8 : 16,
        ),
        child: SoftGlassPanel(
          tier: GlassTier.dock,
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: SizedBox(
            height: 50,
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
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: disableMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? (palette.isDark
                      ? palette.primary.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.52))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 20,
                  color: isSelected ? palette.textPrimary : palette.textMuted,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.1,
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
