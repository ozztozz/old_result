import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Uygulamanın soyut grafik stilleri.
/// Ekran arka planında yalnızca üst-sağ boş alanda düşük opaklıklı tek akış çizgisi kullanılır;
/// eşmerkezli daire veya kontur çizgileri kullanılmaz.
enum AmbientArtStyle {
  flowLines,
  orbitalArcs,
  heroOrbit,
  contourWaves,
  emptyOrbit,
  none,
}

/// Hafif vektör imza katmanı.
/// Metin ve kart alanlarına girmeden yalnızca boş üst-sağ köşede tek zarif akış çizgisi çizer.
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
    if (style == AmbientArtStyle.none ||
        style == AmbientArtStyle.heroOrbit ||
        style == AmbientArtStyle.contourWaves ||
        style == AmbientArtStyle.emptyOrbit) {
      return const SizedBox.shrink();
    }

    final palette = context.palette;
    final baseAccent = accentColor ?? palette.vectorAccent;

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _UpperRightFlowLinePainter(
            color: baseAccent.withValues(
              alpha: (0.22 * opacity).clamp(0.0, 1.0),
            ),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Üst-sağ boş alanda, başlık metni ve kartlara hiç değmeyen tek akışkan eğri
class _UpperRightFlowLinePainter extends CustomPainter {
  final Color color;

  const _UpperRightFlowLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;

    final start = Offset(w * 0.66, -4);
    final end = Offset(w * 1.03, h * 0.13);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        w * 0.74,
        h * 0.055,
        w * 0.89,
        h * 0.045,
        end.dx,
        end.dy,
      );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.35, 0.75, 1.0],
        colors: [
          color.withValues(alpha: 0.0),
          color,
          color.withValues(alpha: color.a * 0.7),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromPoints(start, end));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UpperRightFlowLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Layer 1: Ekran Arka Planı (Cool Sophisticated Ambient Environment)
///
/// - Dikey taban gradyanı: #DCE4E8 (üst) → #B9C7D1 (alt) [koyu modda derin slate]
/// - 3 büyük, organik, asimetrik ve 90–105px bulanıklaştırılmış renk alanı:
///   a. Üst-sağ (istatistik paneli arkası): #657D91 @ ~%35
///   b. Orta-sol (ilk yarış kartı arkası): #AABBC6 @ ~%45
///   c. Alt-sağ (navigasyon yakını): #273746 @ ~%18
/// - Gradyan bantlaşmasını önleyen %2.5 opaklıklı ince film gren (noise) katmanı
/// - Üst-sağ boş köşede metin ve kartlara değmeyen tek zarif akış çizgisi
class AmbientBackground extends StatefulWidget {
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
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  static ui.Image? _cachedNoiseTile;
  static Future<ui.Image>? _noiseFuture;

  @override
  void initState() {
    super.initState();
    _ensureNoiseLoaded();
  }

  void _ensureNoiseLoaded() {
    if (_cachedNoiseTile != null) return;
    _noiseFuture ??= _generateNoiseTile();
    _noiseFuture!.then((img) {
      _cachedNoiseTile = img;
      if (mounted) setState(() {});
    });
  }

  static Future<ui.Image> _generateNoiseTile() {
    const int size = 128;
    final bytes = Uint8List(size * size * 4);
    final rng = math.Random(202604);

    for (int i = 0; i < size * size; i++) {
      final v = rng.nextInt(256);
      final idx = i * 4;
      bytes[idx] = v;
      bytes[idx + 1] = v;
      bytes[idx + 2] = v;
      // ~2.7% opaklık (7 / 255) — bantlaşmayı önleyen çok ince gren
      bytes[idx + 3] = 7;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = palette.isDark;
    final isCoolLight = palette is CoolSophisticatedLightPalette;

    final topColor = isCoolLight
        ? const Color(0xFFDCE4E8)
        : (isDark
            ? Color.lerp(palette.background, const Color(0xFF20303E), 0.35)!
            : const Color(0xFFDCE4E8));
    final bottomColor = isCoolLight
        ? const Color(0xFFB9C7D1)
        : (isDark
            ? Color.lerp(palette.background, const Color(0xFF0C141C), 0.45)!
            : const Color(0xFFB9C7D1));

    // Koyu temada da aynı 3 organik alanın atmosferik dengesini koru
    final topRightColor = isDark
        ? const Color(0xFF657D91).withValues(alpha: 0.30)
        : const Color(0xFF657D91).withValues(alpha: 0.35);
    final midLeftColor = isDark
        ? const Color(0xFFAABBC6).withValues(alpha: 0.18)
        : const Color(0xFFAABBC6).withValues(alpha: 0.45);
    final bottomRightColor = isDark
        ? const Color(0xFF0A1118).withValues(alpha: 0.48)
        : const Color(0xFF273746).withValues(alpha: 0.18);

    return Stack(
      children: [
        // 1. Dikey atmosferik taban gradyanı (#DCE4E8 → #B9C7D1)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, bottomColor],
              ),
            ),
          ),
        ),

