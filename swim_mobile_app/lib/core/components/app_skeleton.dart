import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/tokens/tokens.dart';

/// Katman 3: Atomik UI Bileşeni — AppSkeleton
/// Yüklenme durumları (loading shimmer) için standart bileşen.
class AppSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? child;

  const AppSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.child,
  });

  /// Metin satırı iskeleti
  const AppSkeleton.line({
    super.key,
    this.width = double.infinity,
    this.height = 14.0,
    this.borderRadius = AppRadius.smallRadius,
  }) : child = null;

  /// Yuvarlak avatar veya ikon iskeleti
  AppSkeleton.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = BorderRadius.circular(size / 2),
        child = null;

  /// Kart iskeleti
  const AppSkeleton.card({
    super.key,
    this.width = double.infinity,
    this.height = 80.0,
    this.borderRadius = AppRadius.cardRadius,
    this.child,
  }) ;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = borderRadius ?? AppRadius.smallRadius;

    final baseColor = palette.isDark
        ? palette.surfaceSecondary
        : palette.border;
    final highlightColor = palette.isDark
        ? palette.surfaceElevated
        : palette.surface;

    final content = child ??
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: radius,
          ),
        );

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: content,
    );
  }
}

/// Liste halinde iskelet gösterici
class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final double spacing;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const AppSkeletonList({
    super.key,
    this.itemCount = 5,
    this.spacing = AppSpacing.sm,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: spacing),
      itemBuilder: itemBuilder,
    );
  }
}

