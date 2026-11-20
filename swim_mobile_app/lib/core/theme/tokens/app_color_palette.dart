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
  Color get textTertiary;
  Color get textMuted;

  // Marka & Vurgu (Accent)
  Color get primary;
  Color get accent;
  Color get primaryContainer;
  Color get secondary;
  Color get glowLight;

  // Çerçeve & Ayırıcılar
  Color get border;
  Color get divider;

  // Durum Renkleri
  Color get statusSuccess;
  Color get successText;
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

  // Ambient Arka Plan, Yüzen Navigasyon & Gölge Renkleri
  Color get ambientTop;
  Color get ambientMid;
  Color get ambientBottom;
  Color get ambientFieldA;
  Color get ambientFieldB;
  Color get ambientFieldC;
  Color get navFill;
  Color get navLabelActive;
  Color get navLabelInactive;
  Color get shadowTint;

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
  Color get textTertiary => const Color(0xFF334155);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF0F4C81);

  @override
  Color get accent => const Color(0xFF0F4C81);

  @override
  Color get primaryContainer => const Color(0x1A0F4C81);

  @override
  Color get secondary => const Color(0xFF0D9488);

  @override
  Color get glowLight => const Color(0xFFF0F6FA);

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
  Color get ambientTop => const Color(0xFFE4ECF4);

  @override
  Color get ambientMid => const Color(0xFFC8D7E6);

  @override
  Color get ambientBottom => const Color(0xFFA8C0D6);

  @override
  Color get ambientFieldA => const Color(0xFFF0F6FA).withValues(alpha: 0.75);

  @override
  Color get ambientFieldB => const Color(0xFF0F4C81).withValues(alpha: 0.24);

  @override
  Color get ambientFieldC => const Color(0xFF0F172A).withValues(alpha: 0.20);

  @override
  Color get navFill => const Color(0xFF0F2D4A).withValues(alpha: 0.42);

  @override
  Color get navLabelActive => const Color(0xFFF1F5F9);

  @override
  Color get navLabelInactive => const Color(0xFFCBD5E1);

  @override
  Color get shadowTint => const Color(0xFF0F172A);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF146335);
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
  Color get textSecondary => const Color(0xFFB0C0D0);

  @override
  Color get textTertiary => const Color(0xFFCBD5E1);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF38BDF8);

  @override
  Color get accent => const Color(0xFF38BDF8);

  @override
  Color get primaryContainer => const Color(0x2638BDF8);

  @override
  Color get secondary => const Color(0xFF2DD4BF);

  @override
  Color get glowLight => const Color(0xFFE0F2FE);

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
  Color get ambientTop => const Color(0xFF111C2E);

  @override
  Color get ambientMid => const Color(0xFF0C1524);

  @override
  Color get ambientBottom => const Color(0xFF080E1A);

  @override
  Color get ambientFieldA => const Color(0xFF38BDF8).withValues(alpha: 0.30);

  @override
  Color get ambientFieldB => const Color(0xFF2DD4BF).withValues(alpha: 0.12);

  @override
  Color get ambientFieldC => const Color(0xFF050A12).withValues(alpha: 0.42);

  @override
  Color get navFill => Colors.white.withValues(alpha: 0.08);

  @override
  Color get navLabelActive => const Color(0xFFF8FAFC);

  @override
  Color get navLabelInactive => const Color(0xFF94A3B8);

  @override
  Color get shadowTint => const Color(0xFF050A12);

  @override
  bool get isDark => true;

  @override
  Color get successText => const Color(0xFF4ADE80);
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
  Color get textTertiary => const Color(0xFF1E4966);

  @override
  Color get textMuted => const Color(0xFF64869B);

  @override
  Color get primary => const Color(0xFF0284C7);

  @override
  Color get accent => const Color(0xFF0284C7);

  @override
  Color get primaryContainer => const Color(0x1F0284C7);

  @override
  Color get secondary => const Color(0xFF06B6D4);

  @override
  Color get glowLight => const Color(0xFFE0F2FE);

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
  Color get ambientTop => const Color(0xFFD4EEF9);

  @override
  Color get ambientMid => const Color(0xFFB0DCF0);

  @override
  Color get ambientBottom => const Color(0xFF88C4E0);

  @override
  Color get ambientFieldA => const Color(0xFFF0FAFF).withValues(alpha: 0.78);

  @override
  Color get ambientFieldB => const Color(0xFF0284C7).withValues(alpha: 0.26);

  @override
  Color get ambientFieldC => const Color(0xFF082F49).withValues(alpha: 0.22);

  @override
  Color get navFill => const Color(0xFF082F49).withValues(alpha: 0.42);

  @override
  Color get navLabelActive => const Color(0xFFE0F2FE);

  @override
  Color get navLabelInactive => const Color(0xFFBAE6FD);

  @override
  Color get shadowTint => const Color(0xFF082F49);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF06694B);
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
  Color get textTertiary => const Color(0xFF3F3F46);

  @override
  Color get textMuted => const Color(0xFF71717A);

  @override
  Color get primary => const Color(0xFFC8102E);

  @override
  Color get accent => const Color(0xFFC8102E);

  @override
  Color get primaryContainer => const Color(0x1AC8102E);

  @override
  Color get secondary => const Color(0xFF1E293B);

  @override
  Color get glowLight => const Color(0xFFFDF2F4);

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
  Color get ambientTop => const Color(0xFFEDE2E3);

  @override
  Color get ambientMid => const Color(0xFFDDCACD);

  @override
  Color get ambientBottom => const Color(0xFFC5AEB2);

  @override
  Color get ambientFieldA => const Color(0xFFFDF5F6).withValues(alpha: 0.78);

  @override
  Color get ambientFieldB => const Color(0xFFC8102E).withValues(alpha: 0.20);

  @override
  Color get ambientFieldC => const Color(0xFF1E293B).withValues(alpha: 0.24);

  @override
  Color get navFill => const Color(0xFF2B1B20).withValues(alpha: 0.42);

  @override
  Color get navLabelActive => const Color(0xFFFAF5F5);

  @override
  Color get navLabelInactive => const Color(0xFFD6C7CA);

  @override
  Color get shadowTint => const Color(0xFF18181B);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF146335);
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
  Color get textTertiary => const Color(0xFF4E372A);

  @override
  Color get textMuted => const Color(0xFF947463);

  @override
  Color get primary => const Color(0xFFEA580C);

  @override
  Color get accent => const Color(0xFFEA580C);

  @override
  Color get primaryContainer => const Color(0x1FEA580C);

  @override
  Color get secondary => const Color(0xFF0D9488);

  @override
  Color get glowLight => const Color(0xFFFFF3EB);

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
  Color get ambientTop => const Color(0xFFF2E2D7);

  @override
  Color get ambientMid => const Color(0xFFE3C8B8);

  @override
  Color get ambientBottom => const Color(0xFFCDA894);

  @override
  Color get ambientFieldA => const Color(0xFFFFF8F2).withValues(alpha: 0.78);

  @override
  Color get ambientFieldB => const Color(0xFFEA580C).withValues(alpha: 0.20);

  @override
  Color get ambientFieldC => const Color(0xFF0D9488).withValues(alpha: 0.22);

  @override
  Color get navFill => const Color(0xFF332118).withValues(alpha: 0.42);

  @override
  Color get navLabelActive => const Color(0xFFFFF5EE);

  @override
  Color get navLabelInactive => const Color(0xFFE0CFC4);

  @override
  Color get shadowTint => const Color(0xFF291B14);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF0E5E58);
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
  Color get textSecondary => const Color(0xFFB0C0D0);

  @override
  Color get textTertiary => const Color(0xFFCBD5E1);

  @override
  Color get textMuted => const Color(0xFF64748B);

  @override
  Color get primary => const Color(0xFF00E5FF);

  @override
  Color get accent => const Color(0xFF00E5FF);

  @override
  Color get primaryContainer => const Color(0x2400E5FF);

  @override
  Color get secondary => const Color(0xFF22C55E);

  @override
  Color get glowLight => const Color(0xFFE0FCFF);

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
  Color get ambientTop => const Color(0xFF0B1326);

  @override
  Color get ambientMid => const Color(0xFF070D1B);

  @override
  Color get ambientBottom => const Color(0xFF040710);

  @override
  Color get ambientFieldA => const Color(0xFF00E5FF).withValues(alpha: 0.30);

  @override
  Color get ambientFieldB => const Color(0xFF22C55E).withValues(alpha: 0.14);

  @override
  Color get ambientFieldC => const Color(0xFF02040A).withValues(alpha: 0.45);

  @override
  Color get navFill => Colors.white.withValues(alpha: 0.08);

  @override
  Color get navLabelActive => const Color(0xFFF1F5F9);

  @override
  Color get navLabelInactive => const Color(0xFF94A3B8);

  @override
  Color get shadowTint => const Color(0xFF02040A);

  @override
  bool get isDark => true;

  @override
  Color get successText => const Color(0xFF22C55E);
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
  Color get textSecondary => const Color(0xFFB8C7D8);

  @override
  Color get textTertiary => const Color(0xFFDCE4F0);

  @override
  Color get textMuted => const Color(0xFF7B8BA6);

  @override
  Color get primary => const Color(0xFFF59E0B);

  @override
  Color get accent => const Color(0xFFF59E0B);

  @override
  Color get primaryContainer => const Color(0x26F59E0B);

  @override
  Color get secondary => const Color(0xFF38BDF8);

  @override
  Color get glowLight => const Color(0xFFFEF3C7);

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
  Color get ambientTop => const Color(0xFF131D34);

  @override
  Color get ambientMid => const Color(0xFF0D1528);

  @override
  Color get ambientBottom => const Color(0xFF080E1C);

  @override
  Color get ambientFieldA => const Color(0xFFF59E0B).withValues(alpha: 0.30);

  @override
  Color get ambientFieldB => const Color(0xFF38BDF8).withValues(alpha: 0.14);

  @override
  Color get ambientFieldC => const Color(0xFF040812).withValues(alpha: 0.45);

  @override
  Color get navFill => Colors.white.withValues(alpha: 0.08);

  @override
  Color get navLabelActive => const Color(0xFFF8FAFC);

  @override
  Color get navLabelInactive => const Color(0xFFB0BDD4);

  @override
  Color get shadowTint => const Color(0xFF040812);

  @override
  bool get isDark => true;

  @override
  Color get successText => const Color(0xFF34D399);
}

