import 'package:flutter/material.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/race_result_sorter.dart';
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
  String? _errorMessage;

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.getMeetDetail(widget.meetId),
        widget.repository.getMeetParticipants(widget.meetId),
        widget.repository.getMeetResults(widget.meetId, page: 1),
      ]);

      if (mounted) {
        final list = results[2] as List<RaceResult>;
        RaceResultSorter.sort(list, preferRankFirst: false);
        setState(() {
          _meetDetail = results[0] as MeetDetail;
          _participants = results[1] as MeetParticipants;
          _results = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Müsabaka detayları yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
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
        RaceResultSorter.sort(res, preferRankFirst: false);
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
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: palette.primary))
            : _errorMessage != null && _meetDetail == null
                ? Center(
                    child: EmptyStateWidget(
                      title: 'Bağlantı Hatası',
                      message: _errorMessage!,
                      icon: Icons.cloud_off_rounded,
                      actionText: 'Tekrar Dene',
                      onAction: _loadInitialData,
                    ),
                  )
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Üst Filtre Paneli (Yarış No, Bağımlı Kulüp & Sporcu)
                  _buildFilterHeader(palette),

                  // 3. Yarış Sonuçları Listesi (SwimResultCard)
                  Expanded(
                    child: _isLoadingResults
                        ? Center(child: CircularProgressIndicator(color: palette.primary))
                        : _results.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: palette.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: palette.border),
                                      ),
                                      child: Icon(
                                        Icons.search_off_rounded,
                                        size: 24,
                                        color: palette.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Kriterlere uygun sonuç bulunamadı.',
                                      style: TextStyle(
                                        color: palette.textMuted,
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

  Widget _buildFilterHeader(AppColorPalette palette) {
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
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
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
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedClubId,
                      isExpanded: true,
                      dropdownColor: palette.surfaceElevated,
                      hint: Text('Tüm Takımlar', style: TextStyle(fontSize: 12, color: palette.textMuted)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Tüm Takımlar', style: TextStyle(fontSize: 12, color: palette.textPrimary))),
                        ...clubs.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name, style: TextStyle(fontSize: 12, color: palette.textPrimary), overflow: TextOverflow.ellipsis),
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
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedAthleteId,
                      isExpanded: true,
                      dropdownColor: palette.surfaceElevated,
                      hint: Text('Tüm Sporcular', style: TextStyle(fontSize: 12, color: palette.textMuted)),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Tüm Sporcular', style: TextStyle(fontSize: 12, color: palette.textPrimary))),
                        ...filteredAthletes.map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name}${a.birthYear != null ? " (${a.birthYear})" : ""}',
                                style: TextStyle(fontSize: 12, color: palette.textPrimary),
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
    final palette = context.palette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? palette.primary : palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? palette.primary : palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? onPrimary : palette.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String val, String label) {
    final palette = context.palette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final isSelected = _selectedStatus == val;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedStatus = val);
        _filterResults();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? palette.primary : palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? palette.primary : palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? onPrimary : palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
