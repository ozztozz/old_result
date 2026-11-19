import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';
import 'ambient_canvas.dart';

/// Katman 2 cam yüzey hiyerarşisi.
enum GlassTier {
  /// Seviye 1: Üst istatistik, vitrin panelleri ve alt pencereler (Hero glass)
  hero,

  /// Seviye 2: Müsabaka ve içerik kartları (Frosted card glass)
  card,

  /// Seviye 3: Arama çubuğu, filtre çipleri, rozetler ve yuvarlak butonlar (Lightest glass)
  subtle,

  /// Yüzen koyu yarı saydam alt navigasyon yüzeyi
  dock,
}

/// Uygulamadaki tek merkezi Soft Glass yüzey bileşeni (`BackdropFilter` yalnızca burada bulunur).
///
/// - [level] (`1`, `2`, `3`) verilirse doğrudan ilgili cam seviyesini uygular;
///   verilmezse [tier] değerinden eşlenir (API uyumluluğu korunur).
/// - [shape] (`BoxShape.rectangle` veya `BoxShape.circle`) destekler.
/// - [fillAlphaOverride] / [borderAlphaOverride] / [fillColorOverride] + [animationDuration]
///   ile odak veya aktif durum geçişlerini destekler.
/// - Platform "reduce transparency / high contrast" veya [reduceTransparency] aktifse
///   blur kapatılır ve paletten `0.88` opaklıklı düz yüzeye geçilir.
class SoftGlassPanel extends StatefulWidget {
  /// Uygulama genelinde saydamlık azaltma geri dönüşünü zorlamak için bayrak.
  static bool forceReduceTransparency = false;

  final Widget child;
  final GlassTier tier;
  final int? level;
  final BoxShape shape;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final bool enableBlur;
  final bool reduceTransparency;
  final double? blurSigma;
  final AmbientArtStyle artStyle;
  final bool ambientGlowBehind;
  final Color? borderColor;
  final Color? fillColorOverride;
  final double? fillAlphaOverride;
  final double? borderAlphaOverride;
  final List<BoxShadow>? shadowsOverride;
  final Duration animationDuration;
  final VoidCallback? onTap;

  const SoftGlassPanel({
    super.key,
    required this.child,
    this.tier = GlassTier.hero,
    this.level,
    this.shape = BoxShape.rectangle,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppRadius.cardRadius,
    this.enableBlur = true,
    this.reduceTransparency = false,
    this.blurSigma,
    this.artStyle = AmbientArtStyle.none,
    this.ambientGlowBehind = false,
    this.borderColor,
    this.fillColorOverride,
    this.fillAlphaOverride,
    this.borderAlphaOverride,
    this.shadowsOverride,
    this.animationDuration = Duration.zero,
    this.onTap,
  }) : assert(level == null || (level >= 1 && level <= 3));

  @override
  State<SoftGlassPanel> createState() => _SoftGlassPanelState();
}

class _SoftGlassPanelState extends State<SoftGlassPanel> {
  bool _pressed = false;

