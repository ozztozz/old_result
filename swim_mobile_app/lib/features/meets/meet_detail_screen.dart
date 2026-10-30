import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
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
  String? _selectedEventNo; // null = Tümü
  int? _selectedClubId;
  int? _selectedAthleteId;
  String _selectedStatus = 'all'; // all, finished, pending

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
        setState(() {
          _meetDetail = results[0] as MeetDetail;
          _participants = results[1] as MeetParticipants;
          _results = results[2] as List<RaceResult>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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
          style: const TextStyle(fontSize: 16),
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

                // 2. Yarış Sonuçları Listesi
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
                                return _buildResultCard(_results[index]);
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

    // Seçili kulübe göre daraltılmış sporcu listesi (0 ms filtreleme)
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
                    value: _selectedClubId,
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
                        // Seçili kulüp değiştiğinde sporcu listede yoksa sıfırla
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

                // Sporcu Seçimi (Kulüp seçildiyse sadece o kulübün sporcuları)
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _selectedAthleteId,
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

          // Durum Filtresi (Tümü, Sonuçlananlar, Bekleyenler)
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

  Widget _buildResultCard(RaceResult result) {
    final isWaiting = result.resultStatus == 'WAITING';
    final isDq = result.resultStatus == 'DQ' || result.resultStatus == 'DNS';
    final rankStr = result.rank.isNotEmpty ? '#${result.rank}' : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AthleteProfileScreen(
                athleteId: result.athleteId,
                athleteName: result.athleteName,
                repository: widget.repository,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Sıralama Rozeti
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isWaiting
                      ? Colors.amber.shade50
                      : isDq
                          ? Colors.red.shade50
                          : (result.rank == '1' ? Colors.amber.shade100 : Colors.blue.shade50),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  isWaiting ? '...' : (isDq ? result.resultStatus : rankStr),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isWaiting
                        ? Colors.amber.shade900
                        : isDq
                            ? Colors.red.shade800
                            : Colors.blue.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Sporcu & Kulüp Bilgisi
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.athleteName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.clubName,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (result.heat.isNotEmpty)
                          Text(
                            result.heat,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          ),
                        if (result.lane != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Kulvar ${result.lane}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Derece, Puan ve Baraj Rozeti
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isWaiting ? 'Bekleniyor' : SwimTimeFormatter.formatCs(result.timeCs),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isWaiting ? Colors.amber.shade800 : AppTheme.primaryBlue,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (result.points != null && result.points! > 0)
                    Text(
                      '${result.points} Puan',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                  if (result.qualifyingStandard != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        result.qualifyingStandard!.badge,
                        style: TextStyle(color: Colors.green.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
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
