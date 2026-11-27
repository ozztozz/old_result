import 'package:flutter/material.dart';

import '../../core/components/app_bottom_sheet.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/baraj_rule.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/app_page_shell.dart';
import '../../shared/widgets/baraj_event_selector.dart';
import '../../shared/widgets/baraj_status_table.dart';
import '../../shared/widgets/club_selection_sheet.dart';
import '../athletes/athlete_profile_screen.dart';

/// Seçili kulübün, seçilen resmi TYF barajına tabi sporcularının
/// barajı geçme / kalan fark durumlarını listeleyen kulüp baraj sayfası.
class ClubBarajScreen extends StatefulWidget {
  final SwimRepository repository;
  final List<String> availableClubs;
  final Map<String, int> clubIdsByName;

  const ClubBarajScreen({
    super.key,
    required this.repository,
    this.availableClubs = const [],
    this.clubIdsByName = const {},
  });

  @override
  State<ClubBarajScreen> createState() => _ClubBarajScreenState();
}

class _ClubBarajScreenState extends State<ClubBarajScreen> {
  bool _isLoadingEvents = true;
  bool _isLoadingStatus = false;
  String? _errorMessage;

  List<BarajEventOption> _events = [];
  List<String> _cities = [];
  List<String> _months = [];
  String _selectedCity = '';
  String _selectedMonth = '';
  BarajEventOption? _activeEvent;
  String _selectedType = 'Katılım Barajı'; // 'Katılım Barajı', 'Harcırah Barajı'
  String _selectedPool = '50m'; // '25m', '50m'
  String _statusFilter = 'all'; // 'all', 'passed', 'pending'
  String _searchQuery = '';

  ClubBarajStatusResponse? _statusResponse;

  @override
  void initState() {
    super.initState();
    SelectedClubService.instance.addListener(_onClubChanged);
    _loadBarajEvents();
  }

  @override
  void dispose() {
    SelectedClubService.instance.removeListener(_onClubChanged);
    super.dispose();
  }

  void _onClubChanged() {
    if (!mounted) return;
    _loadClubStatus();
  }

  Future<void> _loadBarajEvents() async {
    setState(() {
      _isLoadingEvents = true;
      _errorMessage = null;
    });
    try {
      final resp = await widget.repository.getBarajlar();
      if (!mounted) return;
      final events = resp.events;
      final cities = resp.cities.isNotEmpty
          ? resp.cities
          : BarajEventSelector.extractCities(events);
      final months = resp.months.isNotEmpty
          ? resp.months
          : BarajEventSelector.extractMonths(events);

      setState(() {
        _events = events;
        _cities = cities;
        _months = months;
        _activeEvent = null;
        _isLoadingEvents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Baraj listesi yüklenemedi.';
        _isLoadingEvents = false;
      });
    }
  }

