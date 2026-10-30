import 'package:flutter/material.dart';
import 'swim_colors.dart';

/// Yüzme Sporuna Özel Tasarım Sistemi (SwimDesign)
class SwimTheme {
  // İmza Süre Tipografisi (Tabular Figures ile sabit genişlikli rakamlar)
  static const TextStyle timeDisplay = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle timeDisplaySmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        primary: const Color(0xFF0A5C99),     // Derin Okyanus Mavisi
        background: const Color(0xFFF6F9FB),  // Serin Açık Gri Zemin
        surface: Colors.white,
        text: const Color(0xFF0B1B2B),        // Yüksek Kontrastlı Lacivert Metin
        textSecondary: const Color(0xFF5B6B7A),
        outline: const Color(0xFFDCE5EC),     // 1 dp İnce Kenarlık
        colors: const SwimColors(
          success: Color(0xFF1B7F4B),
          pending: Color(0xFFB26A00),
          pendingBg: Color(0xFFFFF4DD),
          danger: Color(0xFFB3261E),
          pb: Color(0xFF00838F),             // Yeni PB için Turkuaz/Cyan
          accent: Color(0xFF1AA6B7),
          medalGold: Color(0xFFC9A227),
          medalSilver: Color(0xFF9AA5B1),
          medalBronze: Color(0xFFB0713A),
        ),
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        primary: const Color(0xFF5FB3F0),     // Koyu Zeminde Açılmış Mavi
        background: const Color(0xFF0B141C),  // Derin Okyanus Karanlığı (Saf Siyah Değil)
        surface: const Color(0xFF121E28),     // Koyu Kart Yüzeyi
        text: const Color(0xFFE6EEF4),        // Yumuşak Beyaz Metin
        textSecondary: const Color(0xFF9BB0C0),
        outline: const Color(0xFF24323E),     // Koyu İnce Kenarlık
        colors: const SwimColors(
          success: Color(0xFF5CCB8A),
          pending: Color(0xFFF2B84B),
          pendingBg: Color(0xFF2A2210),
          danger: Color(0xFFFF8A80),
          pb: Color(0xFF4DD0E1),
          accent: Color(0xFF4DD0E1),
          medalGold: Color(0xFFC9A227),
          medalSilver: Color(0xFF9AA5B1),
          medalBronze: Color(0xFFB0713A),
        ),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color text,
    required Color textSecondary,
    required Color outline,
    required SwimColors colors,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      surface: surface,
      outline: outline,
    );

    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(
        fontFamily: 'Inter',
        bodyColor: text,
        displayColor: text,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outline, width: 1),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline, width: 1),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
        titleTextStyle: TextStyle(
          color: text,
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      extensions: [colors],
    );
  }
}

/// Kolay Erişim Yardımcısı (Extension Getter)
extension SwimThemeContext on BuildContext {
  SwimColors get swimColors => Theme.of(this).extension<SwimColors>()!;
}

