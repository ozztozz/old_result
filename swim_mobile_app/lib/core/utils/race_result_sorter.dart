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

  /// Sonuç listesinde birden fazla 1., 2. gibi tekrarlanan sıralamalar (farklı
  /// derecelerle) varsa, derece sürekliliğine göre yerel olarak ayrı sıralama
  /// kategorilerine böler. Tek sıralama varsa `title: null` tek grup döner.
  static List<({String? title, List<RaceResult> results})>
      splitMultipleRankings(
    List<RaceResult> list, {
    bool preferRankFirst = true,
  }) {
    if (list.isEmpty) return const [];

    final ranked = <({RaceResult item, int rank, int timeCs})>[];
    final others = <RaceResult>[];

    for (final r in list) {
      final parsedRank = parseLeadingInt(r.rank);
      final isRanked = parsedRank != 999999 &&
          parsedRank > 0 &&
          !isDisqualified(r) &&
          hasValidTime(r);
      if (isRanked) {
        ranked.add((
          item: r,
          rank: parsedRank,
          timeCs: r.timeCs ?? 99999999,
        ));
      } else {
        others.add(r);
      }
    }

    // Aynı sırada farklı dereceler var mı? (Gerçek beraberliklerde süre aynıdır)
    final timesByRank = <int, Set<int>>{};
    for (final entry in ranked) {
      timesByRank.putIfAbsent(entry.rank, () => <int>{}).add(entry.timeCs);
    }
    final hasMultipleCategories =
        timesByRank.values.any((times) => times.length > 1);

    if (!hasMultipleCategories) {
      final single = List<RaceResult>.from(list);
      sort(single, preferRankFirst: preferRankFirst);
      return [(title: null, results: single)];
    }

    final currentYear = DateTime.now().year;
    int? effectiveAgeOf(RaceResult r) {
      if (r.age != null && r.age! > 0) return r.age!;
      if (r.birthYear != null && r.birthYear! > 1900) {
        final calc = currentYear - r.birthYear!;
        if (calc > 0) return calc;
      }
      return null;
    }

    ranked.sort((a, b) {
      final cmp = a.rank.compareTo(b.rank);
      return cmp != 0 ? cmp : a.timeCs.compareTo(b.timeCs);
    });

    final tracks = <({
      List<RaceResult> items,
      int lastRank,
      int lastTimeCs,
      Set<int> ages,
    })>[];

    for (final entry in ranked) {
      final entryAge = effectiveAgeOf(entry.item);
      int? bestIdx;
      int bestScore = -1;

      for (var i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        final isNextStep =
            t.lastRank < entry.rank && t.lastTimeCs <= entry.timeCs;
        final isSameRankTie =
            t.lastRank == entry.rank && t.lastTimeCs == entry.timeCs;
        if (!isNextStep && !isSameRankTie) continue;

        // Öncelik: Aynı yaş grubundaki sporcuları aynı sıralama izine bağla.
        // İkinci öncelik: Tam bir sonraki sıra (lastRank == rank - 1).
        var score = 0;
        if (entryAge != null && t.ages.contains(entryAge)) {
          score += 100;
        }
        if (t.lastRank == entry.rank - 1) {
          score += 10;
        }
        if (score > bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }

      if (bestIdx != null) {
        final prev = tracks[bestIdx];
        prev.items.add(entry.item);
        if (entryAge != null) prev.ages.add(entryAge);
        tracks[bestIdx] = (
          items: prev.items,
          lastRank: entry.rank,
          lastTimeCs: entry.timeCs,
          ages: prev.ages,
        );
      } else {
        tracks.add((
          items: [entry.item],
          lastRank: entry.rank,
          lastTimeCs: entry.timeCs,
          ages: {if (entryAge != null) entryAge},
        ));
      }
    }

    if (tracks.length <= 1) {
      final single = List<RaceResult>.from(list);
      sort(single, preferRankFirst: preferRankFirst);
      return [(title: null, results: single)];
    }

    // Yaş bilgisi varsa grupları küçük yaştan büyüğe sırala (9, 10, 11, 12...)
    tracks.sort((a, b) {
      final minA = a.ages.isEmpty
          ? 999
          : a.ages.reduce((x, y) => x < y ? x : y);
      final minB = b.ages.isEmpty
          ? 999
          : b.ages.reduce((x, y) => x < y ? x : y);
      if (minA != minB) return minA.compareTo(minB);
      return a.items.length.compareTo(b.items.length);
    });

    final groups = <({String? title, List<RaceResult> results})>[];
    for (var i = 0; i < tracks.length; i++) {
      groups.add((
        title: _formatGroupAgeRange(tracks[i].items, i),
        results: tracks[i].items,
      ));
    }

    if (others.isNotEmpty) {
      sort(others, preferRankFirst: preferRankFirst);
      groups.add((title: 'Diğer / Beklenen', results: others));
    }

    return groups;
  }

  static String _formatGroupAgeRange(
    List<RaceResult> items,
    int fallbackIndex,
  ) {
    final currentYear = DateTime.now().year;
    final ages = <int>[];
    for (final r in items) {
      if (r.age != null && r.age! > 0) {
        ages.add(r.age!);
      } else if (r.birthYear != null && r.birthYear! > 1900) {
        final calc = currentYear - r.birthYear!;
        if (calc > 0) ages.add(calc);
      }
    }
    if (ages.isEmpty) return '${fallbackIndex + 1}. Kategori';
    ages.sort();
    final minAge = ages.first;
    final maxAge = ages.last;
    return minAge == maxAge ? '$minAge Yaş' : '$minAge–$maxAge Yaş';
  }
}
