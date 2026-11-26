import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/repositories/swim_repository.dart';
import '../../main.dart';

/// KulvaR Açılış (Splash) Ekranı — Çok Aşamalı Havuz Dalgası & Ripple Animasyonu
class SplashScreen extends StatefulWidget {
  final SwimRepository repository;

  const SplashScreen({super.key, required this.repository});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _ambientController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subFade;
  late final Animation<double> _dividerWidth;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _logoFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.68, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.58, curve: Curves.easeOutBack),
      ),
    );

    _titleFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.32, 0.72, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.32, 0.76, curve: Curves.easeOutCubic),
      ),
    );

    _subFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.55, 0.92, curve: Curves.easeOut),
    );
    _dividerWidth = Tween<double>(begin: 0, end: 52).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.52, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    _introController.forward();

    Future.delayed(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, __, ___) =>
              MainNavigationContainer(repository: widget.repository),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.03, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coralColor =
        palette.isDark ? const Color(0xFFFF7A6B) : const Color(0xFFE85D4A);

    return Scaffold(
      backgroundColor: palette.background,
      body: AmbientBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Alt kısımda akışkan 2 katmanlı havuz su dalgaları
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ambientController,
                builder: (_, __) => CustomPaint(
                  painter: _PoolWavePainter(
                    phase: _ambientController.value * math.pi * 2,
                    colorPrimary: palette.accent.withAlpha(28),
                    colorSecondary: palette.primary.withAlpha(18),
                  ),
                ),
              ),
            ),

            // Merkez: Su halkaları + Logo + KulvaR Başlık
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Genişleyen su halkaları
                        AnimatedBuilder(
                          animation: _ambientController,
                          builder: (_, __) => CustomPaint(
                            size: const Size(220, 220),
                            painter: _RippleRingsPainter(
                              progress: _ambientController.value,
                              color: palette.accent,
                            ),
                          ),
                        ),
                        // Logo kartı
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.accent.withAlpha(55),
                                    blurRadius: 34,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: SoftGlassPanel(
                                level: 1,
                                width: 122,
                                height: 122,
                                shape: BoxShape.circle,
                                padding: const EdgeInsets.all(6),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/app_logo.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontFamilyFallback:
                                AppTextStyles.fontFamilyFallback,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.0,
                          ),
                          children: [
                            TextSpan(
                              text: 'Kulva',
                              style: TextStyle(color: palette.textPrimary),
                            ),
                            TextSpan(
                              text: 'R',
                              style: TextStyle(color: coralColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _dividerWidth,
                    builder: (_, __) => Container(
                      width: _dividerWidth.value,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: [palette.accent, coralColor],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: _subFade,
                    child: Text(
                      'Yüzme Platformu',
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Alt kısımda ince akışkan yükleme çubuğu
            Positioned(
              left: 0,
              right: 0,
              bottom: 42,
              child: FadeTransition(
                opacity: _subFade,
                child: Center(
                  child: SizedBox(
                    width: 110,
                    height: 3.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: AnimatedBuilder(
                        animation: _ambientController,
                        builder: (_, __) {
                          return FractionallySizedBox(
                            alignment: Alignment(
                              -1.0 + 2.0 * _ambientController.value,
                              0,
                            ),
                            widthFactor: 0.45,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  colors: [palette.accent, coralColor],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo arkasında genişleyip sönen 3 eş merkezli su halkası.
class _RippleRingsPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RippleRingsPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 56 + (maxRadius - 56) * Curves.easeOut.transform(t);
      final alpha = ((1.0 - t) * 75).round().clamp(0, 255);
      final paint = Paint()
        ..color = color.withAlpha(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1.0 - t * 0.5);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RippleRingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Alt kısımda yumuşakça akan 2 katmanlı havuz su dalgası.
class _PoolWavePainter extends CustomPainter {
  final double phase;
  final Color colorPrimary;
  final Color colorSecondary;

  const _PoolWavePainter({
    required this.phase,
    required this.colorPrimary,
    required this.colorSecondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawWave(
      canvas,
      size,
      amplitude: 16,
      baseHeight: size.height * 0.84,
      phaseShift: phase,
      frequency: 1.6,
      color: colorSecondary,
    );
    _drawWave(
      canvas,
      size,
      amplitude: 12,
      baseHeight: size.height * 0.88,
      phaseShift: -phase * 0.85 + 1.4,
      frequency: 2.1,
      color: colorPrimary,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double amplitude,
    required double baseHeight,
    required double phaseShift,
    required double frequency,
    required Color color,
  }) {
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 6) {
      final normX = x / size.width;
      final y = baseHeight +
          math.sin(normX * math.pi * 2 * frequency + phaseShift) * amplitude;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PoolWavePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.colorPrimary != colorPrimary ||
      oldDelegate.colorSecondary != colorSecondary;
}
