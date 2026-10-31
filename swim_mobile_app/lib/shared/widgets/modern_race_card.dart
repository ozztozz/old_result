import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/race_model.dart';
import 'status_badge.dart';

/// TYF Yüzme Sonuçları — Modern Yarış Kartı Bileşeni (v2.0)
/// Apple Esintili Sade Kart: #FFFFFF zemin, 16px radius, 1px sınır
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
    final palette = context.palette;
    final cleanAge = race.ageCategory.replaceAll(RegExp(r'\s*\(\d{4}\)'), '').trim();
    final subtitle = cleanAge.isNotEmpty ? '${race.gender} • $cleanAge' : race.gender;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: palette.border,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.textPrimary.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Sade Metraj (Kutusuz)
                SizedBox(
                  width: 44,
                  child: Text(
                    race.distance,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                      letterSpacing: -0.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                AppSpacing.hSm,

                // 2. Branş Adı, Kategori Bilgisi & Takım Sporcu Rozeti
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.strokeName,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: palette.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: palette.textSecondary,
                        ),
                      ),

                      // Kullanıcının seçili takımından katılan sporcu sayısı
                      if (race.myTeamAthleteCount > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: palette.primaryContainer,
                            borderRadius: AppRadius.badgeRadius,
                            border: Border.all(
                              color: palette.primary.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                size: 12,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${race.myTeamAthleteCount} Sporcunuz',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: palette.primary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (race.winnerSummary != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          race.winnerSummary!,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: palette.statusSuccess,
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
                    color: race.isFavorite ? palette.primary : palette.textMuted,
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