/// Cool Sophisticated — Açık Tema (Soft Glass + Ambient Glass)
/// Primary family: Ice #DCE4E8, Mist #AABBC6, Steel #657D91, Deep #273746
class CoolSophisticatedLightPalette implements AppColorPalette {
  const CoolSophisticatedLightPalette();

  @override
  Color get background => const Color(0xFFF4F7FA);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFEBF1F6);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF182433);

  @override
  Color get textSecondary => const Color(0xFF6E7F91);

  @override
  Color get textTertiary => const Color(0xFF3E566A);

  @override
  Color get textMuted => const Color(0xFF8FA3B8);

  @override
  Color get primary => const Color(0xFF007AFF);

  @override
  Color get accent => const Color(0xFF007AFF);

  @override
  Color get primaryContainer => const Color(0xFFE5F1FF);

  @override
  Color get secondary => const Color(0xFF0B192C);

  @override
  Color get glowLight => const Color(0xFFFFFFFF);

  @override
  Color get border => const Color(0xFFE1E8EF);

  @override
  Color get divider => const Color(0xFFEDF2F7);

  @override
  Color get statusSuccess => const Color(0xFF10B981);

  @override
  Color get statusSuccessBg => const Color(0xFFECFDF5);

  @override
  Color get statusWarning => const Color(0xFFF59E0B);

  @override
  Color get statusWarningBg => const Color(0xFFFFFBEB);

  @override
  Color get statusDanger => const Color(0xFFEF4444);

  @override
  Color get statusDangerBg => const Color(0xFFFEF2F2);

  @override
  Color get statusLive => const Color(0xFFEF4444);

  @override
  Color get statusLiveBg => const Color(0xFFFEF2F2);

  @override
  Color get gold => const Color(0xFFF59E0B);

  @override
  Color get goldBg => const Color(0xFFFFFBEB);

  @override
  Color get ambientTop => const Color(0xFFF4F7FA);

  @override
  Color get ambientMid => const Color(0xFFF0F5FA);

  @override
  Color get ambientBottom => const Color(0xFFEBF1F6);

  @override
  Color get ambientFieldA => const Color(0xFFFFFFFF).withValues(alpha: 0.90);

  @override
  Color get ambientFieldB => const Color(0xFF007AFF).withValues(alpha: 0.05);

  @override
  Color get ambientFieldC => const Color(0xFF0B192C).withValues(alpha: 0.03);

  @override
  Color get navFill => const Color(0xFFFFFFFF);

  @override
  Color get navLabelActive => const Color(0xFF007AFF);

  @override
  Color get navLabelInactive => const Color(0xFF6E7F91);

  @override
  Color get shadowTint => const Color(0xFF0B192C);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF059669);
}

