import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Minimalist Filtre Çipi Tanımı
class FilterChipItem {
  final String label;
  final IconData? icon;

  const FilterChipItem({
    required this.label,
    this.icon,
  });
}

/// TYF Yüzme Sonuçları — Apple Esintili Filtre Çipi (v2.0)
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.border : Colors.transparent,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x0A3D3038),
                    blurRadius: 2,
                    offset: Offset(0, 1),
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
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
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

