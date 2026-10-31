import 'package:flutter/material.dart';
import 'swim_colors.dart';
import 'app_typography.dart';

export 'swim_colors.dart';
export 'app_colors.dart';
export 'app_typography.dart';
export 'app_decorations.dart';

/// TYF Yüzme Sonuçları — Mobil Tasarım Sistemi ve Şartnamesi (v2.0)
class TYFTheme {
  static const Color background = Color(0xFFFAF8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primaryText = Color(0xFF3D3038);
  static const Color secondaryText = Color(0xFF81777D);
  static const Color accent = Color(0xFFBC8C91);
  static const Color divider = Color(0xFFEFE9E7);

  static ThemeData get lightTheme {
    return ThemeData(
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        surface: surface,
        primary: primaryText,
        secondary: accent,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: primaryText,
          letterSpacing: -0.2,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: primaryText,
        ),
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: secondaryText,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
          color: primaryText,
        ),
      ),
    );
  }
}

/// TYF Yüzme Sporuna Özel Merkezi Tasarım Sistemi (SwimTheme v2.0)
class SwimTheme {
  static const TextStyle timeDisplay = AppTextStyles.officialTime;
  static const TextStyle timeDisplaySmall = AppTextStyles.categorySeries;

  static ThemeData light() => _buildLight();
  static ThemeData dark() => _buildLight(); // v2.0: Ferah Nötr Aydınlık Zemin (#FAF8F7)

  static ThemeData _buildLight() {
    final base = TYFTheme.lightTheme;
    const colors = SwimColors(
      success: AppColors.statusSuccess,
      pending: AppColors.warning,
      pendingBg: AppColors.warningBg,
      danger: AppColors.danger,
      pb: AppColors.gold,
      accent: AppColors.accent,
      medalGold: AppColors.starGold,
      medalSilver: AppColors.laneNeutral,
      medalBronze: AppColors.warning,
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      extensions: const [colors],
    );
  }
}