/// Cool Horizon — Koyu Tema (Crisp Athletic Glass + Focal Contrast)
/// Deep navy surfaces (#0D1520 / #152232) with Vibrant Pool Azure (#2997FF) accents.
class CoolSophisticatedDarkPalette implements AppColorPalette {
  const CoolSophisticatedDarkPalette();

  @override
  Color get background => const Color(0xFF0D1520);

  @override
  Color get surface => const Color(0xFF152232);

  @override
  Color get surfaceSecondary => const Color(0xFF1D2D42);

  @override
  Color get surfaceElevated => const Color(0xFF1E3552);

  @override
  Color get textPrimary => const Color(0xFFF0F4F8);

  @override
  Color get textSecondary => const Color(0xFF8FA3B8);

  @override
  Color get textTertiary => const Color(0xFFDCE4E8);

  @override
  Color get textMuted => const Color(0xFF6E7F91);

  @override
  Color get primary => const Color(0xFF2997FF);

  @override
  Color get accent => const Color(0xFF2997FF);

  @override
  Color get primaryContainer => const Color(0x292997FF);

  @override
  Color get secondary => const Color(0xFF06B6D4);

  @override
  Color get glowLight => const Color(0xFFEEF3F6);

  @override
  Color get border => const Color(0x14FFFFFF);

