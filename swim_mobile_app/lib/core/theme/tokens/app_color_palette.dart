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

/// Standart Açık Tema Renk Paleti (TYF Yüzme Minimalist & Zarif Stil)
class LightColorPalette implements AppColorPalette {
  const LightColorPalette();

  @override
  Color get background => const Color(0xFFFAF8F7);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFF5F0EE);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF3D3038);

  @override
  Color get textSecondary => const Color(0xFF81777D);

  @override
  Color get textMuted => const Color(0xFFB3A8AE);

  @override
  Color get primary => const Color(0xFFBC8C91);

  @override
  Color get primaryContainer => const Color(0x1FBC8C91);

  @override
  Color get secondary => const Color(0xFF7D6B7D);

  @override
  Color get border => const Color(0xFFEFE9E7);

  @override
  Color get divider => const Color(0xFFEFE9E7);

  @override
  Color get statusSuccess => const Color(0xFF4A7C59);

  @override
  Color get statusSuccessBg => const Color(0x144A7C59);

  @override
  Color get statusWarning => const Color(0xFFD97706);

  @override
  Color get statusWarningBg => const Color(0x1AD97706);

  @override
  Color get statusDanger => const Color(0xFFDC2626);

  @override
  Color get statusDangerBg => const Color(0x1ADC2626);

  @override
  Color get statusLive => const Color(0xFFBC8C91);

  @override
  Color get statusLiveBg => const Color(0x1FBC8C91);

  @override
  Color get gold => const Color(0xFFB8860B);

  @override
  Color get goldBg => const Color(0x14B8860B);

  @override
  bool get isDark => false;
}

/// Standart Koyu Tema Renk Paleti (Gece Modu Spor Gösterge Paneli)
class DarkColorPalette implements AppColorPalette {
  const DarkColorPalette();

  @override
  Color get background => const Color(0xFF141214);

  @override
  Color get surface => const Color(0xFF1F1C1E);

  @override
  Color get surfaceSecondary => const Color(0xFF2B272A);

  @override
  Color get surfaceElevated => const Color(0xFF262325);

  @override
  Color get textPrimary => const Color(0xFFF5F0EE);

  @override
  Color get textSecondary => const Color(0xFFA89CA3);

  @override
  Color get textMuted => const Color(0xFF6B6167);

  @override
  Color get primary => const Color(0xFFD4A3A8);

  @override
  Color get primaryContainer => const Color(0x33D4A3A8);

  @override
  Color get secondary => const Color(0xFFA592A5);

  @override
  Color get border => const Color(0xFF2E292C);

  @override
  Color get divider => const Color(0xFF2E292C);

  @override
  Color get statusSuccess => const Color(0xFF68A67B);

  @override
  Color get statusSuccessBg => const Color(0x2668A67B);

  @override
  Color get statusWarning => const Color(0xFFF59E0B);

  @override
  Color get statusWarningBg => const Color(0x26F59E0B);

  @override
  Color get statusDanger => const Color(0xFFEF4444);

  @override
  Color get statusDangerBg => const Color(0x26EF4444);

  @override
  Color get statusLive => const Color(0xFFE8B4B8);

  @override
  Color get statusLiveBg => const Color(0x33E8B4B8);

  @override
  Color get gold => const Color(0xFFE5A93C);

  @override
  Color get goldBg => const Color(0x26E5A93C);

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

