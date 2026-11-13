import 'package:flutter/material.dart';

/// Katman 1: Design Tokens — Çoklu Palet & Dinamik Tema Arayüzü (AppColorPalette)
/// Ekranlar doğrudan statik renk değerlerine bağımlı olmamalı, tema üzerinden palete erişmelidir.
abstract class AppColorPalette {
  // Arka plan ve Yüzeyler
  Color get background;
  Color get surface;
  Color get surfaceSecondary;
  Color get surfaceElevated;

  // Tipografi ve Metin Renkleri
  Color get textPrimary;
  Color get textSecondary;
  Color get textMuted;

  // Marka & Vurgu (Accent)
  Color get primary;
  Color get primaryContainer;
  Color get secondary;

  // Çerçeve & Ayırıcılar
  Color get border;
  Color get divider;

  // Durum Renkleri
  Color get statusSuccess;
  Color get statusSuccessBg;
  Color get statusWarning;
  Color get statusWarningBg;
  Color get statusDanger;
  Color get statusDangerBg;
  Color get statusLive;
  Color get statusLiveBg;

  // Spor / Başarı / Madalya Renkleri
  Color get gold;
  Color get goldBg;

  // Tema Türü
  bool get isDark;
}

/// Standart Açık Tema Renk Paleti (TYF Su Sporları — Yüksek Kontrastlı & Modern)
class LightColorPalette implements AppColorPalette {
  const LightColorPalette();

  @override
  Color get background => const Color(0xFFF8FAFC);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFF1F5F9);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF0F172A);

  @override
  Color get textSecondary => const Color(0xFF475569);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF0F4C81);

  @override
  Color get primaryContainer => const Color(0x1A0F4C81);

  @override
  Color get secondary => const Color(0xFF0D9488);

  @override
  Color get border => const Color(0xFFE2E8F0);

  @override
  Color get divider => const Color(0xFFE2E8F0);

  @override
  Color get statusSuccess => const Color(0xFF15803D);

  @override
  Color get statusSuccessBg => const Color(0x1415803D);

  @override
  Color get statusWarning => const Color(0xFFD97706);

  @override
  Color get statusWarningBg => const Color(0x1AD97706);

  @override
  Color get statusDanger => const Color(0xFFDC2626);

  @override
  Color get statusDangerBg => const Color(0x1ADC2626);

  @override
  Color get statusLive => const Color(0xFFE11D48);

  @override
  Color get statusLiveBg => const Color(0x1AE11D48);

  @override
  Color get gold => const Color(0xFFB45309);

  @override
  Color get goldBg => const Color(0x14B45309);

  @override
  bool get isDark => false;
}

/// Standart Koyu Tema Renk Paleti (Gece Modu Spor Gösterge Paneli)
class DarkColorPalette implements AppColorPalette {
  const DarkColorPalette();

  @override
  Color get background => const Color(0xFF0B1120);

  @override
  Color get surface => const Color(0xFF111827);

  @override
  Color get surfaceSecondary => const Color(0xFF1E293B);

  @override
  Color get surfaceElevated => const Color(0xFF1E293B);

  @override
  Color get textPrimary => const Color(0xFFF8FAFC);

  @override
  Color get textSecondary => const Color(0xFF94A3B8);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF38BDF8);

  @override
  Color get primaryContainer => const Color(0x2638BDF8);

  @override
  Color get secondary => const Color(0xFF2DD4BF);

  @override
  Color get border => const Color(0xFF1E293B);

  @override
  Color get divider => const Color(0xFF1E293B);

  @override
  Color get statusSuccess => const Color(0xFF4ADE80);

  @override
  Color get statusSuccessBg => const Color(0x264ADE80);

  @override
  Color get statusWarning => const Color(0xFFFBBF24);

  @override
  Color get statusWarningBg => const Color(0x26FBBF24);

  @override
  Color get statusDanger => const Color(0xFFF87171);

  @override
  Color get statusDangerBg => const Color(0x26F87171);

  @override
  Color get statusLive => const Color(0xFFFB7185);

  @override
  Color get statusLiveBg => const Color(0x26FB7185);

  @override
  Color get gold => const Color(0xFFFBBF24);

  @override
  Color get goldBg => const Color(0x26FBBF24);

  @override
  bool get isDark => true;
}

/// Material ThemeData ile entegre olabilen ThemeExtension
class AppPaletteExtension extends ThemeExtension<AppPaletteExtension> {
  final AppColorPalette palette;

  const AppPaletteExtension({required this.palette});

  @override
  ThemeExtension<AppPaletteExtension> copyWith({AppColorPalette? palette}) {
    return AppPaletteExtension(palette: palette ?? this.palette);
  }

  @override
  ThemeExtension<AppPaletteExtension> lerp(
    covariant ThemeExtension<AppPaletteExtension>? other,
    double t,
  ) {
    if (other is! AppPaletteExtension) return this;
    // Palet geçişlerinde hedefe t >= 0.5 ile geçiş
    return t < 0.5 ? this : other;
  }
}

/// Context üzerinden palete hızlı ve güvenli erişim için Extension
extension BuildContextPalette on BuildContext {
  AppColorPalette get palette {
    return Theme.of(this).extension<AppPaletteExtension>()?.palette ??
        const LightColorPalette();
  }
}

