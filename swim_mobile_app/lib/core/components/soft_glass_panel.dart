import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'ambient_canvas.dart';

/// Seçici Soft Glass yüzey bileşeni (design.md — Soft Glass + Ambient Glass).
///
/// Hero kartlar, özet panelleri, alt navigasyon ve modallar için:
/// - Kontrollü backdrop blur (isteğe bağlı olarak kapatılabilir)
/// - Yarı saydam katmanlı yüzey ve hafif üst-sol ışık yansıması
/// - 1px zarif parlak kenarlık ve yumuşak atmosferik gölge
/// - Opsiyonel soyut vektör grafik katmanı ([artStyle])
class SoftGlassPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final bool enableBlur;
  final double blurSigma;
  final bool strongGlass;
  final AmbientArtStyle artStyle;
  final Color? borderColor;
  final VoidCallback? onTap;

  const SoftGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppRadius.cardRadius,
    this.enableBlur = true,
    this.blurSigma = 14.0,
    this.strongGlass = false,
    this.artStyle = AmbientArtStyle.none,
    this.borderColor,
    this.onTap,
  });

  @override
  State<SoftGlassPanel> createState() => _SoftGlassPanelState();
}

class _SoftGlassPanelState extends State<SoftGlassPanel> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disableMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final surfaceColor =
        widget.strongGlass ? palette.surfaceGlassStrong : palette.surfaceGlass;

    final innerDecoration = BoxDecoration(
      borderRadius: widget.borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(palette.glassSheen, surfaceColor),
          surfaceColor,
        ],
      ),
      border: Border.all(
        color: widget.borderColor ?? palette.glassBorder,
        width: 1.0,
      ),
    );

    Widget content = Stack(
      children: [
        if (widget.artStyle != AmbientArtStyle.none)
          Positioned.fill(
            child: AmbientVectorArt(
              style: widget.artStyle,
              opacity: 0.95,
            ),
          ),
        Padding(
          padding: widget.padding,
          child: widget.child,
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
      decoration: innerDecoration,
      child: content,
    );

    if (widget.enableBlur) {
      surface = ClipRRect(
        borderRadius: widget.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
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
        boxShadow: [
          BoxShadow(
            color: palette.softShadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
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

/// Üst çubuk aksiyonları için zarif dairesel Soft Glass buton.
/// İnce hatlı ikonografi ve rahat dokunma alanı (40x40) sağlar.
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

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: palette.surfaceGlassStrong,
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.isDark ? palette.border : palette.glassBorder,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.softShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
                spreadRadius: -2,
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
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