        // 2. 3 büyük, organik, asimetrik ve 90–105px bulanıklaştırılmış renk alanı
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _OrganicAmbientFieldsPainter(
                  topRightColor: topRightColor,
                  midLeftColor: midLeftColor,
                  bottomRightColor: bottomRightColor,
                ),
              ),
            ),
          ),
        ),

        // 3. Üst-sağ boş köşede metin ve kartlara değmeyen tek düşük opaklıklı akış çizgisi
        if (widget.artStyle != AmbientArtStyle.none)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _UpperRightFlowLinePainter(
                    color: (isDark
                            ? const Color(0xFFAABBC6)
                            : const Color(0xFF657D91))
                        .withValues(alpha: isDark ? 0.16 : 0.22),
                  ),
                ),
              ),
            ),
          ),

        // 4. Gradyan bantlaşmasını önleyen %2.5 ince gren (noise) dokusu
        if (_cachedNoiseTile != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GrainOverlayPainter(noiseTile: _cachedNoiseTile!),
                ),
              ),
            ),
          ),

        // 5. Mevcut ekran içeriği (kartlar, tipografi, navigasyon)
        widget.child,
      ],
    );
  }
}

/// 3 asimetrik organik renk alanını Gaussian blur (92–106px) ile çizen ressam.
/// Kusursuz daire veya tekrar eden desen içermez; kenarları tamamen yumuşaktır.
class _OrganicAmbientFieldsPainter extends CustomPainter {
  final Color topRightColor;
  final Color midLeftColor;
  final Color bottomRightColor;

  const _OrganicAmbientFieldsPainter({
    required this.topRightColor,
    required this.midLeftColor,
    required this.bottomRightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // a. Üst-sağ, istatistik paneli arkası: #657D91 (~%35) — asimetrik organik form
    final topRightPath = Path()
      ..moveTo(w * 0.48, h * 0.06)
      ..cubicTo(w * 0.66, -h * 0.02, w * 0.96, h * 0.02, w * 1.10, h * 0.14)
      ..cubicTo(w * 1.16, h * 0.25, w * 0.98, h * 0.34, w * 0.78, h * 0.31)
      ..cubicTo(w * 0.56, h * 0.29, w * 0.38, h * 0.17, w * 0.48, h * 0.06)
      ..close();

    canvas.drawPath(
      topRightPath,
      Paint()
        ..color = topRightColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 94),
    );

    // b. Orta-sol, ilk müsabaka kartı arkası: #AABBC6 (~%45) — geniş organik dalga formu
    final midLeftPath = Path()
      ..moveTo(-w * 0.14, h * 0.36)
      ..cubicTo(w * 0.08, h * 0.30, w * 0.44, h * 0.35, w * 0.54, h * 0.47)
      ..cubicTo(w * 0.60, h * 0.58, w * 0.34, h * 0.69, w * 0.08, h * 0.65)
      ..cubicTo(-w * 0.12, h * 0.62, -w * 0.24, h * 0.46, -w * 0.14, h * 0.36)
      ..close();

    canvas.drawPath(
      midLeftPath,
      Paint()
        ..color = midLeftColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 106),
    );

    // c. Alt-sağ, yüzen navigasyon yakını: #273746 (~%18) — yatay asimetrik derinlik alanı
    final bottomRightPath = Path()
      ..moveTo(w * 0.38, h * 0.80)
      ..cubicTo(w * 0.58, h * 0.72, w * 0.94, h * 0.73, w * 1.12, h * 0.84)
      ..cubicTo(w * 1.18, h * 0.96, w * 0.92, h * 1.07, w * 0.64, h * 1.03)
      ..cubicTo(w * 0.42, h * 1.00, w * 0.26, h * 0.89, w * 0.38, h * 0.80)
      ..close();

    canvas.drawPath(
      bottomRightPath,
      Paint()
        ..color = bottomRightColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 98),
    );
  }

  @override
  bool shouldRepaint(covariant _OrganicAmbientFieldsPainter oldDelegate) {
    return oldDelegate.topRightColor != topRightColor ||
        oldDelegate.midLeftColor != midLeftColor ||
        oldDelegate.bottomRightColor != bottomRightColor;
  }
}

class _GrainOverlayPainter extends CustomPainter {
  final ui.Image noiseTile;

  const _GrainOverlayPainter({required this.noiseTile});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(
        noiseTile,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList(const [
          1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        ]),
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GrainOverlayPainter oldDelegate) {
    return oldDelegate.noiseTile != noiseTile;
  }
}
