import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/athlete.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';

/// Kulüp Bayrak Takımı Simülatörü (4x50 / 4x100 Serbest & Karışık).
class RelaySimulatorScreen extends StatefulWidget {
  final SwimRepository repository;

  const RelaySimulatorScreen({super.key, required this.repository});

  @override
  State<RelaySimulatorScreen> createState() => _RelaySimulatorScreenState();
}

class _RelaySimulatorScreenState extends State<RelaySimulatorScreen> {
  final TextEditingController _clubSearchCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  Timer? _debounce;

  int? _clubId;
  String? _clubName;
  bool _searchingClubs = false;
  List<ClubSearchItem> _clubResults = [];

  String _relayType = '4x50_free';
  String _gender = 'Erkek';
  String _course = 'LC';

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _simData;

  @override
  void initState() {
    super.initState();
    final sel = SelectedClubService.instance;
    if (sel.hasSelectedClub) {
      _clubId = sel.clubId;
      _clubName = sel.clubName;
      _runSimulation();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clubSearchCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _onClubSearchChanged(String q) {
    _debounce?.cancel();
    final t = q.trim();
    if (t.length < 2) {
      setState(() {
        _clubResults = [];
        _searchingClubs = false;
      });
      return;
    }
    setState(() => _searchingClubs = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await widget.repository.searchGlobal(t);
        if (mounted) {
          setState(() {
            _clubResults = res.clubs;
            _searchingClubs = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingClubs = false);
      }
    });
  }

  Future<void> _runSimulation() async {
    if (_clubId == null && (_clubName == null || _clubName!.isEmpty)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final y = int.tryParse(_yearCtrl.text.trim());
      final data = await widget.repository.getRelaySimulator(
        clubId: _clubId,
        clubName: _clubName,
        relayType: _relayType,
        gender: _gender,
        course: _course,
        birthYear: y,
      );
      if (mounted) {
        setState(() {
          _simData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Bayrak simülasyonu hesaplanamadı.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final legs = (_simData?['legs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final totalTime = _simData?['total_time'] as String?;
    final complete = _simData?['complete'] == true;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Bayrak Takımı Simülatörü',
          style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // Kulüp Seçimi
          if (_clubName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.primaryContainer,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, color: palette.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _clubName!,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _clubId = null;
                      _clubName = null;
                      _simData = null;
                    }),
                    child: const Text('Değiştir'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.inputRadius,
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: palette.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _clubSearchCtrl,
                      onChanged: _onClubSearchChanged,
                      style: TextStyle(fontSize: 14, color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Kulüp ara (ör. Enka, Fenerbahçe, Alpha)...',
                        hintStyle: TextStyle(fontSize: 13.5, color: palette.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchingClubs)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                    ),
                ],
              ),
            ),
            if (_clubResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: _clubResults.take(8).map((c) {
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.shield_outlined, color: palette.primary, size: 18),
                      title: Text(
                        c.name,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: palette.textPrimary),
                      ),
                      onTap: () {
                        setState(() {
                          _clubId = c.id;
                          _clubName = c.name;
                          _clubResults = [];
                          _clubSearchCtrl.clear();
                        });
                        _runSimulation();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],

          // Filtreler
          if (_clubName != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(palette, '4x50 Serbest', _relayType == '4x50_free', () {
                  setState(() => _relayType = '4x50_free');
                  _runSimulation();
                }),
                _chip(palette, '4x100 Serbest', _relayType == '4x100_free', () {
                  setState(() => _relayType = '4x100_free');
                  _runSimulation();
                }),
                _chip(palette, '4x50 Karışık', _relayType == '4x50_medley', () {
                  setState(() => _relayType = '4x50_medley');
                  _runSimulation();
                }),
                _chip(palette, '4x100 Karışık', _relayType == '4x100_medley', () {
                  setState(() => _relayType = '4x100_medley');
                  _runSimulation();
                }),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip(palette, 'Erkek', _gender == 'Erkek', () {
                  setState(() => _gender = 'Erkek');
                  _runSimulation();
                }),
                const SizedBox(width: 6),
                _chip(palette, 'Kadın', _gender == 'Kadın', () {
                  setState(() => _gender = 'Kadın');
                  _runSimulation();
                }),
                const SizedBox(width: 10),
                _chip(palette, '50m', _course == 'LC', () {
                  setState(() => _course = 'LC');
                  _runSimulation();
                }),
                const SizedBox(width: 6),
                _chip(palette, '25m', _course == 'SC', () {
                  setState(() => _course = 'SC');
                  _runSimulation();
                }),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _runSimulation(),
                    style: TextStyle(fontSize: 13, color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'D.Yılı',
                      hintStyle: TextStyle(fontSize: 12, color: palette.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          if (_loading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: palette.primary)),
            )
          else if (_error != null)
            Text(_error!, style: TextStyle(color: palette.statusDanger))
          else if (_simData != null) ...[
            // Tahmini Toplam Süre Kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          complete ? 'Tahmini En Hızlı Bayrak' : 'Yeterli Sporcu Bulunamadı',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: complete ? palette.statusSuccess : palette.statusWarning,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Son 2 yıl PB derecelerine göre otomatik kadro',
                          style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    totalTime ?? '--:--.--',
                    style: AppTextStyles.officialTime.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: complete ? palette.primary : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 4 Ayak Listesi
            if (legs.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: legs.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final leg = entry.value;
                    final athId = leg['athlete_id'] as int;
                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: palette.primaryContainer,
                            child: Text(
                              '${leg['leg']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: palette.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            leg['athlete_name'] as String? ?? '',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '${leg['distance']}m ${leg['stroke_label']}'
                            '${leg['birth_year'] != null ? ' • ${leg['birth_year']}' : ''}',
                            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                          ),
                          trailing: Text(
                            leg['time'] as String? ?? '',
                            style: AppTextStyles.officialTime.copyWith(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AthleteProfileScreen(
                                  athleteId: athId,
                                  athleteName: leg['athlete_name'] as String? ?? '',
                                  repository: widget.repository,
                                ),
                              ),
                            );
                          },
                        ),
                        if (idx < legs.length - 1) Divider(height: 1, color: palette.divider),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(AppColorPalette palette, String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? Colors.white : palette.textSecondary,
      ),
      selectedColor: palette.primary,
      backgroundColor: palette.surface,
      side: BorderSide(color: selected ? palette.primary : palette.border),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
