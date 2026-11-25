import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Sayısal özet değerleri (örn. `124`, `42+`, `%85`) kısa bir gecikmeyle
/// 0'dan hedefe vurgulu şekilde saydırır.
///
/// Saat/süre (`1:02.45`), ondalık veya metin değerlerde animasyon uygulamaz,
/// doğrudan [Text] gösterir.
class AnimatedCountText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final Duration duration;
  final Duration delay;

  const AnimatedCountText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.duration = const Duration(milliseconds: 1650),
    this.delay = const Duration(milliseconds: 350),
  });

  @override
  State<AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends State<AnimatedCountText>
    with SingleTickerProviderStateMixin {
  static final RegExp _countPattern = RegExp(r'^(\d+)([+%]?)$');

  late final AnimationController _controller;
  Timer? _delayTimer;
  double _beginValue = 0;
  int? _target;
  String _suffix = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _parseText();
    _scheduleAnimation(withDelay: true);
  }

  void _parseText() {
    final match = _countPattern.firstMatch(widget.text.trim());
    _target = match != null ? int.tryParse(match.group(1)!) : null;
    _suffix = match?.group(2) ?? '';
  }

  void _scheduleAnimation({required bool withDelay}) {
    _delayTimer?.cancel();
    if (_target == null || _target! <= 0) return;

    if (!withDelay || widget.delay == Duration.zero) {
      _controller.forward(from: 0.0);
      return;
    }

    _controller.value = 0.0;
    _delayTimer = Timer(widget.delay, () {
      if (mounted) {
        _controller.forward(from: 0.0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.text != oldWidget.text) {
      final oldTarget = _target ?? 0;
      final progress = Curves.easeOutQuart.transform(_controller.value);
      _beginValue = _beginValue + (oldTarget - _beginValue) * progress;
      _parseText();
      if (_target == null || _target! <= 0) {
        _beginValue = 0;
        _delayTimer?.cancel();
      } else {
        _scheduleAnimation(withDelay: false);
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final effectiveStyle = (widget.style ?? const TextStyle()).copyWith(
      fontFeatures:
          widget.style?.fontFeatures ?? const [FontFeature.tabularFigures()],
    );

    if (_target == null || _target! <= 0 || disableAnimations) {
      return Text(
        widget.text,
        style: effectiveStyle,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        softWrap: widget.softWrap,
      );
    }

    final target = _target!.toDouble();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = _controller.value;
        final curved = Curves.easeOutQuart.transform(raw);
        final current = (_beginValue + (target - _beginValue) * curved).round();

        // Hedef rakama ulaşırken hafif vurgu ölçeklenmesi (1.0 -> 1.08 -> 1.0)
        final popScale = raw > 0.82
            ? 1.0 + 0.08 * math.sin(((raw - 0.82) / 0.18) * math.pi)
            : 1.0;

        return Transform.scale(
          scale: popScale,
          child: Text(
            '$current$_suffix',
            style: effectiveStyle,
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            softWrap: widget.softWrap,
          ),
        );
      },
    );
  }
}
