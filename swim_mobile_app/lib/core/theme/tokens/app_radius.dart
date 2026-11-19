import 'package:flutter/material.dart';

/// Katman 1: Design Tokens — Köşe Yuvarlatma Sabitleri (AppRadius)
/// Ekranlarda keyfi `BorderRadius.circular(12)` tanımları kesinlikle yasaktır.
abstract final class AppRadius {
  // Temel yarıçap değerleri (4-point design system + Soft Glass)
  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 14.0;
  static const double r16Val = 16.0;
  static const double lg = 20.0;
  static const double xl = 26.0;
  static const double r28Val = 28.0;
  static const double pill = 999.0;

  // Radius Sabitleri
  static const Radius rXs = Radius.circular(xs);
  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius r16 = Radius.circular(r16Val);
  static const Radius rLg = Radius.circular(lg);
  static const Radius rXl = Radius.circular(xl);
  static const Radius r28 = Radius.circular(r28Val);
  static const Radius rPill = Radius.circular(pill);

  // Standart BorderRadius Sabitleri
  static const BorderRadius zero = BorderRadius.zero;
  static const BorderRadius small = BorderRadius.all(rSm);
  static const BorderRadius medium = BorderRadius.all(rMd);
  static const BorderRadius radius16 = BorderRadius.all(r16);
  static const BorderRadius large = BorderRadius.all(rLg);
  static const BorderRadius rounded = BorderRadius.all(rXl);
  static const BorderRadius radius28 = BorderRadius.all(r28);
  static const BorderRadius full = BorderRadius.all(rPill);

  // Anlamsal Bileşen Radiusları
  static const BorderRadius cardRadius = large;
  static const BorderRadius buttonRadius = medium;
  static const BorderRadius inputRadius = medium;
  static const BorderRadius chipRadius = full;
  static const BorderRadius badgeRadius = small;
  static const BorderRadius sheetRadius = BorderRadius.vertical(top: rXl);
  static const BorderRadius smallRadius = small;
}

