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

/// Olimpik Havuz Paleti (Açık — Canlı Havuz Mavisi & Turkuaz)
class OlympicPoolPalette implements AppColorPalette {
  const OlympicPoolPalette();

  @override
  Color get background => const Color(0xFFEDF7FD);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFE0F2FE);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF082F49);

  @override
  Color get textSecondary => const Color(0xFF335C75);

  @override
  Color get textMuted => const Color(0xFF64869B);

  @override
  Color get primary => const Color(0xFF0284C7);

  @override
  Color get primaryContainer => const Color(0x1F0284C7);

  @override
  Color get secondary => const Color(0xFF06B6D4);

  @override
  Color get border => const Color(0xFFBAE6FD);

  @override
  Color get divider => const Color(0xFFD4EEFD);

  @override
  Color get statusSuccess => const Color(0xFF059669);

  @override
  Color get statusSuccessBg => const Color(0x18059669);

  @override
  Color get statusWarning => const Color(0xFFD97706);

  @override
  Color get statusWarningBg => const Color(0x1AD97706);

  @override
  Color get statusDanger => const Color(0xFFE11D48);

  @override
  Color get statusDangerBg => const Color(0x1AE11D48);

  @override
  Color get statusLive => const Color(0xFFE11D48);

  @override
  Color get statusLiveBg => const Color(0x1AE11D48);

  @override
  Color get gold => const Color(0xFFB45309);

  @override
  Color get goldBg => const Color(0x18B45309);

  @override
  bool get isDark => false;
}

/// Milli Takım Paleti (Açık — Ay-Yıldız Kırmızısı & Antrasit)
class NationalTeamPalette implements AppColorPalette {
  const NationalTeamPalette();

  @override
  Color get background => const Color(0xFFFBF8F8);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFF5EDED);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF18181B);

  @override
  Color get textSecondary => const Color(0xFF52525B);

  @override
  Color get textMuted => const Color(0xFF71717A);

  @override
  Color get primary => const Color(0xFFC8102E);

  @override
  Color get primaryContainer => const Color(0x1AC8102E);

  @override
  Color get secondary => const Color(0xFF1E293B);

  @override
  Color get border => const Color(0xFFEADCDC);

  @override
  Color get divider => const Color(0xFFF1E5E5);

  @override
  Color get statusSuccess => const Color(0xFF15803D);

  @override
  Color get statusSuccessBg => const Color(0x1415803D);

  @override
  Color get statusWarning => const Color(0xFFD97706);

  @override
  Color get statusWarningBg => const Color(0x1AD97706);

  @override
  Color get statusDanger => const Color(0xFFB91C1C);

  @override
  Color get statusDangerBg => const Color(0x1AB91C1C);

  @override
  Color get statusLive => const Color(0xFFDC2626);

  @override
  Color get statusLiveBg => const Color(0x1ADC2626);

  @override
  Color get gold => const Color(0xFFB45309);

  @override
  Color get goldBg => const Color(0x18B45309);

  @override
  bool get isDark => false;
}

/// Akdeniz Mercan Paleti (Açık — Sıcak Mercan & Ege Petrol Yeşili)
class MediterraneanCoralPalette implements AppColorPalette {
  const MediterraneanCoralPalette();

  @override
  Color get background => const Color(0xFFFFF9F5);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFFFEFE5);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF291B14);

  @override
  Color get textSecondary => const Color(0xFF6B4E3D);

  @override
  Color get textMuted => const Color(0xFF947463);

  @override
  Color get primary => const Color(0xFFEA580C);

  @override
  Color get primaryContainer => const Color(0x1FEA580C);

  @override
  Color get secondary => const Color(0xFF0D9488);

  @override
  Color get border => const Color(0xFFF5DEC9);

  @override
  Color get divider => const Color(0xFFF7E7D9);

  @override
  Color get statusSuccess => const Color(0xFF0F766E);

  @override
  Color get statusSuccessBg => const Color(0x160F766E);

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
  Color get goldBg => const Color(0x18B45309);

  @override
  bool get isDark => false;
}

/// Gece Arenası Paleti (Koyu — AMOLED Siyah & Neon Cyan / Yeşil)
class NightArenaNeonPalette implements AppColorPalette {
  const NightArenaNeonPalette();

