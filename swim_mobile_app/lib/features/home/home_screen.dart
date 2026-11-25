import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/components/empty_state_widget.dart';
import '../../core/services/favorite_athletes_service.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/tyf_news.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';
import '../barajlar/barajlar_screen.dart';
import '../calendar/event_calendar_screen.dart';
import '../clubs/club_search_screen.dart';
import '../clubs/relay_simulator_screen.dart';
import '../live/live_meet_detail_screen.dart';
import '../meets/meet_search_screen.dart';
import '../rankings/rankings_screen.dart';

// ═══════════════════════════════════════════════════════════════
// RENK & TİPOGRAFİ SABİTLERİ (Sportif Havuz Editoryal Tasarım)
// ═══════════════════════════════════════════════════════════════

class _PoolColors {
  const _PoolColors({
    required this.bg,
    required this.card,
    required this.navy,
    required this.cyan,
    required this.coral,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.isDark,
  });

  final Color bg;
  final Color card;
  final Color navy;
  final Color cyan;
  final Color coral;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color divider;
  final bool isDark;

  factory _PoolColors.of(AppColorPalette palette) {
    final dark = palette.isDark;
    if (dark) {
      return _PoolColors(
        bg: palette.background,
        card: palette.surface,
        navy: const Color(0xFF0A1926),
        cyan: const Color(0xFF14B8CC),
        coral: const Color(0xFFFF6238),
        textPrimary: palette.textPrimary,
        textSecondary: palette.textSecondary,
        border: palette.border,
        divider: palette.divider,
        isDark: true,
      );
    }
    return const _PoolColors(
      bg: Color(0xFFF6F8F9),
      card: Color(0xFFFFFFFF),
      navy: Color(0xFF0F273B),
      cyan: Color(0xFF14B8CC),
      coral: Color(0xFFFF6238),
      textPrimary: Color(0xFF0F273B),
      textSecondary: Color(0xFF526675),
      border: Color(0xFFD9E2EC),
      divider: Color(0xFFE4EBF1),
      isDark: false,
    );
  }
}

