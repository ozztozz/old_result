import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Yüzen Yarı Saydam Cam Navigasyon Kabuğu
/// Doğrudan [SoftGlassPanel] (`GlassTier.dock`) kullanır.
class AppScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<Widget> screens;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.screens,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      extendBody: true,
      body: _AnimatedTabStack(
        currentIndex: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0F273B),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  _buildNavItem(
                    context,
                    0,
                    'Ana Sayfa',
                    Icons.home_outlined,
                    Icons.home_outlined,
                  ),
                  _buildNavItem(
                    context,
                    1,
                    'Canlı Takip',
                    Icons.sensors,
                    Icons.sensors,
                  ),
                  _buildNavItem(
                    context,
                    2,
                    'Favorilerim',
                    Icons.star_border,
                    Icons.star_border,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData activeIcon,
  ) {
    final isSelected = currentIndex == index;
    const cyan = Color(0xFF14B8CC);
    const navy = Color(0xFF0F273B);
    final contentColor = isSelected ? navy : Colors.white.withAlpha(204);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigationChanged(index),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? cyan : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 21,
                  color: contentColor,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.1,
                    color: contentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sekme durumlarını korurken (`IndexedStack`) geçişlerde yumuşak fade + yönlü kayma uygular.
class _AnimatedTabStack extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;

  const _AnimatedTabStack({
    required this.currentIndex,
    required this.children,
  });

  @override
  State<_AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<_AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _configureAnimations(forward: true);
  }

  void _configureAnimations({required bool forward}) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: Offset(forward ? 0.03 : -0.03, 0),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _configureAnimations(
        forward: widget.currentIndex > oldWidget.currentIndex,
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: IndexedStack(
          index: widget.currentIndex,
          children: widget.children,
        ),
      ),
    );
  }
}
