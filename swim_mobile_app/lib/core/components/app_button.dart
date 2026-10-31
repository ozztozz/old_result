import 'package:flutter/material.dart';
import '../theme/tokens/tokens.dart';

/// Buton Varyantları
enum AppButtonVariant {
  /// Ana aksiyon rengi (Primary / Accent)
  primary,

  /// İkincil yumuşak zeminli buton
  secondary,

  /// Kenarlıklı buton
  outline,

  /// Sadece metin ve ikon içeren şeffaf buton
  text,

  /// Kritik / Silme aksiyonları
  danger,

  /// Başarı / Onay aksiyonları
  success,
}

/// Buton Boyutları
enum AppButtonSize {
  small,
  medium,
  large,
}

/// Katman 3: Atomik UI Bileşeni — AppButton
/// Durum ve aksiyon butonlarının standart üreticisidir.
/// Loading state, ikon desteği ve tokens entegrasyonu sunar.
class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool isFullWidth;
  final AppButtonVariant variant;
  final AppButtonSize size;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
  });

  const AppButton.secondary({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.size = AppButtonSize.medium,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outline({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.size = AppButtonSize.medium,
  }) : variant = AppButtonVariant.outline;

  const AppButton.danger({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.size = AppButtonSize.medium,
  }) : variant = AppButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isEnabled = onPressed != null && !isLoading;

    // Boyut belirleme
    final EdgeInsets padding;
    final double iconSize;
    final TextStyle textStyle;

    switch (size) {
      case AppButtonSize.small:
        padding = const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        );
        iconSize = 14.0;
        textStyle = AppTextStyles.labelMuted.copyWith(
          fontWeight: FontWeight.w600,
        );
        break;
      case AppButtonSize.medium:
        padding = const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        );
        iconSize = 18.0;
        textStyle = AppTextStyles.tabSelected.copyWith(fontSize: 13.5);
        break;
      case AppButtonSize.large:
        padding = const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        );
        iconSize = 20.0;
        textStyle = AppTextStyles.tabSelected.copyWith(fontSize: 15.0);
        break;
    }

    // Renk ve zemin belirleme
    Color bg;
    Color fg;
    BorderSide side = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = palette.primary;
        fg = Colors.white;
        break;
      case AppButtonVariant.secondary:
        bg = palette.surfaceSecondary;
        fg = palette.textPrimary;
        break;
      case AppButtonVariant.outline:
        bg = Colors.transparent;
        fg = palette.textPrimary;
        side = BorderSide(color: palette.border);
        break;
      case AppButtonVariant.text:
        bg = Colors.transparent;
        fg = palette.primary;
        break;
      case AppButtonVariant.danger:
        bg = palette.statusDanger;
        fg = Colors.white;
        break;
      case AppButtonVariant.success:
        bg = palette.statusSuccess;
        fg = Colors.white;
        break;
    }

    if (!isEnabled && !isLoading) {
      bg = palette.surfaceSecondary;
      fg = palette.textMuted;
      side = BorderSide.none;
    }

    Widget content;
    if (isLoading) {
      content = SizedBox(
        height: iconSize,
        width: iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(fg),
        ),
      );
    } else {
      final List<Widget> children = [];
      if (icon != null) {
        children.add(Icon(icon, size: iconSize, color: fg));
        children.add(AppSpacing.hXs);
      }
      children.add(
        Text(
          text,
          style: textStyle.copyWith(color: fg),
        ),
      );
      if (trailingIcon != null) {
        children.add(AppSpacing.hXs);
        children.add(Icon(trailingIcon, size: iconSize, color: fg));
      }

      content = Row(
        mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      );
    }

    final button = Material(
      color: bg,
      borderRadius: AppRadius.buttonRadius,
      shape: side != BorderSide.none
          ? RoundedRectangleBorder(
              borderRadius: AppRadius.buttonRadius,
              side: side,
            )
          : null,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: AppRadius.buttonRadius,
        child: Padding(
          padding: padding,
          child: content,
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}