  @override
  Color get divider => const Color(0x0FFFFFFF);

  @override
  Color get statusSuccess => const Color(0xFF10B981);

  @override
  Color get statusSuccessBg => const Color(0x2410B981);

  @override
  Color get statusWarning => const Color(0xFFF59E0B);

  @override
  Color get statusWarningBg => const Color(0x24F59E0B);

  @override
  Color get statusDanger => const Color(0xFFEF4444);

  @override
  Color get statusDangerBg => const Color(0x24EF4444);

  @override
  Color get statusLive => const Color(0xFFEF4444);

  @override
  Color get statusLiveBg => const Color(0x24EF4444);

  @override
  Color get gold => const Color(0xFFF59E0B);

  @override
  Color get goldBg => const Color(0x24F59E0B);

  @override
  Color get ambientTop => const Color(0xFF0D1520);

  @override
  Color get ambientMid => const Color(0xFF0B131D);

  @override
  Color get ambientBottom => const Color(0xFF091019);

  @override
  Color get ambientFieldA => const Color(0xFF2997FF).withValues(alpha: 0.10);

  @override
  Color get ambientFieldB => const Color(0xFF1E3552).withValues(alpha: 0.25);

  @override
  Color get ambientFieldC => const Color(0xFF070D14).withValues(alpha: 0.45);

