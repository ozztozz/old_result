import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_decorations.dart';

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

  /// Kişisel En İyi Derece (PB)
  factory StatusBadge.pb({String label = 'PB'}) {
    return StatusBadge(
      label: label,
      bgColor: AppColors.accentLight,
      textColor: AppColors.accent,
      hasBorder: true,
    );
  }

  /// Sıradaki / Bekliyor (Açık Nötr)
  factory StatusBadge.pending({String label = 'Bekliyor'}) {
    return StatusBadge(
      label: label,
      bgColor: AppColors.background,
      textColor: AppColors.textSecondary,
      hasBorder: true,
    );
  }

  /// Durum Metninden Otomatik Rozet Üretimi
  factory StatusBadge.fromStatus(String status) {
    final s = status.toLowerCase();
    if (s.contains('canli') || s.contains('live') || s.contains('isleniyor')) {
      return StatusBadge.live(label: status);
    }
    if (s.contains('tamam') || s.contains('sonuc') || s.contains('ok')) {
      return StatusBadge.completed(label: status);
    }
    if (s.contains('pb') || s.contains('zirve')) {
      return StatusBadge.pb(label: status);
    }
    return StatusBadge(
      label: status,
      bgColor: AppColors.background,
      textColor: AppColors.textSecondary,
      hasBorder: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppBorders.small,
        border: hasBorder
            ? Border.all(color: textColor.withValues(alpha: 0.25), width: 1.0)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) leading!,
          Text(
            label,
            style: AppTextStyles.badge.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}

class LiveBadge extends StatelessWidget {
  final String label;

  const LiveBadge({super.key, this.label = 'CANLI'});

  @override
  Widget build(BuildContext context) {
    return StatusBadge.live(label: label);
  }
}