  bool get _isDock => widget.level == null && widget.tier == GlassTier.dock;
  bool get _isCircle => widget.shape == BoxShape.circle;

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
            ? 24.0
            : switch (_resolvedLevel) {
                1 => 24.0,
                2 => 16.0,
                _ => 10.0,
              });
    return raw.clamp(0.0, 28.0);
  }

  BoxDecoration _surfaceDecoration(
    AppColorPalette palette, {
    required bool reducedTransparency,
  }) {
    final isDark = palette.isDark;
    final radius = _isCircle ? null : widget.borderRadius;

    // Platform "reduce transparency / high contrast" veya bayrak etkinse
    // blur yerine paletten 0.88 opaklıklı düz yüzeye geri dön.
    if (reducedTransparency) {
      final solidFill = widget.fillColorOverride != null
          ? widget.fillColorOverride!.withValues(alpha: 0.88)
          : (_isDock
              ? (isDark
                  ? palette.surface.withValues(alpha: 0.88)
                  : palette.navFill.withValues(alpha: 0.88))
              : palette.surface.withValues(alpha: 0.88));
      return BoxDecoration(
        shape: widget.shape,
        borderRadius: radius,
        color: solidFill,
        border: Border.all(
          color: widget.borderColor ?? palette.border,
          width: 1.0,
        ),
      );
    }

    if (_isDock) {
      return BoxDecoration(
        shape: widget.shape,
        borderRadius: radius,
        color: widget.fillColorOverride ?? palette.navFill,
        border: Border.all(
          color: widget.borderColor ??
              Colors.white.withValues(alpha: widget.borderAlphaOverride ?? 0.18),
          width: 1.0,
        ),
      );
    }

    switch (_resolvedLevel) {
      // LEVEL 1 — Statistics panel & sheet (hero glass)
      case 1:
        return BoxDecoration(
          shape: widget.shape,
          borderRadius: radius,
          color: widget.fillColorOverride,
          gradient: widget.fillColorOverride != null
              ? null
              : LinearGradient(
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
                Colors.white.withValues(
                  alpha: widget.borderAlphaOverride ?? (isDark ? 0.24 : 0.45),
                ),
            width: 1.0,
          ),
        );

      // LEVEL 2 — Competition cards
      case 2:
        return BoxDecoration(
          shape: widget.shape,
          borderRadius: radius,
          color: widget.fillColorOverride,
          gradient: widget.fillColorOverride != null
              ? null
              : LinearGradient(
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
                Colors.white.withValues(
                  alpha: widget.borderAlphaOverride ?? (isDark ? 0.18 : 0.30),
                ),
            width: 1.0,
          ),
        );

      // LEVEL 3 — Search bar, filter chips, badges, round buttons
      default:
        final fillAlpha = widget.fillAlphaOverride ?? (isDark ? 0.09 : 0.14);
        final borderAlpha =
            widget.borderAlphaOverride ?? (isDark ? 0.16 : 0.25);
        return BoxDecoration(
          shape: widget.shape,
          borderRadius: radius,
          color: widget.fillColorOverride ??
              Colors.white.withValues(alpha: fillAlpha),
          border: Border.all(
            color: widget.borderColor ??
                Colors.white.withValues(alpha: borderAlpha),
            width: 1.0,
          ),
        );
    }
  }

  List<BoxShadow> _shadows(AppColorPalette palette) {
    if (widget.shadowsOverride != null) return widget.shadowsOverride!;

    if (_isDock) {
      return [
        BoxShadow(
          color: palette.shadowTint.withValues(alpha: 0.22),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ];
    }

    switch (_resolvedLevel) {
      case 1:
        return [
          BoxShadow(
            color: palette.shadowTint.withValues(alpha: 0.18),
            blurRadius: 50,
            offset: const Offset(0, 20),
          ),
        ];
      case 2:
        return [
          BoxShadow(
            color: palette.shadowTint.withValues(alpha: 0.10),
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
    if (_isCircle) return null;
    if (_isDock) return 0.22;
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
    final media = MediaQuery.maybeOf(context);
    final disableMotion = media?.disableAnimations ?? false;
    final reducedTransparency = widget.reduceTransparency ||
        SoftGlassPanel.forceReduceTransparency ||
        (media?.highContrast ?? false);
    final topHighlightAlpha =
        reducedTransparency ? null : _topHighlightAlpha(palette);

    Widget inner = Padding(
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.artStyle != AmbientArtStyle.none || topHighlightAlpha != null) {
      inner = Stack(
        children: [
          if (widget.artStyle != AmbientArtStyle.none)
            Positioned.fill(
              child: AmbientVectorArt(
                style: widget.artStyle,
                opacity: _resolvedLevel == 1 ? 1.0 : 0.85,
              ),
            ),
          if (topHighlightAlpha != null)
            Positioned(
              top: 0,
              left: 1,
              right: 1,
              height: 1.0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _isDock
                        ? Colors.white.withValues(alpha: topHighlightAlpha)
                        : null,
                    gradient: _isDock
                        ? null
                        : LinearGradient(
                            colors: [
                              Colors.white
                                  .withValues(alpha: topHighlightAlpha * 0.25),
                              Colors.white.withValues(alpha: topHighlightAlpha),
                              Colors.white
                                  .withValues(alpha: topHighlightAlpha * 0.25),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          inner,
        ],
      );
    }

    if (widget.onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _isCircle ? null : widget.borderRadius,
          customBorder: _isCircle ? const CircleBorder() : null,
          onTap: widget.onTap,
          onHighlightChanged: (v) {
            if (!disableMotion && mounted) {
              setState(() => _pressed = v);
            }
          },
          child: inner,
        ),
      );
    }

    final decoration = _surfaceDecoration(
      palette,
      reducedTransparency: reducedTransparency,
    );

    Widget surface = widget.animationDuration > Duration.zero && !disableMotion
        ? AnimatedContainer(
            duration: widget.animationDuration,
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: widget.height,
            decoration: decoration,
            child: inner,
          )
        : Container(
            width: widget.width,
            height: widget.height,
            decoration: decoration,
            child: inner,
          );

    final shouldBlur = widget.enableBlur && !reducedTransparency;
    if (shouldBlur) {
      final filtered = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _effectiveBlur,
          sigmaY: _effectiveBlur,
        ),
        child: surface,
      );
      surface = _isCircle
          ? ClipOval(child: filtered)
          : ClipRRect(borderRadius: widget.borderRadius, child: filtered);
    } else {
      surface = _isCircle
          ? ClipOval(child: surface)
          : ClipRRect(borderRadius: widget.borderRadius, child: surface);
    }

    final shadows = _shadows(palette);
    Widget panel = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        shape: widget.shape,
        borderRadius: _isCircle ? null : widget.borderRadius,
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

/// Üst çubuk aksiyonları için Seviye 3 (Level 3) dairesel Soft Glass buton.
/// Doğrudan [SoftGlassPanel] (shape: BoxShape.circle, level: 3) üzerinden çalışır.
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

    final button = SoftGlassPanel(
      level: 3,
      shape: BoxShape.circle,
      width: 40,
      height: 40,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? palette.textPrimary,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
