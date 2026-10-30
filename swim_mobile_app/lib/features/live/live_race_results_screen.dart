import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/swim_theme.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/swim_result_card.dart';
import '../athletes/athlete_profile_screen.dart';

/// Tek Bir Canlı Yarışın Sonuçları Ekranı (Dereceler, Seriler, Kulvarlar)
/// Başlıkta veya ekranda yarış numarası KESİNLİKLE yer almaz.
class LiveRaceResultsScreen extends StatefulWidget {
  final LiveMeetSummary live;
  final LiveEventProgramItem event;
  final SwimRepository repository;

  const LiveRaceResultsScreen({
    super.key,
    required this.live,
    required this.event,
    required this.repository,
  });

  @override
  State<LiveRaceResultsScreen> createState() => _LiveRaceResultsScreenState();
}

class _LiveRaceResultsScreenState extends State<LiveRaceResultsScreen> {
  bool _isLoading = true;
  bool _isAutoRefresh = false;
  Timer? _refreshTimer;

  List<RaceResult> _allResults = [];
  List<RaceResult> _filteredResults = [];

  String _selectedStatus = 'all'; // 'all', 'finished', 'pending'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAutoRefresh(bool enable) {
    setState(() => _isAutoRefresh = enable);
    _refreshTimer?.cancel();
    if (enable) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _loadResults(silent: true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Otomatik yenileme devrede (15 sn)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadResults({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final feed = await widget.repository.getLiveFeedResponse(
        widget.live.id,
        eventNo: widget.event.eventNo,
        status: _selectedStatus,
      );

      List<RaceResult> results = feed.data;

      // Canlı akış henüz bu yarış için boşsa ancak meetId varsa müsabaka sonuçlarından çek
      if (results.isEmpty && widget.live.meetId != null) {
        try {
          results = await widget.repository.getMeetResults(
            widget.live.meetId!,
            eventNo: widget.event.eventNo,
            status: _selectedStatus != 'all' ? _selectedStatus : null,
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _allResults = results;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    List<RaceResult> list;
    if (_searchQuery.trim().isEmpty) {
      list = List.from(_allResults);
    } else {
      final q = _searchQuery.toLowerCase();
      list = _allResults.where((r) {
        return r.athleteName.toLowerCase().contains(q) ||
            r.clubName.toLowerCase().contains(q);
      }).toList();
    }

    // Sıralama Kuralı:
    // 1. Sonuçlar varsa dereceye göre sırala (en hızlı derece en üstte)
    // 2. Diskalifiyeler (DQ, DNS, DNF) DAİMA EN SONDA
    // 3. Sonuç yoksa (veya derecesizler) seri ve kulvara göre sırala
    final bool hasFinishedResults = list.any((r) => r.timeCs != null && r.timeCs! > 0);

    list.sort((a, b) {
      final bool isDqA = a.resultStatus == 'DQ' ||
          a.resultStatus == 'DNS' ||
          a.resultStatus == 'DNF' ||
          a.rank.toUpperCase().startsWith('DQ') ||
          a.rank.toUpperCase().startsWith('DSQ');
      final bool isDqB = b.resultStatus == 'DQ' ||
          b.resultStatus == 'DNS' ||
          b.resultStatus == 'DNF' ||
          b.rank.toUpperCase().startsWith('DQ') ||
          b.rank.toUpperCase().startsWith('DSQ');

      // 1. Diskalifiyeler EN SONDA
      if (isDqA && !isDqB) return 1;
      if (!isDqA && isDqB) return -1;
      if (isDqA && isDqB) {
        final heatA = int.tryParse(a.heat) ?? 999;
        final heatB = int.tryParse(b.heat) ?? 999;
        if (heatA != heatB) return heatA.compareTo(heatB);
        return (a.lane ?? 999).compareTo(b.lane ?? 999);
      }

      // 2. Sonuçlar varsa: Dereceye göre sırala (küçükten büyüğe)
      if (hasFinishedResults) {
        final bool hasTimeA = a.timeCs != null && a.timeCs! > 0;
        final bool hasTimeB = b.timeCs != null && b.timeCs! > 0;

        if (hasTimeA && !hasTimeB) return -1;
        if (!hasTimeA && hasTimeB) return 1;

        if (hasTimeA && hasTimeB) {
          final cmp = a.timeCs!.compareTo(b.timeCs!);
          if (cmp != 0) return cmp;
          final rankA = int.tryParse(a.rank) ?? 999;
          final rankB = int.tryParse(b.rank) ?? 999;
          if (rankA != rankB) return rankA.compareTo(rankB);
        }
      }

      // 3. Sonuç yoksa: Seri ve kulvara göre sırala
      final heatA = int.tryParse(a.heat) ?? 999;
      final heatB = int.tryParse(b.heat) ?? 999;
      if (heatA != heatB) return heatA.compareTo(heatB);
      return (a.lane ?? 999).compareTo(b.lane ?? 999);
    });

    _filteredResults = list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.swimColors;
    final isRunning = widget.live.status == 'ISLENIYOR';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.genderLabel.isNotEmpty
                  ? '${widget.event.displayTitle} - ${widget.event.genderLabel}'
                  : widget.event.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (widget.event.ageGroup != null && widget.event.ageGroup!.isNotEmpty)
              Text(
                widget.event.ageGroup!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isAutoRefresh ? 'Otomatik Yenilemeyi Kapat' : 'Otomatik Yenilemeyi Aç',
            icon: Icon(
              _isAutoRefresh ? Icons.sync : Icons.sync_disabled,
              color: _isAutoRefresh ? Colors.green : null,
            ),
            onPressed: () => _toggleAutoRefresh(!_isAutoRefresh),
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadResults(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadResults(silent: true),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. Yarış Bilgi Başlığı (Numarasız)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStrokeIcon(widget.event.stroke),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.event.displayTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.live.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isRunning)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: Colors.green),
                                SizedBox(width: 4),
                                Text(
                                  'CANLI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (widget.event.gender != null && widget.event.gender!.isNotEmpty)
                          _buildBadge(
                            widget.event.gender!,
                            widget.event.gender!.toLowerCase().contains('kad')
                                ? Colors.purple.shade50
                                : Colors.blue.shade50,
                            widget.event.gender!.toLowerCase().contains('kad')
                                ? Colors.purple.shade900
                                : Colors.blue.shade900,
                          ),
                        if (widget.event.ageGroup != null && widget.event.ageGroup!.isNotEmpty)
                          _buildBadge(
                            widget.event.ageGroup!,
                            Colors.grey.shade100,
                            Colors.grey.shade800,
                          ),
                        _buildBadge(
                          '${_allResults.length} Sporcu',
                          Colors.teal.shade50,
                          Colors.teal.shade900,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Arama ve Durum Filtreleri
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Yarışta sporcu veya kulüp ara...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilter();
                });
              },
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                _buildStatusChip('all', 'Tümü'),
                const SizedBox(width: 6),
                _buildStatusChip('finished', 'Sonuçlananlar'),
                const SizedBox(width: 6),
                _buildStatusChip('pending', 'Beklenenler'),
              ],
            ),
            const SizedBox(height: 12),

            // 3. Sonuç Listesi
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredResults.isEmpty)
              _buildEmptyState()
            else
              ..._filteredResults.map((result) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Seri ve Kulvar Rozeti
                    if (result.heat.isNotEmpty || (result.lane != null && result.lane! > 0))
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Row(
                          children: [
                            if (result.heat.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Text(
                                  'Seri: ${result.heat}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            if (result.lane != null && result.lane! > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(
                                  'Kulvar ${result.lane}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    SwimResultCard(
                      result: result,
                      onTap: () {
                        if (result.athleteId > 0) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AthleteProfileScreen(
                                athleteId: result.athleteId,
                                athleteName: result.athleteName,
                                repository: widget.repository,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStrokeIcon(String stroke) {
    IconData iconData = Icons.pool;
    Color iconColor = Colors.blue;

    switch (stroke.toUpperCase()) {
      case 'FREE':
        iconData = Icons.waves;
        iconColor = Colors.blue;
        break;
      case 'BACK':
        iconData = Icons.water;
        iconColor = Colors.indigo;
        break;
      case 'BREAST':
        iconData = Icons.arrow_downward;
        iconColor = Colors.teal;
        break;
      case 'FLY':
        iconData = Icons.air;
        iconColor = Colors.deepOrange;
        break;
      case 'MEDLEY':
        iconData = Icons.auto_awesome;
        iconColor = Colors.purple;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: iconColor, size: 22),
    );
  }

  Widget _buildBadge(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textCol),
      ),
    );
  }

  Widget _buildStatusChip(String val, String label) {
    final isSelected = _selectedStatus == val;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        setState(() => _selectedStatus = val);
        _loadResults();
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.sports_score, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Bu yarış için henüz netice bulunmuyor.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Yarış yüzüldükçe sonuçlar buraya anlık olarak gelecektir.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

