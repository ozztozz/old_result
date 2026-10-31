import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/race_model.dart';
import 'status_badge.dart';

/// TYF Yüzme Sonuçları — Modern Yarış Kartı Bileşeni (v2.0)
/// Apple Esintili Sade Kart: #FFFFFF zemin, 16px radius, 1px #EFE9E7 sınır
class ModernRaceCard extends StatelessWidget {
  final RaceModel race;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onTap;

  const ModernRaceCard({
    super.key,
    required this.race,
    this.onFavoriteToggle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cleanAge = race.ageCategory.replaceAll(RegExp(r'\s*\(\d{4}\)'), '').trim();
    final subtitle = cleanAge.isNotEmpty ? '${race.gender} • $cleanAge' : race.gender;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x083D3038),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Sade Metraj (Kutusuz)
                SizedBox(
                  width: 42,
                  child: Text(
                    race.distance,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Branş Adı & Kategori Bilgisi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.strokeName,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (race.winnerSummary != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          race.winnerSummary!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.statusSuccess,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 3. Durum Rozeti (Sade)
                _buildStatusBadge(race),
                const SizedBox(width: 10),

                // 4. Favori Yıldız Butonu
                GestureDetector(
                  onTap: onFavoriteToggle,
                  child: Icon(
                    race.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: race.isFavorite ? AppColors.accent : AppColors.laneNeutral,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RaceModel race) {
    switch (race.status) {
      case RaceStatus.completed:
        return StatusBadge.completed(label: 'Sonuçlandı');
      case RaceStatus.live:
        return StatusBadge.live(label: 'Sıradaki');
      case RaceStatus.upcoming:
        return StatusBadge.pending(
          label: race.startTime != null ? race.startTime! : 'Bekliyor',
        );
    }
  }
}

