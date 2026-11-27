import 'package:flutter/material.dart';

import '../../core/components/ambient_canvas.dart';
import '../../core/utils/responsive.dart';
import 'brand_header_bar.dart';

/// Uygulama genelinde ortak sayfa kabuğu:
/// [AmbientBackground] + [Scaffold] + [SafeArea] + [BrandHeaderBar] + içerik.
class AppPageShell extends StatelessWidget {
  final String subtitle;
  final bool? showBack;
  final List<Widget> actions;
  final Widget body;
  final double? maxWidth;
  final bool safeBottom;
  final EdgeInsetsGeometry? headerPadding;

  const AppPageShell({
    super.key,
    required this.subtitle,
    required this.body,
    this.showBack,
    this.actions = const [],
    this.maxWidth = 1040,
    this.safeBottom = false,
    this.headerPadding,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandHeaderBar(
          subtitle: subtitle,
          showBack: showBack,
          actions: actions,
          padding: headerPadding ??
              const EdgeInsets.fromLTRB(
                20,
                10,
                20,
                4,
              ),
        ),
        Expanded(child: body),
      ],
    );

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: safeBottom,
          child: maxWidth != null
              ? ResponsiveCenter(
                  maxWidth: maxWidth!,
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}
