import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'soft_glass_panel.dart';

/// Editoryal bölüm başlığı bileşeni.
/// Sağ rozet doğrudan [SoftGlassPanel] Seviye 3 kullanır.
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

    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (trailingText != null)
          SoftGlassPanel(
            level: 3,
            height: 26,
            borderRadius: BorderRadius.circular(999),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Text(
                trailingText!,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
