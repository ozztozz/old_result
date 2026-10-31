import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Ana Kabuk ve Navigasyon (v2.0)
/// Apple Esintili Yalınlık, dinamik AppColorPalette desteği.
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(
            top: BorderSide(
              color: palette.divider,
              width: 1.0,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _buildNavItem(context, 0, 'Ana Sayfa', Icons.home_outlined, Icons.home_rounded),
                _buildNavItem(context, 1, 'Canlı Takip', Icons.sensors_outlined, Icons.sensors_rounded),
                _buildNavItem(context, 2, 'Favorilerim', Icons.star_outline_rounded, Icons.star_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, String label, IconData icon, IconData activeIcon) {
    final palette = context.palette;
    final isSelected = currentIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => onNavigationChanged(index),
        child: Column(
          children: [
            // Seçili olan sekmenin üstünde 2px kalınlığında zarif çizgi
            Container(
              height: 2,
              width: 36,
              decoration: BoxDecoration(
                color: isSelected ? palette.primary : Colors.transparent,
                borderRadius: AppRadius.smallRadius,
              ),
            ),
            const Spacer(),
            Icon(
              isSelected ? activeIcon : icon,
              size: 21,
              color: isSelected ? palette.textPrimary : palette.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? palette.textPrimary : palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
