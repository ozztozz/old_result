import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/app_page_shell.dart';
import '../../shared/widgets/club_selection_sheet.dart';
import '../../shared/widgets/status_badge.dart';
import 'live_club_tab.dart';

/// Kulübün canlı yarışlar dışındaki (geçmiş / arşivlenmiş) tüm müsabakaları
/// sorgulayıp kulüp bazlı sonuçlarını inceleyebileceği arama ekranı.
class ClubMeetSearchScreen extends StatefulWidget {
  final SwimRepository repository;
  final List<String> availableClubs;
  final Map<String, int> clubIdsByName;

  const ClubMeetSearchScreen({
    super.key,
    required this.repository,
    this.availableClubs = const [],
    this.clubIdsByName = const {},
  });

  @override
  State<ClubMeetSearchScreen> createState() => _ClubMeetSearchScreenState();
}

class _ClubMeetSearchScreenState extends State<ClubMeetSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _openingMeet = false;
  int _page = 1;
  String? _selectedYear;
  String? _errorMessage;
  List<MeetSummary> _meets = [];

  static const _years = ['Tümü', '2026', '2025', '2024', '2023'];

  @override
  void initState() {
    super.initState();
    SelectedClubService.instance.addListener(_onClubChanged);
    _runSearch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _cityController.dispose();
    SelectedClubService.instance.removeListener(_onClubChanged);
    super.dispose();
  }

  void _onClubChanged() {
    if (!mounted) return;
    _runSearch(reset: true);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch(reset: true);
    });
  }

  Future<void> _runSearch({required bool reset}) async {
    final clubService = SelectedClubService.instance;
    if (!clubService.hasSelectedClub) {
      setState(() {
        _meets = [];
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _errorMessage = null;
      });
      return;
    }

    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final q = _searchController.text.trim();
      final city = _cityController.text.trim();
      final year = (_selectedYear != null && _selectedYear != 'Tümü')
          ? _selectedYear
          : null;
      final list = await widget.repository.searchMeets(
        page: _page,
        q: q.isNotEmpty ? q : null,
        city: city.isNotEmpty ? city : null,
        year: year,
        clubId: clubService.clubId,
        club: clubService.clubId == null ? clubService.clubName : null,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _meets = list;
        } else {
          _meets = [..._meets, ...list];
        }
        _hasMore = list.length >= 20;
        if (list.isNotEmpty) _page++;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Müsabakalar sorgulanamadı.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _openClubPicker() async {
    await ClubSelectionSheet.show(
      context,
      availableClubs: widget.availableClubs,
      clubIdsByName: widget.clubIdsByName,
    );
  }

  Future<void> _openArchivedMeet(MeetSummary meet) async {
    if (_openingMeet) return;
    final clubService = SelectedClubService.instance;
    if (!clubService.hasSelectedClub) {
      await _openClubPicker();
      if (!mounted || !clubService.hasSelectedClub) return;
    }

    setState(() => _openingMeet = true);
    try {
      final detail = await widget.repository.getMeetDetail(meet.id);
      var resolvedClubId = clubService.clubId;
      if (resolvedClubId == null) {
        try {
          final participants =
              await widget.repository.getMeetParticipants(meet.id);
          final matched = participants.clubs
              .where((c) => clubService.matches(c.name, c.id))
              .firstOrNull;
          if (matched != null && matched.id > 0) {
            resolvedClubId = matched.id;
          }
        } catch (_) {}
      }

      final allResults = <RaceResult>[];
      for (var p = 1; p <= 10; p++) {
        final batch = await widget.repository.getMeetResults(
          meet.id,
          clubId: resolvedClubId,
          page: p,
        );
        allResults.addAll(batch);
        if (batch.length < 50) break;
      }

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

      final dateLabel = [
        if (meet.startDate.isNotEmpty) meet.startDate,
        if (meet.endDate.isNotEmpty && meet.endDate != meet.startDate)
          meet.endDate,
      ].join(' - ');

      final liveMeet = LiveMeetSummary(
        id: 0,
        meetId: meet.id,
        name: meet.name,
        city: meet.city,
        date: dateLabel,
        status: 'TAMAMLANDI',
        totalAthletes: detail.totalAthletes,
        startListProgress: LiveProgress(processed: 1, total: 1),
        resultListProgress: LiveProgress(processed: 1, total: 1),
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClubMeetScreen(
            meet: liveMeet,
            initialEvents: mappedEvents,
            initialResults: allResults,
            repository: widget.repository,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Müsabaka kulüp sonuçları yüklenemedi.'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingMeet = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clubService = SelectedClubService.instance;
    final hasClub = clubService.hasSelectedClub;

    return AppPageShell(
      subtitle: 'Kulüp Yarış Arama',
      showBack: true,
      safeBottom: true,
      actions: [
        GlassCircleButton(
          icon: Icons.groups_rounded,
          iconSize: 20,
          iconColor: palette.accent,
          tooltip: 'Kulüp Seç / Değiştir',
          onTap: _openClubPicker,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _buildSearchControls(palette, clubService, hasClub),
          ),
          if (_openingMeet)
            LinearProgressIndicator(
              minHeight: 2,
              color: palette.accent,
              backgroundColor: palette.accent.withValues(alpha: 0.12),
            ),
          Expanded(
            child: _buildResultsBody(palette, hasClub),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchControls(
    AppColorPalette palette,
    SelectedClubService clubService,
    bool hasClub,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftGlassPanel(
          level: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: AppRadius.cardRadius,
          child: Row(
            children: [
              Icon(Icons.shield_rounded, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasClub
                      ? StringUtils.toTitleCase(clubService.clubName!)
                      : 'Kulüp seçilmedi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openClubPicker,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(hasClub ? 'Değiştir' : 'Kulüp Seç'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _runSearch(reset: true),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Müsabaka adı ara...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _runSearch(reset: true);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _cityController,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _runSearch(reset: true),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'İl...',
                  prefixIcon: const Icon(Icons.location_on_outlined, size: 19),
                  suffixIcon: _cityController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _cityController.clear();
                            _runSearch(reset: true);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _years.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final y = _years[i];
              final selected = (_selectedYear ?? 'Tümü') == y;
              return ChoiceChip(
                label: Text(y),
                selected: selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _selectedYear = y);
                  _runSearch(reset: true);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsBody(AppColorPalette palette, bool hasClub) {
    if (!hasClub) {
      return EmptyStateWidget(
        title: 'Kulüp Seçin',
        message:
            'Kulübünüzün katıldığı geçmiş müsabakaları sorgulamak için bir kulüp seçin.',
        icon: Icons.groups_outlined,
        actionText: 'Kulüp Seç',
        onAction: _openClubPicker,
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return EmptyStateWidget(
        title: 'Sorgulanamadı',
        message: _errorMessage!,
        icon: Icons.wifi_off_rounded,
        actionText: 'Tekrar Dene',
        onAction: () => _runSearch(reset: true),
      );
    }
    if (_meets.isEmpty) {
      return const EmptyStateWidget(
        title: 'Müsabaka Bulunamadı',
        message: 'Seçili kulüp ve arama kriterlerine uygun müsabaka bulunamadı.',
        icon: Icons.search_off_rounded,
      );
    }

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: () => _runSearch(reset: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _meets.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _meets.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => _runSearch(reset: false),
                        child: const Text('Daha Fazla Yükle'),
                      ),
              ),
            );
          }

          final meet = _meets[index];
          final dateLabel = [
            if (meet.startDate.isNotEmpty) meet.startDate,
            if (meet.endDate.isNotEmpty && meet.endDate != meet.startDate)
              meet.endDate,
          ].join(' - ');
          return Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openingMeet ? null : () => _openArchivedMeet(meet),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (meet.course.isNotEmpty) ...[
                            StatusBadge(
                              label: meet.course,
                              variant: StatusBadgeVariant.neutral,
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            StringUtils.toTitleCase(meet.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          if (meet.city.isNotEmpty || dateLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (meet.city.isNotEmpty) meet.city,
                                if (dateLabel.isNotEmpty) dateLabel,
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: palette.accent,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
