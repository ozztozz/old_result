import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/live_meet.dart';
import '../meets/meet_detail_screen.dart';
import '../athletes/athlete_profile_screen.dart';

/// 1. Ekran: Ana Sayfa & Keşfet (Home Dashboard)
class HomeScreen extends StatefulWidget {
  final SwimRepository repository;

  const HomeScreen({super.key, required this.repository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<MeetSummary> _recentMeets = [];
  List<LiveMeetSummary> _liveMeets = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getMeets(page: 1),
        widget.repository.getLiveMeets(),
      ]);
      if (mounted) {
        setState(() {
          _recentMeets = results[0] as List<MeetSummary>;
          _liveMeets = results[1] as List<LiveMeetSummary>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSearchModal() {
    showSearch(
      context: context,
      delegate: _SwimSearchDelegate(repository: widget.repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.pool, color: AppTheme.primaryBlue, size: 28),
            SizedBox(width: 8),
            Text('TYF Yüzme Sonuçları'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearchModal,
            tooltip: 'Sporcu / Kulüp Ara',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Hızlı Arama Butonu (Search Bar Placeholder)
                  InkWell(
                    onTap: _openSearchModal,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey.shade500),
                          const SizedBox(width: 12),
                          Text(
                            'Sporcu, kulüp veya müsabaka ara...',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Aktif Canlı Yarış Varsa Canlı Banner
                  if (_liveMeets.isNotEmpty) ...[
                    _buildLiveBanner(_liveMeets.first),
                    const SizedBox(height: 24),
                  ],

                  // Son Eklenen Müsabakalar Başlığı
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Güncel Müsabakalar',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_recentMeets.length} Müsabaka',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Müsabaka Kartları Listesi
                  ..._recentMeets.take(8).map((meet) => _buildMeetCard(meet)),
                ],
              ),
            ),
    );
  }

  Widget _buildLiveBanner(LiveMeetSummary live) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade700, Colors.red.shade900],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'CANLI YARIŞ',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (live.city.isNotEmpty)
                Text(
                  live.city,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            live.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start: ${live.startListProgress.processed}/${live.startListProgress.total} · Sonuç: ${live.resultListProgress.processed}/${live.resultListProgress.total}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetCard(MeetSummary meet) {
    final is25m = meet.course == 'SC';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MeetDetailScreen(
                meetId: meet.id,
                meetTitle: meet.name,
                repository: widget.repository,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      meet.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: is25m ? Colors.purple.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: is25m ? Colors.purple.shade200 : Colors.blue.shade200,
                      ),
                    ),
                    child: Text(
                      is25m ? '25m (Kısa)' : '50m (Uzun)',
                      style: TextStyle(
                        color: is25m ? Colors.purple.shade700 : Colors.blue.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (meet.city.isNotEmpty) ...[
                    Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(meet.city, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(width: 12),
                  ],
                  if (meet.startDate.isNotEmpty) ...[
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(meet.startDate, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${meet.totalRaces} Yarış',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const Text(' · ', style: TextStyle(color: Colors.grey)),
                  Text(
                    '${meet.totalAthletes} Sporcu',
                    style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arama Delegesi (Search Delegate)
class _SwimSearchDelegate extends SearchDelegate {
  final SwimRepository repository;

  _SwimSearchDelegate({required this.repository});

  @override
  String get searchFieldLabel => 'Sporcu veya kulüp ara...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.trim().length < 2) {
      return const Center(child: Text('Aramak için en az 2 harf girin.'));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: repository.searchGlobal(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.hasError) {
          return const Center(child: Text('Sonuç bulunamadı.'));
        }

        final data = snapshot.data!;
        final athletes = (data['athletes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        final clubs = (data['clubs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

        if (athletes.isEmpty && clubs.isEmpty) {
          return const Center(child: Text('Eşleşen sonuç bulunamadı.'));
        }

        return ListView(
          children: [
            if (athletes.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sporcular', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              ...athletes.map((a) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.primaryBlue,
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    title: Text(a['name'] as String? ?? ''),
                    subtitle: Text(
                      '${a['birth_year'] ?? '-'} · ${a['club_name'] ?? 'Ferdi'}',
                    ),
                    onTap: () {
                      close(context, null);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AthleteProfileScreen(
                            athleteId: a['id'] as int,
                            athleteName: a['name'] as String? ?? '',
                            repository: repository,
                          ),
                        ),
                      );
                    },
                  )),
            ],
            if (clubs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Kulüpler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              ...clubs.map((c) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.shield, color: Colors.white, size: 20),
                    ),
                    title: Text(c['name'] as String? ?? ''),
                    subtitle: Text('${c['athlete_count'] ?? 0} Kayıtlı Sporcu'),
                    onTap: () {
                      // Kulüp ekranı Faz 4
                    },
                  )),
            ],
          ],
        );
      },
    );
  }
}