  @override
  Color get background => const Color(0xFF050811);

  @override
  Color get surface => const Color(0xFF0D1324);

  @override
  Color get surfaceSecondary => const Color(0xFF151E35);

  @override
  Color get surfaceElevated => const Color(0xFF1A2542);

  @override
  Color get textPrimary => const Color(0xFFF1F5F9);

  @override
  Color get textSecondary => const Color(0xFF94A3B8);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF00E5FF);

  @override
  Color get primaryContainer => const Color(0x2400E5FF);

  @override
  Color get secondary => const Color(0xFF22C55E);

  @override
  Color get border => const Color(0xFF1E2E4A);

  @override
  Color get divider => const Color(0xFF18243D);

  @override
  Color get statusSuccess => const Color(0xFF22C55E);

  @override
  Color get statusSuccessBg => const Color(0x2622C55E);

  @override
  Color get statusWarning => const Color(0xFFFACC15);

  @override
  Color get statusWarningBg => const Color(0x26FACC15);

  @override
  Color get statusDanger => const Color(0xFFFB7185);

  @override
  Color get statusDangerBg => const Color(0x26FB7185);

  @override
  Color get statusLive => const Color(0xFFFF2E63);

  @override
  Color get statusLiveBg => const Color(0x29FF2E63);

  @override
  Color get gold => const Color(0xFFFDE047);

  @override
  Color get goldBg => const Color(0x24FDE047);

  @override
  bool get isDark => true;
}

/// Final Gecesi Paleti (Koyu — Şampiyona Laciverti & Altın)
class FinalNightGoldPalette implements AppColorPalette {
  const FinalNightGoldPalette();

  @override
  Color get background => const Color(0xFF0B1120);

  @override
  Color get surface => const Color(0xFF131C31);

  @override
  Color get surfaceSecondary => const Color(0xFF1C2845);

  @override
  Color get surfaceElevated => const Color(0xFF223052);

  @override
  Color get textPrimary => const Color(0xFFF8FAFC);

  @override
  Color get textSecondary => const Color(0xFFB0BDD4);

  @override
  Color get textMuted => const Color(0xFF7B8BA6);

  @override
  Color get primary => const Color(0xFFF59E0B);

  @override
  Color get primaryContainer => const Color(0x26F59E0B);

  @override
  Color get secondary => const Color(0xFF38BDF8);

  @override
  Color get border => const Color(0xFF263554);

  @override
  Color get divider => const Color(0xFF1E2B47);

  @override
  Color get statusSuccess => const Color(0xFF34D399);

  @override
  Color get statusSuccessBg => const Color(0x2634D399);

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
  Color get goldBg => const Color(0x28FBBF24);

  @override
  bool get isDark => true;
}

/// Cool Sophisticated — Açık Tema (Soft Glass + Ambient Glass)
/// Primary family: Ice #DCE4E8, Mist #AABBC6, Steel #657D91, Deep #273746
class CoolSophisticatedLightPalette implements AppColorPalette {
  const CoolSophisticatedLightPalette();

  @override
  Color get background => const Color(0xFFF1F4F6);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFEDF2F5);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF273746);

  @override
  Color get textSecondary => const Color(0xFF71808C);

  @override
  Color get textMuted => const Color(0xFF8E9DA8);

  @override
  Color get primary => const Color(0xFF657D91);

  @override
  Color get primaryContainer => const Color(0x1F657D91);

  @override
  Color get secondary => const Color(0xFF4A667B);

  @override
  Color get border => const Color(0xFFD8E1E6);

  @override
  Color get divider => const Color(0xFFE3EAEF);

  @override
  Color get statusSuccess => const Color(0xFF2E7D64);

  @override
  Color get statusSuccessBg => const Color(0x172E7D64);

  @override
  Color get statusWarning => const Color(0xFFB3742B);

  @override
  Color get statusWarningBg => const Color(0x1AB3742B);

  @override
  Color get statusDanger => const Color(0xFFB94A53);

  @override
  Color get statusDangerBg => const Color(0x17B94A53);

  @override
  Color get statusLive => const Color(0xFFC24B57);

  @override
  Color get statusLiveBg => const Color(0x18C24B57);

  @override
  Color get gold => const Color(0xFFA57B36);

  @override
  Color get goldBg => const Color(0x18A57B36);

  @override
  bool get isDark => false;
}

