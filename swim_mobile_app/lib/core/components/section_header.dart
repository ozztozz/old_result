import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Editoryal bölüm başlığı bileşeni.
/// Sağ rozet Seviye 3 (Level 3) frosted cam yüzeyi kullanır.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailingText;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailingText,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = palette.isDark;

    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: palette.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (trailingText != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.25),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  trailingText!,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
