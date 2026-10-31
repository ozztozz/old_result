import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/race_model.dart';

/// TYF Yüzme Sonuçları — Canlı Takip Kartı (v2.0)
/// Apple Esintili Yalınlık:
/// - Zemin: #FFFFFF temiz beyaz
/// - Kenar Yuvarlatma: 16px köşe yarıçapı
/// - 1px sınır çizgisi (#EFE9E7) ve mikro-derinlik gölgesi
/// - Durum İndikatörü: Küçük soluk pudra gülü dolgulu nokta (•) ve yanında 11px CANLI YARIŞ etiketi
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
    final isLive = race.status == RaceStatus.live;
    final cleanAge = race.ageCategory.replaceAll(RegExp(r'\s*\(\d{4}\)'), '').trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Durum İndikatörü: Soluk pudra gülü nokta (•) ve 11px CANLI YARIŞ etiketi
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive ? 'CANLI YARIŞ' : 'SIRADAKİ YARIŞ',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: AppColors.accent,
                      ),
                    ),
                    const Spacer(),
                    if (race.heatLaneInfo != null && race.heatLaneInfo!.isNotEmpty)
                      Text(
                        race.heatLaneInfo!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Müsabaka / Yarış Başlığı (17px / FontWeight.w600 / #3D3038)
                Text(
                  '${race.distance} ${race.strokeName}',
                  style: AppTextStyles.raceTitle,
                ),
                const SizedBox(height: 3),

                // Kategori & Seri Bilgisi (13px / FontWeight.w400 / #81777D)
                Text(
                  cleanAge.isNotEmpty ? '${race.gender} • $cleanAge' : race.gender,
                  style: AppTextStyles.categorySeries,
                ),
                const SizedBox(height: 14),

                // İnce 1px Ayırıcı Çizgi (#EFE9E7)
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                const SizedBox(height: 10),

                // Alt Satır
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Havuzda • Sonuç Bekleniyor',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Canlı İzle',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

