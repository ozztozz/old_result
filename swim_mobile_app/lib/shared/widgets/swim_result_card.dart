import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../core/services/selected_club_service.dart';
import '../../data/models/race_result.dart';

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

int? _parseTimeToCs(String? s) {
  if (s == null) return null;
  final clean = s.trim();
  if (clean.isEmpty || clean == '-' || clean == '0' || clean == '00:00.00') return null;
  try {
    final parts = clean.split(':');
    if (parts.length == 2) {
      final m = int.parse(parts[0]);
      final secParts = parts[1].split('.');
      final sec = int.parse(secParts[0]);
      final cs = secParts.length > 1
          ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
          : 0;
      return (m * 60 + sec) * 100 + cs;
    } else if (parts.length == 1) {
      final secParts = parts[0].split('.');
      final sec = int.parse(secParts[0]);
      final cs = secParts.length > 1
          ? int.parse(secParts[1].padRight(2, '0').substring(0, 2))
          : 0;
      return sec * 100 + cs;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// TYF Yüzme Sonuçları — Sonuç Listesi Satır Yapısı (v2.0)
/// Katı Design System ve Minimalist Spor Paneli:
/// 1. Sol Sütun:
///    - Yarış sonuçlanmışsa: Yarış sonu resmi sıralaması (Örn: 1., 2., 3.)
///    - Yarış bekliyorsa: Seri / Kulvar kısaltması (Örn: S3/7)
/// 2. Orta Sütun: Sporcu Adı (15px w500) ve Kulüp Adı (12px w400, seçili takımsa rozet)
/// 3. Sağ Sütun:
///    - Üst: Resmi Bitiş Derecesi (15px tabular rakamlar)
///    - Alt (Sonuçlananlar için): Küçük karakterle giriş derecesi, iyileşme varsa yeşil yukarı ok
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
    final palette = context.palette;

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

    // Sol taraftaki gösterge:
    // Yarış sonuçlanmışsa -> Sıralama (1., 2., 3. vb.)
    // Yarış bekliyorsa -> S3/7 (Seri/Kulvar kısaltması)
    final String leadingText;
    final TextStyle leadingStyle;

    if (isCompleted) {
      if (effectiveRank != null) {
        leadingText = '$effectiveRank.';
        // Podyum için zarif vurgu
        final isPodium = effectiveRank <= 3;
        leadingStyle = TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 14.5,
          fontWeight: isPodium ? FontWeight.w700 : FontWeight.w600,
          color: isPodium ? palette.gold : palette.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
      } else if (isDq) {
        leadingText = result.resultStatus.isNotEmpty ? result.resultStatus : 'DQ';
        leadingStyle = TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: palette.statusDanger,
        );
      } else {
        leadingText = '-';
        leadingStyle = TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary,
        );
      }
    } else {
      // Bekleyen yarış -> S3/7 formatında seri ve kulvar
      leadingText = 'S$heatStr/$laneStr';
      leadingStyle = TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
        letterSpacing: -0.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }

    // Bitiş süresi
    final String timeDisplay;
    final Color timeColor;
    if (isDq) {
      timeDisplay = result.resultStatus.isNotEmpty ? result.resultStatus : 'DQ';
      timeColor = palette.statusDanger;
    } else if (isSwimming) {
      timeDisplay = 'CANLI';
      timeColor = palette.statusLive;
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
      timeColor = palette.textPrimary;
    } else {
      // Bekleyen yarış için giriş derecesi
      final seed = _getDisplaySeedTime();
      timeDisplay = seed != null && seed.isNotEmpty ? seed : '-';
      timeColor = palette.textSecondary;
    }

    // İyileşme (İyileşme = Bitiş derecesi giriş derecesinden daha hızlıysa)
    final finishCs = result.timeCs ?? _parseTimeToCs(result.time);
    final seedCs = (result.seedTimeCs != null && result.seedTimeCs! > 0)
        ? result.seedTimeCs
        : _parseTimeToCs(result.seedTime);

    final bool hasImprovement = isCompleted &&
        !isDq &&
        finishCs != null &&
        seedCs != null &&
        finishCs > 0 &&
        seedCs > 0 &&
        finishCs < seedCs;

    final seedDisplay = _getDisplaySeedTime();

    final clubName = result.clubName.isNotEmpty
        ? _toTitleCase(result.clubName)
        : 'Ferdi Sporcu';

    final isMyTeam = SelectedClubService.instance.matches(result.clubName, result.clubId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: palette.surface,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Sol Alan: Yarış bittiyse Sıralama (1., 2.), bekliyorsa S3/7
                  SizedBox(
                    width: 44,
                    child: Text(
                      leadingText,
                      style: leadingStyle,
                      textAlign: TextAlign.start,
                    ),
                  ),
                  AppSpacing.hSm,

                  // 2. Orta Alan: Sporcu Adı ve Kulüp
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _toTitleCase(result.athleteName),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: palette.textPrimary,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (isMyTeam) ...[
                              Icon(
                                Icons.shield_rounded,
                                size: 12,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text(
                                clubName,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  fontWeight: isMyTeam ? FontWeight.w600 : FontWeight.w400,
                                  color: isMyTeam ? palette.primary : palette.textSecondary,
                                  height: 1.25,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.hSm,

                  // 3. Sağ Alan: Derece ve (Sonuçlananlar için) Giriş Derecesi + İyileşme Oku
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Ana Derece
                      Text(
                        timeDisplay,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: timeColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),

                      // Yarış sonuçlanmışsa: Giriş Derecesi ve İyileşme Durumu
                      if (isCompleted && seedDisplay != null && seedDisplay.isNotEmpty) ...[
                        const SizedBox(height: 1.5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (hasImprovement) ...[
                              Icon(
                                Icons.arrow_drop_up_rounded,
                                size: 15,
                                color: palette.statusSuccess,
                              ),
                            ],
                            Text(
                              seedDisplay,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11,
                                fontWeight: hasImprovement ? FontWeight.w600 : FontWeight.w400,
                                color: hasImprovement
                                    ? palette.statusSuccess
                                    : palette.textSecondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: palette.divider,
            indent: 44 + AppSpacing.sm,
          ),
      ],
    );
  }
}
