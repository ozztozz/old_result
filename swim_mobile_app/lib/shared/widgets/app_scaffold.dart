import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fadeBaseColor = palette.ambientBottom;

    return Scaffold(
      backgroundColor: palette.background,
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: currentIndex,
            children: screens,
          ),
          // Navigasyon arkasında 120px yumuşak alt sönümleme katmanı
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120 + bottomInset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      fadeBaseColor.withValues(alpha: 0.0),
                      fadeBaseColor.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomInset),
        child: SoftGlassPanel(
          tier: GlassTier.dock,
          height: 64,
          borderRadius: BorderRadius.circular(28),
          padding: const EdgeInsets.all(5),
          child: _buildNavContent(context),
        ),
      ),
    );
  }

  Widget _buildNavContent(BuildContext context) {
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final clampedIndex = currentIndex.clamp(0, 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / 3;

        return Stack(
          children: [
            // Kayan yumuşak yarı saydam aktif hap (200ms, easeOut, kenarlıksız)
            AnimatedPositioned(
              duration: disableMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: clampedIndex * tabWidth,
              top: 0,
              bottom: 0,
              width: tabWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 1.0,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3 Sekme Butonu
            Row(
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
          ],
        );
      },
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
    final activeColor = palette.navLabelActive;
    final inactiveColor = palette.navLabelInactive.withValues(alpha: 0.86);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigationChanged(index),
          borderRadius: BorderRadius.circular(22),
          splashColor: Colors.white.withValues(alpha: 0.08),
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
                    fontSize: 11.5,
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