  @override
  Color get navFill => const Color(0xFF152232);

  @override
  Color get navLabelActive => const Color(0xFF2997FF);

  @override
  Color get navLabelInactive => const Color(0xFF8FA3B8);

  @override
  Color get shadowTint => const Color(0xFF070D14);

  @override
  bool get isDark => true;

  @override
  Color get successText => const Color(0xFF10B981);
}

/// shadcn/ui Zinc — Açık Tema (Yüksek kontrast, net 1px kenarlık, minimal gölge)
class ShadcnLightPalette implements AppColorPalette {
  const ShadcnLightPalette();

  @override
  Color get background => const Color(0xFFFFFFFF);

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceSecondary => const Color(0xFFF4F4F5);

  @override
  Color get surfaceElevated => const Color(0xFFFFFFFF);

  @override
  Color get textPrimary => const Color(0xFF09090B);

  @override
  Color get textSecondary => const Color(0xFF71717A);

  @override
  Color get textTertiary => const Color(0xFF3F3F46);

  @override
  Color get textMuted => const Color(0xFFA1A1AA);

  @override
  Color get primary => const Color(0xFF18181B);

  @override
  Color get accent => const Color(0xFF18181B);

  @override
  Color get primaryContainer => const Color(0xFFF4F4F5);

  @override
  Color get secondary => const Color(0xFF2563EB);

  @override
  Color get glowLight => const Color(0xFFFFFFFF);

  @override
  Color get border => const Color(0xFFE4E4E7);

  @override
  Color get divider => const Color(0xFFE4E4E7);

  @override
  Color get statusSuccess => const Color(0xFF16A34A);

  @override
  Color get statusSuccessBg => const Color(0xFFDCFCE7);

  @override
  Color get statusWarning => const Color(0xFFD97706);

  @override
  Color get statusWarningBg => const Color(0xFFFEF3C7);

  @override
  Color get statusDanger => const Color(0xFFDC2626);

  @override
  Color get statusDangerBg => const Color(0xFFFEE2E2);

  @override
  Color get statusLive => const Color(0xFFDC2626);

  @override
  Color get statusLiveBg => const Color(0xFFFEE2E2);

  @override
  Color get gold => const Color(0xFFD97706);

  @override
  Color get goldBg => const Color(0xFFFEF3C7);

  @override
  Color get ambientTop => const Color(0xFFFFFFFF);

  @override
  Color get ambientMid => const Color(0xFFFFFFFF);

  @override
  Color get ambientBottom => const Color(0xFFFFFFFF);

  @override
  Color get ambientFieldA => Colors.transparent;

  @override
  Color get ambientFieldB => Colors.transparent;

  @override
  Color get ambientFieldC => Colors.transparent;

  @override
  Color get navFill => const Color(0xFFFFFFFF);

  @override
  Color get navLabelActive => const Color(0xFF09090B);

  @override
  Color get navLabelInactive => const Color(0xFF71717A);

  @override
  Color get shadowTint => const Color(0xFF09090B);

  @override
  bool get isDark => false;

  @override
  Color get successText => const Color(0xFF15803D);
}

/// shadcn/ui Zinc — Koyu Tema (Derin #09090B zemin, net #27272A kenarlık)
class ShadcnDarkPalette implements AppColorPalette {
  const ShadcnDarkPalette();

  @override
  Color get background => const Color(0xFF09090B);

  @override
  Color get surface => const Color(0xFF111113);

  @override
  Color get surfaceSecondary => const Color(0xFF18181B);

  @override
  Color get surfaceElevated => const Color(0xFF18181B);

  @override
  Color get textPrimary => const Color(0xFFFAFAFA);

  @override
  Color get textSecondary => const Color(0xFFA1A1AA);

  @override
  Color get textTertiary => const Color(0xFFD4D4D8);

  @override
  Color get textMuted => const Color(0xFF71717A);

  @override
  Color get primary => const Color(0xFFFAFAFA);

  @override
  Color get accent => const Color(0xFFFAFAFA);

