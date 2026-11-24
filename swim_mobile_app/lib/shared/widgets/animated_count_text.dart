import 'package:flutter/material.dart';

/// Sayısal özet değerleri (örn. `124`, `42+`, `%85`) 0'dan hedefe yumuşakça saydırır.
///
/// Saat/süre (`1:02.45`), ondalık veya metin değerlerde animasyon uygulamaz,
/// doğrudan [Text] gösterir.
class AnimatedCountText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final Duration duration;

  static final RegExp _countPattern = RegExp(r'^(\d+)([+%]?)$');

  const AnimatedCountText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.duration = const Duration(milliseconds: 1100),
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    final match = _countPattern.firstMatch(trimmed);
    final target = match != null ? int.tryParse(match.group(1)!) : null;
    final suffix = match?.group(2) ?? '';
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final effectiveStyle = (style ?? const TextStyle()).copyWith(
      fontFeatures: style?.fontFeatures ?? const [FontFeature.tabularFigures()],
    );

    if (target == null || target <= 0 || disableAnimations) {
      return Text(
        text,
        style: effectiveStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(
          '${value.round()}$suffix',
          style: effectiveStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
        );
      },
    );
  }
}
