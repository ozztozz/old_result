import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_bottom_sheet.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/favorite_live_meets_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../shared/widgets/club_selection_sheet.dart';
import 'live_meet_detail_screen.dart';
import 'live_race_results_screen.dart';

/// TYF Yüzme Sonuçları — Canlı Müsabakalar Ekranı
/// Tarih zaman çizelgesi + odak merkezli (fisheye) kaydırma efekti.
class LiveScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueListenable<int?>? selectedMeetIdListenable;
  final ValueListenable<LiveMeetSummary?>? selectedMeetListenable;

  const LiveScreen({
    super.key,
    required this.repository,
    this.selectedMeetIdListenable,
    this.selectedMeetListenable,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

// ---------------------------------------------------------------------------
// Yardımcı veri tipleri
// ---------------------------------------------------------------------------

class _MeetStatus {
  final bool completed;
  final bool live;
  final bool future;
  final double ratio;
  final int percent;
  final int total;
  final int processed;

  const _MeetStatus({
    required this.completed,
    required this.live,
    required this.future,
    required this.ratio,
    required this.percent,
    required this.total,
    required this.processed,
  });
}

// ---------------------------------------------------------------------------
// Ekran durumu
// ---------------------------------------------------------------------------

class _LiveScreenState extends State<LiveScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LiveMeetSummary> _liveMeets = [];
  int? _selectedStoryMeetId;
  bool _isFeedLoading = false;
  LiveFeedResponse? _selectedFeed;
  final Map<int, LiveFeedResponse> _feedCache = {};
  final Map<int, MeetParticipants> _participantsCache = {};
  final Map<int, String> _computedMeetAgeRanges = {};
  int _feedTabIndex = 0;
  String? _selectedAthleteName;
  bool _onlySelectedFocus = false;
  Timer? _autoRefreshTimer;

  final PageController _feedPageController = PageController();

  @override
  void initState() {
    super.initState();
    SelectedClubService.instance.addListener(_onSelectedClubChanged);
    FavoriteLiveMeetsService.instance.addListener(_onFavoriteLiveMeetsChanged);
    widget.selectedMeetIdListenable?.addListener(_onRequestedMeetIdChanged);
    widget.selectedMeetListenable?.addListener(_onRequestedMeetChanged);
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _autoRefreshSelectedFeed(),
    );
    _loadLiveMeets();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    widget.selectedMeetListenable?.removeListener(_onRequestedMeetChanged);
    widget.selectedMeetIdListenable?.removeListener(_onRequestedMeetIdChanged);
    FavoriteLiveMeetsService.instance
        .removeListener(_onFavoriteLiveMeetsChanged);
    SelectedClubService.instance.removeListener(_onSelectedClubChanged);
    _feedPageController.dispose();
    super.dispose();
  }

  void _onFavoriteLiveMeetsChanged() {
    if (!mounted) return;
    setState(() {
      _liveMeets =
          FavoriteLiveMeetsService.instance.sortWithFavoritesFirst(_liveMeets);
    });
  }

  void _onRequestedMeetIdChanged() {
    final requestedId = widget.selectedMeetIdListenable?.value;
    if (requestedId == null || !mounted) return;
    final match = _liveMeets.where((m) => m.id == requestedId).firstOrNull;
    if (match != null) {
      _selectStoryMeet(match);
    }
  }

  void _onRequestedMeetChanged() {
    final requestedMeet = widget.selectedMeetListenable?.value;
    if (requestedMeet == null || !mounted || _isLoading) return;
    _selectOrInsertMeet(requestedMeet);
  }

  LiveMeetSummary? _findMatchingMeet(
    List<LiveMeetSummary> meets,
    LiveMeetSummary target,
  ) {
    return meets.where((m) {
      if (target.id > 0 && m.id == target.id) return true;
      if (target.meetId != null && m.meetId == target.meetId) return true;
      return m.id == target.id;
    }).firstOrNull;
  }

  void _selectOrInsertMeet(LiveMeetSummary requestedMeet) {
    final match = _findMatchingMeet(_liveMeets, requestedMeet);
    if (match != null) {
      _selectStoryMeet(match);
      return;
    }
    setState(() {
      _liveMeets = [requestedMeet, ..._liveMeets];
    });
    _selectStoryMeet(requestedMeet);
  }

  void _onSelectedClubChanged() {
    if (!mounted) return;
    setState(() {});
    if (_selectedStoryMeetId != null) {
      _loadSelectedFeed(_selectedStoryMeetId!, forceRefresh: true);
    }
  }

  Future<void> _loadLiveMeets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FavoriteLiveMeetsService.instance.init();
      final rawList = await widget.repository.getLiveMeets();
      final list =
          FavoriteLiveMeetsService.instance.sortWithFavoritesFirst(rawList);
      if (mounted) {
        final requestedMeet = widget.selectedMeetListenable?.value;
        final requestedId = widget.selectedMeetIdListenable?.value;
        LiveMeetSummary? initial;
        if (requestedMeet != null) {
          initial = _findMatchingMeet(list, requestedMeet);
          if (initial == null) {
            list.insert(0, requestedMeet);
            initial = requestedMeet;
          }
        }
        initial ??= requestedId == null
            ? null
            : list.where((m) => m.id == requestedId).firstOrNull;
        if (initial == null) {
          final favs = list.where(
            (m) => FavoriteLiveMeetsService.instance.isFavorite(m.id),
          );
          for (final m in favs) {
            if (_statusOf(m).live) {
              initial = m;
              break;
            }
          }
          initial ??= favs.firstOrNull;
        }
        if (initial == null) {
          for (final m in list) {
            if (_statusOf(m).live) {
              initial = m;
              break;
            }
          }
        }
        initial ??= list.isNotEmpty ? list.first : null;

        setState(() {
          _liveMeets = list;
          _isLoading = false;
          _selectedStoryMeetId = initial?.id;
        });
        if (initial != null) {
          _loadSelectedFeed(initial.id);
        }
        _prefetchMissingAgeRanges(list);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Canlı müsabakalar yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _selectStoryMeet(LiveMeetSummary meet) {
    if (_selectedStoryMeetId == meet.id) return;
    setState(() {
      _selectedStoryMeetId = meet.id;
      _selectedFeed = _feedCache[meet.id];
      _selectedAthleteName = null;
      _onlySelectedFocus = false;
      _feedTabIndex = 0;
    });
    if (_feedPageController.hasClients) {
      _feedPageController.jumpToPage(0);
    }
    _loadSelectedFeed(meet.id);
  }

  Future<void> _autoRefreshSelectedFeed() async {
    final meetId = _selectedStoryMeetId;
    if (!mounted || meetId == null || meetId <= 0 || _isFeedLoading) return;
    final meet = _liveMeets.where((m) => m.id == meetId).firstOrNull;
    if (meet == null) return;
    final total = meet.resultListProgress.total;
    final processed = meet.resultListProgress.processed;
    if (total > 0 && processed >= total) return;
    await _loadSelectedFeed(meetId, forceRefresh: true, silent: true);
  }

  Future<void> _prefetchMissingAgeRanges(List<LiveMeetSummary> meets) async {
    final missing = meets
        .where((m) =>
            (m.ageRange == null || m.ageRange!.trim().isEmpty) &&
            m.meetId != null &&
            !_computedMeetAgeRanges.containsKey(m.id))
        .take(12)
        .toList();
    if (missing.isEmpty) return;

    final currentYear = DateTime.now().year;
    await Future.wait(
      missing.map((m) async {
        try {
          final participants =
              await widget.repository.getMeetParticipants(m.meetId!);
          _participantsCache[m.meetId!] = participants;
          final isoMatch = RegExp(r'(\d{4})').firstMatch(m.date);
          final meetYear = int.tryParse(isoMatch?.group(1) ?? '') ?? currentYear;
          final ages = participants.athletes
              .map((a) => a.birthYear)
              .whereType<int>()
              .where((by) => by > 1900 && by < meetYear)
              .map((by) => meetYear - by)
              .where((age) => age > 0 && age < 100)
              .toList();
          if (ages.isNotEmpty && mounted) {
            final counts = <int, int>{};
            for (final age in ages) {
              counts[age] = (counts[age] ?? 0) + 1;
            }
            final total = ages.length;
            final threshold =
                total < 10 ? 1 : (total * 0.03).floor().clamp(3, total);
            var valid = counts.entries
                .where((e) => e.value >= threshold)
                .map((e) => e.key)
                .toList();
            if (valid.isEmpty) valid = counts.keys.toList();
            valid.sort();
            final label = valid.first == valid.last
                ? '${valid.first} Yaş'
                : '${valid.first}–${valid.last} Yaş';
            setState(() {
              _computedMeetAgeRanges[m.id] = label;
            });
          }
        } catch (_) {
          // Katılımcı listesi alınamazsa sessizce atla
        }
      }),
    );
  }

  Future<void> _loadSelectedFeed(
    int liveMeetId, {
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (!forceRefresh && _feedCache.containsKey(liveMeetId)) {
      if (mounted && _selectedStoryMeetId == liveMeetId) {
        setState(() {
          _selectedFeed = _feedCache[liveMeetId];
          _isFeedLoading = false;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() => _isFeedLoading = true);
    }
    try {
      final clubService = SelectedClubService.instance;
      final LiveFeedResponse feed;
      final meet = _liveMeets.where((m) => m.id == liveMeetId).firstOrNull;
      if (meet?.meetId != null && !_participantsCache.containsKey(meet!.meetId!)) {
        widget.repository.getMeetParticipants(meet.meetId!).then((p) {
          if (mounted) {
            setState(() {
              _participantsCache[meet.meetId!] = p;
            });
          }
        }).catchError((_) {});
      }
      if (meet != null && meet.id <= 0 && meet.meetId != null) {
        final responses = await Future.wait([
          widget.repository.getMeetDetail(meet.meetId!),
          widget.repository.getMeetResults(
            meet.meetId!,
            page: 1,
            summary: true,
          ),
        ]);
        final detail = responses[0] as MeetDetail;
        var results = List<RaceResult>.from(responses[1] as List<RaceResult>);
        final mappedEvents = detail.events.map((e) {
          final lowerStatus = e.status.toLowerCase();
          final isDone = !e.isPending ||
              lowerStatus.contains('tamam') ||
              lowerStatus.contains('sonuc') ||
              lowerStatus.contains('sonuç');
          return LiveEventProgramItem(
            eventNo: e.eventNo,
            name: '${e.distance != null ? '${e.distance}m ' : ''}${e.strokeLabel}'
                .trim(),
            distance: e.distance,
            stroke: e.stroke,
            strokeLabel: e.strokeLabel,
            gender: e.gender,
            isPending: !isDone,
            status: e.status,
          );
        }).toList();

        // Eğer sunucu summary=1 desteklemiyorsa, ilk sayfada eksik kalan
        // tamamlanmış yarışların ilk sonuçlarını yarış bazında çek.
        if (results.isNotEmpty) {
          final coveredEvents =
              results.map((r) => r.eventNo.trim()).where((e) => e.isNotEmpty).toSet();
          final missingEvents = mappedEvents
              .where((ev) => !ev.isPending && !coveredEvents.contains(ev.eventNo.trim()))
              .toList();
          for (var i = 0; i < missingEvents.length; i += 6) {
            final chunk = missingEvents.skip(i).take(6).toList();
            final chunkResults = await Future.wait(
              chunk.map(
                (ev) => widget.repository
                    .getMeetResults(meet.meetId!, eventNo: ev.eventNo, page: 1)
                    .catchError((_) => <RaceResult>[]),
              ),
            );
            for (final list in chunkResults) {
              results.addAll(list.take(3));
            }
          }
        }

        feed = LiveFeedResponse(
          liveId: meet.id,
          status: 'TAMAMLANDI',
          events: mappedEvents,
          data: results,
        );
      } else {
        feed = await widget.repository.getLiveSummary(
          liveMeetId,
          clubId: clubService.clubId,
          clubName: clubService.clubName,
          athleteName: _selectedAthleteName,
        );
      }
      _feedCache[liveMeetId] = feed;
      if (mounted && _selectedStoryMeetId == liveMeetId) {
        setState(() {
          _selectedFeed = feed;
          _isFeedLoading = false;
        });
      }
    } catch (_) {
      if (!silent && mounted && _selectedStoryMeetId == liveMeetId) {
        setState(() => _isFeedLoading = false);
      }
    }
  }

  void _openLiveDetail(LiveMeetSummary live) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMeetDetailScreen(
          live: live,
          repository: widget.repository,
        ),
      ),
    );
  }

  static const List<String> _trMonthsShort = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  static String _formatBadgeStartDate(String rawDate, String fallbackName) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return _toTurkishTitleCase(fallbackName);
    }
    final isoMatch = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (isoMatch != null) {
      final day = int.tryParse(isoMatch.group(3) ?? '') ?? 1;
      final month = int.tryParse(isoMatch.group(2) ?? '') ?? 1;
      final mAbbr =
          (month >= 1 && month <= 12) ? _trMonthsShort[month - 1] : '';
      return mAbbr.isNotEmpty ? '$day $mAbbr' : trimmed;
    }
    final dotMatch = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(trimmed);
    if (dotMatch != null) {
      final day = int.tryParse(dotMatch.group(1) ?? '') ?? 1;
      final month = int.tryParse(dotMatch.group(2) ?? '') ?? 1;
      final mAbbr =
          (month >= 1 && month <= 12) ? _trMonthsShort[month - 1] : '';
      return mAbbr.isNotEmpty ? '$day $mAbbr' : trimmed;
    }
    final textMatch = RegExp(
      r'^(\d{1,2})(?:\s*[-–]\s*\d{1,2})?\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)',
    ).firstMatch(trimmed);
    if (textMatch != null) {
      final day = textMatch.group(1)!;
      final monthWord = textMatch.group(2)!;
      final shortMonth =
          monthWord.length >= 3 ? monthWord.substring(0, 3) : monthWord;
      return '$day $shortMonth';
    }
    return trimmed;
  }

  String? _extractBadgeAgeRange(LiveMeetSummary meet) {
    final apiRange = meet.ageRange?.trim() ?? '';
    if (apiRange.isNotEmpty) return apiRange;

    final computed = _computedMeetAgeRanges[meet.id];
    if (computed != null && computed.isNotEmpty) return computed;

    final cachedResults = _feedCache[meet.id]?.results;
    if (cachedResults != null && cachedResults.isNotEmpty) {
      final currentYear = DateTime.now().year;
      final ages = <int>[];
      for (final r in cachedResults) {
        if (r.age != null && r.age! > 0 && r.age! < 100) {
          ages.add(r.age!);
        } else if (r.birthYear != null && r.birthYear! > 1900) {
          final calc = currentYear - r.birthYear!;
          if (calc > 0 && calc < 100) ages.add(calc);
        }
      }
      if (ages.isNotEmpty) {
        ages.sort();
        final minA = ages.first;
        final maxA = ages.last;
        return minA == maxA ? '$minA Yaş' : '$minA–$maxA Yaş';
      }
    }

    final name = meet.name.trim();
    if (name.isEmpty) return null;

    final listMatch = RegExp(
      r'(\d{1,2}(?:\s*[-–,/]\s*\d{1,2})+)\s*yaş',
      caseSensitive: false,
    ).firstMatch(name);
    if (listMatch != null) {
      final nums = RegExp(r'\d{1,2}')
          .allMatches(listMatch.group(1)!)
          .map((m) => int.tryParse(m.group(0)!))
          .whereType<int>()
          .toList()
        ..sort();
      if (nums.isNotEmpty) {
        return nums.first == nums.last
            ? '${nums.first} Yaş'
            : '${nums.first}–${nums.last} Yaş';
      }
    }

    final plusMatch = RegExp(
      r'(\d{1,2}\s*\+)\s*yaş',
      caseSensitive: false,
    ).firstMatch(name);
    if (plusMatch != null) {
      return '${plusMatch.group(1)!.replaceAll(' ', '')} Yaş';
    }

    final singleMatch = RegExp(
      r'(\d{1,2})\s*yaş',
      caseSensitive: false,
    ).firstMatch(name);
    if (singleMatch != null) {
      return '${singleMatch.group(1)} Yaş';
    }

    return null;
  }

  static String _toTurkishTitleCase(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    return StringUtils.toTitleCase(trimmed);
  }

  static String _formatAthleteName(String raw) {
    return StringUtils.formatAthleteName(raw);
  }

  static bool _isFutureDate(String rawDate) {
    final trimmed = rawDate.trim();
    DateTime? parsed;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (iso != null) {
      parsed = DateTime.tryParse(
        '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}',
      );
    } else {
      final dot =
          RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(trimmed);
      if (dot != null) {
        final d = int.tryParse(dot.group(1)!);
        final m = int.tryParse(dot.group(2)!);
        final y = int.tryParse(dot.group(3)!);
        if (d != null && m != null && y != null) {
          parsed = DateTime(y, m, d);
        }
      }
    }
    if (parsed == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return parsed.isAfter(today);
  }

  _MeetStatus _statusOf(LiveMeetSummary meet) {
    final total = meet.resultListProgress.total;
    final processed = meet.resultListProgress.processed;
    final ratio = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round().clamp(0, 100);
    final s = meet.status.toLowerCase();
    final completed =
        (total > 0 && percent >= 100) || (total == 0 && s.contains('tamam'));
    final live = !completed &&
        (s.contains('canl') ||
            s.contains('isleniyor') ||
            s.contains('devam') ||
            s.contains('live'));
    final future = !completed && !live && _isFutureDate(meet.date);
    return _MeetStatus(
      completed: completed,
      live: live,
      future: future,
      ratio: ratio,
      percent: percent,
      total: total,
      processed: processed,
    );
  }

  Color _statusColor(AppColorPalette palette, _MeetStatus st) {
    if (st.live) return palette.statusLive;
    if (st.completed) return palette.primary;
    if (st.future) return const Color(0xFF5B7C99);
    return palette.gold;
  }

  @override
  Widget build(BuildContext context) {
    final meets = _liveMeets;
    final palette = context.palette;

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: _isLoading
                    ? _buildLoadingSkeleton()
                    : _errorMessage != null && _liveMeets.isEmpty
                        ? Center(
                            child: EmptyStateWidget(
                              title: 'Bağlantı Hatası',
                              message: _errorMessage!,
                              icon: Icons.cloud_off_outlined,
                              actionText: 'Tekrar Dene',
                              onAction: _loadLiveMeets,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            child: _buildFixedLayoutBody(palette, meets),
                          ),
        ),
      ),
    );
  }

  /// Yükleme iskeleti (spinner yok). İstersen AppSkeleton.card ile değiştir.
  Widget _buildLoadingSkeleton() {
    final palette = context.palette;
    final bar = palette.textSecondary.withValues(alpha: 0.14);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        for (int i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftGlassPanel(
              level: 2,
              height: 92,
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height: 10,
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 180,
                    height: 10,
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFixedLayoutBody(
    AppColorPalette palette,
    List<LiveMeetSummary> meets,
  ) {
    if (meets.isEmpty) {
      return RefreshIndicator(
        color: palette.primary,
        onRefresh: _loadLiveMeets,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 12),
          children: const [
            EmptyStateWidget(
              title: 'Aktif Müsabaka Bulunamadı',
              message:
                  'Filtre kriterlerinize uyan canlı yarış şu anda bulunmuyor.',
              icon: Icons.pool_outlined,
            ),
          ],
        ),
      );
    }

    final selectedStoryMeet = meets.firstWhere(
      (m) => m.id == _selectedStoryMeetId,
      orElse: () => meets.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMeetStoriesStrip(palette, meets, selectedStoryMeet),
        const SizedBox(height: 14),
        Expanded(
          child: _buildSelectedStoryFeedSection(palette, selectedStoryMeet),
        ),
      ],
    );
  }

  Widget _buildMeetStoriesStrip(
    AppColorPalette palette,
    List<LiveMeetSummary> meets,
    LiveMeetSummary? selected,
  ) {
    final selectedIndex =
        selected == null ? 0 : meets.indexWhere((m) => m.id == selected.id);
    final activeDotIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: meets.length,
            itemBuilder: (context, index) {
              final meet = meets[index];
              final st = _statusOf(meet);
              final isSelected = selected?.id == meet.id;
              final city =
                  meet.city.trim().isNotEmpty ? meet.city.trim() : 'Türkiye';
              final initials = city.length >= 3
                  ? city.substring(0, 3).toUpperCase()
                  : city.toUpperCase();
              final statusColor = _statusColor(palette, st);

              return Padding(
                padding: EdgeInsets.only(
                  right: index == meets.length - 1 ? 0 : 14,
                ),
                child: _KheloLiveOnTapScale(
                  onTap: () => _selectStoryMeet(meet),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 58,
                              height: 58,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.surface,
                                border: Border.all(
                                  color: isSelected
                                      ? statusColor
                                      : statusColor.withValues(alpha: 0.72),
                                  width: isSelected ? 2.4 : 1.6,
                                ),
                              ),
                              child: CircleAvatar(
                                backgroundColor: isSelected
                                    ? palette.surfaceContrast
                                    : statusColor.withValues(alpha: 0.16),
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.displayFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? palette.textOnContrast
                                        : palette.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            if (FavoriteLiveMeetsService.instance
                                .isFavorite(meet.id))
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: palette.statusWarning,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: palette.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.star_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (st.live)
                              Positioned(
                                right: 1,
                                bottom: 1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: palette.statusLive,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: palette.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _formatBadgeStartDate(meet.date, meet.name),
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      height: 1.15,
                                      color: isSelected
                                          ? palette.textPrimary
                                          : palette.textSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_extractBadgeAgeRange(meet) != null) ...[
                                const SizedBox(height: 2),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _extractBadgeAgeRange(meet)!,
                                      maxLines: 1,
                                      softWrap: false,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        height: 1.1,
                                        color: palette.textSecondary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (meets.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < meets.length && i < 8; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == activeDotIndex ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == activeDotIndex
                        ? palette.accent
                        : palette.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSelectedStoryFeedSection(
    AppColorPalette palette,
    LiveMeetSummary meet,
  ) {
    final city = meet.city.trim().isNotEmpty ? meet.city.trim() : 'Türkiye';
    final feed =
        (_selectedFeed?.liveId == meet.id) ? _selectedFeed : _feedCache[meet.id];
    final events = feed?.events ?? const <LiveEventProgramItem>[];
    final results = feed?.data ?? const <RaceResult>[];

    final resultsByEvent = <String, List<RaceResult>>{};
    for (final r in results) {
      final key = r.eventNo;
      if (key.isEmpty) continue;
      resultsByEvent.putIfAbsent(key, () => []).add(r);
    }

    final st = _statusOf(meet);
    final totalRaces = meet.resultListProgress.total > 0
        ? '${meet.resultListProgress.processed}/${meet.resultListProgress.total}'
        : '${events.length}';

    final onContrast = palette.textOnContrast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: palette.surfaceContrast,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('selected_story_meet_header'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openLiveDetail(meet),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.location_on_rounded,
                                      size: 13.5,
                                      color: palette.primary,
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text: city,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: palette.primary,
                                  ),
                                ),
                                if (meet.date.trim().isNotEmpty) ...[
                                  TextSpan(
                                    text: '  ·  ',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: onContrast.withAlpha(140),
                                    ),
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(
                                        Icons.calendar_today_rounded,
                                        size: 11.5,
                                        color: onContrast.withAlpha(180),
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: meet.date.trim(),
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: onContrast.withAlpha(185),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _toTurkishTitleCase(meet.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.displayFontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: onContrast,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ListenableBuilder(
                    listenable: NotificationService.instance,
                    builder: (context, _) {
                      final notifService = NotificationService.instance;
                      final isEnabled = notifService.liveNotificationsEnabled &&
                          notifService.hasPermission;
                      return IconButton(
                        key: const ValueKey('live_notifications_toggle'),
                        onPressed: () async {
                          final next = !isEnabled;
                          final ok =
                              await notifService.setLiveNotificationsEnabled(
                            next,
                            favoriteMeetIds:
                                FavoriteLiveMeetsService.instance.favoriteIds,
                          );
                          if (!context.mounted) return;
                          final msg = !ok
                              ? 'Bildirim izni verilmedi. Ayarlardan izin verebilirsiniz.'
                              : next
                                  ? 'Favori canlı yarış bildirimleri açıldı.'
                                  : 'Canlı yarış bildirimleri kapatıldı.';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        tooltip: isEnabled
                            ? 'Canlı yarış bildirimlerini kapat'
                            : 'Canlı yarış bildirimlerini aç',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: Icon(
                          isEnabled
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_off_outlined,
                          size: 20,
                          color: isEnabled
                              ? palette.primary
                              : onContrast.withAlpha(165),
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final isFav =
                          FavoriteLiveMeetsService.instance.isFavorite(meet.id);
                      return IconButton(
                        key: ValueKey('favorite_live_meet_${meet.id}'),
                        onPressed: () => FavoriteLiveMeetsService.instance
                            .toggleFavorite(meet.id),
                        tooltip: isFav
                            ? 'Favorilerden çıkar'
                            : 'Favori canlı yarışa ekle',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: Icon(
                          isFav
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 21,
                          color: isFav
                              ? palette.statusWarning
                              : onContrast.withAlpha(185),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: onContrast.withAlpha(32),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _statusColor(palette, st),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            st.live
                                ? 'Canlı'
                                : (st.completed
                                    ? 'Tamamlandı'
                                    : (st.future ? 'İleri Tarihli' : 'Bekliyor')),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: onContrast,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Yarış: $totalRaces',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: onContrast.withAlpha(190),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        meet.totalAthletes > 0
                            ? 'Sporcu: ${meet.totalAthletes}'
                            : 'Şehir: $city',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: onContrast.withAlpha(190),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (meet.resultListProgress.total > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (meet.resultListProgress.processed /
                            meet.resultListProgress.total)
                        .clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: onContrast.withAlpha(36),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _statusColor(palette, st),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
          if (_isFeedLoading && feed == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: palette.progressTrack,
                valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
              ),
            )
          else if (events.isEmpty)
            GestureDetector(
              onTap: () => _openLiveDetail(meet),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pool_rounded,
                      size: 18,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Seri programı & sonuçları görüntülemek için dokunun',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Expanded(
              child: Builder(
                builder: (context) {
                  final clubService = SelectedClubService.instance;
                  final selectedAthlete =
                      _selectedAthleteName?.trim().toLowerCase();
                  final hasFocus = clubService.hasSelectedClub ||
                      (selectedAthlete != null && selectedAthlete.isNotEmpty);

                  bool eventHasFocusMatch(LiveEventProgramItem e) {
                    final list =
                        resultsByEvent[e.eventNo] ?? const <RaceResult>[];
                    return list.any((r) {
                      final matchesClub = clubService.hasSelectedClub &&
                          clubService.matches(r.clubName, r.clubId);
                      final matchesAthlete = selectedAthlete != null &&
                          selectedAthlete.isNotEmpty &&
                          r.athleteName.trim().toLowerCase() ==
                              selectedAthlete;
                      return matchesClub || matchesAthlete;
                    });
                  }

                  final visibleEvents = (_onlySelectedFocus && hasFocus)
                      ? events.where(eventHasFocusMatch).toList()
                      : events;

                  bool isEventDone(LiveEventProgramItem e) =>
                      !e.isPending || e.status.toLowerCase().contains('sonu');
                  int parseEventOrder(LiveEventProgramItem e) =>
                      int.tryParse(
                        e.eventNo.replaceAll(RegExp(r'[^0-9]'), ''),
                      ) ??
                      0;

                  final completedEvents =
                      visibleEvents.where(isEventDone).toList()
                        ..sort(
                          (a, b) =>
                              parseEventOrder(b).compareTo(parseEventOrder(a)),
                        );
                  final pendingEvents =
                      visibleEvents.where((e) => !isEventDone(e)).toList()
                        ..sort(
                          (a, b) =>
                              parseEventOrder(a).compareTo(parseEventOrder(b)),
                        );

                  List<LiveEventProgramItem> eventsForTab(int tabIndex) {
                    if (tabIndex == 0) {
                      return [
                        if (completedEvents.isNotEmpty) completedEvents.first,
                        if (pendingEvents.isNotEmpty) pendingEvents.first,
                      ];
                    } else if (tabIndex == 1) {
                      return pendingEvents;
                    }
                    return completedEvents;
                  }

                  final tabs = [
                    (0, 'Son & Sıradaki'),
                    (1, 'Beklenen (${pendingEvents.length})'),
                    (2, 'Sonuçlanan (${completedEvents.length})'),
                  ];

                  final disableMotion =
                      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

                  void switchTab(int nextIndex) {
                    if (nextIndex < 0 ||
                        nextIndex > 2 ||
                        nextIndex == _feedTabIndex) {
                      return;
                    }
                    setState(() => _feedTabIndex = nextIndex);
                    if (_feedPageController.hasClients) {
                      if (disableMotion) {
                        _feedPageController.jumpToPage(nextIndex);
                      } else {
                        _feedPageController.animateToPage(
                          nextIndex,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    }
                  }

                  final selectedMeet = _liveMeets
                      .where((m) => m.id == _selectedStoryMeetId)
                      .firstOrNull;
                  final cachedParticipants = selectedMeet?.meetId != null
                      ? _participantsCache[selectedMeet!.meetId!]
                      : null;

                  final availableClubs = (cachedParticipants != null &&
                          cachedParticipants.clubs.isNotEmpty)
                      ? (cachedParticipants.clubs
                          .map((c) => c.name.trim())
                          .where((c) => c.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort())
                      : ((feed?.results ?? const <RaceResult>[])
                          .map((r) => r.clubName.trim())
                          .where((c) => c.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort());

                  final availableAthletes = (cachedParticipants != null &&
                          cachedParticipants.athletes.isNotEmpty)
                      ? (cachedParticipants.athletes
                          .map((a) => a.name.trim())
                          .where((a) => a.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort())
                      : ((feed?.results ?? const <RaceResult>[])
                          .map((r) => r.athleteName.trim())
                          .where((a) => a.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort());

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFeedFocusSelectorRow(
                        palette,
                        availableClubs: availableClubs,
                        availableAthletes: availableAthletes,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            for (final tab in tabs)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: tab.$1 < 2 ? 8 : 0,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => switchTab(tab.$1),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _feedTabIndex == tab.$1
                                            ? palette.accent
                                            : palette.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_feedTabIndex == tab.$1
                                                    ? palette.accent
                                                    : palette.textPrimary)
                                                .withValues(
                                              alpha: _feedTabIndex == tab.$1
                                                  ? 0.24
                                                  : 0.04,
                                            ),
                                            blurRadius:
                                                _feedTabIndex == tab.$1 ? 10 : 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            tab.$2,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTextStyles.fontFamily,
                                              fontSize: 12,
                                              fontWeight:
                                                  _feedTabIndex == tab.$1
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                              color: _feedTabIndex == tab.$1
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary
                                                  : palette.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _feedPageController,
                          itemCount: 3,
                          onPageChanged: (index) {
                            if (_feedTabIndex != index) {
                              setState(() => _feedTabIndex = index);
                            }
                          },
                          itemBuilder: (context, pageIndex) {
                            final tabEvents = eventsForTab(pageIndex);
                            final emptyMessage = pageIndex == 1
                                ? 'Beklenen yarış bulunmuyor.'
                                : pageIndex == 2
                                    ? 'Henüz sonuçlanan yarış bulunmuyor.'
                                    : 'Bu sekmede yarış bulunmuyor.';
                            final listBottomPadding = 64 +
                                16 +
                                MediaQuery.of(context).padding.bottom;

                            return RefreshIndicator(
                              color: palette.primary,
                              onRefresh: () => _loadSelectedFeed(
                                meet.id,
                                forceRefresh: true,
                              ),
                              child: tabEvents.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.only(
                                        top: 12,
                                        bottom: listBottomPadding,
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 16,
                                          ),
                                          child: Text(
                                            emptyMessage,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: palette.textMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.separated(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.only(
                                        top: 2,
                                        bottom: listBottomPadding,
                                      ),
                                      itemCount: tabEvents.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (_, i) {
                                        final ev = tabEvents[i];
                                        return _buildInlineEventFeedCard(
                                          palette,
                                          meet,
                                          ev,
                                          resultsByEvent[ev.eventNo] ??
                                              const [],
                                          sectionTag: pageIndex == 0
                                              ? ((ev.isPending &&
                                                      !ev.status
                                                          .toLowerCase()
                                                          .contains('sonu'))
                                                  ? 'Başlayacak İlk Yarış'
                                                  : 'Sonuçlanan Son Yarış')
                                              : null,
                                        );
                                      },
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      );
  }

  Widget _buildFeedFocusSelectorRow(
    AppColorPalette palette, {
    required List<String> availableClubs,
    required List<String> availableAthletes,
  }) {
    final clubService = SelectedClubService.instance;
    final hasClub = clubService.hasSelectedClub;
    final hasAthlete =
        _selectedAthleteName != null && _selectedAthleteName!.trim().isNotEmpty;
    final hasAnyFocus = hasClub || hasAthlete;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: _buildFocusSelectorChip(
              palette,
              icon: hasClub ? Icons.star_rounded : Icons.groups_rounded,
              label: hasClub ? clubService.clubName! : 'Kulüp Seç',
              isSelected: hasClub,
              onTap: () => ClubSelectionSheet.show(
                context,
                availableClubs: availableClubs,
              ),
              onClear: hasClub
                  ? () {
                      clubService.clearClub();
                      if (!hasAthlete) {
                        setState(() => _onlySelectedFocus = false);
                      }
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildFocusSelectorChip(
              palette,
              icon: hasAthlete
                  ? Icons.star_rounded
                  : Icons.person_search_rounded,
              label: hasAthlete
                  ? _formatAthleteName(_selectedAthleteName!)
                  : 'Sporcu Seç',
              isSelected: hasAthlete,
              onTap: () => _showAthleteSelectionSheet(availableAthletes),
              onClear: hasAthlete
                  ? () {
                      setState(() {
                        _selectedAthleteName = null;
                        if (!hasClub) _onlySelectedFocus = false;
                      });
                      if (_selectedStoryMeetId != null) {
                        _loadSelectedFeed(_selectedStoryMeetId!,
                            forceRefresh: true);
                      }
                    }
                  : null,
            ),
          ),
          if (hasAnyFocus) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: _onlySelectedFocus
                  ? 'Yalnızca seçili yarışlar gösteriliyor'
                  : 'Sadece seçili yarışları göster',
              child: GestureDetector(
                onTap: () =>
                    setState(() => _onlySelectedFocus = !_onlySelectedFocus),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _onlySelectedFocus
                        ? palette.accent
                        : palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _onlySelectedFocus
                        ? [
                            BoxShadow(
                              color: palette.accent.withValues(alpha: 0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _onlySelectedFocus
                        ? Theme.of(context).colorScheme.onPrimary
                        : palette.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusSelectorChip(
    AppColorPalette palette, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.12)
              : palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? palette.accent.withValues(alpha: 0.35)
                : palette.border.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? palette.accent : palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? palette.accent : palette.textSecondary,
                ),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: palette.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAthleteSelectionSheet(List<String> athletes) async {
    final palette = context.palette;
    String query = '';

    await AppBottomSheet.show<void>(
      context,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final trimmed = query.trim().toLowerCase();
            final filtered = trimmed.isEmpty
                ? athletes
                : athletes
                    .where((a) => a.toLowerCase().contains(trimmed))
                    .toList();

            return AppBottomSheet(
              scrollable: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.65,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sporcu Seç',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (_selectedAthleteName != null)
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedAthleteName = null);
                              Navigator.pop(sheetCtx);
                              if (_selectedStoryMeetId != null) {
                                _loadSelectedFeed(_selectedStoryMeetId!,
                                    forceRefresh: true);
                              }
                            },
                            child: Text(
                              'Temizle',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      autofocus: false,
                      onChanged: (val) => setSheetState(() => query = val),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Sporcu ara...',
                        hintStyle: TextStyle(color: palette.textMuted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: palette.textSecondary,
                        ),
                        filled: true,
                        fillColor: palette.surfaceSecondary,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              athletes.isEmpty
                                  ? 'Bu müsabakada sporcu listesi yok.'
                                  : 'Eşleşen sporcu bulunamadı.',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: palette.textMuted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: palette.divider,
                            ),
                            itemBuilder: (_, index) {
                              final name = filtered[index];
                              final isCurrent = _selectedAthleteName
                                      ?.trim()
                                      .toLowerCase() ==
                                  name.trim().toLowerCase();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                title: Text(
                                  _formatAthleteName(name),
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 14,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrent
                                        ? palette.accent
                                        : palette.textPrimary,
                                  ),
                                ),
                                trailing: isCurrent
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: palette.accent,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() => _selectedAthleteName = name);
                                  Navigator.pop(sheetCtx);
                                  if (_selectedStoryMeetId != null) {
                                    _loadSelectedFeed(_selectedStoryMeetId!,
                                        forceRefresh: true);
                                  }
                                },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInlineEventFeedCard(
    AppColorPalette palette,
    LiveMeetSummary meet,
    LiveEventProgramItem event,
    List<RaceResult> eventResults, {
    String? sectionTag,
  }) {
    final topThree = eventResults.take(3).toList();
    final clubService = SelectedClubService.instance;
    final selectedAthlete = _selectedAthleteName?.trim().toLowerCase();
    bool isResultMatch(RaceResult r) {
      final matchesClub = clubService.hasSelectedClub &&
          clubService.matches(r.clubName, r.clubId);
      final matchesAthlete = selectedAthlete != null &&
          selectedAthlete.isNotEmpty &&
          r.athleteName.trim().toLowerCase() == selectedAthlete;
      return matchesClub || matchesAthlete;
    }

    final clubMatches = eventResults.where(isResultMatch).toList();
    final extraClubMatches = clubMatches
        .where((m) => !topThree.any((t) => t.id == m.id))
        .toList();
    final hasDistance = event.distance != null && event.distance! > 0;
    final strokeText = (hasDistance && event.strokeLabel.isNotEmpty)
        ? event.strokeLabel
        : event.displayTitle;
    final genderText = event.genderLabel;
    final isFemale = genderText == 'Kadınlar';
    final isMale = genderText == 'Erkekler';
    final isDone = !event.isPending ||
        event.status.toLowerCase().contains('sonu');
    final ageText = (event.ageGroup ?? '').trim();

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          LiveRaceResultsScreen.showSheet(
            context,
            live: meet,
            event: event,
            repository: widget.repository,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: sectionTag == 'Başlayacak İlk Yarış'
                ? Border(
                    left: BorderSide(
                      color: palette.statusWarning,
                      width: 3.5,
                    ),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: palette.textPrimary.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sectionTag != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (isDone
                            ? palette.statusSuccess
                            : palette.statusWarning)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    sectionTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDone
                          ? palette.statusSuccess
                          : palette.statusWarning,
                    ),
                  ),
                ),
              ],
            Row(
              children: [
                if (hasDistance) ...[
                  Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.accent.withValues(alpha: 0.2),
                          palette.infoCyan.withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border.all(
                        color: palette.accent.withValues(alpha: 0.38),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface.withValues(alpha: 0.65),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${event.distance}',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: AppTextStyles.displayFontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: palette.accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          strokeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (genderText.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Tooltip(
                          message: genderText,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: (isFemale
                                      ? palette.statusLive
                                      : (isMale
                                          ? palette.accent
                                          : palette.infoCyan))
                                  .withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (isFemale
                                        ? palette.statusLive
                                        : (isMale
                                            ? palette.accent
                                            : palette.infoCyan))
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              isFemale
                                  ? Icons.female_rounded
                                  : (isMale
                                      ? Icons.male_rounded
                                      : Icons.wc_rounded),
                              size: 16,
                              color: isFemale
                                  ? palette.statusLive
                                  : (isMale
                                      ? palette.accent
                                      : palette.infoCyan),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (clubMatches.isNotEmpty && !isDone) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: palette.accent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${clubMatches.length}',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (event.eventNo.trim().isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceContrast,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Yarış ${event.eventNo.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textOnContrast,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Tooltip(
                  message: event.status,
                  child: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 17,
                    color: isDone
                        ? palette.statusSuccess
                        : palette.statusWarning,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
                ),
              ],
            ),
            if (ageText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.7),
                    width: 1,
                  ),
                ),
                child: Text(
                  ageText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
            if (topThree.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (int r = 0; r < topThree.length; r++)
                _buildInlineResultRow(
                  palette,
                  rankLabel: _formatInlineRankLabel(
                    topThree[r],
                    isDone: isDone,
                    fallbackIndex: r,
                  ),
                  result: topThree[r],
                  isHighlighted: isResultMatch(topThree[r]),
                  isPending: !isDone,
                ),
              if (extraClubMatches.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 1),
                  child: Text(
                    '···',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                for (final extra in extraClubMatches)
                  _buildInlineResultRow(
                    palette,
                    rankLabel: _formatInlineRankLabel(
                      extra,
                      isDone: isDone,
                    ),
                    result: extra,
                    isHighlighted: true,
                    isPending: !isDone,
                  ),
              ],
            ],
          ],
        ),
        ),
      ),
    );
  }

  String _formatInlineRankLabel(
    RaceResult result, {
    required bool isDone,
    int? fallbackIndex,
  }) {
    if (!isDone) {
      final heatMatch = RegExp(r'\d+').firstMatch(result.heat);
      final heat = heatMatch?.group(0) ?? result.heat.trim();
      final lane = result.lane;
      if (heat.isNotEmpty && lane != null) return '$heat/$lane';
      if (heat.isNotEmpty) return heat;
      if (lane != null) return '$lane';
      return '•';
    }
    if (fallbackIndex != null) return '${fallbackIndex + 1}.';
    final rank = result.rank.trim();
    return rank.isNotEmpty ? '$rank.' : '•';
  }

  Widget _buildInlineRankBadge(
    AppColorPalette palette, {
    required String rankLabel,
    required bool isPending,
  }) {
    if (isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: palette.border.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        child: Text(
          rankLabel,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: palette.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final cleanRank = rankLabel.replaceAll('.', '').trim();
    final Color badgeColor;
    if (cleanRank == '1') {
      badgeColor = palette.statusWarning;
    } else if (cleanRank == '2') {
      badgeColor = palette.textSecondary;
    } else if (cleanRank == '3') {
      badgeColor = palette.accent;
    } else {
      return Text(
        rankLabel,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: palette.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        cleanRank,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: badgeColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildInlineResultRow(
    AppColorPalette palette, {
    required String rankLabel,
    required RaceResult result,
    required bool isHighlighted,
    required bool isPending,
  }) {
    final seed = result.seedTime?.trim();
    final displayTime = isPending
        ? ((seed != null && seed.isNotEmpty) ? seed : (result.time ?? '–'))
        : (result.time ?? '–');
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: isHighlighted
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
          : EdgeInsets.zero,
      decoration: isHighlighted
          ? BoxDecoration(
              color: palette.accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(7),
            )
          : null,
      child: Row(
        children: [
          if (isHighlighted) ...[
            Icon(
              Icons.star_rounded,
              size: 12,
              color: palette.accent,
            ),
            const SizedBox(width: 4),
          ],
          _buildInlineRankBadge(
            palette,
            rankLabel: rankLabel,
            isPending: isPending,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _formatAthleteName(result.athleteName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            displayTime,
            style: TextStyle(
              fontFamily: AppTextStyles.displayFontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isHighlighted ? palette.accent : palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

}

class _KheloLiveOnTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _KheloLiveOnTapScale({
    required this.child,
    this.onTap,
  });

  @override
  State<_KheloLiveOnTapScale> createState() => _KheloLiveOnTapScaleState();
}

class _KheloLiveOnTapScaleState extends State<_KheloLiveOnTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration:
            disableMotion ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

