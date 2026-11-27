import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/calendar_event.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/app_page_shell.dart';
import '../../shared/widgets/formatted_summary_view.dart';
import '../meets/meet_detail_screen.dart';

/// Ulusal (TYF) ve İl Etkinlik Takvimi Ekranı
class EventCalendarScreen extends StatefulWidget {
  final SwimRepository repository;
  final int? initialAge;
  final String? subtitle;
  final bool embedded;

  const EventCalendarScreen({
    super.key,
    required this.repository,
    this.initialAge,
    this.subtitle,
    this.embedded = false,
  });

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.embedded;
  bool _isLoading = true;
  String? _error;
  List<CalendarEvent> _events = [];
  List<String> _cities = [];

  String _scope = 'all'; // all | national | provincial
  String _selectedCity = '';
  String _selectedPool = ''; // '' | 25m | 50m
  int? _selectedAge;
  bool _includePast = false;
  bool _showCalendarGrid = true;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedAge = widget.initialAge;
    _loadCalendar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCalendar() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.repository.getEventCalendar(
        scope: _scope,
        city: _selectedCity.isEmpty ? null : _selectedCity,
        pool: _selectedPool.isEmpty ? null : _selectedPool,
        age: _selectedAge,
        q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        includePast: _includePast,
      );
      if (mounted) {
        setState(() {
          _events = res.events;
          if (res.cities.isNotEmpty) {
            _cities = res.cities;
          }
          _selectedDate = null;
          if (_events.isNotEmpty) {
            final hasFocusedMonth = _events.any((e) {
              final d = _parseYmd(e.startDate);
              return d != null &&
                  d.year == _focusedMonth.year &&
                  d.month == _focusedMonth.month;
            });
            if (!hasFocusedMonth) {
              final first = _parseYmd(_events.first.startDate);
              if (first != null) {
                _focusedMonth = DateTime(first.year, first.month);
              }
            }
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Etkinlik takvimi yüklenemedi.';
          _isLoading = false;
        });
      }
    }
  }

  String _formatMonthTitle(String ym) {
    if (!ym.contains('-')) return ym;
    final parts = ym.split('-');
    if (parts.length < 2) return ym;
    const months = {
      '01': 'Ocak',
      '02': 'Şubat',
      '03': 'Mart',
      '04': 'Nisan',
      '05': 'Mayıs',
      '06': 'Haziran',
      '07': 'Temmuz',
      '08': 'Ağustos',
      '09': 'Eylül',
      '10': 'Ekim',
      '11': 'Kasım',
      '12': 'Aralık',
    };
    return '${months[parts[1]] ?? parts[1]} ${parts[0]}';
  }

  DateTime? _parseYmd(String raw) {
    final s = raw.trim();
    if (s.length < 10) return null;
    final parsed = DateTime.tryParse(s.substring(0, 10));
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _eventCoversDay(CalendarEvent ev, DateTime day) {
    final start = _parseYmd(ev.startDate);
    if (start == null) return false;
    final target = DateTime(day.year, day.month, day.day);
    return target == start;
  }

  String _formatDayTitle(DateTime day) {
    final mm = day.month.toString().padLeft(2, '0');
    final monthLabel = _formatMonthTitle('${day.year}-$mm');
    return '${day.day} $monthLabel';
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onEventTap(CalendarEvent ev, AppColorPalette palette) {
    if (ev.hasResults) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetDetailScreen(
            meetId: ev.id,
            meetTitle: ev.name,
            repository: widget.repository,
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: ev.ozet.isNotEmpty ? 0.72 : 0.45,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(ev.scope == 'IL' ? 'İl Etkinliği' : 'Ulusal'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (ev.pool.isNotEmpty)
                    Chip(
                      label: Text(ev.pool),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (ev.barajCount > 0)
                    Chip(
                      label: Text('${ev.barajCount} Baraj Kuralı'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ev.name,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  ev.rawDate.isNotEmpty ? ev.rawDate : ev.startDate,
                  if (ev.city.isNotEmpty) ev.city,
                ].join(' • '),
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  color: palette.textSecondary,
                ),
              ),
              if (ev.ageGroup.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Yaş Grubu: ${ev.ageGroup}',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
              ],
              if (ev.ozet.isNotEmpty) ...[
                const SizedBox(height: 12),
                FormattedSummaryView(
                  text: ev.ozet,
                  baseStyle: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13.5,
                    height: 1.5,
                    color: palette.textPrimary,
                  ),
                  boldColor: palette.textPrimary,
                  bulletColor: palette.accent,
                ),
              ],
              if (ev.pdfUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openPdf(ev.pdfUrl),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Reglaman / PDF Belgesini Aç'),
                  ),
                ),
              ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;

    // Seçili güne göre (varsa) etkinlikleri filtrele ve aya göre grupla
    final visibleEvents = _selectedDate == null
        ? _events
        : _events.where((ev) => _eventCoversDay(ev, _selectedDate!)).toList();

    final grouped = <String, List<CalendarEvent>>{};
    for (final ev in visibleEvents) {
      grouped.putIfAbsent(ev.monthKey, () => []).add(ev);
    }
    final monthKeys = grouped.keys.toList();

    final content = Column(
      children: [
          const SizedBox(height: 6),
            // Arama + Kapsam + Havuz + İl Filtreleri
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loadCalendar(),
                    decoration: InputDecoration(
                      hintText: 'Müsabaka, il veya yaş grubu ara...',
                      prefixIcon: const Icon(Icons.search_outlined, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _loadCalendar();
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
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('Tümü', _scope == 'all', palette, () {
                          setState(() => _scope = 'all');
                          _loadCalendar();
                        }),
                        const SizedBox(width: 6),
                        _filterChip('Aylık Takvim', _showCalendarGrid, palette, () {
                          setState(() => _showCalendarGrid = !_showCalendarGrid);
                        }),
                        const SizedBox(width: 6),
                        _filterChip('Ulusal', _scope == 'national', palette, () {
                          setState(() => _scope = 'national');
                          _loadCalendar();
                        }),
                        const SizedBox(width: 6),
                        _filterChip('İl Yarışları', _scope == 'provincial', palette, () {
                          setState(() => _scope = 'provincial');
                          _loadCalendar();
                        }),
                        if (widget.initialAge != null) ...[
                          const SizedBox(width: 6),
                          _filterChip(
                            '${widget.initialAge} Yaş',
                            _selectedAge != null,
                            palette,
                            () {
                              setState(() {
                                _selectedAge = _selectedAge == null
                                    ? widget.initialAge
                                    : null;
                              });
                              _loadCalendar();
                            },
                          ),
                        ],
                        if (widget.embedded) ...[
                          const SizedBox(width: 6),
                          _filterChip(
                            'Geçmiş',
                            _includePast,
                            palette,
                            () {
                              setState(() => _includePast = !_includePast);
                              _loadCalendar();
                            },
                          ),
                        ],
                        const SizedBox(width: 10),
                        _filterChip('25m', _selectedPool == '25m', palette, () {
                          setState(() => _selectedPool = _selectedPool == '25m' ? '' : '25m');
                          _loadCalendar();
                        }),
                        const SizedBox(width: 6),
                        _filterChip('50m', _selectedPool == '50m', palette, () {
                          setState(() => _selectedPool = _selectedPool == '50m' ? '' : '50m');
                          _loadCalendar();
                        }),
                        if (_cities.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              setState(() => _selectedCity = val);
                              _loadCalendar();
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: '', child: Text('Tüm İller')),
                              ..._cities.map((c) => PopupMenuItem(value: c, child: Text(c))),
                            ],
                            child: Chip(
                              avatar: const Icon(Icons.location_on_outlined, size: 16),
                              label: Text(_selectedCity.isEmpty ? 'İl Seç' : _selectedCity),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: palette.primary))
                  : _error != null
                      ? Center(
                          child: SingleChildScrollView(
                            child: EmptyStateWidget(
                              title: 'Takvim Yüklenemedi',
                              message: _error!,
                              icon: Icons.event_busy_outlined,
                              actionText: 'Tekrar Dene',
                              onAction: _loadCalendar,
                              compact: widget.embedded,
                            ),
                          ),
                        )
                      : _events.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                child: EmptyStateWidget(
                                  title: 'Etkinlik Bulunamadı',
                                  message:
                                      'Seçili filtrelere uygun planlanmış müsabaka yok.',
                                  icon: Icons.calendar_today_outlined,
                                  compact: widget.embedded,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: palette.primary,
                              onRefresh: _loadCalendar,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                                children: [
                                  if (_showCalendarGrid) ...[
                                    _MonthlyCalendarCard(
                                      focusedMonth: _focusedMonth,
                                      selectedDate: _selectedDate,
                                      events: _events,
                                      palette: palette,
                                      monthTitle: _formatMonthTitle(
                                        '${_focusedMonth.year}-${_focusedMonth.month.toString().padLeft(2, '0')}',
                                      ),
                                      eventCoversDay: _eventCoversDay,
                                      onMonthChanged: (next) {
                                        setState(() => _focusedMonth = next);
                                      },
                                      onDaySelected: (day) {
                                        setState(() {
                                          if (_selectedDate != null &&
                                              _selectedDate!.year == day.year &&
                                              _selectedDate!.month == day.month &&
                                              _selectedDate!.day == day.day) {
                                            _selectedDate = null;
                                          } else {
                                            _selectedDate = day;
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_selectedDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.event_available_outlined,
                                            size: 16,
                                            color: palette.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${_formatDayTitle(_selectedDate!)} • ${visibleEvents.length} etkinlik',
                                              style: TextStyle(
                                                fontFamily: AppTextStyles.fontFamily,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: palette.textPrimary,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                setState(() => _selectedDate = null),
                                            style: TextButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                              ),
                                            ),
                                            child: const Text('Tümünü Göster'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (visibleEvents.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 20),
                                      child: EmptyStateWidget(
                                        title: 'Bu Günde Etkinlik Yok',
                                        message:
                                            'Seçili tarihte planlanmış müsabaka bulunmuyor.',
                                        icon: Icons.event_note_outlined,
                                        compact: true,
                                      ),
                                    )
                                  else
                                    ...monthKeys.map((mk) {
                                      final list = grouped[mk]!;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            child: Text(
                                              _formatMonthTitle(mk),
                                              style: TextStyle(
                                                fontFamily: AppTextStyles.fontFamily,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: palette.primary,
                                              ),
                                            ),
                                          ),
                                          ...list.map(
                                            (ev) => Padding(
                                              padding: const EdgeInsets.only(bottom: 10),
                                              child: _buildEventCard(ev, palette),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                ],
                              ),
                            ),
                          ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return AppPageShell(
      subtitle: widget.subtitle ?? 'Etkinlik Takvimi',
      actions: [
        IconButton(
          tooltip: _includePast ? 'Yalnız Yaklaşanlar' : 'Geçmişi de Göster',
          icon: Icon(
            _includePast ? Icons.history_toggle_off : Icons.history_rounded,
            color: _includePast ? palette.accent : palette.textSecondary,
          ),
          onPressed: () {
            setState(() => _includePast = !_includePast);
            _loadCalendar();
          },
        ),
      ],
      body: content,
    );
  }

  Widget _filterChip(String label, bool selected, AppColorPalette palette, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: palette.accentSoft,
      labelStyle: TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? palette.accent : palette.textSecondary,
      ),
    );
  }

  Widget _buildEventCard(CalendarEvent ev, AppColorPalette palette) {
    final dayStr = ev.startDate.length >= 10 ? ev.startDate.substring(8, 10) : '--';
    final monStr = ev.startDate.length >= 7 ? ev.startDate.substring(5, 7) : '--';

    return SoftGlassPanel(
      level: 2,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      onTap: () => _onEventTap(ev, palette),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  dayStr,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: palette.accent,
                  ),
                ),
                Text(
                  monStr,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniTag(
                      ev.scope == 'IL' ? 'İL' : 'ULUSAL',
                      ev.scope == 'IL' ? palette.statusSuccess : palette.primary,
                    ),
                    if (ev.pool.isNotEmpty) _miniTag(ev.pool, palette.textSecondary),
                    if (ev.barajCount > 0) _miniTag('${ev.barajCount} Baraj', palette.accent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ev.name,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (ev.rawDate.isNotEmpty) ev.rawDate,
                    if (ev.city.isNotEmpty) ev.city,
                  ].join(' • '),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
                if (ev.ageGroup.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ev.ageGroup,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            ev.hasResults
                ? Icons.chevron_right_rounded
                : (ev.pdfUrl.isNotEmpty ? Icons.picture_as_pdf_outlined : Icons.info_outline),
            size: 18,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MonthlyCalendarCard extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime? selectedDate;
  final List<CalendarEvent> events;
  final AppColorPalette palette;
  final String monthTitle;
  final bool Function(CalendarEvent ev, DateTime day) eventCoversDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  const _MonthlyCalendarCard({
    required this.focusedMonth,
    required this.selectedDate,
    required this.events,
    required this.palette,
    required this.monthTitle,
    required this.eventCoversDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final leadingEmpty = firstDayOfMonth.weekday - 1; // Pazartesi = 0
    final totalCells = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    const weekdays = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'];
    final prevMonthLastDay = DateTime(focusedMonth.year, focusedMonth.month, 0).day;

    // Etkinliği olan ayları kronolojik sırayla çıkar (hızlı ay atlama çipleri için)
    final activeMonths = <DateTime>[];
    final seenMonths = <String>{};
    for (final ev in events) {
      if (ev.startDate.length >= 7) {
        final ym = ev.startDate.substring(0, 7);
        if (seenMonths.add(ym)) {
          final p = ym.split('-');
          final y = int.tryParse(p[0]);
          final m = int.tryParse(p[1]);
          if (y != null && m != null) {
            activeMonths.add(DateTime(y, m));
          }
        }
      }
    }
    activeMonths.sort();

    // Odaklanılan aydaki etkinlik sayısı
    int monthEventCount = 0;
    for (final ev in events) {
      bool inMonth = false;
      for (int d = 1; d <= daysInMonth; d++) {
        if (eventCoversDay(ev, DateTime(focusedMonth.year, focusedMonth.month, d))) {
          inMonth = true;
          break;
        }
      }
      if (inMonth) monthEventCount++;
    }

    final cardBg = palette.isDark
        ? palette.surfaceElevated
        : Color.alphaBlend(palette.navFill, palette.shadowTint);
    final dotNationalColor = palette.accent;
    final dotProvincialColor = palette.statusWarning;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadowTint.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Önceki Ay',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                iconSize: 19,
                color: Colors.white.withValues(alpha: 0.8),
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      monthTitle,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '($monthEventCount)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: monthEventCount > 0
                            ? dotNationalColor
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sonraki Ay',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                iconSize: 19,
                color: Colors.white.withValues(alpha: 0.8),
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1),
                ),
              ),
            ],
          ),
          if (activeMonths.length > 1) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 22,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: activeMonths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (_, i) {
                  final m = activeMonths[i];
                  final isCurrent =
                      m.year == focusedMonth.year && m.month == focusedMonth.month;
                  const shortMonths = [
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
                  final label =
                      "${shortMonths[m.month - 1]} '${m.year.toString().substring(2)}";
                  return InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => onMonthChanged(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? palette.primary
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 9.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          for (int weekStart = 0; weekStart < totalCells; weekStart += 7) ...[
            if (weekStart > 0) const SizedBox(height: 2),
            SizedBox(
              height: 30,
              child: Row(
                children: List.generate(7, (col) {
                  final index = weekStart + col;
                  final dayOffset = index - leadingEmpty + 1;
                  final bool isOutside = dayOffset < 1 || dayOffset > daysInMonth;

                  if (isOutside) {
                    final outsideNum = dayOffset < 1
                        ? prevMonthLastDay + dayOffset
                        : dayOffset - daysInMonth;
                    return Expanded(
                      child: Center(
                        child: Text(
                          '$outsideNum',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    );
                  }

                  final dayNum = dayOffset;
                  final day = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
                  final isToday = day == todayDate;
                  final isSelected = selectedDate != null &&
                      selectedDate!.year == day.year &&
                      selectedDate!.month == day.month &&
                      selectedDate!.day == day.day;

                  bool hasNational = false;
                  bool hasProvincial = false;
                  int dayEventCount = 0;
                  for (final ev in events) {
                    if (eventCoversDay(ev, day)) {
                      dayEventCount++;
                      if (ev.scope == 'IL') {
                        hasProvincial = true;
                      } else {
                        hasNational = true;
                      }
                    }
                  }
                  final hasAny = dayEventCount > 0;

                  return Expanded(
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onDaySelected(day),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: isSelected
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.primary.withValues(alpha: 0.45),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                )
                              : BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isToday
                                      ? dotNationalColor.withValues(alpha: 0.24)
                                      : hasAny
                                          ? Colors.white.withValues(alpha: 0.13)
                                          : null,
                                  border: isToday
                                      ? Border.all(
                                          color: dotNationalColor,
                                          width: 1.6,
                                        )
                                      : null,
                                ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dayNum',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11.5,
                                  height: 1.1,
                                  fontWeight: isSelected || isToday || hasAny
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected || isToday
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                              if (hasAny) ...[
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (hasNational)
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? Colors.white
                                              : dotNationalColor,
                                        ),
                                      ),
                                    if (hasNational && hasProvincial)
                                      const SizedBox(width: 2),
                                    if (hasProvincial)
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? Colors.white
                                              : dotProvincialColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(dotNationalColor, 'Ulusal', Colors.white.withValues(alpha: 0.68)),
              const SizedBox(width: 12),
              _legendDot(dotProvincialColor, 'İl Yarışı', Colors.white.withValues(alpha: 0.68)),
              const SizedBox(width: 12),
              _legendRing(dotNationalColor, 'Bugün', Colors.white.withValues(alpha: 0.68)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10.5,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _legendRing(Color color, String label, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10.5,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
