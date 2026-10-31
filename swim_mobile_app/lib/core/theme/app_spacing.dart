import 'package:flutter/material.dart';

/// 1. Temel Yapı Taşları: Boşluk Tokenları (AppSpacing)
abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: lg,
  );

  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(md, sm, md, 96.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(horizontal: md);
}

