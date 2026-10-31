import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/services/selected_club_service.dart';
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
/// Apple Esintili Spor Gösterge Paneli
/// Kulüp seçili olduğunda en başta kulüp sporcularının özet kartı (Pinned Section) gösterilir.
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
    SelectedClubService.instance.addListener(_onClubChanged);
    _loadResults();
  }

  @override
  void dispose() {
    SelectedClubService.instance.removeListener(_onClubChanged);
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onClubChanged() {
    if (mounted) setState(() {});
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

  /// Seçili kulübe ait sporcuların bu yarıştaki sonuçları
  List<RaceResult> get _myClubResults {
    if (!SelectedClubService.instance.hasSelectedClub) return [];
    return _allResults.where((r) {
      return SelectedClubService.instance.matches(r.clubName, r.clubId);
    }).toList();
  }

  /// Sporcunun genel yarış sıralamasındaki kesin sırası
  int? _getOverallRank(RaceResult result) {
    final parsed = int.tryParse(result.rank.replaceAll('.', '').trim());
    if (parsed != null && parsed > 0) return parsed;
    final idx = _allResults.indexOf(result);
    return idx >= 0 ? idx + 1 : null;
  }

  void _openAthleteProfile(RaceResult result) {
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
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = widget.event.name.isNotEmpty
        ? widget.event.name
        : '${widget.event.distance ?? ''} ${widget.event.strokeLabel}'.trim();

    final myClubResults = _myClubResults;
    final hasClubAthletes = myClubResults.isNotEmpty;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: palette.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _toTitleCase(title),
              style: AppTextStyles.raceTitle.copyWith(color: palette.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _toTitleCase(widget.live.name),
              style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isAutoRefresh ? Icons.sync_rounded : Icons.sync_disabled_rounded,
              color: _isAutoRefresh ? palette.primary : palette.textSecondary,
              size: 20,
            ),
            tooltip: _isAutoRefresh ? 'Otomatik Yenileme Açık' : 'Otomatik Yenileme Kapalı',
            onPressed: () => _toggleAutoRefresh(!_isAutoRefresh),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: palette.textSecondary, size: 20),
            tooltip: 'Yenile',
            onPressed: () => _loadResults(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: palette.primary,
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
                  color: palette.surface,
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(color: palette.border, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: palette.textPrimary.withValues(alpha: 0.03),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _toTitleCase(title),
                            style: AppTextStyles.raceTitle.copyWith(color: palette.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: palette.background,
                            borderRadius: AppRadius.badgeRadius,
                            border: Border.all(color: palette.border),
                          ),
                          child: Text(
                            '${_allResults.length} Sporcu',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: palette.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.live.name} • ${widget.event.status}',
                      style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Arama Çubuğu
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: AppRadius.inputRadius,
                  border: Border.all(color: palette.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: palette.textSecondary,
                      size: 18,
                    ),
                    AppSpacing.hSm,
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          _searchQuery = val;
                          _applyFilter();
                        },
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Sporcu veya kulüp ara...',
                          hintStyle: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13.5,
                            color: palette.textMuted,
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
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: palette.textSecondary,
                        ),
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

              // 4. KULÜP ÖNE ÇIKARILAN BÖLÜM (PINNED SECTION)
              // Kulüp seçiliyse ve o yarışta sporcuları varsa listenin en başında vitrin olarak gösterilir
              if (!_isLoading && hasClubAthletes) ...[
                _buildClubPinnedSection(context, myClubResults),
                const SizedBox(height: 8),
              ],

              // 5. Genel Sonuç Listesi Başlığı
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  hasClubAthletes
                      ? 'Tüm Yarış Sıralaması (${_filteredResults.length})'
                      : 'Yarış Sıralaması (${_filteredResults.length})',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),

              // 6. Genel Sonuç Listesi Paneli
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: palette.primary),
                  ),
                )
              else if (_filteredResults.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_search_outlined,
                        size: 40,
                        color: palette.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kriterlere uygun sonuç bulunamadı',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: palette.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: palette.border, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: palette.textPrimary.withValues(alpha: 0.03),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
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
                        onTap: () => _openAthleteProfile(result),
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

  /// Kulüp Sporcularının Listenin Başında Ayrı ve Vurgulu Gösterildiği Vitrin Paneli
  Widget _buildClubPinnedSection(BuildContext context, List<RaceResult> clubResults) {
    final palette = context.palette;
    final clubName = SelectedClubService.instance.clubName ?? 'Kulübünüz';

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Bilgi Başlığı (Marka Vurgulu Zemin)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: palette.primaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  size: 16,
                  color: palette.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_toTitleCase(clubName)} (${clubResults.length} Sporcu)',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'KULÜP ÖZETİ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: palette.primary,
                  ),
                ),
              ],
            ),
          ),

          // Kulüp Sporcularının Satırları
          Column(
            children: clubResults.asMap().entries.map((entry) {
              final idx = entry.key;
              final result = entry.value;
              final isLast = idx == clubResults.length - 1;
              final overallRank = _getOverallRank(result);

              return SwimResultCard(
                result: result,
                rankIndex: overallRank,
                showDivider: !isLast,
                onTap: () => _openAthleteProfile(result),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
