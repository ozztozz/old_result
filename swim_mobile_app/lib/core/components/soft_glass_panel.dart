import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'ambient_canvas.dart';

/// Katman 2 cam yüzey hiyerarşisi.
enum GlassTier {
  /// Seviye 1: Üst istatistik & vitrin panelleri (Hero glass)
  hero,

  /// Seviye 2: Müsabaka ve içerik kartları (Frosted card glass)
  card,

  /// Seviye 3: Arama çubuğu, filtreler ve ikincil yüzeyler (Lightest glass)
  subtle,

  /// Yüzen alt navigasyon yüzeyi (bu adımda dokunulmaz)
  dock,
}

/// Seçici Soft Glass yüzey bileşeni (3 kademeli gerçek buzlu cam malzemesi).
///
/// [level] (1, 2, 3) verilirse doğrudan ilgili cam seviyesini uygular;
/// verilmezse mevcut [tier] değerinden eşlenir (API uyumluluğu korunur).
class SoftGlassPanel extends StatefulWidget {
  final Widget child;
  final GlassTier tier;
  final int? level;
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
    this.level,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppRadius.cardRadius,
    this.enableBlur = true,
    this.blurSigma,
    this.artStyle = AmbientArtStyle.none,
    this.ambientGlowBehind = false,
    this.borderColor,
    this.onTap,
  }) : assert(level == null || (level >= 1 && level <= 3));

  @override
  State<SoftGlassPanel> createState() => _SoftGlassPanelState();
}

class _SoftGlassPanelState extends State<SoftGlassPanel> {
  bool _pressed = false;

  bool get _isDock => widget.level == null && widget.tier == GlassTier.dock;

  int get _resolvedLevel {
    if (widget.level != null) return widget.level!;
    switch (widget.tier) {
      case GlassTier.hero:
        return 1;
      case GlassTier.card:
        return 2;
      case GlassTier.subtle:
        return 3;
      case GlassTier.dock:
        return 0;
    }
  }

  double get _effectiveBlur {
    final raw = widget.blurSigma ??
        (_isDock
            ? 20.0
            : switch (_resolvedLevel) {
                1 => 24.0,
                2 => 16.0,
                _ => 10.0,
              });
    return raw.clamp(0.0, 28.0);
  }

  BoxDecoration _surfaceDecoration(AppColorPalette palette) {
    final isDark = palette.isDark;

    if (_isDock) {
      return BoxDecoration(
        borderRadius: widget.borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              palette.glassSheen.withValues(alpha: 0.45),
              palette.surfaceGlassStrong,
            ),
            palette.surfaceGlassStrong,
          ],
        ),
      );
    }

    switch (_resolvedLevel) {
      // LEVEL 1 — Statistics panel (hero glass)
      case 1:
        return BoxDecoration(
          borderRadius: widget.borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.06),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0.12),
                  ],
          ),
          border: Border.all(
            color: widget.borderColor ??
                Colors.white.withValues(alpha: isDark ? 0.24 : 0.45),
            width: 1.0,
          ),
        );

      // LEVEL 2 — Competition cards
      case 2:
        return BoxDecoration(
          borderRadius: widget.borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.13),
                    Colors.white.withValues(alpha: 0.06),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.26),
                    Colors.white.withValues(alpha: 0.14),
                  ],
          ),
          border: Border.all(
            color: widget.borderColor ??
                Colors.white.withValues(alpha: isDark ? 0.18 : 0.30),
            width: 1.0,
          ),
        );

      // LEVEL 3 — Search bar, subtle controls
      default:
        return BoxDecoration(
          borderRadius: widget.borderRadius,
          color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.14),
          border: Border.all(
            color: widget.borderColor ??
                Colors.white.withValues(alpha: isDark ? 0.16 : 0.25),
            width: 1.0,
          ),
        );
    }
  }

  List<BoxShadow> _shadows(AppColorPalette palette) {
    if (_isDock) {
      return [
        BoxShadow(
          color: palette.softShadow,
          blurRadius: 28,
          offset: const Offset(0, 12),
          spreadRadius: -4,
        ),
      ];
    }

    switch (_resolvedLevel) {
      case 1:
        return [
          BoxShadow(
            color: const Color(0xFF273746).withValues(alpha: 0.18),
            blurRadius: 50,
            offset: const Offset(0, 20),
          ),
        ];
      case 2:
        return [
          BoxShadow(
            color: const Color(0xFF273746).withValues(alpha: 0.10),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ];
      default:
        // Level 3: No shadow
        return const [];
    }
  }

  double? _topHighlightAlpha(AppColorPalette palette) {
    if (_isDock) return palette.glassSheen.a;
    switch (_resolvedLevel) {
      case 1:
        return palette.isDark ? 0.32 : 0.60;
      case 2:
        return palette.isDark ? 0.22 : 0.40;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disableMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final topHighlightAlpha = _topHighlightAlpha(palette);

    Widget content = Stack(
      children: [
        if (widget.artStyle != AmbientArtStyle.none)
          Positioned.fill(
            child: AmbientVectorArt(
              style: widget.artStyle,
              opacity: _resolvedLevel == 1 ? 1.0 : 0.85,
            ),
          ),

        // Üst kenarda 1px iç ışık yansıması (Level 1: 0.60, Level 2: 0.40)
        if (topHighlightAlpha != null)
          Positioned(
            top: 0,
            left: 1,
            right: 1,
            height: 1.0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: topHighlightAlpha * 0.25),
                      Colors.white.withValues(alpha: topHighlightAlpha),
                      Colors.white.withValues(alpha: topHighlightAlpha * 0.25),
                    ],
                  ),
                ),
              ),
            ),
          ),

        Padding(
          padding: widget.padding,
          child: widget.child,
        ),

        // Yalnızca dock için mevcut kenarlık çizimini koru
        if (_isDock)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassRimPainter(
                  borderRadius: widget.borderRadius,
                  startColor: widget.borderColor ?? palette.glassBorder,
                  endColor: widget.borderColor?.withValues(alpha: 0.35) ??
                      palette.glassBorderSubtle,
                  strokeWidth: 0.8,
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
      decoration: _surfaceDecoration(palette),
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

    final shadows = _shadows(palette);
    Widget panel = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: shadows.isEmpty ? null : shadows,
      ),
      child: surface,
    );

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

/// Dock yüzeyi için ince gradyan kenarlık çizicisi
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

/// Üst çubuk aksiyonları için Seviye 3 (Level 3) dairesel Soft Glass buton.
/// Fill: white @ 0.14, Blur: sigma 10, Border: 1px white @ 0.25, Gölgesiz.
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
    final isDark = palette.isDark;

    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.25),
                  width: 1.0,
                ),
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
