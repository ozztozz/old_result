import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Uygulama genelinde seçilebilen tema önayarları.
/// Varsayılan olarak Soft Glass + Ambient Glass (Cool Sophisticated) tasarım dili
/// hem Açık hem Koyu modda aktif gelir; Klasik TYF ve diğer paletler de seçilebilir.
enum AppThemePreset {
  coolGlassSystem(
    id: 'cool_glass_system',
    title: 'Cool Glass',
    subtitle: 'Soft & Ambient Glass · Sistem (Açık / Koyu)',
    badge: 'Önerilen',
    isDarkOnly: false,
    isSystemAdaptive: true,
    previewBackground: Color(0xFFF1F4F6),
    previewSurface: Color(0xFFFFFFFF),
    previewPrimary: Color(0xFF657D91),
    previewSecondary: Color(0xFFAABBC6),
  ),
  coolGlassLight(
    id: 'cool_glass_light',
    title: 'Cool Glass Açık',
    subtitle: 'Ferah Ice & Steel cam yüzeyler',
    badge: 'Açık',
    isDarkOnly: false,
    isSystemAdaptive: false,
    previewBackground: Color(0xFFF1F4F6),
    previewSurface: Color(0xFFFFFFFF),
    previewPrimary: Color(0xFF657D91),
    previewSecondary: Color(0xFFDCE4E8),
  ),
  coolGlassDark(
    id: 'cool_glass_dark',
    title: 'Cool Glass Koyu',
    subtitle: 'Derin slate atmosfer & Mist vurgu',
    badge: 'Koyu',
    isDarkOnly: true,
    isSystemAdaptive: false,
    previewBackground: Color(0xFF17232D),
    previewSurface: Color(0xFF202F3B),
    previewPrimary: Color(0xFFAABBC6),
    previewSecondary: Color(0xFF657D91),
  ),
  classic(
    id: 'classic',
    title: 'Klasik TYF',
    subtitle: 'Geleneksel TYF laciverti · Sistem',
    badge: 'Klasik',
    isDarkOnly: false,
    isSystemAdaptive: true,
    previewBackground: Color(0xFFF8FAFC),
    previewSurface: Color(0xFFFFFFFF),
    previewPrimary: Color(0xFF0F4C81),
    previewSecondary: Color(0xFF0D9488),
  ),
  olympicPool(
    id: 'olympic_pool',
    title: 'Olimpik Havuz',
    subtitle: 'Canlı havuz mavisi & turkuaz ferahlığı',
    badge: 'Açık',
    isDarkOnly: false,
    isSystemAdaptive: false,
    previewBackground: Color(0xFFEDF7FD),
    previewSurface: Color(0xFFFFFFFF),
    previewPrimary: Color(0xFF0284C7),
    previewSecondary: Color(0xFF06B6D4),
  ),
  nationalTeam(
    id: 'national_team',
    title: 'Milli Takım',
    subtitle: 'Ay-Yıldız kırmızısı & güçlü antrasit',
    badge: 'Açık',
    isDarkOnly: false,
    isSystemAdaptive: false,
    previewBackground: Color(0xFFFBF8F8),
    previewSurface: Color(0xFFFFFFFF),
    previewPrimary: Color(0xFFC8102E),
    previewSecondary: Color(0xFF1E293B),
  ),
  nightArena(
    id: 'night_arena',
    title: 'Gece Arenası',
    subtitle: 'AMOLED koyu zemin & neon cyan',
    badge: 'Koyu',
    isDarkOnly: true,
    isSystemAdaptive: false,
    previewBackground: Color(0xFF050811),
    previewSurface: Color(0xFF0D1324),
    previewPrimary: Color(0xFF00E5FF),
    previewSecondary: Color(0xFF22C55E),
  ),
  finalNightGold(
    id: 'final_night_gold',
    title: 'Final Gecesi',
    subtitle: 'Şampiyona laciverti & madalya altını',
    badge: 'Koyu',
    isDarkOnly: true,
    isSystemAdaptive: false,
    previewBackground: Color(0xFF0B1120),
    previewSurface: Color(0xFF131C31),
    previewPrimary: Color(0xFFF59E0B),
    previewSecondary: Color(0xFF38BDF8),
  );

  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final bool isDarkOnly;
  final bool isSystemAdaptive;
  final Color previewBackground;
  final Color previewSurface;
  final Color previewPrimary;
  final Color previewSecondary;

  const AppThemePreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.isDarkOnly,
    required this.isSystemAdaptive,
    required this.previewBackground,
    required this.previewSurface,
    required this.previewPrimary,
    required this.previewSecondary,
  });

  static AppThemePreset fromId(String? id) {
    if (id == null) return AppThemePreset.coolGlassSystem;
    for (final preset in AppThemePreset.values) {
      if (preset.id == id) return preset;
    }
    return AppThemePreset.coolGlassSystem;
  }

  AppColorPalette? get fixedPalette {
    switch (this) {
      case AppThemePreset.coolGlassSystem:
      case AppThemePreset.classic:
        return null;
      case AppThemePreset.coolGlassLight:
        return const CoolSophisticatedLightPalette();
      case AppThemePreset.coolGlassDark:
        return const CoolSophisticatedDarkPalette();
      case AppThemePreset.olympicPool:
        return const OlympicPoolPalette();
      case AppThemePreset.nationalTeam:
        return const NationalTeamPalette();
      case AppThemePreset.nightArena:
        return const NightArenaNeonPalette();
      case AppThemePreset.finalNightGold:
        return const FinalNightGoldPalette();
    }
  }
}

/// Global Tema Yönetim Servisi
/// Seçili temayı SharedPreferences ile kalıcı olarak saklar ve tüm
/// MaterialApp ağacını anında günceller.
class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();

  ThemeService._internal();

  static const String _keyThemePreset = 'selected_theme_preset_v2';

  SharedPreferences? _prefs;
  AppThemePreset _preset = AppThemePreset.coolGlassSystem;
  bool _isInitialized = false;

  AppThemePreset get preset => _preset;
  bool get isInitialized => _isInitialized;

  ThemeMode get themeMode {
    if (_preset.isSystemAdaptive) return ThemeMode.system;
    return _preset.isDarkOnly ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData get lightTheme {
    if (_preset == AppThemePreset.coolGlassSystem) {
      return AppTheme.fromPalette(const CoolSophisticatedLightPalette());
    }
    final palette = _preset.fixedPalette;
    if (palette != null && !palette.isDark) {
      return AppTheme.fromPalette(palette);
    }
    return AppTheme.light();
  }

  ThemeData get darkTheme {
    if (_preset == AppThemePreset.coolGlassSystem) {
      return AppTheme.fromPalette(const CoolSophisticatedDarkPalette());
    }
    final palette = _preset.fixedPalette;
    if (palette != null && palette.isDark) {
      return AppTheme.fromPalette(palette);
    }
    return AppTheme.dark();
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final savedId = _prefs?.getString(_keyThemePreset);
      _preset = AppThemePreset.fromId(savedId);
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
    }
  }

  Future<void> setPreset(AppThemePreset newPreset) async {
    if (_preset == newPreset) return;
    _preset = newPreset;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_keyThemePreset, newPreset.id);
    } catch (_) {
      // Depolama hatası olsa bile çalışma anındaki seçim korunur
    }
  }
}
