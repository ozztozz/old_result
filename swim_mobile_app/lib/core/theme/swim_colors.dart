import 'package:flutter/material.dart';
export 'app_colors.dart';

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

  static const defaultColors = SwimColors(
    success: Color(0xFF4A7C59),
    pending: Color(0xFFB8860B),
    pendingBg: Color(0x14B8860B),
    danger: Color(0xFFB91C1C),
    pb: Color(0xFFB8860B),
    accent: Color(0xFFBC8C91),
    medalGold: Color(0xFFD4A373),
    medalSilver: Color(0xFFB3A8AE),
    medalBronze: Color(0xFFB8860B),
  );

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

extension SwimColorsExtension on BuildContext {
  SwimColors get swimColors =>
      Theme.of(this).extension<SwimColors>() ?? SwimColors.defaultColors;
}
