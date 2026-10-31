import 'package:flutter/material.dart';

/// 1. Temel Yapı Taşları: Köşe Yuvarlatma Tokenları (AppRadius)
abstract final class AppRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double pill = 999.0;

  static final BorderRadius cardRadius = BorderRadius.circular(lg);
  static final BorderRadius buttonRadius = BorderRadius.circular(md);
  static final BorderRadius inputRadius = BorderRadius.circular(md);
  static final BorderRadius chipRadius = BorderRadius.circular(pill);
  static final BorderRadius smallRadius = BorderRadius.circular(sm);
}

