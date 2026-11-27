import 'package:flutter/material.dart';

import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/live_meet.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/app_page_shell.dart';
import '../../shared/widgets/club_selection_sheet.dart';
import '../../shared/widgets/status_badge.dart';
import 'club_baraj_screen.dart';
import 'club_meet_search_screen.dart';
import 'live_club_tab.dart';

/// Kulüp rolü için ayrılmış bağımsız Canlı Kulüp Takip sayfası.
/// Yalnızca seçili kulübün katıldığı canlı/tamamlanan müsabakaları listeler.
class ClubLiveScreen extends StatefulWidget {
  final SwimRepository repository;
  final List<LiveMeetSummary>? initialMeets;
  final int? initialMeetId;

  const ClubLiveScreen({
    super.key,
    required this.repository,
    this.initialMeets,
    this.initialMeetId,
  });

  @override
  State<ClubLiveScreen> createState() => _ClubLiveScreenState();
}

class _ClubLiveScreenState extends State<ClubLiveScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LiveMeetSummary> _clubMeets = [];
  List<String> _availableClubs = [];
  final Map<String, int> _clubIdsByName = {};
  final Map<int, LiveFeedResponse> _feedCache = {};
  bool _openingMeet = false;

  @override
  void initState() {
    super.initState();
    SelectedClubService.instance.addListener(_onClubChanged);
    _loadClubMeets();
  }

  @override
  void dispose() {
    SelectedClubService.instance.removeListener(_onClubChanged);
    super.dispose();
  }

  void _onClubChanged() {
    if (!mounted) return;
    _feedCache.clear();
    _loadClubMeets();
  }

  Future<void> _loadClubMeets() async {
    final clubService = SelectedClubService.instance;
    if (!clubService.hasSelectedClub) {
      if (mounted) {
        setState(() {
          _clubMeets = [];
          _isLoading = false;
          _errorMessage = null;
        });
      }
      _warmUpAvailableClubs();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final meets = await widget.repository.getClubLiveMeets(
        clubId: clubService.clubId,
        clubName: clubService.clubName,
      );
      if (!mounted) return;
      setState(() {
        _clubMeets = meets;
        _isLoading = false;
      });
      _warmUpAvailableClubs(meets);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Canlı müsabakalar yüklenemedi.';
        _isLoading = false;
      });
    }
  }

  Future<void> _warmUpAvailableClubs([List<LiveMeetSummary>? sourceMeets]) async {
    if (_availableClubs.isNotEmpty) return;
    final list = sourceMeets ?? widget.initialMeets ?? const <LiveMeetSummary>[];
    if (list.isEmpty) return;
    final clubs = <String>{};
    final target = list.firstWhere(
      (m) => m.id == widget.initialMeetId,
      orElse: () => list.first,
    );
    try {
      if (target.meetId != null) {
        final participants =
            await widget.repository.getMeetParticipants(target.meetId!);
        for (final c in participants.clubs) {
          final name = c.name.trim();
          if (name.isNotEmpty) {
            clubs.add(name);
            if (c.id > 0) _clubIdsByName[name] = c.id;
          }
        }
      } else if (target.id > 0) {
        final feed = await widget.repository.getLiveSummary(target.id);
        for (final r in feed.results) {
          final name = r.clubName.trim();
          if (name.isNotEmpty) {
            clubs.add(name);
            if (r.clubId != null && r.clubId! > 0) {
              _clubIdsByName[name] = r.clubId!;
            }
          }
        }
      }
    } catch (_) {}
    if (!mounted || clubs.isEmpty) return;
    final sorted = clubs.toList()..sort();
    setState(() => _availableClubs = sorted);
  }

  Future<void> _openClubPicker() async {
    await ClubSelectionSheet.show(
      context,
      availableClubs: _availableClubs,
      clubIdsByName: _clubIdsByName,
    );
  }

  Future<void> _openMeetForClub(LiveMeetSummary meet) async {
    if (_openingMeet) return;
    final clubService = SelectedClubService.instance;
    if (!clubService.hasSelectedClub) {
      await _openClubPicker();
      if (!mounted || !clubService.hasSelectedClub) return;
    }

    setState(() => _openingMeet = true);
    try {
      LiveFeedResponse? feed = _feedCache[meet.id];
      if (feed == null && meet.id > 0) {
        feed = await widget.repository.getLiveSummary(
          meet.id,
          clubId: clubService.clubId,
          clubName: clubService.clubName,
        );
        _feedCache[meet.id] = feed;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClubMeetScreen(
            meet: meet,
            initialEvents: feed?.events ?? const [],
            initialResults: feed?.results ?? const [],
            repository: widget.repository,
            onRefreshFeed: meet.id > 0
                ? () async {
                    final refreshed = await widget.repository.getLiveSummary(
                      meet.id,
                      clubId: clubService.clubId,
                      clubName: clubService.clubName,
                    );
                    _feedCache[meet.id] = refreshed;
                    return refreshed;
                  }
                : null,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Müsabaka kulüp verileri yüklenemedi.'),
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
      subtitle: 'Kulüp Canlı Takip',
      showBack: true,
      safeBottom: true,
      actions: [
        GlassCircleButton(
          icon: Icons.emoji_events_outlined,
          iconSize: 20,
          iconColor: palette.textPrimary,
          tooltip: 'Kulüp Baraj Durumu',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClubBarajScreen(
                  repository: widget.repository,
                  availableClubs: _availableClubs,
                  clubIdsByName: _clubIdsByName,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        GlassCircleButton(
          icon: Icons.search_rounded,
          iconSize: 20,
          iconColor: palette.textPrimary,
          tooltip: 'Tüm Yarışlarda Ara',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClubMeetSearchScreen(
                  repository: widget.repository,
                  availableClubs: _availableClubs,
                  clubIdsByName: _clubIdsByName,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: _buildSelectedClubCard(palette, clubService, hasClub),
          ),
          Expanded(
            child: _buildBody(palette, hasClub),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedClubCard(
    AppColorPalette palette,
    SelectedClubService clubService,
    bool hasClub,
  ) {
    return SoftGlassPanel(
      level: 2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: AppRadius.cardRadius,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasClub ? Icons.shield_rounded : Icons.groups_outlined,
              color: palette.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasClub ? 'Seçili Kulüp' : 'Kulüp Seçilmedi',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasClub
                      ? StringUtils.toTitleCase(clubService.clubName!)
                      : 'Sporcularınızı takip etmek için kulüp seçin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _openClubPicker,
            child: Text(hasClub ? 'Değiştir' : 'Kulüp Seç'),
          ),
          if (hasClub)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textMuted,
              ),
              tooltip: 'Kulüp seçimini temizle',
              onPressed: clubService.clearClub,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AppColorPalette palette, bool hasClub) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return EmptyStateWidget(
        title: 'Yüklenemedi',
        message: _errorMessage!,
        icon: Icons.wifi_off_rounded,
        actionText: 'Tekrar Dene',
        onAction: _loadClubMeets,
      );
    }
    if (!hasClub) {
      return EmptyStateWidget(
        title: 'Kulüp Seçin',
        message:
            'Yalnızca kulübünüzün katıldığı canlı müsabakaları görmek için yukarıdan bir kulüp seçin.',
        icon: Icons.groups_outlined,
        actionText: 'Kulüp Seç',
        onAction: _openClubPicker,
      );
    }
    if (_clubMeets.isEmpty) {
      return const EmptyStateWidget(
        title: 'Katılım Bulunamadı',
        message: 'Seçili kulübün katıldığı aktif canlı müsabaka bulunmuyor.',
        icon: Icons.pool_outlined,
      );
    }

    return RefreshIndicator(
      color: palette.primary,
      onRefresh: () async {
        _feedCache.clear();
        await _loadClubMeets();
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _clubMeets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final meet = _clubMeets[index];
          final isHighlighted =
              widget.initialMeetId != null && meet.id == widget.initialMeetId;
          final isLive = meet.status.toUpperCase().contains('CANLI');

          return Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openingMeet ? null : () => _openMeetForClub(meet),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHighlighted
                        ? palette.accent.withValues(alpha: 0.45)
                        : palette.border,
                    width: isHighlighted ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              StatusBadge(
                                label: isLive ? 'CANLI' : meet.status,
                                variant: isLive
                                    ? StatusBadgeVariant.success
                                    : StatusBadgeVariant.neutral,
                              ),
                              if (isHighlighted) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'Seçili Müsabaka',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: palette.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
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
                          if (meet.city.isNotEmpty || meet.date.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (meet.city.isNotEmpty) meet.city,
                                if (meet.date.isNotEmpty) meet.date,
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