  @override
  Color get primaryContainer => const Color(0xFF27272A);

  @override
  Color get secondary => const Color(0xFF3B82F6);

  @override
  Color get glowLight => const Color(0xFF18181B);

  @override
  Color get border => const Color(0xFF27272A);

  @override
  Color get divider => const Color(0xFF27272A);

  @override
  Color get statusSuccess => const Color(0xFF22C55E);

  @override
  Color get statusSuccessBg => const Color(0x2622C55E);

  @override
  Color get statusWarning => const Color(0xFFF59E0B);

  @override
  Color get statusWarningBg => const Color(0x26F59E0B);

  @override
  Color get statusDanger => const Color(0xFFEF4444);

  @override
  Color get statusDangerBg => const Color(0x26EF4444);

  @override
  Color get statusLive => const Color(0xFFEF4444);

  @override
  Color get statusLiveBg => const Color(0x26EF4444);

  @override
  Color get gold => const Color(0xFFF59E0B);

  @override
  Color get goldBg => const Color(0x26F59E0B);

  @override
  Color get ambientTop => const Color(0xFF09090B);

  @override
  Color get ambientMid => const Color(0xFF09090B);

  @override
  Color get ambientBottom => const Color(0xFF09090B);

  @override
  Color get ambientFieldA => Colors.transparent;

  @override
  Color get ambientFieldB => Colors.transparent;

  @override
  Color get ambientFieldC => Colors.transparent;

  @override
  Color get navFill => const Color(0xFF09090B);

  @override
  Color get navLabelActive => const Color(0xFFFAFAFA);

  @override
  Color get navLabelInactive => const Color(0xFFA1A1AA);

  @override
  Color get shadowTint => const Color(0xFF000000);

  @override
  bool get isDark => true;

  @override
  Color get successText => const Color(0xFF22C55E);
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
/// 3 katmanlı mimari: Layer 1 (Ambient ortam) → Layer 2 (Frosted cam) → Layer 3 (İçerik)
extension AppColorPaletteGlass on AppColorPalette {
  bool get _isCoolLight => this is CoolSophisticatedLightPalette;
  bool get _isCoolDark => this is CoolSophisticatedDarkPalette;
  bool get isCoolHorizon => _isCoolLight || _isCoolDark;
  bool get isShadcn => this is ShadcnLightPalette || this is ShadcnDarkPalette;
  bool get isCrispCardTheme => isCoolHorizon || isShadcn;

  /// Kontrast odak kartı yüzeyi
  Color get surfaceContrast {
    if (isShadcn) return const Color(0xFF18181B);
    if (_isCoolLight) return const Color(0xFF0B192C);
    if (_isCoolDark) return const Color(0xFF1E3552);
    return isDark ? surfaceElevated : const Color(0xFF0B192C);
  }

  /// Kontrast odak kartı üzerindeki metin rengi
  Color get textOnContrast {
    if (isShadcn) return const Color(0xFFFAFAFA);
    if (_isCoolLight) return const Color(0xFFF4F7FA);
    if (_isCoolDark) return Colors.white;
    return Colors.white;
  }

  /// Yumuşak vurgu dolgusu
  Color get accentSoft {
    if (isShadcn) return surfaceSecondary;
    if (_isCoolLight) return const Color(0xFFE5F1FF);
    if (_isCoolDark) return const Color(0x292997FF);
    return accent.withValues(alpha: isDark ? 0.16 : 0.12);
  }

  Color get infoCyan => const Color(0xFF06B6D4);

  Color get infoCyanBg =>
      isDark ? const Color(0x2406B6D4) : const Color(0xFFECFEFF);

  // --- Layer 1: Ambient Arka Plan Katmanı ---

  /// Atmosferik arka plan üst tonu
  Color get ambientBaseStart {
    if (_isCoolLight) return const Color(0xFFF4F7FA);
    if (_isCoolDark) return const Color(0xFF0D1520);
    return isDark
        ? Color.lerp(background, const Color(0xFF223342), 0.25)!
        : Color.lerp(background, primary, 0.14)!;
  }

