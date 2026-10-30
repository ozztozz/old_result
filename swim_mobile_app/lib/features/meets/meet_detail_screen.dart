import 'package:flutter/material.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../shared/widgets/swim_result_card.dart';
import '../athletes/athlete_profile_screen.dart';

/// 2. Ekran: Müsabaka Detayı, Filtreler ve Yarış Sonuçları
class MeetDetailScreen extends StatefulWidget {
  final int meetId;
  final String meetTitle;
  final SwimRepository repository;

  const MeetDetailScreen({
    super.key,
    required this.meetId,
    required this.meetTitle,
    required this.repository,
  });

  @override
  State<MeetDetailScreen> createState() => _MeetDetailScreenState();
}

class _MeetDetailScreenState extends State<MeetDetailScreen> {
  bool _isLoading = true;
  bool _isLoadingResults = false;

  MeetDetail? _meetDetail;
  MeetParticipants? _participants;
  List<RaceResult> _results = [];

  // Filtre Değerleri
  String? _selectedEventNo;
  int? _selectedClubId;
  int? _selectedAthleteId;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getMeetDetail(widget.meetId),
        widget.repository.getMeetParticipants(widget.meetId),
        widget.repository.getMeetResults(widget.meetId, page: 1),
      ]);

      if (mounted) {
        final list = results[2] as List<RaceResult>;
        _sortResults(list);
        setState(() {
          _meetDetail = results[0] as MeetDetail;
          _participants = results[1] as MeetParticipants;
          _results = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sortResults(List<RaceResult> list) {
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
  }

  Future<void> _filterResults() async {
    setState(() => _isLoadingResults = true);
    try {
      final res = await widget.repository.getMeetResults(
        widget.meetId,
        eventNo: _selectedEventNo,
        clubId: _selectedClubId,
        athleteId: _selectedAthleteId,
        status: _selectedStatus,
        page: 1,
      );
      if (mounted) {
        _sortResults(res);
        setState(() {
          _results = res;
          _isLoadingResults = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.meetTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Üst Filtre Paneli (Yarış No, Bağımlı Kulüp & Sporcu)
                _buildFilterHeader(),

                // 2. Yarış Sonuçları Listesi (SwimResultCard)
                Expanded(
                  child: _isLoadingResults
                      ? const Center(child: CircularProgressIndicator())
                      : _results.isEmpty
                          ? const Center(
                              child: Text('Kriterlere uygun sonuç bulunamadı.'),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final r = _results[index];
                                return SwimResultCard(
                                  result: r,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AthleteProfileScreen(
                                          athleteId: r.athleteId,
                                          athleteName: r.athleteName,
                                          repository: widget.repository,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterHeader() {
    final events = _meetDetail?.events ?? [];
    final clubs = _participants?.clubs ?? [];

    // Seçili kulübe göre daraltılmış sporcu listesi (0 ms gecikme)
    final allAthletes = _participants?.athletes ?? [];
    final filteredAthletes = _selectedClubId == null
        ? allAthletes
        : allAthletes.where((a) => a.clubId == _selectedClubId).toList();

    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Yatay Yarış No Seçici (Hap Butonlar)
          if (events.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Tüm Yarışlar'),
                    selected: _selectedEventNo == null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedEventNo = null);
                        _filterResults();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ...events.map((ev) {
                    final label = 'Yarış ${ev.eventNo}${ev.distance != null ? " · ${ev.distance}m ${ev.strokeLabel}" : ""}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _selectedEventNo == ev.eventNo,
                        onSelected: (selected) {
                          setState(() {
                            _selectedEventNo = selected ? ev.eventNo : null;
                          });
                          _filterResults();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

          // Bağımlı Kulüp ve Sporcu Seçici Dropdown'lar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Kulüp Seçimi
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedClubId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      hintText: 'Tüm Takımlar',
                      hintStyle: const TextStyle(fontSize: 12),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tüm Takımlar', style: TextStyle(fontSize: 12))),
                      ...clubs.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedClubId = val;
                        if (_selectedAthleteId != null) {
                          final match = filteredAthletes.any((a) => a.id == _selectedAthleteId);
                          if (!match) _selectedAthleteId = null;
                        }
                      });
                      _filterResults();
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Sporcu Seçimi
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _selectedAthleteId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      hintText: 'Tüm Sporcular',
                      hintStyle: const TextStyle(fontSize: 12),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tüm Sporcular', style: TextStyle(fontSize: 12))),
                      ...filteredAthletes.map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.name}${a.birthYear != null ? " (${a.birthYear})" : ""}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedAthleteId = val);
                      _filterResults();
                    },
                  ),
                ),
              ],
            ),
          ),

          // Durum Filtresi (SegmentedButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Tümü', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'finished', label: Text('Sonuçlanan', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'pending', label: Text('Bekleyen', style: TextStyle(fontSize: 12))),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (set) {
                setState(() => _selectedStatus = set.first);
                _filterResults();
              },
            ),
          ),
        ],
      ),
    );
  }
}
