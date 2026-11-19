import 'package:flutter/material.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/race_model.dart';

/// TYF Yüzme Sonuçları — Canlı Takip Hero Yarış Kartı (Soft Glass + Ambient Art)
class HeroRaceCard extends StatelessWidget {
  final RaceModel race;
  final VoidCallback? onTap;

  const HeroRaceCard({
    super.key,
    required this.race,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isLive = race.status == RaceStatus.live;
    final cleanAge = race.ageCategory.replaceAll(RegExp(r'\s*\(\d{4}\)'), '').trim();
    final indicatorColor = isLive ? palette.statusLive : palette.primary;

    return SoftGlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      borderRadius: AppRadius.cardRadius,
      artStyle: AmbientArtStyle.contourWaves,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Durum İndikatörü
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isLive ? palette.statusLiveBg : palette.primaryContainer,
                  borderRadius: AppRadius.full,
                  border: Border.all(
                    color: indicatorColor.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: indicatorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive ? 'CANLI YARIŞ' : 'SIRADAKİ YARIŞ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: indicatorColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (race.heatLaneInfo != null && race.heatLaneInfo!.isNotEmpty)
                Text(
                  race.heatLaneInfo!,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Müsabaka / Yarış Başlığı
          Text(
            '${race.distance}m ${race.strokeName}',
            style: AppTextStyles.raceTitle.copyWith(
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // Kategori & Seri Bilgisi
          Text(
            cleanAge.isNotEmpty ? '${race.gender} · $cleanAge' : race.gender,
            style: AppTextStyles.categorySeries.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          Divider(height: 1, thickness: 1, color: palette.divider),
          const SizedBox(height: 12),

          // Alt Satır
          Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 15,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Havuzda · Sonuç Bekleniyor',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                'Canlı İzle',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 11,
                color: palette.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
