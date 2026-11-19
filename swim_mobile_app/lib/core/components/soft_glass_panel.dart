import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'ambient_canvas.dart';

/// Katman 2 cam yüzey hiyerarşisi (DESIGN_REFINEMENT — Glassmorphism).
/// Her kartı aynı şeffaflıkta yapmak yerine önem sırasına göre yüzey derinliği tanımlar.
enum GlassTier {
  /// Üst istatistik & öne çıkan vitrin panelleri (en belirgin frosted derinlik & ışık yansıması)
  hero,

  /// Müsabaka ve içerik kartları (ortamla bütünleşik yarı saydam buzlu cam)
  card,

  /// Arama çubuğu ve ikincil kontrol yüzeyleri (daha sakin, girintili cam yüzey)
  subtle,

  /// Yüzen alt navigasyon ve modal yüzeyler (yoğun frosted cam & güçlü blur)
  dock,
}

/// Seçici Soft Glass yüzey bileşeni.
///
/// - Gerçek `BackdropFilter` buzlu cam bulanıklığı
/// - Üst-sol ışık kırılmalı gradyan cam kenarlığı (`_GlassRimPainter`)
/// - İnce üst iç ışık yansıması (specular highlight)
/// - Opsiyonel panel arkası ambient ışık alanı (`ambientGlowBehind`)
/// - Opsiyonel özgün vektör çizim katmanı (`artStyle`)
class SoftGlassPanel extends StatefulWidget {
  final Widget child;
  final GlassTier tier;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final bool enableBlur;
  final double? blurSigma;
  final AmbientArtStyle artStyle;
  final bool ambientGlowBehind;
  final Color? borderColor;
  final VoidCallback? onTap;

  const SoftGlassPanel({
    super.key,
    required this.child,
    this.tier = GlassTier.hero,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppRadius.cardRadius,
    this.enableBlur = true,
    this.blurSigma,
    this.artStyle = AmbientArtStyle.none,
    this.ambientGlowBehind = false,
    this.borderColor,
    this.onTap,
  });

  @override
  State<SoftGlassPanel> createState() => _SoftGlassPanelState();
}

class _SoftGlassPanelState extends State<SoftGlassPanel> {
  bool _pressed = false;

  double get _effectiveBlur {
    if (widget.blurSigma != null) return widget.blurSigma!;
    switch (widget.tier) {
      case GlassTier.hero:
        return 18.0;
      case GlassTier.card:
        return 12.0;
      case GlassTier.subtle:
        return 10.0;
      case GlassTier.dock:
        return 20.0;
    }
  }

  List<Color> _surfaceGradient(AppColorPalette palette) {
    switch (widget.tier) {
      case GlassTier.hero:
        return [palette.heroGlassTop, palette.heroGlassBottom];
      case GlassTier.card:
        return [palette.cardGlassTop, palette.cardGlassBottom];
      case GlassTier.subtle:
        return [
          palette.surfaceGlass,
          palette.surfaceGlass.withValues(alpha: palette.surfaceGlass.a * 0.85),
        ];
      case GlassTier.dock:
        return [
          Color.alphaBlend(palette.glassSheen.withValues(alpha: 0.45), palette.surfaceGlassStrong),
          palette.surfaceGlassStrong,
        ];
    }
  }

  List<BoxShadow> _shadows(AppColorPalette palette) {
    switch (widget.tier) {
      case GlassTier.hero:
        return [
          BoxShadow(
            color: palette.softShadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: palette.softShadow.withValues(alpha: palette.softShadow.a * 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
      case GlassTier.card:
        return [
          BoxShadow(
            color: palette.softShadow.withValues(alpha: palette.softShadow.a * 0.85),
            blurRadius: 18,
            offset: const Offset(0, 7),
            spreadRadius: -5,
          ),
        ];
      case GlassTier.subtle:
        return [
          BoxShadow(
            color: palette.softShadow.withValues(alpha: palette.softShadow.a * 0.55),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ];
      case GlassTier.dock:
        return [
          BoxShadow(
            color: palette.softShadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disableMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final gradientColors = _surfaceGradient(palette);
    final rimStart = widget.borderColor ?? palette.glassBorder;
    final rimEnd = widget.borderColor?.withValues(alpha: 0.35) ?? palette.glassBorderSubtle;

    Widget content = Stack(
      children: [
        // Özgün soyut vektör katmanı
        if (widget.artStyle != AmbientArtStyle.none)
          Positioned.fill(
            child: AmbientVectorArt(
              style: widget.artStyle,
              opacity: widget.tier == GlassTier.hero ? 1.0 : 0.85,
            ),
          ),

        // Üst kenarda ince iç ışık yansıması (soft inner specular highlight)
        if (widget.tier != GlassTier.subtle)
          Positioned(
            top: 0,
            left: 18,
            right: 18,
            height: 1.0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      palette.glassSheen.withValues(
                        alpha: widget.tier == GlassTier.card
                            ? palette.glassSheen.a * 0.65
                            : palette.glassSheen.a,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Asıl içerik
        Padding(
          padding: widget.padding,
          child: widget.child,
        ),

        // Üst-soldan alt-sağa zarif ışık kırılmalı cam kenarlığı
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GlassRimPainter(
                borderRadius: widget.borderRadius,
                startColor: rimStart,
                endColor: rimEnd,
                strokeWidth: widget.tier == GlassTier.dock ? 0.8 : 1.0,
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onHighlightChanged: (v) {
            if (!disableMotion && mounted) {
              setState(() => _pressed = v);
            }
          },
          child: content,
        ),
      );
    }

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: content,
    );

    if (widget.enableBlur) {
      surface = ClipRRect(
        borderRadius: widget.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _effectiveBlur,
            sigmaY: _effectiveBlur,
          ),
          child: surface,
        ),
      );
    } else {
      surface = ClipRRect(
        borderRadius: widget.borderRadius,
        child: surface,
      );
    }

    Widget panel = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: _shadows(palette),
      ),
      child: surface,
    );

    // Hero panel arkasında yumuşak ambient ışık katmanı
    if (widget.ambientGlowBehind) {
      panel = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -16,
            right: -12,
            width: 220,
            height: 140,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: RadialGradient(
                      colors: [
                        palette.heroAmbientGlow,
                        palette.heroAmbientGlow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -14,
            left: -10,
            width: 180,
            height: 110,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
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
          panel,
        ],
      );
    }

    if (widget.onTap != null && !disableMotion) {
      panel = AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: panel,
      );
    }

    return panel;
  }
}

/// Üst-soldan alt-sağa ışık kırılması oluşturan ince gradyan cam kenarlığı çizicisi
class _GlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Color startColor;
  final Color endColor;
  final double strokeWidth;

  const _GlassRimPainter({
    required this.borderRadius,
    required this.startColor,
    required this.endColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(strokeWidth / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [startColor, endColor],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Üst çubuk aksiyonları için zarif dairesel Soft Glass buton.
/// Frosted cam yüzeyi, ince parlak kenarlık ve rahat dokunma alanı (40x40) sunar.
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? iconColor;
  final double iconSize;

  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.iconColor,
    this.iconSize = 19,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.cardGlassTop,
                    palette.cardGlassBottom,
                  ],
                ),
                border: Border.all(
                  color: palette.glassBorder,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.softShadow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -3,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor ?? palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
