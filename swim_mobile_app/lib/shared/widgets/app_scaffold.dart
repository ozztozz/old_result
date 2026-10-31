import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// TYF Yüzme Sonuçları — Ana Kabuk ve Navigasyon (v2.0)
/// Apple Esintili Yalınlık:
/// - Zemin: #FAF8F7 ferah kırık beyaz
/// - Alt Bar: #FFFFFF temiz beyaz, 1px #EFE9E7 üst sınır çizgisi
/// - Seçili sekmenin altında #BC8C91 renginde 2px kalınlığında zarif bir çizgi
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
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
                _buildNavItem(0, 'Ana Sayfa', Icons.home_outlined, Icons.home_rounded),
                _buildNavItem(1, 'Canlı Takip', Icons.sensors_outlined, Icons.sensors_rounded),
                _buildNavItem(2, 'Favorilerim', Icons.star_outline_rounded, Icons.star_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon, IconData activeIcon) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => onNavigationChanged(index),
        child: Column(
          children: [
            // Seçili olan sekmenin üstünde 2px kalınlığında zarif #BC8C91 çizgi
            Container(
              height: 2,
              width: 36,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const Spacer(),
            Icon(
              isSelected ? activeIcon : icon,
              size: 21,
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

