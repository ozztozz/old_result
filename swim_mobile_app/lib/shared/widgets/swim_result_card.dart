import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/models/race_result.dart';

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

/// TYF Yüzme Sonuçları — Sonuç Listesi Satır Yapısı (v2.0)
/// Apple Esintili Yalınlık:
/// - Her satır 52px minimum dokunma yüksekliğine sahiptir.
/// - Soldan sağa hiyerarşi:
///   1. Kulvar numarası (18px genişlik, nötr gri #81777D).
///   2. Sporcu adı (15px w500 #3D3038) ve hemen altında kulüp adı (12px w400 #81777D, dikeyde 2px boşluk).
///   3. Derece (sağa hizalı, sabit genişlikli rakamlar 15px w500 tabularFigures #3D3038).
///   4. Sıralama numarası (20px hafif gri nötr rozet içinde #FAF8F7 zemin, #EFE9E7 çerçeve).
/// - Satırlar arasına tam boy yerine soldan 32px girintili 1px #EFE9E7 ayırıcı çizgi çekilir.
class SwimResultCard extends StatelessWidget {
  final RaceResult result;
  final VoidCallback? onTap;
  final int? rankIndex;
  final bool showDivider;

  const SwimResultCard({
    super.key,
    required this.result,
    this.onTap,
    this.rankIndex,
    this.showDivider = true,
  });

  String? _getDisplaySeedTime() {
    if (result.seedTime != null &&
        result.seedTime!.isNotEmpty &&
        result.seedTime != '0' &&
        result.seedTime != '00:00.00' &&
        result.seedTime != '-') {
      String s = result.seedTime!.trim();
      if (s.startsWith('00:')) s = s.substring(3);
      return s;
    }
    if (result.seedTimeCs != null && result.seedTimeCs! > 0) {
      return SwimTimeFormatter.formatCs(result.seedTimeCs);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isWaiting = result.resultStatus == 'WAITING';
    final isDq = result.resultStatus == 'DQ' ||
        result.resultStatus == 'DNS' ||
        result.resultStatus == 'DNF' ||
        result.rank.toUpperCase().startsWith('DQ') ||
        result.rank.toUpperCase().startsWith('DSQ');
    final isSwimming = result.resultStatus == 'SWIMMING' || result.resultStatus == 'HAVUZDA';

    final hasFinished = !isWaiting &&
        !isDq &&
        !isSwimming &&
        ((result.timeCs ?? 0) > 0 || (result.time != null && result.time!.isNotEmpty));

    final rawRank = result.rank.replaceAll('.', '').trim();
    final parsedRank = int.tryParse(rawRank);
    final effectiveRank = (parsedRank != null && parsedRank > 0)
        ? parsedRank
        : (rankIndex != null && rankIndex! > 0 ? rankIndex : null);

    final bool isCompleted = hasFinished &&
        (effectiveRank != null ||
            (result.timeCs ?? 0) > 0 ||
            (result.time != null && result.time!.isNotEmpty));

    // Kulvar & Seri
    final cleanHeat = result.heat.replaceAll(RegExp(r'[^\d]'), '').trim();
    final heatStr = cleanHeat.isNotEmpty
        ? cleanHeat
        : (result.heat.isNotEmpty ? result.heat : '-');
    final laneStr = result.lane != null && result.lane! > 0 ? '${result.lane}' : '-';

    // Bitiş süresi
    final String timeDisplay;
    final Color timeColor;
    if (isDq) {
      timeDisplay = result.resultStatus.isNotEmpty ? result.resultStatus : 'DQ';
      timeColor = AppColors.danger;
    } else if (isSwimming) {
      timeDisplay = 'CANLI';
      timeColor = AppColors.accent;
    } else if (isCompleted) {
      if (result.timeCs != null && result.timeCs! > 0) {
        timeDisplay = SwimTimeFormatter.formatCs(result.timeCs);
      } else if (result.time != null && result.time!.isNotEmpty) {
        String t = result.time!.trim();
        if (t.startsWith('00:')) t = t.substring(3);
        timeDisplay = t;
      } else {
        timeDisplay = '-';
      }
      timeColor = AppColors.textPrimary;
    } else {
      // Bekleyen yarış için giriş derecesi
      final seed = _getDisplaySeedTime();
      timeDisplay = seed != null && seed.isNotEmpty ? seed : '-';
      timeColor = AppColors.textSecondary;
    }

    final clubName = result.clubName.isNotEmpty
        ? _toTitleCase(result.clubName)
        : 'Ferdi Sporcu';
    final subtitleText = isCompleted
        ? '$clubName • Seri $heatStr'
        : '$clubName • Seri $heatStr';

    final rankBadgeText = isCompleted && effectiveRank != null
        ? '$effectiveRank'
        : (isDq ? '-' : (laneStr != '-' ? laneStr : '-'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Kulvar numarası (18px genişlik, nötr gri)
                  SizedBox(
                    width: 18,
                    child: Text(
                      laneStr,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // 2. Sporcu adı ve hemen altında kulüp adı (dikeyde 2px boşluk)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _toTitleCase(result.athleteName),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleText,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 3. Derece (sağa hizalı, sabit genişlikli rakamlar)
                  Text(
                    timeDisplay,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: timeColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 4. Sıralama numarası (20px hafif gri nötr rozet içinde)
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: AppColors.divider,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      rankBadgeText,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.divider,
            indent: 32,
          ),
      ],
    );
  }
}