  /// Atmosferik arka plan orta tonu
  Color get ambientBaseMid {
    if (_isCoolLight) return const Color(0xFFF0F5FA);
    if (_isCoolDark) return const Color(0xFF0B131D);
    return isDark ? background : Color.lerp(background, primary, 0.22)!;
  }

  /// Atmosferik arka plan alt tonu
  Color get ambientBaseEnd {
    if (_isCoolLight) return const Color(0xFFEBF1F6);
    if (_isCoolDark) return const Color(0xFF091019);
    return isDark
        ? Color.lerp(background, Colors.black, 0.28)!
        : Color.lerp(background, secondary, 0.30)!;
  }

  /// Büyük organik atmosferik ışık alanı 1 (Üst-sağ: Mist / Steel difüzyonu)
  Color get ambientPrimary {
    if (_isCoolLight) return const Color(0x998EA6B7);
    if (_isCoolDark) return const Color(0x52657D91);
    return isDark
        ? primary.withValues(alpha: 0.24)
        : primary.withValues(alpha: 0.22);
  }

  /// Büyük organik atmosferik ışık alanı 2 (Orta-sol: Yumuşak Steel renk alanı)
  Color get ambientSecondary {
    if (_isCoolLight) return const Color(0x66657D91);
    if (_isCoolDark) return const Color(0x3DAABBC6);
    return isDark
        ? secondary.withValues(alpha: 0.20)
        : secondary.withValues(alpha: 0.19);
  }

  /// Alt atmosferik ışık alanı 3 (Alt-sağ: Yumuşak Mist & derinlik)
  Color get ambientTertiary {
    if (_isCoolLight) return const Color(0x8CAABBC6);
    if (_isCoolDark) return const Color(0x403D5870);
    return isDark
        ? primary.withValues(alpha: 0.18)
        : primary.withValues(alpha: 0.17);
  }

  /// Üst-sol yumuşak atmosferik aydınlık difüzyonu (ışık kaynağı hissi)
  Color get ambientLightBeam {
    if (_isCoolLight) return const Color(0xB8F7FAFC);
    if (_isCoolDark) return const Color(0x26AABBC6);
    return isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.65);
  }

  /// Hero panel arkası yumuşak organik renk & ışık alanı
  Color get heroAmbientGlow {
    if (_isCoolLight) return const Color(0x7A657D91);
    if (_isCoolDark) return const Color(0x59AABBC6);
    return primary.withValues(alpha: isDark ? 0.28 : 0.26);
  }

  // --- Layer 2: Gerçek Buzlu Cam (Frosted Glass) Yüzeyleri ---

  /// Hero Panel cam gradyanı — belirgin yarı saydam buzlu derinlik
  Color get heroGlassTop {
    if (_isCoolLight) return const Color(0x8FFFFFFF);
    if (_isCoolDark) return const Color(0xA62B4052);
    return surface.withValues(alpha: isDark ? 0.66 : 0.58);
  }

  Color get heroGlassBottom {
    if (_isCoolLight) return const Color(0x5CDCE4E8);
    if (_isCoolDark) return const Color(0x781B2A37);
    return Color.lerp(surface, primary, isDark ? 0.14 : 0.10)!
        .withValues(alpha: isDark ? 0.48 : 0.40);
  }

  /// Yarış / İçerik Kartı — ölçülü, okunaklı ama gerçekten yarı saydam buzlu cam
  Color get cardGlassTop {
    if (_isCoolLight) return const Color(0x94FFFFFF);
    if (_isCoolDark) return const Color(0x99243544);
    return surface.withValues(alpha: isDark ? 0.62 : 0.60);
  }

  Color get cardGlassBottom {
    if (_isCoolLight) return const Color(0x69E4ECF1);
    if (_isCoolDark) return const Color(0x731A2834);
    return surfaceSecondary.withValues(alpha: isDark ? 0.48 : 0.44);
  }

