import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/services/theme_service.dart';
import '../../core/theme/tokens/tokens.dart';

/// Soft Glass canlı tema seçici alt penceresi (Modal Bottom Sheet).
/// Kullanıcı her dokunuşta temayı anlık olarak önizler ve seçim kalıcı kaydedilir.
class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.36),
      builder: (_) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final palette = context.palette;
        final activePreset = ThemeService.instance.preset;
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return ClipRRect(
          borderRadius: AppRadius.sheetRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.sheetRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(palette.glassSheen, palette.surfaceGlassStrong),
                    palette.surfaceGlassStrong,
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: palette.isDark ? palette.border : palette.glassBorder,
                    width: 1.0,
                  ),
                ),
              ),
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tutamaç çizgisi
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: palette.textMuted.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Başlık satırı
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: palette.primaryContainer,
                                borderRadius: AppRadius.medium,
                                border: Border.all(
                                  color: palette.primary.withValues(alpha: 0.22),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.palette_outlined,
                                color: palette.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Görünüm ve Tema',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cool Glass (Açık / Koyu) ve alternatif paletler',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 12.5,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close_rounded,
                                color: palette.textSecondary,
                                size: 20,
                              ),
                              tooltip: 'Kapat',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Tema Kartları Izgarası
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = constraints.maxWidth >= 520 ? 3 : 2;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: AppThemePreset.values.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.08,
                              ),
                              itemBuilder: (context, index) {
                                final preset = AppThemePreset.values[index];
                                final isSelected = preset == activePreset;
                                return _ThemePresetCard(
                                  preset: preset,
                                  isSelected: isSelected,
                                  palette: palette,
                                  onTap: () => ThemeService.instance.setPreset(preset),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  final AppThemePreset preset;
  final bool isSelected;
  final AppColorPalette palette;
  final VoidCallback onTap;

  const _ThemePresetCard({
    required this.preset,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? palette.primary : palette.border;
    final checkFg = preset.previewPrimary.computeLuminance() > 0.42
        ? const Color(0xFF090D16)
        : Colors.white;

    return Material(
      color: isSelected
          ? palette.primaryContainer
          : palette.surface.withValues(alpha: palette.isDark ? 0.55 : 0.78),
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini Ekran Önizlemesi
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: preset.previewBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: preset.isDarkOnly
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 6,
                            decoration: BoxDecoration(
                              color: preset.previewPrimary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 14,
                            height: 6,
                            decoration: BoxDecoration(
                              color: preset.previewSecondary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: preset.previewPrimary,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: checkFg,
                              ),
                            )
                          else
                            _ColorDotStrip(
                              colors: [
                                preset.previewPrimary,
                                preset.previewSecondary,
                              ],
                            ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: preset.previewSurface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: preset.previewPrimary.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: preset.previewPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    height: 4,
                                    width: 46,
                                    decoration: BoxDecoration(
                                      color: preset.isDarkOnly
                                          ? Colors.white.withValues(alpha: 0.72)
                                          : Colors.black.withValues(alpha: 0.60),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 3,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: preset.previewPrimary.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Başlık + Mod Rozeti
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.title,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.primary.withValues(alpha: 0.18)
                          : palette.surfaceSecondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      preset.badge,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? palette.primary : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                preset.subtitle,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 10.5,
                  color: palette.textSecondary,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDotStrip extends StatelessWidget {
  final List<Color> colors;

  const _ColorDotStrip({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < colors.length; i++)
          Container(
            width: 9,
            height: 9,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            decoration: BoxDecoration(
              color: colors[i],
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
