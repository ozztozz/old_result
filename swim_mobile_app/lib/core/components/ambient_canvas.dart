import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Uygulamanın özgün soyut vektör grafik dili (design.md — Distinctive Graphic Identity)
enum AmbientArtStyle {
  /// İnce, akışkan organik vektör eğrileri (Ana ekran & Hero kartlar)
  flowLines,

  /// Asimetrik kesişen yaylar, yörünge halkaları ve minimal odak noktaları (Profil & Keşfet)
  orbitalArcs,

  /// Hareket ve derinlik hissi veren paralel kontur çizgileri (Canlı kartlar & Özetler)
  contourWaves,

  /// Boş durumlar için sakin eşmerkezli yörünge kompozisyonu
  emptyOrbit,

  none,
}

/// Hafif, yüksek performanslı soyut vektör çizim katmanı.
/// Metin ve butonlarla asla yarışmayan düşük opaklıklı çizgiler üretir.
class AmbientVectorArt extends StatelessWidget {
  final AmbientArtStyle style;
  final Color? strokeColor;
  final Color? accentColor;
  final double opacity;

  const AmbientVectorArt({
    super.key,
    required this.style,
    this.strokeColor,
    this.accentColor,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (style == AmbientArtStyle.none) return const SizedBox.shrink();
    final palette = context.palette;

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientVectorPainter(
            style: style,
            strokeColor: (strokeColor ?? palette.vectorStroke)
                .withValues(alpha: ((strokeColor ?? palette.vectorStroke).a * opacity).clamp(0.0, 1.0)),
            accentColor: (accentColor ?? palette.primary)
                .withValues(alpha: (palette.isDark ? 0.22 : 0.18) * opacity),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _AmbientVectorPainter extends CustomPainter {
  final AmbientArtStyle style;
  final Color strokeColor;
  final Color accentColor;

  const _AmbientVectorPainter({
    required this.style,
    required this.strokeColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    switch (style) {
      case AmbientArtStyle.flowLines:
        _paintFlowLines(canvas, size);
        break;
      case AmbientArtStyle.orbitalArcs:
        _paintOrbitalArcs(canvas, size);
        break;
      case AmbientArtStyle.contourWaves:
        _paintContourWaves(canvas, size);
        break;
      case AmbientArtStyle.emptyOrbit:
        _paintEmptyOrbit(canvas, size);
        break;
      case AmbientArtStyle.none:
        break;
    }
  }

  void _paintFlowLines(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < 4; i++) {
      final t = i / 3.0;
      final paint = Paint()
        ..color = i == 1 ? accentColor : strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 1 ? 1.25 : 0.9
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(-w * 0.08, h * (0.22 + t * 0.22))
        ..cubicTo(
          w * (0.28 + t * 0.06),
          h * (0.04 + t * 0.14),
          w * (0.58 - t * 0.04),
          h * (0.52 + t * 0.12),
          w * 1.08,
          h * (0.16 + t * 0.26),
        );
      canvas.drawPath(path, paint);
    }

    // Sağ üstte zarif kesişim halkası ve ince odak noktası
    final ringPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;
    final center = Offset(w * 0.86, h * 0.24);
    canvas.drawCircle(center, h * 0.26, ringPaint);

    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.86 - h * 0.26, h * 0.24), 2.4, dotPaint);
  }

  void _paintOrbitalArcs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.88, h * 0.18);
    final baseRadius = math.min(w, h) * 0.42;

    final primaryStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    final subtleStroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;

    // 3 asimetrik yörünge yayı
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 0.72),
      math.pi * 0.45,
      math.pi * 0.95,
      false,
      primaryStroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 1.12),
      math.pi * 0.32,
      math.pi * 1.12,
      false,
      subtleStroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 1.54),
      math.pi * 0.50,
      math.pi * 0.80,
      false,
      subtleStroke,
    );

    // Kesişen ince diyagonal vektör çizgisi
    final diagPath = Path()
      ..moveTo(w * 0.35, h * 0.0)
      ..quadraticBezierTo(w * 0.68, h * 0.48, w * 1.05, h * 0.62);
    canvas.drawPath(diagPath, subtleStroke);

    // Minimal yörünge noktaları
    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final p1 = Offset(
      center.dx + math.cos(math.pi * 0.82) * baseRadius * 0.72,
      center.dy + math.sin(math.pi * 0.82) * baseRadius * 0.72,
    );
    final p2 = Offset(
      center.dx + math.cos(math.pi * 1.14) * baseRadius * 1.12,
      center.dy + math.sin(math.pi * 1.14) * baseRadius * 1.12,
    );
    canvas.drawCircle(p1, 2.5, dotPaint);
    canvas.drawCircle(p2, 2.0, dotPaint);
  }

  void _paintContourWaves(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < 5; i++) {
      final offset = i * 9.0;
      final paint = Paint()
        ..color = i == 0 ? accentColor : strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.15 : 0.8;

      final path = Path()
        ..moveTo(w * 0.42 + offset * 0.4, -10)
        ..cubicTo(
          w * 0.56 + offset * 0.5,
          h * 0.34,
          w * 0.76 + offset * 0.5,
          h * 0.62,
          w * 1.06 + offset * 0.3,
          h * 0.92,
        );
      canvas.drawPath(path, paint);
    }
  }

  void _paintEmptyOrbit(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.46;

    final subtlePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final accentPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, maxR * 0.62, subtlePaint);
    canvas.drawCircle(center, maxR * 0.92, subtlePaint);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.92),
      -math.pi * 0.68,
      math.pi * 0.46,
      false,
      accentPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.62),
      math.pi * 0.25,
      math.pi * 0.55,
      false,
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientVectorPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.accentColor != accentColor;
  }
}

/// Ekran zeminine yumuşak Ambient Glass atmosferi (radyal ışık alanları +
/// üst bölüm soyut vektör kompozisyonu) ekleyen hafif arka plan katmanı.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final AmbientArtStyle artStyle;
  final double artHeight;

  const AmbientBackground({
    super.key,
    required this.child,
    this.artStyle = AmbientArtStyle.flowLines,
    this.artHeight = 250,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        // 1. Temel zemin rengi
        Positioned.fill(
          child: ColoredBox(color: palette.background),
        ),

        // 2. Üst-sağ yumuşak atmosferik ışık alanı (Ambient Glass)
        Positioned(
          top: -90,
          right: -70,
          width: 300,
          height: 300,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.ambientPrimary,
                      palette.ambientPrimary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // 3. Sol-orta ikincil yumuşak atmosferik ışık alanı
        Positioned(
          top: 120,
          left: -110,
          width: 260,
          height: 260,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.ambientSecondary,
                      palette.ambientSecondary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // 4. Üst başlık alanında zarif soyut vektör çizimi
        if (artStyle != AmbientArtStyle.none)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: artHeight,
            child: AmbientVectorArt(style: artStyle),
          ),

        // 5. Asıl ekran içeriği
        child,
      ],
    );
  }
}
