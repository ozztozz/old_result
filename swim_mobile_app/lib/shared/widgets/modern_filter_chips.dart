import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

/// Minimalist Filtre Çipi Tanımı
class FilterChipItem {
  final String label;
  final IconData? icon;

  const FilterChipItem({
    required this.label,
    this.icon,
  });
}

/// TYF Yüzme Sonuçları — Soft Glass Filtre Çipi
class ModernFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool softRaised;

  const ModernFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.softRaised = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (softRaised) {
      final fillColor = isSelected
          ? palette.textPrimary
          : (palette.isCrispCardTheme
              ? palette.surface
              : Colors.white.withValues(alpha: palette.isDark ? 0.08 : 0.35));
      final textColor = isSelected
          ? (palette.isDark ? palette.background : Colors.white)
          : (palette.isCrispCardTheme
              ? palette.textSecondary
              : palette.textTertiary);

      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.chipRadius,
            child: AnimatedContainer(
              duration:
                  disableMotion ? Duration.zero : const Duration(milliseconds: 180),
              height: 36,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: AppRadius.chipRadius,
                border: Border.all(
                  color: isSelected
                      ? palette.textPrimary
                      : (palette.isCrispCardTheme
                          ? palette.border
                          : Colors.white.withValues(
                              alpha: palette.isDark ? 0.14 : 0.45,
                            )),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadowTint.withValues(
                      alpha: palette.isShadcn ? 0.04 : 0.10,
                    ),
                    blurRadius: palette.isShadcn ? 2 : 10,
                    offset: Offset(0, palette.isShadcn ? 1 : 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadius.chipRadius,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isSelected)
                      Positioned(
                        top: 0,
                        left: 10,
                        right: 10,
                        height: 1,
                        child: ColoredBox(
                          color: Colors.white.withValues(
                            alpha: palette.isDark ? 0.18 : 0.65,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: textColor),
                            AppSpacing.hXs,
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13.5,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SoftGlassPanel(
      level: 3,
      height: 36,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      borderRadius: AppRadius.chipRadius,
      animationDuration: const Duration(milliseconds: 180),
      fillColorOverride: isSelected ? palette.activeChipFill : null,
      borderAlphaOverride: isSelected ? palette.activeChipBorderAlpha : null,
      shadowsOverride: isSelected
          ? [
              BoxShadow(
                color: palette.activeChipShadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: isSelected ? palette.activeChipText : palette.textTertiary,
            ),
            AppSpacing.hXs,
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? palette.activeChipText : palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yatay Kaydırılabilir Modern Filtre Çipleri Listesi
class ModernFilterChipBar extends StatelessWidget {
  final List<FilterChipItem> chips;
  final String selectedChip;
  final ValueChanged<String> onSelected;
  final bool softRaised;

  const ModernFilterChipBar({
    super.key,
    required this.chips,
    required this.selectedChip,
    required this.onSelected,
    this.softRaised = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: softRaised ? 44 : 36,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final fadeStart = bounds.width > 28
              ? ((bounds.width - 28) / bounds.width).clamp(0.0, 1.0)
              : 0.0;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0.0, fadeStart, 1.0],
            colors: const [Colors.white, Colors.white, Colors.transparent],
          ).createShader(bounds);
        },
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.only(
            right: AppSpacing.md,
            top: softRaised ? 2 : 0,
            bottom: softRaised ? 6 : 0,
          ),
          itemCount: chips.length,
          itemBuilder: (context, index) {
            final item = chips[index];
            final isSelected = item.label == selectedChip;
            return ModernFilterChip(
              label: item.label,
              icon: item.icon,
              isSelected: isSelected,
              softRaised: softRaised,
              onTap: () => onSelected(item.label),
            );
          },
        ),
      ),
    );
  }
}
