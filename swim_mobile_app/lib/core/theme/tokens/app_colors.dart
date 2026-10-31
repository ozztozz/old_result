import 'package:flutter/material.dart';

/// Katman 1: Design Tokens — Statik Renk Sabitleri (AppColors)
/// Temel palet sabitlerini ve geriye dönük uyumluluk tanımlarını içerir.
abstract final class AppColors {
  // 1. Zemin (Background)
  static const Color background = Color(0xFFFAF8F7);
  static const Color darkCanvas = Color(0xFFFAF8F7);

  // 2. Kart / Yüzey (Surface)
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceGlass = Color(0xFFFFFFFF);
  static const Color surfaceGlassLight = Color(0xFFFAF8F7);

  // 3. Tipografi
  static const Color textPrimary = Color(0xFF3D3038);
  static const Color textSecondary = Color(0xFF81777D);
  static const Color textMuted = Color(0xFF81777D);
  static const Color laneNeutral = Color(0xFFB3A8AE);

  // 4. Vurgu (Accent)
  static const Color accent = Color(0xFFBC8C91);
  static const Color accentLight = Color(0x1FBC8C91);
  static const Color accentGlow = Color(0x26BC8C91);

  // 5. Ayırıcılar ve Çerçeve
  static const Color divider = Color(0xFFEFE9E7);
  static const Color border = Color(0xFFEFE9E7);
  static const Color glassBorder = Color(0xFFEFE9E7);

  // 6. Durum Renkleri
  static const Color statusLive = Color(0xFFBC8C91);
  static const Color statusLiveBg = Color(0x1FBC8C91);
  static const Color statusSuccess = Color(0xFF4A7C59);
  static const Color statusSuccessBg = Color(0x144A7C59);

  // 7. Spor & Madalya
  static const Color gold = Color(0xFFB8860B);
  static const Color goldBg = Color(0x14B8860B);
  static const Color starGold = Color(0xFFD4A373);
  static const Color heroAccentYellow = Color(0xFFD4A373);

  // Marka & Başlık Renkleri
  static const Color brandPrimary = accent;
  static const Color brandPrimaryDark = Color(0xFF3D3038);
  static const Color brandDeep = Color(0xFF3D3038);

  // Durum / Uyarı
  static const Color liveGreen = statusLive;
  static const Color success = statusSuccess;
  static const Color successBg = statusSuccessBg;
  static const Color warning = Color(0xFFB8860B);
  static const Color warningBg = Color(0x14B8860B);
  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerBg = Color(0x14B91C1C);
  static const Color tabContainerBg = Color(0xFFF2ECE9);

  // Nötr Renk Takma Adları
  static const Color slate50 = background;
  static const Color slate100 = divider;
  static const Color slate200 = border;
  static const Color slate300 = Color(0xFFDDD4D1);
  static const Color slate400 = textMuted;
  static const Color slate500 = textSecondary;
  static const Color slate600 = Color(0xFF5A4D55);
  static const Color slate900 = textPrimary;

  // Geriye Dönük Uyumluluk Takma Adları
  static const Color bg = background;
  static const Color card = surface;
  static const Color ink = textPrimary;
  static const Color muted = textMuted;
  static const Color mint = Color(0xFFD1E8E2);
  static const Color lavender = Color(0xFFE8D7F1);
  static const Color lime = Color(0xFFE2EFCB);
  static const Color teal = Color(0xFFD8E2DC);
}

