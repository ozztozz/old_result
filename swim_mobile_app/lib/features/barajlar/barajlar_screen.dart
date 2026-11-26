import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/baraj_rule.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/baraj_event_selector.dart';
import '../../shared/widgets/brand_header_bar.dart';
import '../../shared/widgets/formatted_summary_view.dart';

/// Resmi TYF Katılım & Harcırah Barajları Ekranı
class BarajlarScreen extends StatefulWidget {
  final SwimRepository repository;

  const BarajlarScreen({
    super.key,
    required this.repository,
  });

  @override
  State<BarajlarScreen> createState() => _BarajlarScreenState();
}

class _BarajlarScreenState extends State<BarajlarScreen> {
  bool _isLoading = true;
  String? _error;
  List<BarajRule> _rules = [];
  List<BarajEventOption> _allEvents = [];
  List<String> _cities = [];
  List<String> _months = [];
  List<String> _ageLabels = [];

  String _selectedBaraj = '';
  int? _selectedEventId;
  String _selectedCity = '';
  String _selectedMonth = '';
  String _selectedPool = '50m';
  String _selectedType = 'Katılım Barajı';
  String _selectedAge = '';

  @override
  void initState() {
    super.initState();
    _loadBarajlar(initial: true);
  }

  List<BarajEventOption> get _filteredEvents {
    return BarajEventSelector.filterEvents(
      _allEvents,
      city: _selectedCity,
      month: _selectedMonth,
    );
  }

  BarajEventOption? get _activeEvent {
    final list = _filteredEvents;
    if (list.isEmpty) return null;
    for (final e in list) {
      if (_selectedEventId != null && e.eventId == _selectedEventId) return e;
      if (_selectedBaraj.isNotEmpty && e.barajAdi == _selectedBaraj) return e;
    }
    return list.first;
  }

