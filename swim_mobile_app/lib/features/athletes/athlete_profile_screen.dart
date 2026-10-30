import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/athlete.dart';

/// 3. Ekran: Sporcu Profili, 25m/50m PB Tablosu ve Kariyer Karnesi
class AthleteProfileScreen extends StatefulWidget {
  final int athleteId;
  final String athleteName;
  final SwimRepository repository;

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.repository,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  AthleteDetail? _athlete;
  List<AthleteRaceHistoryItem> _raceHistory = [];
  bool _isFavorite = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAthleteData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAthleteData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getAthleteDetail(widget.athleteId),
        widget.repository.getAthleteRaces(widget.athleteId, page: 1),
      ]);
      if (mounted) {
        setState(() {
          _athlete = results[0] as AthleteDetail;
          _raceHistory = results[1] as List<AthleteRaceHistoryItem>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFavorite ? 'Sporcu favorilere eklendi.' : 'Sporcu favorilerden çıkarıldı.',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.athleteName),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? Colors.amber : null,
            ),
            onPressed: _toggleFavorite,
            tooltip: 'Favoriye Ekle',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _athlete == null
              ? const Center(child: Text('Sporcu bilgileri yüklenemedi.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Profil Başlık Kartı
                      _buildHeaderCard(_athlete!),
                      const SizedBox(height: 16),

                      // 2. Kariyer İstatistikleri
                      _buildStatsRow(_athlete!.stats),
                      const SizedBox(height: 16),

                      // 3. Scout Değerlendirme Notu
                      if (_athlete!.scoutNote.isNotEmpty) ...[
                        _buildScoutNoteCard(_athlete!.scoutNote),
                        const SizedBox(height: 16),
                      ],

                      // 4. Kişisel En İyi Dereceler (PB Tablosu: 50m / 25m Sekmeli)
                      _buildPbSection(_athlete!),
                      const SizedBox(height: 20),

                      // 5. Son Yarış Geçmişi
                      _buildRaceHistorySection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeaderCard(AthleteDetail a) {
    final initials = a.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppTheme.primaryBlue,
              child: Text(
                initials,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.clubName ?? 'Ferdi Sporcu',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (a.school != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      a.school!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${a.birthYear ?? "-"} Doğumlu · ${a.age != null ? "${a.age} Yaşında" : ""}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(AthleteStats stats) {
    return Row(
      children: [
        _buildStatBox('Toplam Yarış', '${stats.totalRaces}', Colors.blue),
        const SizedBox(width: 8),
        _buildStatBox('Podyum / Kürsü', '${stats.podiumCount} (%${stats.podiumRate})', Colors.amber),
        const SizedBox(width: 8),
        _buildStatBox('Geçilen Baraj', '${stats.standardsPassed}', Colors.green),
      ],
    );
  }

  Widget _buildStatBox(String label, String value, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade200),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color.shade900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoutNoteCard(String note) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.slate ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPbSection(AthleteDetail a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Kişisel En İyi Dereceler (PB)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              width: 160,
              height: 32,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '50m (Uzun)'),
                  Tab(text: '25m (Kısa)'),
                ],
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPbList(a.pbs50m, '50m Uzun Kulvar'),
              _buildPbList(a.pbs25m, '25m Kısa Kulvar'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPbList(List<PersonalBest> pbs, String courseName) {
    if (pbs.isEmpty) {
      return Center(
        child: Text(
          '$courseName için kayıtlı PB derecesi bulunmuyor.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: pbs.length,
      itemBuilder: (context, index) {
        final pb = pbs[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pb.distance}m ${pb.strokeLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '${pb.date} · ${pb.meetName}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    SwimTimeFormatter.formatCs(pb.timeCs),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.primaryBlue,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (pb.points != null)
                    Text(
                      '${pb.points} Puan',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRaceHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son Yarış Geçmişi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_raceHistory.isEmpty)
          const Text('Kayıtlı yarış geçmişi bulunamadı.')
        else
          ..._raceHistory.take(10).map((r) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.meetName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${r.distance}m ${r.strokeLabel} · ${r.date}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            SwimTimeFormatter.formatCs(r.timeCs),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.primaryBlue,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (r.rank.isNotEmpty)
                            Text(
                              '#${r.rank} Sıra',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}
