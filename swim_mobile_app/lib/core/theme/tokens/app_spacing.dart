import 'package:flutter/material.dart';

/// Katman 1: Design Tokens — Boşluk Sabitleri (AppSpacing)
/// Ekranlarda keyfi `SizedBox(height: 16)` veya rastgele padding yazımı kesinlikle yasaktır.
abstract final class AppSpacing {
  // Temel boşluk birimleri
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Dikey Boşluk SizedBox Sabitleri (performans ve temiz kod için const)
  static const SizedBox vXs = SizedBox(height: xs);
  static const SizedBox vSm = SizedBox(height: sm);
  static const SizedBox vMd = SizedBox(height: md);
  static const SizedBox vLg = SizedBox(height: lg);
  static const SizedBox vXl = SizedBox(height: xl);
  static const SizedBox vXxl = SizedBox(height: xxl);

  // Yatay Boşluk SizedBox Sabitleri
  static const SizedBox hXs = SizedBox(width: xs);
  static const SizedBox hSm = SizedBox(width: sm);
  static const SizedBox hMd = SizedBox(width: md);
  static const SizedBox hLg = SizedBox(width: lg);
  static const SizedBox hXl = SizedBox(width: xl);
  static const SizedBox hXxl = SizedBox(width: xxl);

  // Standart Padding / Kenar Boşlukları
  static const EdgeInsets zero = EdgeInsets.zero;
  static const EdgeInsets paddingAllXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingAllSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingAllMd = EdgeInsets.all(md);
  static const EdgeInsets paddingAllLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingAllXl = EdgeInsets.all(xl);

  static const EdgeInsets paddingHorizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets paddingVerticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(vertical: lg);

  // Kompozit Düzen Paddingleri
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPaddingCompact = EdgeInsets.all(sm);
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: md, vertical: lg);
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(md, sm, md, 96.0);
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: lg, vertical: sm);
}

