import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Uygulamanın ölçülü, sakin soyut grafik imzası (SECOND DESIGN REFINEMENT).
/// Teknik plan/duvar kağıdı yerine yalnızca seçili alanlarda fısıltı düzeyinde
/// organik akış çizgisi ve ışık difüzyonu kullanır.
enum AmbientArtStyle {
  /// Üst başlık atmosferinde uçları eriyen 2 zarif akışkan eğri
  flowLines,

  /// Keşfet / Profil üst alanında tek akışkan ipek eğri
  orbitalArcs,

  /// Hero panel alt kenarında metinle hiç kesişmeyen tek fısıltı çizgi
  heroOrbit,

  /// Seçili tek bir kartta çok hafif köşe akış detayı
  contourWaves,

  /// Boş durum ikonu arkasında sakin minimal yörünge
  emptyOrbit,

  none,
}

/// Hafif, yüksek performanslı vektör imza katmanı.
/// Kenarlara doğru şeffaflaşan fırça geçişleriyle içerikle asla çatışmaz.
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

  Paint _fadingLinePaint(Size size, Color color, double width) {
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: const [0.0, 0.25, 0.78, 1.0],
        colors: [
          color.withValues(alpha: 0.0),
          color,
          color.withValues(alpha: color.a * 0.7),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    switch (style) {
      case AmbientArtStyle.flowLines:
        _paintFlowSignature(canvas, size);
        break;
      case AmbientArtStyle.orbitalArcs:
        _paintSingleSilkRibbon(canvas, size);
        break;
      case AmbientArtStyle.heroOrbit:
        _paintHeroWhisper(canvas, size);
        break;
      case AmbientArtStyle.contourWaves:
        _paintSubtleCornerWave(canvas, size);
        break;
      case AmbientArtStyle.emptyOrbit:
        _paintEmptyOrbit(canvas, size);
        break;
      case AmbientArtStyle.none:
        break;
    }
  }

  /// Yalnızca üst atmosfer şeridinde uçları eriyen 2 zarif akışkan çizgi
  void _paintFlowSignature(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path1 = Path()
      ..moveTo(-w * 0.04, h * 0.52)
      ..cubicTo(
        w * 0.28,
        h * 0.16,
        w * 0.62,
        h * 0.84,
        w * 1.04,
        h * 0.34,
      );
    canvas.drawPath(path1, _fadingLinePaint(size, accentColor, 1.15));

    final path2 = Path()
      ..moveTo(-w * 0.02, h * 0.68)
      ..cubicTo(
        w * 0.32,
        h * 0.34,
        w * 0.66,
        h * 0.96,
        w * 1.02,
        h * 0.50,
      );
    canvas.drawPath(path2, _fadingLinePaint(size, strokeColor, 0.85));
  }

  /// Keşfet / Profil üst alanında tek sakin organik eğri
  void _paintSingleSilkRibbon(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.06, h * 0.72)
      ..cubicTo(
        w * 0.36,
        h * 0.22,
        w * 0.70,
        h * 0.78,
        w * 1.04,
        h * 0.26,
      );
    canvas.drawPath(path, _fadingLinePaint(size, accentColor, 1.05));
  }

  /// Hero istatistik paneli alt kenarında rakamlara hiç değmeyen fısıltı çizgi
  void _paintHeroWhisper(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.04, h * 0.94)
      ..cubicTo(
        w * 0.34,
        h * 0.86,
        w * 0.68,
        h * 0.98,
        w * 0.96,
        h * 0.88,
      );
    canvas.drawPath(path, _fadingLinePaint(size, strokeColor, 0.9));
  }

  /// Seçili kartın sağ-alt köşesinde çok sakin tek akış detayı
  void _paintSubtleCornerWave(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.56, h * 0.96)
      ..quadraticBezierTo(w * 0.80, h * 0.76, w * 1.02, h * 0.84);
    canvas.drawPath(path, _fadingLinePaint(size, strokeColor, 0.9));
  }

  /// Boş durum ikonu için tek sade yörünge halkası
  void _paintEmptyOrbit(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.45;

    canvas.drawCircle(
      center,
      maxR * 0.82,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.82),
      -math.pi * 0.65,
      math.pi * 0.45,
      false,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientVectorPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.accentColor != accentColor;
  }
}

/// Layer 1: Sakin, geniş ve derinlikli Ambient Glass atmosfer ortamı.
/// Düz gri/beyaz veya yoğun çizgi kalabalığı yerine büyük organik ışık difüzyonları,
/// yumuşak mavi-gri renk alanları ve yalnızca üst kenarda fısıltı düzeyinde imza eğrisi.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final AmbientArtStyle artStyle;
  final double artHeight;

  const AmbientBackground({
    super.key,
    required this.child,
    this.artStyle = AmbientArtStyle.flowLines,
    this.artHeight = 165,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Stack(
      children: [
        // 1. Soğuk mavi-gri kontrollü atmosferik zemin gradyanı
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.50, 1.0],
                colors: [
                  palette.ambientBaseStart,
                  palette.ambientBaseMid,
                  palette.ambientBaseEnd,
                ],
              ),
            ),
          ),
        ),

        // 2. Üst-sol yumuşak atmosferik ışık difüzyonu (doğal üst ışık kaynağı)
        Positioned(
          top: -130,
          left: -100,
          width: 420,
          height: 380,
          child: _SoftLightField(color: palette.ambientLightBeam),
        ),

        // 3. Üst-sağ geniş organik Mist/Steel renk alanı (Hero panel arkasında derinlik)
        Positioned(
          top: -70,
          right: -130,
          width: 460,
          height: 440,
          child: _SoftLightField(color: palette.ambientPrimary),
        ),

        // 4. Orta-sol yumuşak Steel renk alanı (Yarış kartları altında buzlu kırılma)
        Positioned(
          top: 240,
          left: -150,
          width: 420,
          height: 440,
          child: _SoftLightField(color: palette.ambientSecondary),
        ),

        // 5. Alt-sağ sakin atmosfer alanı (Yüzen cam navigasyon altında ton geçişi)
        Positioned(
          bottom: -110,
          right: -90,
          width: 420,
          height: 400,
          child: _SoftLightField(color: palette.ambientTertiary),
        ),

        // 6. Yalnızca üst kenarda içerikle çakışmayan fısıltı düzeyinde vektör imza
        if (artStyle != AmbientArtStyle.none)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: artHeight,
            child: AmbientVectorArt(style: artStyle),
          ),

        // 7. Layer 2 & 3 — Frosted cam yüzeyler ve içerik
        child,
      ],
    );
  }
}

/// Keskin sınırı olmayan geniş organik atmosferik ışık difüzyonu
class _SoftLightField extends StatelessWidget {
  final Color color;

  const _SoftLightField({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              stops: const [0.0, 0.35, 0.68, 1.0],
              colors: [
                color,
                color.withValues(alpha: color.a * 0.58),
                color.withValues(alpha: color.a * 0.18),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
