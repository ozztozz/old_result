import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/app_page_shell.dart';
import '../../shared/widgets/live_event_header.dart';
import '../../shared/widgets/live_result_row.dart';
import '../athletes/athlete_profile_screen.dart';
import 'live_race_results_screen.dart';

/// Tam ekran Yarış–Takım Ekranı:
/// Seçili kulübün bu müsabakadaki tüm sporcularını ve yarışlarını
/// Sporcu Bazlı veya Yarış Bazlı (Beklenen / Sonuçlanan sekmeli) kompakt listelerle gösterir.
class LiveClubMeetScreen extends StatefulWidget {
  final LiveMeetSummary meet;
  final List<LiveEventProgramItem> initialEvents;
  final List<RaceResult> initialResults;
  final SwimRepository repository;
  final Future<LiveFeedResponse?> Function()? onRefreshFeed;

  const LiveClubMeetScreen({
    super.key,
    required this.meet,
    required this.initialEvents,
    required this.initialResults,
    required this.repository,
    this.onRefreshFeed,
  });

  @override
  State<LiveClubMeetScreen> createState() => _LiveClubMeetScreenState();
}

class _LiveClubMeetScreenState extends State<LiveClubMeetScreen> {
  late List<LiveEventProgramItem> _events;
  late List<RaceResult> _results;
  bool _isRefreshing = false;

  String _groupBy = 'athlete'; // 'athlete' | 'race'
  int _raceStatusTabIndex = 0; // 0: Beklenen, 1: Sonuçlanan
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, List<RaceResult>> _eventDetailsCache = {};

  Future<Map<String, String>?> _loadSplitsForResult(RaceResult result) async {
    if (result.splitTimes != null && result.splitTimes!.isNotEmpty) {
      return result.splitTimes;
    }
    final eventNo = result.eventNo.trim();
    if (eventNo.isEmpty) return null;

    var list = _eventDetailsCache[eventNo];
    if (list == null) {
      if (widget.meet.id > 0) {
        final feed = await widget.repository.getLiveFeedResponse(
          widget.meet.id,
          eventNo: eventNo,
        );
        list = List<RaceResult>.from(feed.results);
      } else if (widget.meet.meetId != null) {
        list = await widget.repository.getMeetResults(
          widget.meet.meetId!,
          eventNo: eventNo,
          page: 1,
        );
      } else {
        list = const [];
      }
      _eventDetailsCache[eventNo] = list;
    }

    final targetName = result.athleteName.trim().toLowerCase();
    final match = list.where((r) {
      if (result.id > 0 && r.id == result.id) return true;
      if (result.athleteId > 0 && r.athleteId == result.athleteId) return true;
      return r.athleteName.trim().toLowerCase() == targetName;
    }).firstOrNull;
    return match?.splitTimes;
  }