  Future<void> _loadClubStatus() async {
    final clubService = SelectedClubService.instance;
    final ev = _activeEvent;
    if (!clubService.hasSelectedClub || ev == null) {
      setState(() {
        _statusResponse = null;
        _isLoadingStatus = false;
      });
      return;
    }

    setState(() {
      _isLoadingStatus = true;
      _errorMessage = null;
    });

    try {
      var resp = await widget.repository.getClubBarajStatus(
        clubId: clubService.clubId,
        clubName: clubService.clubId == null ? clubService.clubName : null,
        eventId: ev.eventId,
        barajAdi: ev.eventId == null ? ev.barajAdi : null,
        barajTuru: _selectedType,
        havuz: _selectedPool,
      );
      // Seçilen havuzda kural yoksa diğer havuzu dene (ör. sadece 25m tanımlı barajlar)
      if (resp.athletes.isEmpty) {
        final altPool = _selectedPool == '50m' ? '25m' : '50m';
        final altResp = await widget.repository.getClubBarajStatus(
          clubId: clubService.clubId,
          clubName: clubService.clubId == null ? clubService.clubName : null,
          eventId: ev.eventId,
          barajAdi: ev.eventId == null ? ev.barajAdi : null,
          barajTuru: _selectedType,
          havuz: altPool,
        );
        if (altResp.athletes.isNotEmpty) {
          resp = altResp;
          _selectedPool = altPool;
        }
      }
      if (!mounted) return;
      setState(() {
        _statusResponse = resp;
        _isLoadingStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Kulüp baraj durumu yüklenemedi.';
        _isLoadingStatus = false;
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clubService = SelectedClubService.instance;
    final hasClub = clubService.hasSelectedClub;

    return AppPageShell(
      subtitle: 'Kulüp Baraj Durumu',
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
      body: _isLoadingEvents
          ? const Center(child: CircularProgressIndicator())
          : !hasClub
              ? EmptyStateWidget(
                  title: 'Kulüp Seçin',
                  message:
                      'Kulübünüzün baraj durumunu görmek için bir kulüp seçin.',
                  icon: Icons.groups_outlined,
                  actionText: 'Kulüp Seç',
                  onAction: _openClubPicker,
                )
              : RefreshIndicator(
                  color: palette.primary,
                  onRefresh: _loadClubStatus,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      if (_events.isNotEmpty)
                        BarajEventSelector(
                          events: BarajEventSelector.filterEvents(
                            _events,
                            city: _selectedCity,
                            month: _selectedMonth,
                          ),
                          activeEvent: _activeEvent,
                          cities: _cities,
                          months: _months,
                          selectedCity: _selectedCity,
                          selectedMonth: _selectedMonth,
                          onCityChanged: (c) {
                            final next = BarajEventSelector.filterEvents(
                              _events,
                              city: c,
                              month: _selectedMonth,
                            );
                            setState(() {
                              _selectedCity = c;
                              if (next.isNotEmpty &&
                                  !next.any(
                                    (e) => e.eventId == _activeEvent?.eventId &&
                                        e.barajAdi == _activeEvent?.barajAdi,
                                  )) {
                                _activeEvent = next.first;
                              }
                            });
                            _loadClubStatus();
                          },
                          onMonthChanged: (m) {
                            final next = BarajEventSelector.filterEvents(
                              _events,
                              city: _selectedCity,
                              month: m,
                            );
                            setState(() {
                              _selectedMonth = m;
                              if (next.isNotEmpty &&
                                  !next.any(
                                    (e) => e.eventId == _activeEvent?.eventId &&
                                        e.barajAdi == _activeEvent?.barajAdi,
                                  )) {
                                _activeEvent = next.first;
                              }
                            });
                            _loadClubStatus();
                          },
                          onEventSelected: (ev) {
                            setState(() => _activeEvent = ev);
                            _loadClubStatus();
                          },
                          extraFilterChips: [
                            for (final t in const [
                              'Katılım Barajı',
                              'Harcırah Barajı',
                            ])
                              ChoiceChip(
                                label: Text(
                                  t == 'Katılım Barajı'
                                      ? 'Katılım'
                                      : 'Harcırah',
                                ),
                                selected: _selectedType == t,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) {
                                  if (_selectedType == t) return;
                                  setState(() => _selectedType = t);
                                  _loadClubStatus();
                                },
                              ),
                            for (final p in const ['25m', '50m'])
                              ChoiceChip(
                                label: Text(p),
                                selected: _selectedPool == p,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) {
                                  if (_selectedPool == p) return;
                                  setState(() => _selectedPool = p);
                                  _loadClubStatus();
                                },
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      if (_errorMessage != null)
                        EmptyStateWidget(
                          title: 'Yüklenemedi',
                          message: _errorMessage!,
                          icon: Icons.wifi_off_rounded,
                          actionText: 'Tekrar Dene',
                          onAction: _loadClubStatus,
                          compact: true,
                        )
                      else if (_activeEvent == null)
                        const EmptyStateWidget(
                          title: 'Baraj Seçin',
                          message:
                              'Kulübünüzün baraj durumunu görüntülemek için yukarıdan bir baraj seçin.',
                          icon: Icons.emoji_events_outlined,
                          compact: true,
                        )
                      else if (_isLoadingStatus)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_statusResponse != null)
                        ..._buildStatusContent(
                          context,
                          palette,
                          clubService,
                          _statusResponse!,
                        ),
                    ],
                  ),
                ),
    );
  }

  List<Widget> _buildStatusContent(
    BuildContext context,
    AppColorPalette palette,
    SelectedClubService clubService,
    ClubBarajStatusResponse resp,
  ) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = resp.athletes.where((a) {
      if (_statusFilter == 'passed' && a.passedCount == 0) return false;
      if (_statusFilter == 'pending' && a.passedCount > 0) return false;
      if (q.isNotEmpty && !a.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        // Önce yaş (büyükten küçüğe = doğum yılı küçükten büyüğe)
        final byA = a.birthYear ?? 9999;
        final byB = b.birthYear ?? 9999;
        if (byA != byB) return byA.compareTo(byB);
        // Sonra cinsiyet
        final gCmp = a.gender.compareTo(b.gender);
        if (gCmp != 0) return gCmp;
        // Sonra isim
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceContrast,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    StringUtils.toTitleCase(clubService.clubName ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.displayFontFamily,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textOnContrast,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${resp.summary.totalAthletes} Tabi Sporcu · '
                    '${resp.summary.passedAthletes} Baraj Geçen',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: palette.textOnContrast.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.textOnContrast.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${resp.summary.totalPassedRules}/${resp.summary.totalApplicableRules}',
                style: TextStyle(
                  fontFamily: AppTextStyles.displayFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.textOnContrast,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Sporcu ara...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
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
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          for (final f in const [
            ('all', 'Tümü'),
            ('passed', 'Barajı Geçenler'),
            ('pending', 'Henüz Geçemeyenler'),
          ])
            ChoiceChip(
              label: Text(f.$2),
              selected: _statusFilter == f.$1,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _statusFilter = f.$1),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (filtered.isEmpty)
        const EmptyStateWidget(
          title: 'Sporcu Bulunamadı',
          message: 'Bu baraj ve filtreye uygun kulüp sporcusu bulunmuyor.',
          icon: Icons.pool_outlined,
          compact: true,
        )
      else
        for (final athlete in filtered) ...[
          _buildAthleteCard(context, palette, athlete),
          const SizedBox(height: 8),
        ],
    ];
  }

  Widget _buildAthleteCard(
    BuildContext context,
    AppColorPalette palette,
    ClubBarajAthleteStatus athlete,
  ) {
    final hasPassed = athlete.passedCount > 0;

    return SoftGlassPanel(
      level: 1,
      borderRadius: AppRadius.cardRadius,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: () {
          AppBottomSheet.show(
            context,
            builder: (_) => _buildAthleteBarajSheet(context, palette, athlete),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      StringUtils.formatAthleteName(athlete.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (athlete.birthYear != null) '${athlete.birthYear}',
                        athlete.gender,
                        '${athlete.totalCount} Branş',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasPassed
                          ? palette.statusSuccess
                          : palette.surfaceSecondary)
                      .withValues(alpha: hasPassed ? 0.14 : 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${athlete.passedCount}/${athlete.totalCount} Geçti',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: hasPassed
                        ? palette.statusSuccess
                        : palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAthleteBarajSheet(
    BuildContext context,
    AppColorPalette palette,
    ClubBarajAthleteStatus athlete,
  ) {
    return AppBottomSheet(
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      StringUtils.formatAthleteName(athlete.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.displayFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (athlete.birthYear != null) '${athlete.birthYear}',
                        athlete.gender,
                        '${athlete.passedCount}/${athlete.totalCount} Baraj Geçti',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AthleteProfileScreen(
                        athleteId: athlete.id,
                        athleteName: athlete.name,
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
          const SizedBox(height: 10),
          Flexible(
            child: BarajTabbedStatusView(
              scrollableTable: true,
              rows: athlete.rules
                  .map(
                    (r) => BarajStatusRowData(
                      distance: r.distance,
                      strokeLabel: r.strokeLabel,
                      targetTime: r.targetTime,
                      pbTime: r.pbTime ?? '-',
                      diffCs: r.diffCs,
                      passed: r.passed,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