TextStyle _display(
  double size, {
  FontWeight weight = FontWeight.w700,
  required Color color,
  double? height,
  double letterSpacing = 0,
}) =>
    TextStyle(
      fontFamily: AppTextStyles.displayFontFamily,
      fontFamilyFallback: AppTextStyles.fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

TextStyle _num(
  double size, {
  FontWeight weight = FontWeight.w800,
  required Color color,
  double? height,
  double letterSpacing = 0,
}) =>
    TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontFamilyFallback: AppTextStyles.fontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// 1. Ekran: Ana Sayfa & Keşfet
class HomeScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueChanged<int>? onOpenLiveMeet;
  final ValueChanged<MeetSummary>? onOpenMeetInLive;

  const HomeScreen({
    super.key,
    required this.repository,
    this.onOpenLiveMeet,
    this.onOpenMeetInLive,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<MeetSummary> _recentMeets = [];
  List<LiveMeetSummary> _liveMeets = [];
  List<Map<String, dynamic>> _highlights = [];
  List<TyfNewsItem> _newsFeed = [];

  final PageController _newsPageController = PageController(viewportFraction: 1);
  int _newsPageIndex = 0;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _newsPageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final favIds = FavoriteAthletesService.instance.favoriteIds;
      final club = SelectedClubService.instance;
      final Future<List<Map<String, dynamic>>> hlFuture =
          (favIds.isNotEmpty || club.hasSelectedClub)
              ? widget.repository
                  .getHighlightsFeed(
                    athleteIds: favIds,
                    clubId: club.clubId,
                    clubName: club.clubName,
                  )
                  .catchError((_) => <Map<String, dynamic>>[])
              : Future.value(<Map<String, dynamic>>[]);

      final results = await Future.wait([
        widget.repository.getMeets(page: 1),
        widget.repository.getLiveMeets(),
        hlFuture,
        widget.repository
            .getNewsFeed(limit: 15)
            .catchError((_) => <TyfNewsItem>[]),
      ]);
      if (mounted) {
        setState(() {
          _recentMeets = results[0] as List<MeetSummary>;
          _liveMeets = results[1] as List<LiveMeetSummary>;
          _highlights = results[2] as List<Map<String, dynamic>>;
          _newsFeed = results[3] as List<TyfNewsItem>;
          _newsPageIndex = 0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Müsabakalar yüklenirken bir bağlantı sorunu oluştu.';
          _isLoading = false;
        });
      }
    }
  }

  void _openSearchModal() {
    showSearch(
      context: context,
      delegate: _SwimSearchDelegate(
        repository: widget.repository,
        onMeetSelected: widget.onOpenMeetInLive,
      ),
    );
  }

  void _openClubSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClubSearchScreen(
          repository: widget.repository,
          onMeetSelected: widget.onOpenMeetInLive,
        ),
      ),
    );
  }

  void _openMeetSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetSearchScreen(
          repository: widget.repository,
          onMeetSelected: widget.onOpenMeetInLive,
        ),
      ),
    );
  }

  Future<void> _launchPdfUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = _PoolColors.of(palette);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: c.cyan,
                ),
              )
            : _errorMessage != null &&
                    _recentMeets.isEmpty &&
                    _liveMeets.isEmpty
                ? Center(
                    child: EmptyStateWidget(
                      title: 'Veriler Yüklenemedi',
                      message: _errorMessage!,
                      icon: Icons.cloud_off_outlined,
                      actionText: 'Tekrar Dene',
                      onAction: _loadData,
                    ),
                  )
                : RefreshIndicator(
                    color: c.cyan,
                    onRefresh: _loadData,
                    child: ListView(
                      padding: EdgeInsets.only(bottom: 100 + bottomInset),
                      children: [
                        const SizedBox(height: 12),
                        _buildSearchField(c),
                        const SizedBox(height: 14),
                        _buildUnderlinedTabs(c),
                        if (_newsFeed.isNotEmpty)
                          _buildHeroAnnouncements(c, palette),
                        const SizedBox(height: 20),
                        _buildToolCards(c),
                        if (_highlights.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildLiveFeed(c),
                        ],
                        if (_recentMeets.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildRecentMeets(c),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 1. ARAMA ÇUBUĞU
  // ═════════════════════════════════════════════════════════════

  Widget _buildSearchField(_PoolColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border, width: 1),
        ),
        child: InkWell(
          onTap: _openSearchModal,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, size: 22, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sporcu, kulüp, müsabaka',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      15,
                      weight: FontWeight.w400,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 3. ALTI ÇİZGİLİ SEKMELER
  // ═════════════════════════════════════════════════════════════

  Widget _buildUnderlinedTabs(_PoolColors c) {
    final items = <(String, VoidCallback)>[
      ('Yarış Ara', _openMeetSearch),
      (
        'Barajlar',
        () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BarajlarScreen(repository: widget.repository),
              ),
            ),
      ),
      (
        'Takvim',
        () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    EventCalendarScreen(repository: widget.repository),
              ),
            ),
      ),
      ('Kulüpler', _openClubSearch),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _selectedTabIndex = i);
                  items[i].$2();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        items[i].$1,
                        style: _display(
                          14,
                          weight: i == _selectedTabIndex
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: i == _selectedTabIndex
                              ? c.textPrimary
                              : c.textSecondary,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      width: i == _selectedTabIndex ? 60 : 0,
                      decoration: BoxDecoration(
                        color: c.cyan,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 4. KAYDIRILIR KOYU DUYURULAR HERO BANDI
  // ═════════════════════════════════════════════════════════════

  Widget _buildHeroAnnouncements(_PoolColors c, AppColorPalette palette) {
    final total = _newsFeed.length;
    return Container(
      width: double.infinity,
      color: c.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 242,
            child: PageView.builder(
              controller: _newsPageController,
              itemCount: total,
              onPageChanged: (idx) => setState(() => _newsPageIndex = idx),
              itemBuilder: (context, index) {
                final item = _newsFeed[index];
                final isMilli = item.belgeTuru == 'MILLI_TAKIM';
                final dotColor = isMilli ? c.coral : c.cyan;
                final cityUpper = item.sehirYer.trim().toUpperCase();
                final topLabel = cityUpper.isNotEmpty
                    ? '${item.turEtiketi.toUpperCase()} · $cityUpper'
                    : item.turEtiketi.toUpperCase();
                final metaParts = <String>[
                  if (item.yasGrubu.isNotEmpty) item.yasGrubu,
                  if (item.tarihMetni.isNotEmpty) item.tarihMetni,
                  if (item.barajSayisi > 0) '${item.barajSayisi} Baraj',
                ];
                final metaLine = metaParts.isNotEmpty
                    ? metaParts.join(' · ')
                    : 'TYF Resmi Duyuru';

                return Stack(
                  children: [
                    // Sağ tarafta büyük tipografik filigran numara
                    Positioned(
                      right: -6,
                      top: 4,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${index + 1}',
                            style: _num(
                              200,
                              weight: FontWeight.w800,
                              color: Colors.white.withAlpha(14),
                              height: 0.9,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  topLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _display(
                                    11.5,
                                    weight: FontWeight.w700,
                                    color: c.cyan,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${index + 1} / $total',
                                style: _num(
                                  12,
                                  weight: FontWeight.w600,
                                  color: Colors.white.withAlpha(160),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              item.baslik.toUpperCase(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: _display(
                                21,
                                weight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.14,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            metaLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _display(
                              13,
                              weight: FontWeight.w500,
                              color: Colors.white.withAlpha(185),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Material(
                                color: c.coral,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  onTap: () =>
                                      _openNewsDetailSheet(item, palette),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Detayları gör',
                                          style: _display(
                                            13.5,
                                            weight: FontWeight.w700,
                                            color: const Color(0xFF0F273B),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.arrow_forward,
                                          size: 16,
                                          color: Color(0xFF0F273B),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (item.pdfUrl.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Material(
                                  color: Colors.white.withAlpha(20),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    side: BorderSide(
                                      color: Colors.white.withAlpha(60),
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => _launchPdfUrl(item.pdfUrl),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.picture_as_pdf_outlined,
                                            size: 15,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'PDF',
                                            style: _display(
                                              12.5,
                                              weight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  total > 10 ? 10 : total,
                  (i) {
                    final active = i == (_newsPageIndex % 10);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 5,
                      decoration: BoxDecoration(
                        color: active ? c.cyan : Colors.white.withAlpha(60),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 6. ARAÇ KARTLARI (Turkuaz Dolgulu & Çerçeveli Filigranlı)
  // ═════════════════════════════════════════════════════════════

  Widget _buildToolCards(_PoolColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: c.cyan,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RelaySimulatorScreen(repository: widget.repository),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 112,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'BAYRAK\nSİMÜLATÖRÜ',
                          style: _display(
                            17,
                            weight: FontWeight.w800,
                            color: const Color(0xFF0F273B),
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '4x50 / 4x100',
                          style: _display(
                            12.5,
                            weight: FontWeight.w500,
                            color: const Color(0xFF0F273B).withAlpha(210),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: c.textPrimary, width: 1.1),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RankingsScreen(repository: widget.repository),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 112,
                  child: Stack(
                    children: [
                      Positioned(
                        right: 10,
                        top: 8,
                        child: IgnorePointer(
                          child: Text(
                            '25',
                            style: _num(
                              56,
                              weight: FontWeight.w800,
                              color: c.textPrimary.withAlpha(26),
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'TOP 25\nSIRALAMA',
                              style: _display(
                                17,
                                weight: FontWeight.w800,
                                color: c.textPrimary,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Branş ve il',
                              style: _display(
                                12.5,
                                weight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 7. CANLI AKIŞ (Düz Liste Satırları)
  // ═════════════════════════════════════════════════════════════

  Widget _buildLiveFeed(_PoolColors c) {
    final items = _highlights.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: c.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CANLI AKIŞ',
                    style: _display(
                      17,
                      weight: FontWeight.w800,
                      color: c.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              Text(
                '${items.length} kayıt',
                style: _display(
                  12.5,
                  weight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < items.length; i++) ...[
          _buildLiveRow(c, i + 1, items[i]),
          if (i != items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, thickness: 1, color: c.divider),
            ),
        ],
      ],
    );
  }

  Widget _buildLiveRow(
    _PoolColors c,
    int lane,
    Map<String, dynamic> h,
  ) {
    final athId = h['athlete_id'] as int;
    final athleteName = StringUtils.formatAthleteName(
      h['athlete_name'] as String? ?? '',
    );
    final eventLabel =
        '${h['distance'] ?? ''}m ${h['stroke_label'] ?? ''}'.trim();
    final city = StringUtils.toTitleCase((h['city'] as String?)?.trim() ?? '');
    final subtitleText =
        city.isNotEmpty ? '$eventLabel · $city' : eventLabel;
    final time = h['time'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AthleteProfileScreen(
              athleteId: athId,
              athleteName: h['athlete_name'] as String? ?? '',
              repository: widget.repository,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$lane',
                style: _num(22, weight: FontWeight.w800, color: c.cyan),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    athleteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      15,
                      weight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      12.5,
                      weight: FontWeight.w400,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              time,
              style: _num(20, weight: FontWeight.w800, color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 8. GÜNCEL MÜSABAKALAR (Düz Liste)
  // ═════════════════════════════════════════════════════════════

  Widget _buildRecentMeets(_PoolColors c) {
    final items = _recentMeets.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GÜNCEL MÜSABAKALAR',
                style: _display(
                  17,
                  weight: FontWeight.w800,
                  color: c.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              GestureDetector(
                onTap: _openMeetSearch,
                child: Text(
                  'Tümünü Ara',
                  style: _display(
                    13,
                    weight: FontWeight.w700,
                    color: c.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < items.length; i++) ...[
          _buildMeetRow(c, items[i]),
          if (i != items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, thickness: 1, color: c.divider),
            ),
        ],
      ],
    );
  }

  Widget _buildMeetRow(_PoolColors c, MeetSummary meet) {
    final is25m = meet.course == 'SC';
    final cityText = meet.city.isNotEmpty ? meet.city : 'Türkiye';
    final subtitle = [
      cityText,
      if (meet.startDate.isNotEmpty) meet.startDate,
      '${meet.totalRaces} yarış',
    ].join(' · ');

    return InkWell(
      onTap: () {
        final matchingLive = _liveMeets
            .where((m) => m.meetId != null && m.meetId == meet.id)
            .firstOrNull;
        if (matchingLive != null && widget.onOpenLiveMeet != null) {
          widget.onOpenLiveMeet!(matchingLive.id);
          return;
        }
        if (widget.onOpenMeetInLive != null) {
          widget.onOpenMeetInLive!(meet);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveMeetDetailScreen(
              live: LiveMeetSummary.fromMeetSummary(meet),
              repository: widget.repository,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: is25m ? c.cyan.withAlpha(32) : c.navy.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                is25m ? '25m' : '50m',
                style: _num(
                  12,
                  weight: FontWeight.w800,
                  color: is25m ? c.cyan : c.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    StringUtils.toTitleCase(meet.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      14.5,
                      weight: FontWeight.w700,
                      color: c.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      12.5,
                      weight: FontWeight.w400,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _openNewsDetailSheet(TyfNewsItem item, AppColorPalette palette) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(
                        label: Text(item.turEtiketi),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (item.revizyonEtiketi.isNotEmpty)
                        Chip(
                          label: Text(item.revizyonEtiketi),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.havuz.isNotEmpty)
                        Chip(
                          label: Text(item.havuz),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.barajSayisi > 0)
                        Chip(
                          label: Text('${item.barajSayisi} Baraj Kuralı'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.baslik,
                    style: _display(
                      17,
                      weight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (item.tarihMetni.isNotEmpty || item.sehirYer.isNotEmpty)
                    Text(
                      [
                        if (item.tarihMetni.isNotEmpty) item.tarihMetni,
                        if (item.sehirYer.isNotEmpty) item.sehirYer,
                      ].join(' • '),
                      style: _display(
                        13,
                        weight: FontWeight.w500,
                        color: palette.textSecondary,
                      ),
                    ),
                  if (item.yasGrubu.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Yaş Grubu: ${item.yasGrubu}',
                      style: _display(
                        13,
                        weight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ],
                  if (item.ozet.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      item.ozet,
                      style: _display(
                        13.5,
                        weight: FontWeight.w400,
                        color: palette.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (item.onemliNotlar.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Önemli Notlar',
                      style: _display(
                        13,
                        weight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...item.onemliNotlar.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                note,
                                style: _display(
                                  12.5,
                                  weight: FontWeight.w400,
                                  color: palette.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (item.pdfUrl.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _launchPdfUrl(item.pdfUrl),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Resmi PDF Belgesini Aç'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// YARDIMCI WIDGET & PAINTER'LAR
// ═══════════════════════════════════════════════════════════════

/// Arama Delegesi
class _SwimSearchDelegate extends SearchDelegate {
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;

  _SwimSearchDelegate({
    required this.repository,
    this.onMeetSelected,
  });

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

    return FutureBuilder<GlobalSearchResult>(
      future: repository.searchGlobal(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.hasError) {
          return const Center(child: Text('Sonuç bulunamadı.'));
        }

        final data = snapshot.data!;
        final athletes = data.athletes;
        final clubs = data.clubs;

        if (athletes.isEmpty && clubs.isEmpty) {
          return const Center(child: Text('Eşleşen sonuç bulunamadı.'));
        }

        return ListView(
          children: [
            if (athletes.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Sporcular',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ...athletes.map(
                (a) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 20,
                    ),
                  ),
                  title: Text(StringUtils.formatAthleteName(a.name)),
                  subtitle: Text('${a.birthYear ?? '-'} · ${a.clubName}'),
                  onTap: () {
                    close(context, null);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AthleteProfileScreen(
                          athleteId: a.id,
                          athleteName: a.name,
                          repository: repository,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (clubs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Kulüpler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ...clubs.map(
                (c) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    child: Icon(
                      Icons.shield_outlined,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 20,
                    ),
                  ),
                  title: Text(c.name),
                  subtitle: Text('${c.athleteCount} Kayıtlı Sporcu'),
                  onTap: () {
                    close(context, null);
                    ClubSearchScreen.showClubActionsSheet(
                      context,
                      club: c,
                      repository: repository,
                      onMeetSelected: onMeetSelected,
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
