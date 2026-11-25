import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// API uyumluluğu için korunan soyut stil tanımı.
enum AmbientArtStyle {
  flowLines,
  orbitalArcs,
  heroOrbit,
  contourWaves,
  emptyOrbit,
  none,
}

/// Arka plan veya panellerde vektör çizgi çizmez; mevcut API uyumluluğunu korur.
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
    return const SizedBox.shrink();
  }
}

/// Layer 1: Sakin, temiz ve belirgin derinlikli Ambient Glass ekran arka planı.
///
/// - Dikey taban gradyanı: #CFDAE1 (üst) → #B4C4CF (0.45) → #98ABB9 (alt)
/// - 3 büyük (700+ px), eliptik ve hafif döndürülmüş, 6 duraklı yumuşak ışık alanı:
///   A. Üst-sağ (istatistik paneli arkası): parlak buz-beyazı ışık #EEF3F6 @ 0.75
///   B. Orta-sol (ilk kart arkası): çelik mavisi #7F9BB0 @ 0.45
///   C. Alt-sağ (navigasyon arkası): derin #273746 @ 0.22
/// - Sıfır gren/nokta, sıfır vektör çizgi, sıfır leke veya keskin kenar.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final AmbientArtStyle artStyle;
  final double artHeight;
  final double fieldAlphaBoost;
  final double topAccentTintAlpha;

  const AmbientBackground({
    super.key,
    required this.child,
    this.artStyle = AmbientArtStyle.none,
    this.artHeight = 165,
    this.fieldAlphaBoost = 0.0,
    this.topAccentTintAlpha = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (palette.isCrispCardTheme) {
      return ColoredBox(
        color: palette.background,
        child: child,
      );
    }
    final fieldAColor = palette.ambientFieldA.withValues(
      alpha: (palette.ambientFieldA.a + fieldAlphaBoost).clamp(0.0, 1.0),
    );
    final fieldBColor = palette.ambientFieldB.withValues(
      alpha: (palette.ambientFieldB.a + fieldAlphaBoost).clamp(0.0, 1.0),
    );

    return Stack(
      children: [
        // 1. Dikey taban gradyanı (paletten ambientTop → ambientMid @ 0.45 → ambientBottom)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      palette.ambientTop,
                      palette.ambientMid,
                      palette.ambientBottom,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // 2. Field A — Üst-sağ (istatistik paneli arkası)
        Positioned(
          top: -260,
          right: -250,
          width: 760,
          height: 760,
          child: _SmoothEllipticalLightField(
            color: fieldAColor,
            angle: -0.28,
            scaleX: 1.24,
            scaleY: 0.90,
          ),
        ),

        // 3. Field B — Orta-sol (ilk kart arkası)
        Positioned(
          top: 120,
          left: -340,
          width: 780,
          height: 780,
          child: _SmoothEllipticalLightField(
            color: fieldBColor,
            angle: 0.32,
            scaleX: 1.18,
            scaleY: 0.92,
          ),
        ),

        if (topAccentTintAlpha > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 240,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.accent.withValues(
                          alpha: topAccentTintAlpha.clamp(0.0, 1.0),
                        ),
                        palette.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 4. Field C — Alt-sağ (navigasyon arkası)
        Positioned(
          bottom: -330,
          right: -260,
          width: 780,
          height: 780,
          child: _SmoothEllipticalLightField(
            color: palette.ambientFieldC,
            angle: -0.22,
            scaleX: 1.28,
            scaleY: 0.88,
          ),
        ),

        // 5. Mevcut ekran içeriği
        child,
      ],
    );
  }
}

/// 6 duraklı ease-out opaklık eğrisine sahip, hafif eliptik ve döndürülmüş geniş ışık alanı.
/// Hiçbir keskin kenar veya halka oluşturmaz.
class _SmoothEllipticalLightField extends StatelessWidget {
  final Color color;
  final double angle;
  final double scaleX;
  final double scaleY;

  const _SmoothEllipticalLightField({
    required this.color,
    required this.angle,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  Widget build(BuildContext context) {
    final baseAlpha = color.a;
    final matrix = Matrix4.identity()
      ..rotateZ(angle)
      ..scaleByDouble(scaleX, scaleY, 1.0, 1.0);

    return IgnorePointer(
      child: RepaintBoundary(
        child: Transform(
          alignment: Alignment.center,
          transform: matrix,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                radius: 0.5,
                stops: const [0.0, 0.20, 0.40, 0.60, 0.80, 1.0],
                colors: [
                  color.withValues(alpha: baseAlpha * 1.0),
                  color.withValues(alpha: baseAlpha * 0.70),
                  color.withValues(alpha: baseAlpha * 0.45),
                  color.withValues(alpha: baseAlpha * 0.25),
                  color.withValues(alpha: baseAlpha * 0.10),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
