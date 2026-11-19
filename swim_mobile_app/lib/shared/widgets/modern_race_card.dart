import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/race_model.dart';
import 'status_badge.dart';

/// TYF Yüzme Sonuçları — Modern Yarış Kartı Bileşeni (v2.0)
/// Seviye 2 cam kartı, tutarlı başlık ve durum hiyerarşisi.
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
    final cleanAge =
        race.ageCategory.replaceAll(RegExp(r'\s*\(\d{4}\)'), '').trim();
    final subtitle =
        cleanAge.isNotEmpty ? '${race.gender} • $cleanAge' : race.gender;

    return SoftGlassPanel(
      level: 2,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.s12),
      borderRadius: AppRadius.cardRadius,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Sade Metraj (Kutusuz)
          SizedBox(
            width: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  race.distance,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                    letterSpacing: -0.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'm',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMuted.copyWith(
                    fontSize: 12,
                    color: palette.textSecondary,
                    height: 1,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.hSm,

          // 2. Branş Adı, Kategori Bilgisi & Takım Sporcu Rozeti
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StringUtils.toTitleCase(race.strokeName),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: palette.textSecondary,
                  ),
                ),

                // Kullanıcının seçili takımından katılan sporcu sayısı
                if (race.myTeamAthleteCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
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
                      color: palette.successText,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. Durum Rozeti (Sade)
          _buildStatusBadge(race, palette),
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
    );
  }

  Widget _buildStatusBadge(RaceModel race, AppColorPalette palette) {
    switch (race.status) {
      case RaceStatus.completed:
        return StatusBadge(
          label: 'Sonuçlandı',
          variant: StatusBadgeVariant.success,
          textColor: palette.successText,
        );
      case RaceStatus.live:
        return StatusBadge.live(label: 'Sıradaki');
      case RaceStatus.upcoming:
        return StatusBadge.pending(
          label: race.startTime != null ? race.startTime! : 'Bekliyor',
        );
    }
  }
}
