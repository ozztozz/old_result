import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Soft Glass Ana Kabuk ve Yüzen Navigasyon Çubuğu
/// design.md: Minimal, yarı saydam cam yüzey, yumuşak aktif durum geçişleri.
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
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset > 0 ? bottomInset + 6 : 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: palette.softShadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(palette.glassSheen, palette.surfaceGlassStrong),
                      palette.surfaceGlassStrong,
                    ],
                  ),
                  border: Border.all(
                    color: palette.isDark ? palette.border : palette.glassBorder,
                    width: 1.0,
                  ),
                ),
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
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: disableMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? palette.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? Border.all(
                      color: palette.primary.withValues(alpha: 0.22),
                      width: 0.9,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 20,
                  color: isSelected ? palette.primary : palette.textSecondary,
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
