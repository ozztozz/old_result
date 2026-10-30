import 'package:flutter/material.dart';

/// Yüzme Sporuna Özel Material 3 Tasarım Sistemi (SwimDesign)
class AppTheme {
  // Marka & Branş Renkleri
  static const Color primaryBlue = Color(0xFF0284C7); // Okyanus Mavisi
  static const Color primaryDark = Color(0xFF0369A1);
  static const Color accentCyan = Color(0xFF06B6D4);

  // Durum Renkleri (Swim Status Palette)
  static const Color statusSuccess = Color(0xFF10B981); // Sonuçlandı / Baraj Geçildi
  static const Color statusPending = Color(0xFFF59E0B); // Bekleniyor / Sıradaki
  static const Color statusDanger = Color(0xFFEF4444);  // DQ / DNS / DNF
  static const Color statusInfo = Color(0xFF3B82F6);    // Puan / Bilgi

  // Aydınlık Tema (Light Theme)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        primary: primaryBlue,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
      ),
    );
  }

  // Koyu Tema (Dark Theme)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        primary: accentCyan,
        surface: const Color(0xFF1E293B),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      cardTheme: CardTheme(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
    );
  }
}
