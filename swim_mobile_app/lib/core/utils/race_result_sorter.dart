import '../../data/models/race_result.dart';

/// Yarış sonuçları için ortak durum ve sıralama yardımcıları
abstract final class RaceResultSorter {
  /// Sporcunun diskalifiye veya yarış dışı (DQ/DSQ/DNS/DNF) olup olmadığını döndürür.
  static bool isDisqualified(RaceResult result) {
    final status = result.resultStatus.toUpperCase();
    final rankUpper = result.rank.toUpperCase();
    return status == 'DQ' ||
        status == 'DNS' ||
        status == 'DNF' ||
        rankUpper.startsWith('DQ') ||
        rankUpper.startsWith('DSQ');
  }

  /// Sonucun geçerli bir bitiş derecesine sahip olup olmadığını döndürür.
  static bool hasValidTime(RaceResult result) {
    return (result.timeCs != null && result.timeCs! > 0) ||
        (result.time != null &&
            result.time!.isNotEmpty &&
            result.time != 'Bekleniyor');
  }

  static int parseLeadingInt(dynamic val, {int fallback = 999999}) {
    if (val == null) return fallback;
    final m = RegExp(r'\d+').firstMatch(val.toString());
    if (m != null) return int.tryParse(m.group(0)!) ?? fallback;
    return fallback;
  }

  /// Sonuç listesini yerinde sıralar:
  /// 1. Geçerli dereceye sahip olanlar (resmi sıra / timeCs'ye göre)
  /// 2. Henüz bekleyenler (seri ve kulvara göre)
  /// 3. Diskalifiyeler / DNS / DNF (en sonda, seri ve kulvara göre)
  static void sort(List<RaceResult> list, {bool preferRankFirst = true}) {
    final bool hasFinishedResults =
        list.any((r) => !isDisqualified(r) && hasValidTime(r));

    list.sort((a, b) {
      final isDqA = isDisqualified(a);
      final isDqB = isDisqualified(b);

      if (isDqA && !isDqB) return 1;
      if (!isDqA && isDqB) return -1;
      if (isDqA && isDqB) {
        return _compareHeatAndLane(a, b);
      }

      if (hasFinishedResults) {
        final hasTimeA = hasValidTime(a);
        final hasTimeB = hasValidTime(b);

        if (hasTimeA && !hasTimeB) return -1;
        if (!hasTimeA && hasTimeB) return 1;

        if (hasTimeA && hasTimeB) {
          if (preferRankFirst) {
            final rankA = parseLeadingInt(a.rank);
            final rankB = parseLeadingInt(b.rank);
            if (rankA != 999999 && rankB != 999999 && rankA != rankB) {
              return rankA.compareTo(rankB);
            }
          }
          final timeA = a.timeCs ?? 99999999;
          final timeB = b.timeCs ?? 99999999;
          if (timeA != timeB) return timeA.compareTo(timeB);

          if (!preferRankFirst) {
            final rankA = parseLeadingInt(a.rank);
            final rankB = parseLeadingInt(b.rank);
            if (rankA != rankB) return rankA.compareTo(rankB);
          }
        }
      }

      return _compareHeatAndLane(a, b);
    });
  }

  static int _compareHeatAndLane(RaceResult a, RaceResult b) {
    final heatA = parseLeadingInt(a.heat);
    final heatB = parseLeadingInt(b.heat);
    if (heatA != heatB) return heatA.compareTo(heatB);
    return (a.lane ?? 999).compareTo(b.lane ?? 999);
  }
}
