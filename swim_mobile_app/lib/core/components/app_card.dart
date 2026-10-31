import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Kart Görünüm Varyantları
enum AppCardVariant {
  /// Standart yüzey rengi ve 1px ince çerçeve (Varsayılan)
  surface,

  /// Yumuşak gölgeli öne çıkan kart
  elevated,

  /// Çerçevesiz, hafif ikincil arka plan rengi
  flat,

  /// Sadece belirgin çerçeveli kart
  outlined,
}

/// Katman 3: Atomik UI Bileşeni — AppCard
/// Tüm kart yapılarının tekil üretim merkezidir.
/// Sabit stil, keyfi renk ve padding tanımları barındırmaz; tokens üzerinden beslenir.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final AppCardVariant variant;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.margin = EdgeInsets.zero,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onTap,
    this.variant = AppCardVariant.surface,
  });

  /// Daha dar padding'e sahip kompakt varyant
  const AppCard.compact({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPaddingCompact,
    this.margin = EdgeInsets.zero,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onTap,
    this.variant = AppCardVariant.surface,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final effectiveRadius = borderRadius ?? AppRadius.cardRadius;

    Color bg;
    Border? border;
    List<BoxShadow>? shadows;

    switch (variant) {
      case AppCardVariant.surface:
        bg = backgroundColor ?? palette.surface;
        border = Border.all(
          color: borderColor ?? palette.border,
          width: borderWidth,
        );
        break;
      case AppCardVariant.elevated:
        bg = backgroundColor ?? palette.surfaceElevated;
        border = Border.all(
          color: borderColor ?? palette.border,
          width: borderWidth,
        );
        shadows = [
          BoxShadow(
            color: palette.textPrimary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ];
        break;
      case AppCardVariant.flat:
        bg = backgroundColor ?? palette.surfaceSecondary;
        border = null;
        break;
      case AppCardVariant.outlined:
        bg = backgroundColor ?? Colors.transparent;
        border = Border.all(
          color: borderColor ?? palette.border,
          width: borderWidth,
        );
        break;
    }

    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: effectiveRadius,
        border: border,
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) {
      return Padding(
        padding: margin,
        child: cardContent,
      );
    }

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: effectiveRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: effectiveRadius,
          child: cardContent,
        ),
      ),
    );
  }
}

