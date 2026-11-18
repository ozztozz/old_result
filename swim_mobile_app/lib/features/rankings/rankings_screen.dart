import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';

/// Yaş Grubu, Branş ve İl Bazlı Top 25 Sıralamalar Ekranı.
class RankingsScreen extends StatefulWidget {
  final SwimRepository repository;

  const RankingsScreen({super.key, required this.repository});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();

  String _gender = 'Erkek';
  String _course = 'LC';
  String _stroke = 'free';
  int _distance = 50;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  static const _strokes = [
    ('free', 'Serbest'),
    ('back', 'Sırtüstü'),
    ('breast', 'Kurbağa'),
    ('fly', 'Kelebek'),
    ('medley', 'Karışık'),
  ];

  static const _distances = [50, 100, 200, 400, 800, 1500];

  @override
  void initState() {
    super.initState();
    _loadRankings();
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRankings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final y = int.tryParse(_yearCtrl.text.trim());
      final c = _cityCtrl.text.trim();
      final list = await widget.repository.getRankings(
        stroke: _stroke,
        distance: _distance,
        gender: _gender,
        course: _course,
        birthYear: y,
        city: c.isNotEmpty ? c : null,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Sıralama verileri yüklenemedi.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Top 25 Sıralamalar',
          style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // Cinsiyet & Kulvar
          Row(
            children: [
              _chip(palette, 'Erkek', _gender == 'Erkek', () {
                setState(() => _gender = 'Erkek');
                _loadRankings();
              }),
              const SizedBox(width: 6),
              _chip(palette, 'Kadın', _gender == 'Kadın', () {
                setState(() => _gender = 'Kadın');
                _loadRankings();
              }),
              const Spacer(),
              _chip(palette, '50m', _course == 'LC', () {
                setState(() => _course = 'LC');
                _loadRankings();
              }),
              const SizedBox(width: 6),
              _chip(palette, '25m', _course == 'SC', () {
                setState(() => _course = 'SC');
                _loadRankings();
              }),
            ],
          ),
          const SizedBox(height: 10),

          // Stil
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _strokes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, idx) {
                final (code, label) = _strokes[idx];
                return _chip(palette, label, _stroke == code, () {
                  setState(() => _stroke = code);
                  _loadRankings();
                });
              },
            ),
          ),
          const SizedBox(height: 8),

          // Mesafe
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _distances.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, idx) {
                final d = _distances[idx];
                return _chip(palette, '${d}m', _distance == d, () {
                  setState(() => _distance = d);
                  _loadRankings();
                });
              },
            ),
          ),
          const SizedBox(height: 10),

          // İl ve Doğum Yılı
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _cityCtrl,
                  onSubmitted: (_) => _loadRankings(),
                  style: TextStyle(fontSize: 13, color: palette.textPrimary),
                  decoration: _inputDec(palette, 'İl (ör. Ankara)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _yearCtrl,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _loadRankings(),
                  style: TextStyle(fontSize: 13, color: palette.textPrimary),
                  decoration: _inputDec(palette, 'D.Yılı (2014)'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loadRankings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Getir', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_loading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: palette.primary)),
            )
          else if (_error != null)
            Text(_error!, style: TextStyle(color: palette.statusDanger))
          else if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: palette.border),
              ),
              child: Text(
                'Seçilen kriterlerde sonuç bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: _items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final rank = item['rank'] as int? ?? (idx + 1);
                  final isPodium = rank <= 3;
                  final athId = item['athlete_id'] as int;

                  return Column(
                    children: [
                      ListTile(
                        leading: SizedBox(
                          width: 28,
                          child: Text(
                            '$rank.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isPodium ? palette.gold : palette.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        title: Text(
                          item['athlete_name'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (item['birth_year'] != null) '${item['birth_year']}',
                            item['club_name'] as String? ?? 'Ferdi',
                            if ((item['city'] as String? ?? '').isNotEmpty) item['city'],
                          ].join(' • '),
                          style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item['time'] as String? ?? '',
                              style: AppTextStyles.officialTime.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            if (item['points'] != null)
                              Text(
                                '${item['points']} FINA',
                                style: TextStyle(fontSize: 10, color: palette.gold, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AthleteProfileScreen(
                                athleteId: athId,
                                athleteName: item['athlete_name'] as String? ?? '',
                                repository: widget.repository,
                              ),
                            ),
                          );
                        },
                      ),
                      if (idx < _items.length - 1) Divider(height: 1, color: palette.divider),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(AppColorPalette palette, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12.5, color: palette.textMuted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