  /// Arama çubuğu / İkincil sakin frosted yüzey
  Color get surfaceGlass {
    if (_isCoolLight) return const Color(0xC7FFFFFF);
    if (_isCoolDark) return const Color(0xC7152232);
    return surface.withValues(alpha: isDark ? 0.48 : 0.46);
  }

  /// Yüzen Navigasyon & Modal Sheet buzlu cam yüzeyi
  Color get surfaceGlassStrong {
    if (_isCoolLight) return const Color(0xEBFFFFFF);
    if (_isCoolDark) return const Color(0xEB152232);
    return surface.withValues(alpha: isDark ? 0.72 : 0.64);
  }

  /// Parlak üst-sol ince cam kenarlığı (ışık kırılması)
  Color get glassBorder =>
      isDark ? const Color(0x36E7EDF1) : const Color(0xCCFFFFFF);

  /// Alt-sağ yumuşak şeffaf cam kenarlığı
  Color get glassBorderSubtle =>
      isDark ? const Color(0x10E7EDF1) : const Color(0x2E657D91);

  /// Cam panellerin üst iç ışık yansıması
  Color get glassSheen =>
      isDark ? const Color(0x24E7EDF1) : const Color(0xB8FFFFFF);

  /// Fısıltı düzeyinde zarif vektör akış çizgisi rengi (duvar kağıdı değil, imza)
  Color get vectorStroke {
    if (_isCoolLight) return const Color(0x26657D91);
    if (_isCoolDark) return const Color(0x1FAABBC6);
    return isDark
        ? textPrimary.withValues(alpha: 0.11)
        : primary.withValues(alpha: 0.14);
  }

  /// Vektör imza vurgu çizgisi rengi
  Color get vectorAccent {
    if (_isCoolLight) return const Color(0x3D657D91);
    if (_isCoolDark) return const Color(0x33DCE4E8);
    return primary.withValues(alpha: isDark ? 0.20 : 0.22);
  }

  /// Yumuşak, yayvan atmosfer gölgesi (keskin gölge yok)
  Color get softShadow => isDark
      ? Colors.black.withValues(alpha: 0.30)
      : const Color(0xFF0B192C).withValues(alpha: 0.04);

  // --- İlerleme Çubuğu ve Aktif Çip Cam Belirteçleri ---

  Color get progressTrack => isDark
      ? (isShadcn ? border : Colors.white.withValues(alpha: 0.10))
      : ((_isCoolLight || isShadcn)
          ? border
          : Colors.white.withValues(alpha: 0.25));

  Color get progressGradientStart => accent;

  Color get progressGradientEnd => isShadcn
      ? accent
      : (isDark
          ? (_isCoolDark
              ? const Color(0xFF06B6D4)
              : secondary.withValues(alpha: 0.80))
          : (_isCoolLight ? const Color(0xFF38BDF8) : textTertiary));

  Color get progressCompletedFill =>
      isDark ? accent.withValues(alpha: 0.65) : accent;

  Color get progressCompletedIcon => accent;

  Color get activeChipFill {
    if (isCrispCardTheme) return accent;
    if (isDark) return accent.withValues(alpha: 0.80);
    return Color.lerp(accent, textSecondary, 0.45)!.withValues(alpha: 0.82);
  }

  double get activeChipBorderAlpha =>
      isCrispCardTheme ? 0.0 : (isDark ? 0.20 : 0.25);

  Color get activeChipShadow => isDark
      ? Colors.black.withValues(alpha: 0.25)
      : accent.withValues(alpha: isShadcn ? 0.12 : 0.22);

  Color get activeChipText =>
      (isShadcn && isDark) ? const Color(0xFF18181B) : Colors.white;
}

/// Context üzerinden palete hızlı ve güvenli erişim için Extension
extension BuildContextPalette on BuildContext {
  AppColorPalette get palette {
    return Theme.of(this).extension<AppPaletteExtension>()?.palette ??
        const CoolSophisticatedLightPalette();
  }
}
