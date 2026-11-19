import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Uygulamanın özgün soyut vektör grafik dili (DESIGN_REFINEMENT — Original Graphic Language)
enum AmbientArtStyle {
  /// Organik akışkan eğriler + konsantrik yay kesişimi (Canlı Takip zemin atmosferi)
  flowLines,

  /// Asimetrik kesişen yörünge yayları ve eliptik iz (Keşfet & Sporcu Profili)
  orbitalArcs,

  /// İstatistik Hero paneline özel konsantrik yörünge & ince kontur detayı
  heroOrbit,

  /// Kart köşelerinde zarif konsantrik kontur dalgaları (Öne çıkan yarış kartı & Favoriler)
  contourWaves,

  /// Boş durumlar için sakin eşmerkezli yörünge kompozisyonu
  emptyOrbit,

  none,
}

/// Hafif, yüksek performanslı özgün soyut vektör çizim katmanı.
/// Metin ve butonlarla asla yarışmaz; katmanlı derinlik ve görsel imza oluşturur.
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
    final baseStroke = strokeColor ?? palette.vectorStroke;
    final baseAccent = accentColor ?? palette.vectorAccent;

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientVectorPainter(
            style: style,
            strokeColor: baseStroke.withValues(
              alpha: (baseStroke.a * opacity).clamp(0.0, 1.0),
            ),
            accentColor: baseAccent.withValues(
              alpha: (baseAccent.a * opacity).clamp(0.0, 1.0),
            ),
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
      case AmbientArtStyle.heroOrbit:
        _paintHeroOrbit(canvas, size);
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

  /// Organik akışkan kontur şeritleri + üst-sağda konsantrik yay kesişimi
  void _paintFlowLines(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 5 akışkan organik kontur eğrisi (su akışı / kulvar ritmi hissi)
    for (int i = 0; i < 5; i++) {
      final t = i / 4.0;
      final paint = Paint()
        ..color = i == 2 ? accentColor : strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 2 ? 1.3 : 0.85
        ..strokeCap = StrokeCap.round;

      final startY = h * (0.14 + t * 0.11);
      final path = Path()
        ..moveTo(-w * 0.06, startY)
        ..cubicTo(
          w * (0.24 + t * 0.04),
          h * (0.02 + t * 0.09),
          w * (0.56 - t * 0.03),
          h * (0.34 + t * 0.08),
          w * 1.06,
          h * (0.12 + t * 0.14),
        );
      canvas.drawPath(path, paint);
    }

    // Alt yarıda ikinci yumuşak organik akış grubu (kartların arkasında derinlik)
    for (int i = 0; i < 3; i++) {
      final t = i / 2.0;
      final paint = Paint()
        ..color = strokeColor.withValues(alpha: strokeColor.a * 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85;

      final path = Path()
        ..moveTo(-w * 0.08, h * (0.64 + t * 0.055))
        ..cubicTo(
          w * 0.30,
          h * (0.78 + t * 0.04),
          w * 0.66,
          h * (0.52 + t * 0.05),
          w * 1.08,
          h * (0.68 + t * 0.045),
        );
      canvas.drawPath(path, paint);
    }

    // Üst-sağda asimetrik konsantrik yay kompozisyonu
    final arcCenter = Offset(w * 0.90, h * 0.13);
    final baseR = w * 0.24;
    final subtleArc = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final primaryArc = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: baseR * 0.72),
      math.pi * 0.55,
      math.pi * 0.92,
      false,
      primaryArc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: baseR * 1.05),
      math.pi * 0.42,
      math.pi * 1.08,
      false,
      subtleArc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: baseR * 1.38),
      math.pi * 0.58,
      math.pi * 0.78,
      false,
      subtleArc,
    );

    // Kesişim odak noktası
    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final node = Offset(
      arcCenter.dx + math.cos(math.pi * 0.92) * baseR * 0.72,
      arcCenter.dy + math.sin(math.pi * 0.92) * baseR * 0.72,
    );
    canvas.drawCircle(node, 2.8, dotPaint);
    canvas.drawCircle(
      node,
      7.0,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  /// Asimetrik konsantrik yörünge yayları & eliptik iz
  void _paintOrbitalArcs(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.88, h * 0.14);
    final baseRadius = w * 0.26;

    final primaryStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    final subtleStroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 0.65),
      math.pi * 0.45,
      math.pi * 0.98,
      false,
      primaryStroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 1.04),
      math.pi * 0.34,
      math.pi * 1.12,
      false,
      subtleStroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 1.44),
      math.pi * 0.52,
      math.pi * 0.84,
      false,
      subtleStroke,
    );

    // Sol alt bölgede sakin eliptik kontur halkası
    canvas.save();
    canvas.translate(w * 0.12, h * 0.66);
    canvas.rotate(-0.22);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.62, height: w * 0.30),
      subtleStroke,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.48, height: w * 0.22),
      subtleStroke..color = strokeColor.withValues(alpha: strokeColor.a * 0.7),
    );
    canvas.restore();

    // Minimal yörünge düğüm noktaları
    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final p1 = Offset(
      center.dx + math.cos(math.pi * 0.84) * baseRadius * 0.65,
      center.dy + math.sin(math.pi * 0.84) * baseRadius * 0.65,
    );
    final p2 = Offset(
      center.dx + math.cos(math.pi * 1.18) * baseRadius * 1.04,
      center.dy + math.sin(math.pi * 1.18) * baseRadius * 1.04,
    );
    canvas.drawCircle(p1, 2.8, dotPaint);
    canvas.drawCircle(p2, 2.2, dotPaint);
  }

  /// İstatistik Hero paneline özel zarif konsantrik yay & ince akış çizgisi
  void _paintHeroOrbit(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.92, h * 0.16);
    final r = math.min(w, h) * 0.62;

    final subtle = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final accent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.62),
      math.pi * 0.50,
      math.pi * 0.72,
      false,
      accent,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.94),
      math.pi * 0.42,
      math.pi * 0.82,
      false,
      subtle,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 1.26),
      math.pi * 0.56,
      math.pi * 0.64,
      false,
      subtle,
    );

    // Alt kenar boyunca süzülen ince organik akış eğrisi
    final flow = Path()
      ..moveTo(-10, h * 0.88)
      ..cubicTo(
        w * 0.30,
        h * 0.72,
        w * 0.62,
        h * 0.98,
        w + 10,
        h * 0.76,
      );
    canvas.drawPath(flow, subtle);

    // Tek bir zarif kesişim noktası
    final dotPos = Offset(
      center.dx + math.cos(math.pi * 0.86) * r * 0.62,
      center.dy + math.sin(math.pi * 0.86) * r * 0.62,
    );
    canvas.drawCircle(dotPos, 2.4, Paint()..color = accentColor);
  }

  /// Seçili kartların sağ köşesinde konsantrik topoğrafik kontur yayları
  void _paintContourWaves(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.96, h * 0.18);
    final baseR = math.min(w, h) * 0.45;

    for (int i = 0; i < 4; i++) {
      final radius = baseR * (0.68 + i * 0.34);
      final paint = Paint()
        ..color = i == 0 ? accentColor : strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.15 : 0.82
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.48,
        math.pi * 0.72,
        false,
        paint,
      );
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
      ..strokeWidth = 1.3
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

