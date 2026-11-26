import 'package:flutter/material.dart';

/// Ekran genişliğine göre uyarlanabilir düzen kırılım noktaları.
enum ScreenSizeClass {
  compact, // < 600px (Telefon)
  medium, // 600px - 1023px (Tablet dikey / küçük tablet)
  expanded, // >= 1024px (Tablet yatay / masaüstü)
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  ScreenSizeClass get screenSizeClass {
    final w = screenWidth;
    if (w >= 1024) return ScreenSizeClass.expanded;
    if (w >= 600) return ScreenSizeClass.medium;
    return ScreenSizeClass.compact;
  }

  /// Tablet veya daha geniş ekran (>= 600px)
  bool get isWide => screenWidth >= 600;

  /// Yatay tablet / geniş ekran (>= 840px)
  bool get isMasterDetail => screenWidth >= 840;

  /// Geniş masaüstü / büyük tablet (>= 1024px)
  bool get isExpanded => screenWidth >= 1024;
}

/// Geniş ekranlarda içeriği ortalayıp maksimum genişlikle sınırlar.
/// Mobil (< 600px) ekranlarda sıfır ek yük ile doğrudan [child] döndürür.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 960,
  });

  @override
  Widget build(BuildContext context) {
    if (!context.isWide) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
