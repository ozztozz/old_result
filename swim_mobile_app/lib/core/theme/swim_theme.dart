import 'package:flutter/material.dart';
import 'swim_colors.dart';
import 'app_theme.dart';

export 'swim_colors.dart';
export 'tokens/tokens.dart';
export 'app_theme.dart';

/// TYF Yüzme Sonuçları — Mobil Tasarım Sistemi ve Şartnamesi (v2.0)
class TYFTheme {
  static const Color background = Color(0xFFFAF8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primaryText = Color(0xFF3D3038);
  static const Color secondaryText = Color(0xFF81777D);
  static const Color accent = Color(0xFFBC8C91);
  static const Color divider = Color(0xFFEFE9E7);

  static ThemeData get lightTheme => AppTheme.light();
}

/// TYF Yüzme Sporuna Özel Merkezi Tasarım Sistemi (SwimTheme v2.0)
class SwimTheme {
  static const TextStyle timeDisplay = AppTextStyles.officialTime;
  static const TextStyle timeDisplaySmall = AppTextStyles.categorySeries;

  static ThemeData light() => _buildLight();
  static ThemeData dark() => _buildDark();

  static ThemeData _buildLight() {
    final base = AppTheme.light(const LightColorPalette());
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
      extensions: [
        const AppPaletteExtension(palette: LightColorPalette()),
        colors,
      ],
    );
  }

  static ThemeData _buildDark() {
    final base = AppTheme.dark(const DarkColorPalette());
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
      extensions: [
        const AppPaletteExtension(palette: DarkColorPalette()),
        colors,
      ],
    );
  }
}
