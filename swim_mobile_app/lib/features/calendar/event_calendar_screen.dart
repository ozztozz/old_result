import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/calendar_event.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/brand_header_bar.dart';
import '../../shared/widgets/formatted_summary_view.dart';
import '../meets/meet_detail_screen.dart';

/// Ulusal (TYF) ve İl Etkinlik Takvimi Ekranı
class EventCalendarScreen extends StatefulWidget {
  final SwimRepository repository;

  const EventCalendarScreen({
    super.key,
    required this.repository,
  });

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen> {
  bool _isLoading = true;
  String? _error;
  List<CalendarEvent> _events = [];
  List<String> _cities = [];

  String _scope = 'all'; // all | national | provincial
  String _selectedCity = '';
  String _selectedPool = ''; // '' | 25m | 50m
  bool _includePast = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
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
        q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        includePast: _includePast,
      );
      if (mounted) {
        setState(() {
          _events = res.events;
          if (res.cities.isNotEmpty) {
            _cities = res.cities;
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
    final palette = context.palette;

    // Etkinlikleri aya göre grupla
    final grouped = <String, List<CalendarEvent>>{};
    for (final ev in _events) {
      grouped.putIfAbsent(ev.monthKey, () => []).add(ev);
    }
    final monthKeys = grouped.keys.toList();

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              BrandHeaderBar(
                subtitle: 'Etkinlik Takvimi',
                actions: [
                  IconButton(
                    tooltip:
                        _includePast ? 'Yalnız Yaklaşanlar' : 'Geçmişi de Göster',
                    icon: Icon(
                      _includePast
                          ? Icons.history_toggle_off
                          : Icons.history_rounded,
                      color:
                          _includePast ? palette.accent : palette.textSecondary,
                    ),
                    onPressed: () {
                      setState(() => _includePast = !_includePast);
                      _loadCalendar();
                    },
                  ),
                ],
              ),
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
                        _filterChip('Ulusal', _scope == 'national', palette, () {
                          setState(() => _scope = 'national');
                          _loadCalendar();
                        }),
                        const SizedBox(width: 6),
                        _filterChip('İl Yarışları', _scope == 'provincial', palette, () {
                          setState(() => _scope = 'provincial');
                          _loadCalendar();
                        }),
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
                          child: EmptyStateWidget(
                            title: 'Takvim Yüklenemedi',
                            message: _error!,
                            icon: Icons.event_busy_outlined,
                            actionText: 'Tekrar Dene',
                            onAction: _loadCalendar,
                          ),
                        )
                      : _events.isEmpty
                          ? const Center(
                              child: EmptyStateWidget(
                                title: 'Etkinlik Bulunamadı',
                                message: 'Seçili filtrelere uygun planlanmış müsabaka yok.',
                                icon: Icons.calendar_today_outlined,
                              ),
                            )
                          : RefreshIndicator(
                              color: palette.primary,
                              onRefresh: _loadCalendar,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                                itemCount: monthKeys.length,
                                itemBuilder: (context, mIdx) {
                                  final mk = monthKeys[mIdx];
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
                                      ...list.map((ev) => Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: _buildEventCard(ev, palette),
                                          )),
                                    ],
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
        ),
      ),
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
