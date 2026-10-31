import 'package:flutter/material.dart';

/// 3. Özel Durumlar İçin ThemeExtension (AppExtraColors)
@immutable
class AppExtraColors extends ThemeExtension<AppExtraColors> {
  final Color success;
  final Color warning;
  final Color danger;
  final Color live;
  final Color gold;
  final Color neutral;

  const AppExtraColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.live,
    required this.gold,
    required this.neutral,
  });

  @override
  AppExtraColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? live,
    Color? gold,
    Color? neutral,
  }) {
    return AppExtraColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      live: live ?? this.live,
      gold: gold ?? this.gold,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  AppExtraColors lerp(ThemeExtension<AppExtraColors>? other, double t) {
    if (other is! AppExtraColors) return this;
    return AppExtraColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      live: Color.lerp(live, other.live, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

/// Pratik erişim için BuildContext extension:
extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  AppExtraColors get extraColors => Theme.of(this).extension<AppExtraColors>()!;
}

