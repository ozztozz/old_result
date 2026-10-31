import 'package:flutter/material.dart';
import 'tokens/tokens.dart';

export 'tokens/tokens.dart';

/// Katman 2: Global ThemeData (AppTheme)
/// Material 3 tabanlı merkezi tema. FilledButton, TextField, Card, AppBar vb.
/// tüm standart bileşenlerin stillerini merkezi olarak tanımlar.
abstract final class AppTheme {
  /// Açık Tema Üreticisi
  static ThemeData light([AppColorPalette palette = const LightColorPalette()]) {
    return _buildTheme(palette);
  }

  /// Koyu Tema Üreticisi
  static ThemeData dark([AppColorPalette palette = const DarkColorPalette()]) {
    return _buildTheme(palette);
  }

  static ThemeData _buildTheme(AppColorPalette palette) {
    final colorScheme = palette.isDark
        ? ColorScheme.dark(
            primary: palette.primary,
            onPrimary: Colors.white,
            primaryContainer: palette.primaryContainer,
            secondary: palette.secondary,
            surface: palette.surface,
            onSurface: palette.textPrimary,
            error: palette.statusDanger,
            outline: palette.border,
            outlineVariant: palette.divider,
          )
        : ColorScheme.light(
            primary: palette.primary,
            onPrimary: Colors.white,
            primaryContainer: palette.primaryContainer,
            secondary: palette.secondary,
            surface: palette.surface,
            onSurface: palette.textPrimary,
            error: palette.statusDanger,
            outline: palette.border,
            outlineVariant: palette.divider,
          );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTextStyles.fontFamily,
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,

      // AppBar Stili
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: palette.textPrimary),
        titleTextStyle: AppTextStyles.raceTitle.copyWith(
          color: palette.textPrimary,
        ),
      ),

      // Card Stili (0 elevation, 1px border, 16px radius)
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: palette.border),
        ),
      ),

      // FilledButton Stili
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: AppSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: AppTextStyles.tabSelected.copyWith(color: Colors.white),
        ),
      ),

      // OutlinedButton Stili
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          padding: AppSpacing.buttonPadding,
          side: BorderSide(color: palette.border),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: AppTextStyles.tabSelected.copyWith(color: palette.textPrimary),
        ),
      ),

      // TextButton Stili
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          padding: AppSpacing.paddingHorizontalSm,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: AppTextStyles.tabSelected.copyWith(color: palette.primary),
        ),
      ),

      // TextField / InputDecoration Stili
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: AppTextStyles.labelMuted.copyWith(color: palette.textMuted),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide(color: palette.statusDanger),
        ),
      ),

      // Divider Stili
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1.0,
        space: 1.0,
      ),

      // Chip Stili
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.primaryContainer,
        side: BorderSide(color: palette.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.chipRadius),
        labelStyle: AppTextStyles.filterChip.copyWith(color: palette.textPrimary),
      ),

      // Tipografi
      textTheme: AppTextStyles.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),

      // ThemeExtension ile dinamik AppColorPalette entegrasyonu
      extensions: [
        AppPaletteExtension(palette: palette),
      ],
    );
  }
}
