import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';

/// TYF Yüzme Sonuçları — Durum Rozeti (v2.0)
/// "Tamamlandı", "Canlı", "PB", "Bekliyor" mikro rozetleri
class StatusBadge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final Widget? leading;
  final bool hasBorder;

  const StatusBadge({
    super.key,
    required this.label,
    required this.bgColor,
    required this.textColor,
    this.leading,
    this.hasBorder = true,
  });

  /// Tamamlandı / Sonuçlandı (Adaçayı Yeşili Rozet)
  factory StatusBadge.completed({String label = 'Sonuçlandı'}) {
    return StatusBadge(
      label: label,
      bgColor: AppColors.statusSuccessBg,
      textColor: AppColors.statusSuccess,
      hasBorder: true,
    );
  }

  /// Canlı (Pudra Gülü Noktası ile)
  factory StatusBadge.live({String label = 'CANLI'}) {
    return StatusBadge(
      label: label,
      bgColor: AppColors.statusLiveBg,
      textColor: AppColors.statusLive,
      hasBorder: true,
      leading: Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(right: 5),
        decoration: const BoxDecoration(
          color: AppColors.statusLive,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Bekliyor / Başlamadı
  factory StatusBadge.pending({String label = 'Bekliyor'}) {
    return StatusBadge(
      label: label,
      bgColor: const Color(0xFFFAF8F7),
      textColor: AppColors.textSecondary,
      hasBorder: true,
    );
  }

  /// Kişisel En İyi (Personal Best - PB)
  factory StatusBadge.pb({String label = 'PB'}) {
    return StatusBadge(
      label: label,
      bgColor: AppColors.goldBg,
      textColor: AppColors.gold,
      hasBorder: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: hasBorder ? Border.all(color: textColor.withValues(alpha: 0.15), width: 0.8) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) leading!,
          Text(
            label,
            style: AppTextStyles.badge.copyWith(
              color: textColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
