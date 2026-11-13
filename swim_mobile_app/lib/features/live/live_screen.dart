import 'package:flutter/material.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/live_meet.dart';
import 'live_meet_detail_screen.dart';

/// TYF Yüzme Sonuçları — Canlı Müsabakalar Ekranı (v2.0)
/// Apple Esintili Yalınlık:
/// - Zemin: #FAF8F7 nötr kırık beyaz
/// - Üst Bar: Minimal TYF başlığı, ince hatlı aksiyonlar
/// - Canlı Takip Kartı: #FFFFFF, 16px radius, mikro-derinlik, soluk pudra gülü canlı nokta
class LiveScreen extends StatefulWidget {
  final SwimRepository repository;

  const LiveScreen({super.key, required this.repository});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LiveMeetSummary> _liveMeets = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLiveMeets();
  }

  Future<void> _loadLiveMeets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await widget.repository.getLiveMeets();
      if (mounted) {
        setState(() {
          _liveMeets = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Canlı müsabakalar yüklenirken bir sorun oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _openLiveDetail(LiveMeetSummary live) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMeetDetailScreen(
          live: live,
          repository: widget.repository,
        ),
      ),
    );
  }

  List<LiveMeetSummary> get _filteredMeets {
    if (_searchQuery.trim().isEmpty) return _liveMeets;
    final q = _searchQuery.toLowerCase();
    return _liveMeets.where((m) {
      return m.name.toLowerCase().contains(q) ||
          m.city.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final meets = _filteredMeets;
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TÜRKİYE YÜZME FEDERASYONU',
              style: AppTextStyles.appTitle.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              '${_liveMeets.length} Canlı Müsabaka',
              style: AppTextStyles.categorySeries.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: palette.textSecondary, size: 20),
            tooltip: 'Yenile',
            onPressed: _loadLiveMeets,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: palette.primary),
            )
          : _errorMessage != null && _liveMeets.isEmpty
              ? Center(
                  child: EmptyStateWidget(
                    title: 'Bağlantı Hatası',
                    message: _errorMessage!,
                    icon: Icons.cloud_off_rounded,
                    actionText: 'Tekrar Dene',
                    onAction: _loadLiveMeets,
                  ),
                )
              : RefreshIndicator(
              color: palette.primary,
              onRefresh: _loadLiveMeets,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  // Minimalist Arama Girişi
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded,
                            color: palette.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: TextStyle(
                              fontSize: 14,
                              color: palette.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Müsabaka veya şehir ara...',
                              hintStyle: TextStyle(
                                fontSize: 13.5,
                                color: palette.textMuted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Müsabaka Listesi
                  if (meets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pool_outlined,
                              size: 40, color: AppColors.laneNeutral),
                          SizedBox(height: 12),
                          Text(
                            'Şu anda aktif canlı müsabaka bulunmuyor',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...meets.map((m) => _buildLiveMeetCard(m)),
                ],
              ),
            ),
    );
  }

  Widget _buildLiveMeetCard(LiveMeetSummary meet) {
    final resTotal = meet.resultListProgress.total;
    final resProcessed = meet.resultListProgress.processed;
    final resRatio = resTotal > 0 ? (resProcessed / resTotal).clamp(0.0, 1.0) : 0.0;
    final resPercent = (resRatio * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x083D3038),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openLiveDetail(meet),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Üst Rozet Satırı: Soluk pudra gülü nokta (•) + 11px CANLI YARIŞ
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'CANLI YAYIN',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${meet.totalAthletes} Sporcu',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 2. Müsabaka Başlığı
                Text(
                  meet.name,
                  style: AppTextStyles.raceTitle,
                ),
                const SizedBox(height: 4),

                // 3. Şehir ve Tarih
                Row(
                  children: [
                    Text(
                      meet.city.isNotEmpty ? meet.city : 'Türkiye',
                      style: AppTextStyles.categorySeries,
                    ),
                    if (meet.date.isNotEmpty) ...[
                      const Text(
                        ' • ',
                        style: TextStyle(color: AppColors.laneNeutral),
                      ),
                      Text(
                        meet.date,
                        style: AppTextStyles.categorySeries,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // 4. İnce 1px Ayırıcı Çizgi & İlerleme
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sonuçlanan Yarışlar',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      '$resProcessed / $resTotal (%$resPercent)',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: resRatio,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
