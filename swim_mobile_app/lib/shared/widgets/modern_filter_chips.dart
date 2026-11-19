import 'package:flutter/material.dart';
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

  const ModernFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? palette.surfaceGlassStrong : palette.surfaceSecondary.withValues(alpha: 0.55),
          borderRadius: AppRadius.medium,
          border: Border.all(
            color: isSelected ? palette.primary.withValues(alpha: 0.45) : palette.border,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.softShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? palette.primary : palette.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? palette.textPrimary : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yatay Kaydırılabilir Modern Filtre Çipleri Listesi
class ModernFilterChipBar extends StatelessWidget {
  final List<FilterChipItem> chips;
  final String selectedChip;
  final ValueChanged<String> onSelected;

  const ModernFilterChipBar({
    super.key,
    required this.chips,
    required this.selectedChip,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final item = chips[index];
          final isSelected = item.label == selectedChip;
          return ModernFilterChip(
            label: item.label,
            icon: item.icon,
            isSelected: isSelected,
            onTap: () => onSelected(item.label),
          );
        },
      ),
    );
  }
}