  @override
  void initState() {
    super.initState();
    _events = widget.initialEvents;
    _results = widget.initialResults;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      if (widget.onRefreshFeed != null) {
        final updated = await widget.onRefreshFeed!();
        if (updated != null && mounted) {
          setState(() {
            _events = updated.events;
            _results = updated.data;
          });
        }
      } else if (widget.meet.id > 0) {
        final clubService = SelectedClubService.instance;
        final updated = await widget.repository.getLiveSummary(
          widget.meet.id,
          clubId: clubService.clubId,
          clubName: clubService.clubName,
        );
        if (mounted) {
          setState(() {
            _events = updated.events;
            _results = updated.data;
          });
        }
      }
    } catch (_) {
      // Sessizce mevcut veriyi koru
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  bool _isRaceDone(RaceResult r) {
    final st = r.resultStatus.trim().toUpperCase();
    if (st == 'DQ' || st == 'DSQ' || st == 'DNS' || st == 'DNF') return true;
    if (st == 'WAITING') return false;
    return (r.timeCs ?? 0) > 0 ||
        ((r.time ?? '').trim().isNotEmpty && r.time != '-');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clubService = SelectedClubService.instance;

    final eventMap = <String, LiveEventProgramItem>{};
    for (final e in _events) {
      final k = e.eventNo.trim();
      if (k.isNotEmpty) eventMap[k] = e;
    }

    final clubResults = _results
        .where((r) => clubService.matches(r.clubName, r.clubId))
        .toList();

    final q = _searchQuery.trim().toLowerCase();
    final filteredResults = clubResults.where((r) {
      if (q.isEmpty) return true;
      final ev = eventMap[r.eventNo.trim()];
      final athleteMatch = r.athleteName.toLowerCase().contains(q);
      final eventNoMatch = r.eventNo.toLowerCase().contains(q);
      final strokeMatch = r.strokeLabel.toLowerCase().contains(q) ||
          (ev?.strokeLabel.toLowerCase().contains(q) ?? false);
      final distMatch =
          (r.distance != null && '${r.distance}m'.contains(q)) ||
              (ev?.displayTitle.toLowerCase().contains(q) ?? false);
      return athleteMatch || eventNoMatch || strokeMatch || distMatch;
    }).toList();

    final allAthleteKeys = <String>{};
    int finishedCount = 0;
    int pendingCount = 0;
    int goldCount = 0;
    int silverCount = 0;
    int bronzeCount = 0;

    for (final r in clubResults) {
      final aKey = r.athleteId > 0
          ? 'id:${r.athleteId}'
          : 'name:${r.athleteName.trim().toLowerCase()}';
      allAthleteKeys.add(aKey);
      if (_isRaceDone(r)) {
        finishedCount++;
        final st = r.resultStatus.trim().toUpperCase();
        if (st == 'OK') {
          final rankInt = int.tryParse(r.rank.replaceAll('.', '').trim());
          if (rankInt == 1) goldCount++;
          if (rankInt == 2) silverCount++;
          if (rankInt == 3) bronzeCount++;
        }
      } else {
        pendingCount++;
      }
    }

    int parseEventNo(String eno) =>
        int.tryParse(eno.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;

    // Sporcu bazlı gruplama
    final groupedByAthlete = <String, List<RaceResult>>{};
    for (final r in filteredResults) {
      final aKey = r.athleteId > 0
          ? 'id:${r.athleteId}'
          : 'name:${r.athleteName.trim().toLowerCase()}';
      groupedByAthlete.putIfAbsent(aKey, () => []).add(r);
    }
    final athleteEntries = groupedByAthlete.entries.toList()
      ..sort((a, b) => a.value.first.athleteName
          .trim()
          .toLowerCase()
          .compareTo(b.value.first.athleteName.trim().toLowerCase()));
    for (final entry in athleteEntries) {
      entry.value.sort((a, b) {
        final dayA = a.day ?? eventMap[a.eventNo.trim()]?.day ?? 99;
        final dayB = b.day ?? eventMap[b.eventNo.trim()]?.day ?? 99;
        if (dayA != dayB) return dayA.compareTo(dayB);
        final timeA = a.estimatedTime ??
            eventMap[a.eventNo.trim()]?.estimatedTime ??
            '99:99';
        final timeB = b.estimatedTime ??
            eventMap[b.eventNo.trim()]?.estimatedTime ??
            '99:99';
        final tCmp = timeA.compareTo(timeB);
        if (tCmp != 0) return tCmp;
        return parseEventNo(a.eventNo).compareTo(parseEventNo(b.eventNo));
      });
    }

    // Yarış bazlı gruplama (Beklenen / Sonuçlanan)
    final groupedByRace = <String, List<RaceResult>>{};
    for (final r in filteredResults) {
      final eno = r.eventNo.trim();
      final rKey = eno.isNotEmpty
          ? 'event:$eno'
          : 'race:${r.distance}_${r.strokeLabel}';
      groupedByRace.putIfAbsent(rKey, () => []).add(r);
    }
    final raceEntries = groupedByRace.entries.toList()
      ..sort((a, b) {
        final firstA = a.value.first;
        final firstB = b.value.first;
        final dayA = firstA.day ?? eventMap[firstA.eventNo.trim()]?.day ?? 99;
        final dayB = firstB.day ?? eventMap[firstB.eventNo.trim()]?.day ?? 99;
        if (dayA != dayB) return dayA.compareTo(dayB);
        return parseEventNo(firstA.eventNo)
            .compareTo(parseEventNo(firstB.eventNo));
      });
    int parseHeatNo(String heat) {
      final m = RegExp(r'\d+').firstMatch(heat);
      return m != null ? (int.tryParse(m.group(0)!) ?? 9999) : 9999;
    }

    for (final entry in raceEntries) {
      entry.value.sort((a, b) {
        final rankA = int.tryParse(a.rank.replaceAll('.', '').trim()) ?? 9999;
        final rankB = int.tryParse(b.rank.replaceAll('.', '').trim()) ?? 9999;
        if (rankA != rankB) return rankA.compareTo(rankB);
        final csA = a.timeCs ?? 9999999;
        final csB = b.timeCs ?? 9999999;
        if (csA != csB) return csA.compareTo(csB);
        final heatA = parseHeatNo(a.heat);
        final heatB = parseHeatNo(b.heat);
        if (heatA != heatB) return heatA.compareTo(heatB);
        final laneA = a.lane ?? 999;
        final laneB = b.lane ?? 999;
        if (laneA != laneB) return laneA.compareTo(laneB);
        return a.athleteName
            .trim()
            .toLowerCase()
            .compareTo(b.athleteName.trim().toLowerCase());
      });
    }

    bool isRaceGroupFinished(List<RaceResult> races) {
      final ev = eventMap[races.first.eventNo.trim()];
      if (ev != null && (!ev.isPending || ev.status.toLowerCase().contains('sonu'))) {
        return true;
      }
      return races.any(_isRaceDone);
    }

    final pendingRaceEntries =
        raceEntries.where((e) => !isRaceGroupFinished(e.value)).toList();
    final finishedRaceEntries =
        raceEntries.where((e) => isRaceGroupFinished(e.value)).toList().reversed.toList();
    final visibleRaceEntries =
        _raceStatusTabIndex == 0 ? pendingRaceEntries : finishedRaceEntries;

    return AppPageShell(
      subtitle: 'Kulüp Takibi',
      actions: [
        GlassCircleButton(
          icon: Icons.refresh_rounded,
          iconSize: 20,
          iconColor: palette.accent,
          tooltip: 'Yenile',
          onTap: _isRefreshing ? () {} : _handleRefresh,
        ),
      ],
      body: RefreshIndicator(
        color: palette.primary,
        onRefresh: _handleRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
                        _buildClubSummaryCard(
                          palette,
                          athleteCount: allAthleteKeys.length,
                          raceCount: clubResults.length,
                          finishedCount: finishedCount,
                          pendingCount: pendingCount,
                          goldCount: goldCount,
                          silverCount: silverCount,
                          bronzeCount: bronzeCount,
                        ),
                        const SizedBox(height: 10),
                        // Arama Kutusu
                        TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13.5,
                            color: palette.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Sporcu veya yarış ara...',
                            hintStyle: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: palette.textMuted,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 19,
                              color: palette.textMuted,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: palette.textMuted,
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: palette.surface,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Gruplama Seçici
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: palette.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildGroupModeButton(
                                  palette,
                                  icon: Icons.person_rounded,
                                  label:
                                      'Sporcu Bazlı (${athleteEntries.length})',
                                  selected: _groupBy == 'athlete',
                                  onTap: () =>
                                      setState(() => _groupBy = 'athlete'),
                                ),
                              ),
                              Expanded(
                                child: _buildGroupModeButton(
                                  palette,
                                  icon: Icons.pool_rounded,
                                  label: 'Yarış Bazlı (${raceEntries.length})',
                                  selected: _groupBy == 'race',
                                  onTap: () =>
                                      setState(() => _groupBy = 'race'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_groupBy == 'race') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRaceTabButton(
                                  palette,
                                  label:
                                      'Beklenen (${pendingRaceEntries.length})',
                                  selected: _raceStatusTabIndex == 0,
                                  onTap: () =>
                                      setState(() => _raceStatusTabIndex = 0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildRaceTabButton(
                                  palette,
                                  label:
                                      'Sonuçlanan (${finishedRaceEntries.length})',
                                  selected: _raceStatusTabIndex == 1,
                                  onTap: () =>
                                      setState(() => _raceStatusTabIndex = 1),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (clubResults.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Bu müsabakada seçili kulübe ait start veya sonuç listesi kaydı henüz yok.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: palette.textMuted,
                              ),
                            ),
                          )
                        else if (filteredResults.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Aramaya uygun yarış bulunamadı.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: palette.textMuted,
                              ),
                            ),
                          )
                        else if (_groupBy == 'athlete')
                          for (var i = 0; i < athleteEntries.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            _buildAthleteSummaryCard(
                              context,
                              palette,
                              races: athleteEntries[i].value,
                              eventMap: eventMap,
                            ),
                          ]
                        else if (visibleRaceEntries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              _raceStatusTabIndex == 0
                                  ? 'Beklenen yarış bulunmuyor.'
                                  : 'Henüz sonuçlanan yarış bulunmuyor.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: palette.textMuted,
                              ),
                            ),
                          )
                        else
                          for (var i = 0;
                              i < visibleRaceEntries.length;
                              i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            _buildRaceSummaryCard(
                              context,
                              palette,
                              races: visibleRaceEntries[i].value,
                              eventMap: eventMap,
                            ),
                          ],
                ],
              ),
            ),
          );
  }

  Widget _buildClubSummaryCard(
    AppColorPalette palette, {
    required int athleteCount,
    required int raceCount,
    required int finishedCount,
    required int pendingCount,
    required int goldCount,
    required int silverCount,
    required int bronzeCount,
  }) {
    final hasMedals = goldCount + silverCount + bronzeCount > 0;
    final clubName = StringUtils.toTitleCase(
      SelectedClubService.instance.clubName ?? 'Kulübüm',
    );
    final meetName = StringUtils.toTitleCase(widget.meet.name);
    final meetMeta = [
      if (widget.meet.city.trim().isNotEmpty) widget.meet.city.trim(),
      if (widget.meet.date.trim().isNotEmpty) widget.meet.date.trim(),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceContrast,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.textOnContrast.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shield_rounded,
                  size: 18,
                  color: palette.textOnContrast,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clubName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.textOnContrast,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meetName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.textOnContrast.withValues(alpha: 0.85),
                      ),
                    ),
                    if (meetMeta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meetMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          color: palette.textOnContrast.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Divider(
            height: 18,
            thickness: 1,
            color: palette.textOnContrast.withValues(alpha: 0.14),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$athleteCount Sporcu · $raceCount Yarış',
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textOnContrast,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$finishedCount Sonuçlandı · $pendingCount Bekleyen',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        color: palette.textOnContrast.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMedals)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.textOnContrast.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    [
                      if (goldCount > 0) '🥇$goldCount',
                      if (silverCount > 0) '🥈$silverCount',
                      if (bronzeCount > 0) '🥉$bronzeCount',
                    ].join(' '),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textOnContrast,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupModeButton(
    AppColorPalette palette, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : palette.textSecondary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaceTabButton(
    AppColorPalette palette, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAthleteSummaryCard(
    BuildContext context,
    AppColorPalette palette, {
    required List<RaceResult> races,
    required Map<String, LiveEventProgramItem> eventMap,
  }) {
    final first = races.first;
    final athleteName = StringUtils.formatAthleteName(first.athleteName);

    int medals = 0;
    for (final r in races) {
      if (_isRaceDone(r) && r.resultStatus.toUpperCase() == 'OK') {
        final rk = int.tryParse(r.rank.replaceAll('.', '').trim());
        if (rk != null && rk <= 3) medals++;
      }
    }

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _showAthleteDetailSheet(context, palette, races, eventMap),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: palette.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: palette.accent.withValues(alpha: 0.14),
                child: Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  athleteName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.displayFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (medals > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.statusWarning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '🏅$medals',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${races.length} Yarış',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRaceSummaryCard(
    BuildContext context,
    AppColorPalette palette, {
    required List<RaceResult> races,
    required Map<String, LiveEventProgramItem> eventMap,
  }) {
    final first = races.first;
    final programEvent = eventMap[first.eventNo.trim()];
    final isDone = (programEvent != null &&
            (!programEvent.isPending ||
                programEvent.status.toLowerCase().contains('sonu'))) ||
        races.any(_isRaceDone);

    final targetEvent = programEvent ??
        LiveEventProgramItem(
          eventNo: first.eventNo,
          day: first.day,
          estimatedTime: first.estimatedTime,
          name: first.strokeLabel.isNotEmpty
              ? '${first.distance ?? ''}m ${first.strokeLabel}'.trim()
              : 'Yarış ${first.eventNo}',
          distance: first.distance,
          stroke: first.stroke,
          strokeLabel: first.strokeLabel,
          ageGroup: first.ageGroup,
          isPending: !isDone,
          status: isDone ? 'Sonuçlandı' : 'Bekleniyor',
        );

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRaceDetailSheet(context, palette, races, eventMap),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: palette.textPrimary.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LiveEventHeader(
            event: targetEvent,
            isDoneOverride: isDone,
            athleteCountBadge: races.length,
          ),
        ),
      ),
    );
  }

  Future<void> _showOpaqueDetailSheet(
    BuildContext context,
    AppColorPalette palette, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: palette.surface,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                builder(sheetCtx),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAthleteDetailSheet(
    BuildContext context,
    AppColorPalette palette,
    List<RaceResult> races,
    Map<String, LiveEventProgramItem> eventMap,
  ) {
    final first = races.first;
    final athleteName = StringUtils.formatAthleteName(first.athleteName);
    final metaParts = <String>[
      if (first.birthYear != null && first.birthYear! > 1900)
        '${first.birthYear}',
      if ((first.ageGroup ?? '').trim().isNotEmpty &&
          first.ageGroup != 'Genel Sıralama')
        first.ageGroup!.trim(),
      '${races.length} Yarış',
    ];

    _showOpaqueDetailSheet(
      context,
      palette,
      builder: (sheetCtx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(sheetCtx).size.height * 0.62,
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: palette.accent.withValues(alpha: 0.14),
                    child: Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          athleteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          metaParts.join(' · '),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (first.athleteId > 0)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AthleteProfileScreen(
                              athleteId: first.athleteId,
                              athleteName: first.athleteName,
                              repository: widget.repository,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Profil'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SoftGlassPanel(
                  level: 1,
                  borderRadius: AppRadius.cardRadius,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: AppRadius.cardRadius,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: races.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 1,
                        color: palette.divider,
                      ),
                      itemBuilder: (_, i) {
                        return _buildAthleteRaceRow(
                          context,
                          palette,
                          result: races[i],
                          programEvent: eventMap[races[i].eventNo.trim()],
                          onBeforeNavigate: () => Navigator.pop(sheetCtx),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRaceDetailSheet(
    BuildContext context,
    AppColorPalette palette,
    List<RaceResult> races,
    Map<String, LiveEventProgramItem> eventMap,
  ) {
    final first = races.first;
    final programEvent = eventMap[first.eventNo.trim()];
    final day = first.day ?? programEvent?.day;
    final estTime =
        (programEvent?.estimatedTime ?? first.estimatedTime ?? '').trim();
    final distText = first.distance != null && first.distance! > 0
        ? '${first.distance}m'
        : '';
    final strokeText = first.strokeLabel.isNotEmpty
        ? first.strokeLabel
        : (programEvent?.strokeLabel ?? '');
    final raceTitle = '$distText $strokeText'.trim().isNotEmpty
        ? '$distText $strokeText'.trim()
        : (programEvent?.displayTitle ?? 'Yarış ${first.eventNo}');

    final genderText = programEvent?.genderLabel ?? '';
    final metaParts = <String>[
      if (genderText.isNotEmpty) genderText,
      if (day != null && day > 0) '$day. Gün',
      if (estTime.isNotEmpty) estTime,
      '${races.length} Sporcu',
    ];

    final targetEvent = programEvent ??
        LiveEventProgramItem(
          eventNo: first.eventNo,
          day: day,
          estimatedTime: estTime.isNotEmpty ? estTime : null,
          name: raceTitle,
          distance: first.distance,
          stroke: first.stroke,
          strokeLabel: first.strokeLabel,
          ageGroup: first.ageGroup,
        );

    _showOpaqueDetailSheet(
      context,
      palette,
      builder: (sheetCtx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(sheetCtx).size.height * 0.62,
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (first.eventNo.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.surfaceContrast,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Y${first.eventNo.trim()}',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: palette.textOnContrast,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          raceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          metaParts.join(' · '),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      LiveRaceResultsScreen.showSheet(
                        context,
                        live: widget.meet,
                        event: targetEvent,
                        repository: widget.repository,
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Tüm Yarış'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SoftGlassPanel(
                  level: 1,
                  borderRadius: AppRadius.cardRadius,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: AppRadius.cardRadius,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: races.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 1,
                        color: palette.divider,
                      ),
                      itemBuilder: (_, i) {
                        return _buildRaceAthleteRow(
                          context,
                          palette,
                          result: races[i],
                          onBeforeNavigate: () => Navigator.pop(sheetCtx),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAthleteRaceRow(
    BuildContext context,
    AppColorPalette palette, {
    required RaceResult result,
    required LiveEventProgramItem? programEvent,
    VoidCallback? onBeforeNavigate,
  }) {
    final day = result.day ?? programEvent?.day;
    final estTime =
        (result.estimatedTime ?? programEvent?.estimatedTime ?? '').trim();

    final distText = result.distance != null && result.distance! > 0
        ? '${result.distance}m'
        : '';
    final strokeText = result.strokeLabel.isNotEmpty
        ? result.strokeLabel
        : (programEvent?.strokeLabel ?? '');
    final raceTitle = '$distText $strokeText'.trim().isNotEmpty
        ? '$distText $strokeText'.trim()
        : (programEvent?.displayTitle ?? 'Yarış ${result.eventNo}');

    final heatNum =
        RegExp(r'\d+').firstMatch(result.heat)?.group(0) ?? result.heat.trim();
    final metaParts = <String>[
      if (day != null && day > 0) '$day. Gün',
      if (estTime.isNotEmpty) estTime,
      if (heatNum.isNotEmpty) 'Seri $heatNum',
      if (result.lane != null && result.lane! > 0) 'Kulvar ${result.lane}',
    ];

    final targetEvent = programEvent ??
        LiveEventProgramItem(
          eventNo: result.eventNo,
          day: day,
          estimatedTime: estTime.isNotEmpty ? estTime : null,
          name: raceTitle,
          distance: result.distance,
          stroke: result.stroke,
          strokeLabel: result.strokeLabel,
          ageGroup: result.ageGroup,
        );

    return LiveResultRow(
      result: result,
      highlightMyTeam: false,
      eventDistance: result.distance ?? programEvent?.distance,
      titleOverride: raceTitle,
      subtitleOverride: metaParts.join(' · '),
      leadingBadgeText:
          result.eventNo.trim().isNotEmpty ? 'Y${result.eventNo.trim()}' : null,
      onLoadSplits: () => _loadSplitsForResult(result),
      onTap: () {
        onBeforeNavigate?.call();
        LiveRaceResultsScreen.showSheet(
          context,
          live: widget.meet,
          event: targetEvent,
          repository: widget.repository,
        );
      },
    );
  }

  Widget _buildRaceAthleteRow(
    BuildContext context,
    AppColorPalette palette, {
    required RaceResult result,
    VoidCallback? onBeforeNavigate,
  }) {
    final heatNum =
        RegExp(r'\d+').firstMatch(result.heat)?.group(0) ?? result.heat.trim();
    final metaParts = <String>[
      if ((result.ageGroup ?? '').trim().isNotEmpty &&
          result.ageGroup != 'Genel Sıralama')
        result.ageGroup!.trim(),
      if (heatNum.isNotEmpty) 'Seri $heatNum',
      if (result.lane != null && result.lane! > 0) 'Kulvar ${result.lane}',
      if ((result.estimatedTime ?? '').trim().isNotEmpty)
        result.estimatedTime!.trim(),
    ];

    return LiveResultRow(
      result: result,
      highlightMyTeam: false,
      subtitleOverride: metaParts.join(' · '),
      onLoadSplits: () => _loadSplitsForResult(result),
      onTap: result.athleteId > 0
          ? () {
              onBeforeNavigate?.call();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AthleteProfileScreen(
                    athleteId: result.athleteId,
                    athleteName: result.athleteName,
                    repository: widget.repository,
                  ),
                ),
              );
            }
          : null,
    );
  }
}
