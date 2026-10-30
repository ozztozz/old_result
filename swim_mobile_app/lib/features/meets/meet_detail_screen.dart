import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/meet.dart';
import '../../data/models/race_result.dart';
import '../../shared/widgets/swim_design_components.dart';
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
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 1. Üst Bar (RoundIconButton ile Geri Dön Butonu ve Başlık)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        RoundIconButton(
                          Icons.arrow_back,
                          onTap: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.meetTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Üst Filtre Paneli (Yarış No, Bağımlı Kulüp & Sporcu)
                  _buildFilterHeader(),

                  // 3. Yarış Sonuçları Listesi (SwimResultCard)
                  Expanded(
                    child: _isLoadingResults
                        ? const Center(child: CircularProgressIndicator())
                        : _results.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: const BoxDecoration(
                                        color: AppColors.card,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.search_off_rounded,
                                        size: 24,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Kriterlere uygun sonuç bulunamadı.',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
      ),
    );
  }

  Widget _buildFilterHeader() {
    final events = _meetDetail?.events ?? [];
    final clubs = _participants?.clubs ?? [];

    final allAthletes = _participants?.athletes ?? [];
    final filteredAthletes = _selectedClubId == null
        ? allAthletes
        : allAthletes.where((a) => a.clubId == _selectedClubId).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Yatay Yarış Seçici (Pastel Hap Butonlar)
          if (events.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildEventPill(
                    label: 'Tüm Yarışlar',
                    isSelected: _selectedEventNo == null,
                    onTap: () {
                      setState(() => _selectedEventNo = null);
                      _filterResults();
                    },
                  ),
                  const SizedBox(width: 8),
                  ...events.map((ev) {
                    final label = '${ev.distance != null ? "${ev.distance}m " : ""}${ev.strokeLabel}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildEventPill(
                        label: label,
                        isSelected: _selectedEventNo == ev.eventNo,
                        onTap: () {
                          setState(() {
                            _selectedEventNo = _selectedEventNo == ev.eventNo ? null : ev.eventNo;
                          });
                          _filterResults();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Bağımlı Kulüp ve Sporcu Seçici Dropdown'lar
          Row(
            children: [
              // Kulüp Seçimi
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedClubId,
                      isExpanded: true,
                      hint: const Text('Tüm Takımlar', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tüm Takımlar', style: TextStyle(fontSize: 12))),
                        ...clubs.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name, style: const TextStyle(fontSize: 12, color: AppColors.ink), overflow: TextOverflow.ellipsis),
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
                ),
              ),
              const SizedBox(width: 8),

              // Sporcu Seçimi
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedAthleteId,
                      isExpanded: true,
                      hint: const Text('Tüm Sporcular', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tüm Sporcular', style: TextStyle(fontSize: 12))),
                        ...filteredAthletes.map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name}${a.birthYear != null ? " (${a.birthYear})" : ""}',
                                style: const TextStyle(fontSize: 12, color: AppColors.ink),
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Durum Filtresi (Tümü, Sonuçlanan, Bekleyen)
          Row(
            children: [
              _buildStatusPill('all', 'Tümü'),
              const SizedBox(width: 8),
              _buildStatusPill('finished', 'Sonuçlanan'),
              const SizedBox(width: 8),
              _buildStatusPill('pending', 'Bekleyen'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventPill({required String label, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.lime : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String val, String label) {
    final isSelected = _selectedStatus == val;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedStatus = val);
        _filterResults();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.teal : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}