  Future<void> _loadBarajlar({bool initial = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.repository.getBarajlar(
        eventId: _selectedEventId,
        barajAdi: _selectedEventId == null && _selectedBaraj.isNotEmpty
            ? _selectedBaraj
            : null,
        city: _selectedCity.isEmpty ? null : _selectedCity,
        month: _selectedMonth.isEmpty ? null : _selectedMonth,
        barajTuru: _selectedType.isEmpty ? null : _selectedType,
        havuz: _selectedPool.isEmpty ? null : _selectedPool,
        yas: _selectedAge.isEmpty ? null : _selectedAge,
      );
      if (!mounted) return;
      setState(() {
        if (res.events.isNotEmpty) {
          _allEvents = res.events;
        }
        if (res.cities.isNotEmpty) {
          _cities = res.cities;
        }
        if (res.months.isNotEmpty) {
          _months = res.months;
        }
        if (initial && _selectedBaraj.isEmpty && _allEvents.isNotEmpty) {
          _selectedEventId = _allEvents.first.eventId;
          _selectedBaraj = _allEvents.first.barajAdi;
        }
        _ageLabels = res.ageLabels;
        if (_selectedAge.isNotEmpty && !_ageLabels.contains(_selectedAge)) {
          _selectedAge = '';
        }
        _rules = _selectedBaraj.isNotEmpty
            ? res.rules
                .where(
                  (r) =>
                      (_selectedAge.isEmpty || r.yasEtiketi == _selectedAge) &&
                      (_selectedEventId != null
                          ? r.eventId == _selectedEventId
                          : r.barajAdi == _selectedBaraj),
                )
                .toList()
            : [];
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Baraj bilgileri yüklenemedi.';
          _isLoading = false;
        });
      }
    }
  }

  void _syncActiveEventAfterFilter() {
    final list = _filteredEvents;
    if (list.isNotEmpty) {
      _selectedEventId = list.first.eventId;
      _selectedBaraj = list.first.barajAdi;
    } else {
      _selectedEventId = null;
      _selectedBaraj = '';
    }
    _selectedAge = '';
    _loadBarajlar();
  }

  Future<void> _openSourcePdf() async {
    final activeEv = _activeEvent;
    var url = activeEv?.pdfUrl ?? '';
    if (url.isEmpty) {
      url = _rules
          .map((r) => r.pdfUrl.isNotEmpty ? r.pdfUrl : r.sourceUrl)
          .firstWhere((u) => u.isNotEmpty, orElse: () => '');
    }
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final eventsToShow = _filteredEvents;
    final activeEv = _activeEvent;
    final hasSourcePdf = (activeEv?.pdfUrl.isNotEmpty ?? false) ||
        _rules.any((r) => r.pdfUrl.isNotEmpty || r.sourceUrl.isNotEmpty);

    // Stile göre grupla (geleneksel yüzme sırası)
    const strokeOrder = [
      'Serbest',
      'Sırtüstü',
      'Kurbağalama',
      'Kelebek',
      'Karışık',
    ];
    final grouped = <String, List<BarajRule>>{};
    for (final r in _rules) {
      grouped.putIfAbsent(r.stil, () => []).add(r);
    }
    final strokes = grouped.keys.toList()
      ..sort((a, b) {
        final ia = strokeOrder.indexOf(a);
        final ib = strokeOrder.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return AmbientBackground(
      artStyle: AmbientArtStyle.none,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: ResponsiveCenter(
            maxWidth: 1040,
            child: Column(
              children: [
              BrandHeaderBar(
                subtitle: 'Resmi Barajlar',
                actions: [
                  if (hasSourcePdf)
                    TextButton.icon(
                      onPressed: _openSourcePdf,
                      icon: Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 17,
                        color: palette.accent,
                      ),
                      label: Text(
                        'Reglaman',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Yer, Tarih filtreleri ve Bağlı Etkinlik Seçici
                  BarajEventSelector(
                    events: eventsToShow,
                    activeEvent: activeEv,
                    cities: _cities,
                    months: _months,
                    selectedCity: _selectedCity,
                    selectedMonth: _selectedMonth,
                    onCityChanged: (val) {
                      setState(() => _selectedCity = val);
                      _syncActiveEventAfterFilter();
                    },
                    onMonthChanged: (val) {
                      setState(() => _selectedMonth = val);
                      _syncActiveEventAfterFilter();
                    },
                    onEventSelected: (ev) {
                      setState(() {
                        _selectedBaraj = ev.barajAdi;
                        _selectedEventId = ev.eventId;
                        _selectedAge = '';
                      });
                      _loadBarajlar();
                    },
                    onOpenPdf: hasSourcePdf ? _openSourcePdf : null,
                    onOpenSummary: (activeEv != null &&
                            (activeEv.ozet.isNotEmpty ||
                                activeEv.onemliNotlar.isNotEmpty))
                        ? () => showAnnouncementDetailSheet(
                              context,
                              title: activeEv.title,
                              subtitle: [
                                if (activeEv.dateText.isNotEmpty)
                                  activeEv.dateText,
                                if (activeEv.city.isNotEmpty) activeEv.city,
                              ].join(' • '),
                              tags: [
                                if (activeEv.validityText.isNotEmpty)
                                  'Geçerlilik: ${activeEv.validityText}',
                              ],
                              summary: activeEv.ozet,
                              notes: activeEv.onemliNotlar,
                              onOpenPdf: hasSourcePdf ? _openSourcePdf : null,
                            )
                        : null,
                    extraFilterChips: [
                      _chip('50m', _selectedPool == '50m', palette, () {
                        setState(() => _selectedPool = '50m');
                        _loadBarajlar();
                      }),
                      const SizedBox(width: 6),
                      _chip('25m', _selectedPool == '25m', palette, () {
                        setState(() => _selectedPool = '25m');
                        _loadBarajlar();
                      }),
                      const SizedBox(width: 8),
                      _chip(
                        'Katılım',
                        _selectedType == 'Katılım Barajı',
                        palette,
                        () {
                          setState(() => _selectedType = 'Katılım Barajı');
                          _loadBarajlar();
                        },
                      ),
                      const SizedBox(width: 6),
                      _chip(
                        'Harcırah',
                        _selectedType == 'Harcırah Barajı',
                        palette,
                        () {
                          setState(() => _selectedType = 'Harcırah Barajı');
                          _loadBarajlar();
                        },
                      ),
                    ],
                  ),
                  if (_ageLabels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Yaş Grubu',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _chip(
                              'Tümü',
                              _selectedAge.isEmpty,
                              palette,
                              () {
                                if (_selectedAge.isNotEmpty) {
                                  setState(() => _selectedAge = '');
                                  _loadBarajlar();
                                }
                              },
                            ),
                          ),
                          ..._ageLabels.map(
                            (age) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _chip(
                                age,
                                _selectedAge == age,
                                palette,
                                () {
                                  setState(() {
                                    _selectedAge =
                                        _selectedAge == age ? '' : age;
                                  });
                                  _loadBarajlar();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: palette.primary),
                    )
                  : _error != null
                      ? Center(
                          child: EmptyStateWidget(
                            title: 'Barajlar Yüklenemedi',
                            message: _error!,
                            icon: Icons.timer_off_outlined,
                            actionText: 'Tekrar Dene',
                            onAction: _loadBarajlar,
                          ),
                        )
                      : _rules.isEmpty
                              ? const Center(
                                  child: EmptyStateWidget(
                                    title: 'Baraj Bulunamadı',
                                    message:
                                        'Seçili filtrelere uygun baraj kuralı yok.',
                                    icon: Icons.timer_outlined,
                                  ),
                                )
                              : RefreshIndicator(
                                  color: palette.primary,
                                  onRefresh: _loadBarajlar,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      if (constraints.maxWidth < 720) {
                                        return ListView.builder(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            4,
                                            16,
                                            28,
                                          ),
                                          itemCount: strokes.length,
                                          itemBuilder: (context, idx) {
                                            final stroke = strokes[idx];
                                            final items = grouped[stroke]!;
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: _buildCompactStrokeCard(
                                                palette,
                                                stroke,
                                                items,
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      const spacing = 12.0;
                                      final cardWidth =
                                          (constraints.maxWidth - 32 - spacing) /
                                              2;
                                      return SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          4,
                                          16,
                                          28,
                                        ),
                                        child: Wrap(
                                          spacing: spacing,
                                          runSpacing: 12,
                                          children: strokes.map((stroke) {
                                            final items = grouped[stroke]!;
                                            return SizedBox(
                                              width: cardWidth,
                                              child: _buildCompactStrokeCard(
                                                palette,
                                                stroke,
                                                items,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStrokeCard(
    AppColorPalette palette,
    String strokeName,
    List<BarajRule> items,
  ) {
    final byRow = <String, ({int mesafe, String age, Map<String, BarajRule> pair})>{};
    for (final r in items) {
      final key = '${r.mesafe}|${r.yasEtiketi}';
      final entry = byRow.putIfAbsent(
        key,
        () => (mesafe: r.mesafe, age: r.yasEtiketi, pair: <String, BarajRule>{}),
      );
      final g = r.cinsiyet.toLowerCase();
      if (g.contains('kad') || g.contains('bayan')) {
        entry.pair['K'] = r;
      } else {
        entry.pair['E'] = r;
      }
    }
    final rows = byRow.values.toList()
      ..sort((a, b) {
        final d = a.mesafe.compareTo(b.mesafe);
        return d != 0 ? d : a.age.compareTo(b.age);
      });
    final showAgeInRow = _selectedAge.isEmpty &&
        rows.map((r) => r.age).where((a) => a.isNotEmpty).toSet().length > 1;

    return SoftGlassPanel(
      level: 2,
      borderRadius: AppRadius.cardRadius,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: AppRadius.full,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  strokeName,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _selectedAge.isEmpty ? 'Tüm Yaşlar' : _selectedAge,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'KADIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 64),
                Expanded(
                  child: Text(
                    'ERKEK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 8, color: palette.divider),
          ...List.generate(rows.length, (i) {
            final row = rows[i];
            final dist = row.mesafe;
            final female = row.pair['K'];
            final male = row.pair['E'];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                border: i < rows.length - 1
                    ? Border(bottom: BorderSide(color: palette.divider))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      female?.sure ?? '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: female != null
                            ? palette.textPrimary
                            : palette.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Container(
                    width: showAgeInRow ? 74 : 56,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${dist}m',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                          ),
                        ),
                        if (showAgeInRow && row.age.isNotEmpty)
                          Text(
                            row.age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      male?.sure ?? '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: male != null
                            ? palette.textPrimary
                            : palette.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    bool selected,
    AppColorPalette palette,
    VoidCallback onTap,
  ) {
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
}
