import 'package:flutter/material.dart';
import 'app_colors.dart';

/// TYF Yüzme Sonuçları — Çerçeve ve Kenarlık Disiplini (v2.0)
/// Apple Esintili Sade Kartlar: Mikro-derinlik, 16px radius ve 1px #EFE9E7 sınır
class AppBorders {
  static const double radiusCell = 10.0;
  static const double radiusPanel = 16.0;
  static const double radiusSmall = 8.0;
  static const double radiusPill = 999.0;

  static final BorderRadius cell = BorderRadius.circular(radiusCell);
  static final BorderRadius panel = BorderRadius.circular(radiusPanel);
  static final BorderRadius small = BorderRadius.circular(radiusSmall);
  static final BorderRadius pill = BorderRadius.circular(radiusPill);

  static const Border border = Border.fromBorderSide(
    BorderSide(color: AppColors.border, width: 1.0),
  );

  static const BorderSide borderSide = BorderSide(
    color: AppColors.border,
    width: 1.0,
  );

  static Widget divider({double height = 1.0, double indent = 0.0, double endIndent = 0.0}) {
    return Divider(
      height: height,
      thickness: 1.0,
      color: AppColors.divider,
      indent: indent,
      endIndent: endIndent,
    );
  }

  static Widget verticalDivider({double width = 1.0, double indent = 0.0, double endIndent = 0.0}) {
    return VerticalDivider(
      width: width,
      thickness: 1.0,
      color: AppColors.divider,
      indent: indent,
      endIndent: endIndent,
    );
  }
}

class AppDecorations {
  /// Sade Yüzey Paneli (Apple Mikro-Derinlik: 0 1px 3px rgba(61,48,56, 0.04) veya 1px #EFE9E7)
  static BoxDecoration panel({Color? color, BorderRadius? borderRadius}) => BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A3D3038),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      );

  /// Sade Hücre / Metraj Kutusu
  static BoxDecoration cell({Color? color}) => BoxDecoration(
        color: color ?? AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1.0),
      );

  /// Sekme Çubuğu Taşıyıcı Kutusu
  static BoxDecoration tabContainer = BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border, width: 1.0),
  );

  /// Aktif Sekme Göstergesi
  static BoxDecoration tabIndicator = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(10.0),
    border: Border.all(color: AppColors.border, width: 1.0),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0A3D3038),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
  );

  /// Küçük İkincil Buton Dekoru
  static BoxDecoration actionButton = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border, width: 1.0),
    boxShadow: const [
      BoxShadow(
        color: Color(0x083D3038),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
  );
}

