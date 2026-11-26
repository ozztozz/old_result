import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

/// Uygulama genelinde sabit marka başlığı (Logo + KulvaR + Sayfa Alt Başlığı)
/// ve alt sayfalarda geri butonu sağlayan ortak üst bar.
class BrandHeaderBar extends StatelessWidget {
  const BrandHeaderBar({
    super.key,
    this.subtitle = 'Yüzme Platformu',
    this.showBack,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s20,
      10,
      AppSpacing.s20,
      AppSpacing.xs,
    ),
  });

  final String subtitle;
  final bool? showBack;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canPop = showBack ?? (ModalRoute.of(context)?.canPop ?? false);
    final coralColor =
        palette.isDark ? const Color(0xFFFF7A6B) : const Color(0xFFE85D4A);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canPop) ...[
            GlassCircleButton(
              icon: Icons.arrow_back_outlined,
              iconSize: 20,
              iconColor: palette.textPrimary,
              tooltip: 'Geri',
              onTap: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 38,
            height: 38,
            child: ClipOval(
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: AppTextStyles.displayFontFamily,
                      fontFamilyFallback: AppTextStyles.fontFamilyFallback,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.0,
                    ),
                    children: [
                      TextSpan(
                        text: 'Kulva',
                        style: TextStyle(color: palette.textPrimary),
                      ),
                      TextSpan(
                        text: 'R',
                        style: TextStyle(color: coralColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontFamilyFallback: AppTextStyles.fontFamilyFallback,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...actions,
          ],
        ],
      ),
    );
  }
}
