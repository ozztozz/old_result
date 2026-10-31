import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/race_result.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/modern_filter_chips.dart';
import '../../shared/widgets/swim_result_card.dart';
import '../athletes/athlete_profile_screen.dart';

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

/// TYF Yüzme Sonuçları — Canlı Yarış Sonuçları Ekranı (v2.0)
/// Apple Esintili Yalınlık:
/// - Zemin: #FAF8F7 nötr kırık beyaz
/// - Satırlar: 52px min-yükseklik, 18px kulvar, 15px tabular derece, 20px gri rozet
/// - Satırlar arası 32px girintili 1px #EFE9E7 ayırıcı çizgi
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
    }
  }

  Future<void> _loadResults({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    try {
      final feed = await widget.repository.getLiveFeedResponse(
        widget.live.id,
        eventNo: widget.event.eventNo,
      );

      final list = feed.results;

      if (mounted) {
        setState(() {
          _allResults = list;
          _isLoading = false;
        });
        _applyFilter();
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    var filtered = List<RaceResult>.from(_allResults);

    // Durum filtresi
    if (_selectedStatus == 'finished') {
      filtered = filtered.where((r) {
        final isWait = r.resultStatus == 'WAITING';
        final isDq = r.resultStatus == 'DQ' ||
            r.resultStatus == 'DNS' ||
            r.resultStatus == 'DNF' ||
            r.rank.toUpperCase().startsWith('DQ');
        final hasTime = (r.timeCs != null && r.timeCs! > 0) ||
            (r.time != null && r.time!.isNotEmpty);
        return !isWait && !isDq && hasTime;
      }).toList();
    } else if (_selectedStatus == 'pending') {
      filtered = filtered.where((r) {
        final isWait = r.resultStatus == 'WAITING';
        final hasNoTime = (r.timeCs == null || r.timeCs == 0) &&
            (r.time == null || r.time!.isEmpty);
        return isWait || hasNoTime;
      }).toList();
    }

    // Arama filtresi
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        return r.athleteName.toLowerCase().contains(q) ||
            r.clubName.toLowerCase().contains(q);
      }).toList();
    }

    setState(() {
      _filteredResults = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.event.name.isNotEmpty
        ? widget.event.name
        : '${widget.event.distance ?? ''} ${widget.event.strokeLabel}'.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _toTitleCase(title),
              style: AppTextStyles.raceTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _toTitleCase(widget.live.name),
              style: AppTextStyles.categorySeries,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isAutoRefresh ? Icons.sync_rounded : Icons.sync_disabled_rounded,
              color: _isAutoRefresh ? AppColors.accent : AppColors.textSecondary,
              size: 20,
            ),
            tooltip: _isAutoRefresh ? 'Otomatik Yenileme Açık' : 'Otomatik Yenileme Kapalı',
            onPressed: () => _toggleAutoRefresh(!_isAutoRefresh),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
            tooltip: 'Yenile',
            onPressed: () => _loadResults(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _loadResults(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Yarış Üst Bilgi Kartı (Apple 16px radius & mikro-derinlik)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x083D3038),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _toTitleCase(title),
                          style: AppTextStyles.raceTitle,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${_allResults.length} Sporcu',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.live.name} • ${widget.event.status}',
                      style: AppTextStyles.categorySeries,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Arama Çubuğu
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          _searchQuery = val;
                          _applyFilter();
                        },
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Sporcu veya kulüp ara...',
                          hintStyle: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13.5,
                            color: AppColors.laneNeutral,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _searchQuery = '';
                          _applyFilter();
                        },
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3. Durum Filtre Çipleri
              Row(
                children: [
                  ModernFilterChip(
                    label: 'Tümü',
                    isSelected: _selectedStatus == 'all',
                    onTap: () {
                      setState(() => _selectedStatus = 'all');
                      _applyFilter();
                    },
                  ),
                  ModernFilterChip(
                    label: 'Sonuçlananlar',
                    isSelected: _selectedStatus == 'finished',
                    onTap: () {
                      setState(() => _selectedStatus = 'finished');
                      _applyFilter();
                    },
                  ),
                  ModernFilterChip(
                    label: 'Beklenenler',
                    isSelected: _selectedStatus == 'pending',
                    onTap: () {
                      setState(() => _selectedStatus = 'pending');
                      _applyFilter();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4. Sonuç Listesi Başlığı
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Yarış Sıralaması (${_filteredResults.length})',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),

              // 5. Sonuç Listesi Paneli (Beyaz Zemin, 16px radius, satırlar arası 32px girintili 1px çizgi)
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                )
              else if (_filteredResults.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_search_outlined, size: 40, color: AppColors.laneNeutral),
                      SizedBox(height: 12),
                      Text(
                        'Kriterlere uygun sonuç bulunamadı',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border, width: 1.0),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x083D3038),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: _filteredResults.asMap().entries.map((entry) {
                      final index = entry.key;
                      final result = entry.value;
                      final isLast = index == _filteredResults.length - 1;

                      return SwimResultCard(
                        result: result,
                        rankIndex: index + 1,
                        showDivider: !isLast,
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
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
