import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';

/// 5. Ekran: Favorilerim & Hızlı Takip (Mobil Özel)
class FavoritesScreen extends StatefulWidget {
  final SwimRepository repository;

  const FavoritesScreen({super.key, required this.repository});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isLoading = false;
  // Varsayılan / kayıtlı örnek favori ID'leri (gerçekte SharedPreferences / Drift'ten okunur)
  final List<int> _favoriteIds = [1, 2];
  List<Map<String, dynamic>> _favoritesData = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    if (_favoriteIds.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final list = await widget.repository.getAthletesSummary(_favoriteIds);
      if (mounted) {
        setState(() {
          _favoritesData = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.star, color: Colors.amber),
            SizedBox(width: 8),
            Text('Takip Ettiğim Sporcular'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoritesData.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_border, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'Henüz favori sporcu eklemediniz.',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sporcu profilindeki yıldız simgesine dokunarak\nçocuğunuzu veya öğrencilerinizi buraya ekleyebilirsiniz.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _favoritesData.length,
                    itemBuilder: (context, index) {
                      final fav = _favoritesData[index];
                      final latest = fav['latest_race'] as Map<String, dynamic>?;
                      final topPerf = fav['top_performance'] as Map<String, dynamic>?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AthleteProfileScreen(
                                  athleteId: fav['id'] as int,
                                  athleteName: fav['name'] as String? ?? '',
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
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.primaryBlue,
                                      child: const Icon(Icons.person, color: Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fav['name'] as String? ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          Text(
                                            '${fav['birth_year'] ?? "-"} · ${fav['club_name'] ?? "Ferdi"}',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.grey),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Son Yarışı',
                                            style: TextStyle(color: Colors.grey, fontSize: 11),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            latest != null
                                                ? '${latest['distance']}m ${latest['stroke']} (${latest['time']})'
                                                : '-',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          const Text(
                                            'En Yüksek FINA',
                                            style: TextStyle(color: Colors.grey, fontSize: 11),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            topPerf != null ? '${topPerf['points']} Puan' : '-',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