/// Layer 1: Tam ekran Ambient Glass atmosfer katmanı.
/// Çok duraklı soğuk tonlu zemin gradyanı, 3 geniş organik atmosferik ışık alanı
/// ve tüm ekranla bütünleşen özgün soyut vektör kompozisyonunu birleştirir.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final AmbientArtStyle artStyle;
  final double? artHeight;

  const AmbientBackground({
    super.key,
    required this.child,
    this.artStyle = AmbientArtStyle.flowLines,
    this.artHeight,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        // 1. Kontrollü tonal derinliğe sahip soğuk atmosferik zemin gradyanı
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.48, 1.0],
                colors: [
                  palette.ambientBaseStart,
                  palette.ambientBaseMid,
                  palette.ambientBaseEnd,
                ],
              ),
            ),
          ),
        ),

        // 2. Üst-sağ geniş organik ışık alanı (Hero ve başlık arkası derinlik)
        Positioned(
          top: -110,
          right: -95,
          width: 390,
          height: 390,
          child: _AmbientOrb(color: palette.ambientPrimary),
        ),

        // 3. Orta-sol organik ışık alanı (Yarış kartları arkasında frosted kırılma)
        Positioned(
          top: 210,
          left: -135,
          width: 360,
          height: 360,
          child: _AmbientOrb(color: palette.ambientSecondary),
        ),

        // 4. Alt-sağ yumuşak ışık alanı (Yüzen cam navigasyon altında atmosferik derinlik)
        Positioned(
          bottom: -90,
          right: -70,
          width: 340,
          height: 340,
          child: _AmbientOrb(color: palette.ambientTertiary),
        ),

        // 5. Özgün soyut vektör grafik katmanı
        if (artStyle != AmbientArtStyle.none)
          if (artHeight != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: artHeight,
              child: AmbientVectorArt(style: artStyle),
            )
          else
            Positioned.fill(
              child: AmbientVectorArt(style: artStyle),
            ),

        // 6. Layer 2 & 3 — Cam yüzeyler ve ekran içeriği
        child,
      ],
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final Color color;

  const _AmbientOrb({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              stops: const [0.0, 0.45, 0.78, 1.0],
              colors: [
                color,
                color.withValues(alpha: color.a * 0.52),
                color.withValues(alpha: color.a * 0.14),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