/// Cool Sophisticated — Koyu Tema (Soft Glass + Ambient Glass)
/// Deep atmospheric slate surfaces with Ice/Mist accents & luminous hairlines.
class CoolSophisticatedDarkPalette implements AppColorPalette {
  const CoolSophisticatedDarkPalette();

  @override
  Color get background => const Color(0xFF17232D);

  @override
  Color get surface => const Color(0xFF202F3B);

  @override
  Color get surfaceSecondary => const Color(0xFF273746);

  @override
  Color get surfaceElevated => const Color(0xFF2B3D4E);

  @override
  Color get textPrimary => const Color(0xFFE7EDF1);

  @override
  Color get textSecondary => const Color(0xFFAABBC6);

  @override
  Color get textMuted => const Color(0xFF7B90A0);

  @override
  Color get primary => const Color(0xFFAABBC6);

  @override
  Color get primaryContainer => const Color(0x26AABBC6);

  @override
  Color get secondary => const Color(0xFF7FA0B5);

  @override
  Color get border => const Color(0x1FE7EDF1);

  @override
  Color get divider => const Color(0x16E7EDF1);

  @override
  Color get statusSuccess => const Color(0xFF6BC2A4);

  @override
  Color get statusSuccessBg => const Color(0x246BC2A4);

  @override
  Color get statusWarning => const Color(0xFFE0AE62);

  @override
  Color get statusWarningBg => const Color(0x24E0AE62);

  @override
  Color get statusDanger => const Color(0xFFE07A82);

  @override
  Color get statusDangerBg => const Color(0x24E07A82);

  @override
  Color get statusLive => const Color(0xFFE5737D);

  @override
  Color get statusLiveBg => const Color(0x24E5737D);

  @override
  Color get gold => const Color(0xFFDFBD73);

  @override
  Color get goldBg => const Color(0x24DFBD73);

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

/// Soft Glass + Ambient Glass anlamsal yüzey ve atmosfer belirteçleri
extension AppColorPaletteGlass on AppColorPalette {
  /// Yarı saydam ana cam yüzey (Hero kartlar, öne çıkan paneller)
  Color get surfaceGlass => isDark
      ? surface.withValues(alpha: 0.72)
      : surface.withValues(alpha: 0.74);

  /// Daha yoğun cam yüzey (Navigasyon çubuğu, Modal / BottomSheet)
  Color get surfaceGlassStrong => isDark
      ? surface.withValues(alpha: 0.86)
      : surface.withValues(alpha: 0.86);

  /// İnce, parlak cam kenarlığı
  Color get glassBorder => isDark
      ? const Color(0x2BE7EDF1)
      : Colors.white.withValues(alpha: 0.88);

  /// Cam panellerin üst-sol yumuşak ışık yansıması
  Color get glassSheen => isDark
      ? const Color(0x16E7EDF1)
      : Colors.white.withValues(alpha: 0.55);

  /// Arka plan atmosferik ışık alanı 1 (Ice / Steel)
  Color get ambientPrimary => isDark
      ? primary.withValues(alpha: 0.14)
      : const Color(0x66DCE4E8);

  /// Arka plan atmosferik ışık alanı 2 (Mist / Secondary)
  Color get ambientSecondary => isDark
      ? secondary.withValues(alpha: 0.11)
      : primary.withValues(alpha: 0.11);

  /// Soyut vektör çizim (Flow Lines / Orbital Arcs / Contour) çizgi rengi
  Color get vectorStroke => isDark
      ? textPrimary.withValues(alpha: 0.11)
      : primary.withValues(alpha: 0.14);

  /// Yumuşak, zarif derinlik gölgesi
  Color get softShadow => isDark
      ? Colors.black.withValues(alpha: 0.28)
      : const Color(0xFF273746).withValues(alpha: 0.06);
}

/// Context üzerinden palete hızlı ve güvenli erişim için Extension
extension BuildContextPalette on BuildContext {
  AppColorPalette get palette {
    return Theme.of(this).extension<AppPaletteExtension>()?.palette ??
        const CoolSophisticatedLightPalette();
  }
}

