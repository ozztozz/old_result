import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Katman 1: Design Tokens — Tipografi Sabitleri (AppTypography & AppTextStyles)
/// Apple esintili yalınlık, tabular rakamlar, okunaklı ve dengeli hiyerarşi.
abstract final class AppTextStyles {
  static const String fontFamily = 'Inter';

  // 1. Uygulama Başlığı
  static const TextStyle appTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textPrimary,
  );

  // 2. Müsabaka / Yarış Başlığı
  static const TextStyle raceTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17.0,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  // 3. Kategori & Seri Bilgisi
  static const TextStyle categorySeries = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // 4. Sporcu Adı
  static const TextStyle athleteName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  // 5. Kulüp Adı
  static const TextStyle clubName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // 6. Resmi Derece (Tabular Figures)
  static const TextStyle officialTime = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // 7. Sıra ve Kulvar Numaraları (Tabular Figures)
  static const TextStyle laneRank = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Metrik ve Özel Gösterimler
  static const TextStyle metricLarge = officialTime;
  static const TextStyle metricHero = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle sectionHeader = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0.8,
  );

  static const TextStyle screenTitle = raceTitle;
  static const TextStyle screenSubtitle = categorySeries;
  static const TextStyle cardTitle = raceTitle;
  static const TextStyle cardSubtitle = categorySeries;

  static const TextStyle labelMuted = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  static const TextStyle tabSelected = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle tabUnselected = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle filterChip = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  // Material 3 TextTheme Eşlemesi
  static TextTheme get textTheme => const TextTheme(
        headlineSmall: raceTitle,
        titleMedium: athleteName,
        titleSmall: sectionHeader,
        bodyLarge: athleteName,
        bodyMedium: clubName,
        bodySmall: labelMuted,
        labelLarge: officialTime,
        labelSmall: badge,
      );
}

typedef AppTypography = AppTextStyles;

