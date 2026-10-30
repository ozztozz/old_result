import 'package:flutter/material.dart';

/// Minimalist İskandinav Pastel Renk Paleti (AppColors)
class AppColors {
  static const bg = Color(0xFFEEF2F0);
  static const card = Color(0xFFF7F7F7);
  static const mint = Color(0xFFCFE8C9);
  static const lime = Color(0xFFE6F26B);
  static const lavender = Color(0xFFDCD3F0);
  static const teal = Color(0xFFCDE3DE);
  static const ink = Color(0xFF1E1E1E);
  static const muted = Color(0xFF9A9A9A);
}

/// TYF Yüzme Mobil Uygulaması Özel Renk Uzantısı (ThemeExtension)
/// Widget'lar sabit renkler yerine Theme.of(context).extension<SwimColors>()! kullanır.
@immutable
class SwimColors extends ThemeExtension<SwimColors> {
  final Color success;
  final Color pending;
  final Color pendingBg;
  final Color danger;
  final Color pb;
  final Color accent;
  final Color medalGold;
  final Color medalSilver;
  final Color medalBronze;

  const SwimColors({
    required this.success,
    required this.pending,
    required this.pendingBg,
    required this.danger,
    required this.pb,
    required this.accent,
    required this.medalGold,
    required this.medalSilver,
    required this.medalBronze,
  });

  @override
  SwimColors copyWith({
    Color? success,
    Color? pending,
    Color? pendingBg,
    Color? danger,
    Color? pb,
    Color? accent,
    Color? medalGold,
    Color? medalSilver,
    Color? medalBronze,
  }) {
    return SwimColors(
      success: success ?? this.success,
      pending: pending ?? this.pending,
      pendingBg: pendingBg ?? this.pendingBg,
      danger: danger ?? this.danger,
      pb: pb ?? this.pb,
      accent: accent ?? this.accent,
      medalGold: medalGold ?? this.medalGold,
      medalSilver: medalSilver ?? this.medalSilver,
      medalBronze: medalBronze ?? this.medalBronze,
    );
  }

  @override
  SwimColors lerp(SwimColors? other, double t) {
    if (other == null) return this;
    return SwimColors(
      success: Color.lerp(success, other.success, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingBg: Color.lerp(pendingBg, other.pendingBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      pb: Color.lerp(pb, other.pb, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      medalGold: Color.lerp(medalGold, other.medalGold, t)!,
      medalSilver: Color.lerp(medalSilver, other.medalSilver, t)!,
      medalBronze: Color.lerp(medalBronze, other.medalBronze, t)!,
    );
  }
}

