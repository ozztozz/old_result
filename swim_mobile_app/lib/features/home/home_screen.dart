import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/components/empty_state_widget.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/models/live_meet.dart';
import '../../data/models/meet.dart';
import '../../data/models/tyf_news.dart';
import '../../data/repositories/swim_repository.dart';
import '../../shared/widgets/formatted_summary_view.dart';
import '../athletes/athlete_profile_screen.dart';
import '../barajlar/barajlar_screen.dart';
import '../calendar/event_calendar_screen.dart';
import '../clubs/club_search_screen.dart';
import '../live/live_meet_detail_screen.dart';
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
    return _PoolColors(
      bg: palette.background,
      card: palette.surface,
      navy: palette.isDark ? palette.surfaceSecondary : palette.secondary,
      cyan: palette.primary,
      coral: palette.statusLive,
      textPrimary: palette.textPrimary,
      textSecondary: palette.textSecondary,
      border: palette.border,
      divider: palette.divider,
      isDark: palette.isDark,
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  List<LiveMeetSummary> _liveMeets = [];
  List<TyfNewsItem> _newsFeed = [];

  final PageController _newsPageController = PageController(viewportFraction: 1);
  int _newsPageIndex = 0;

  late final AnimationController _brandController;
  late final Animation<double> _brandFade;
  late final Animation<Offset> _brandSlide;
  late final Animation<double> _brandScale;

  @override
  void initState() {
    super.initState();
    _brandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    final curved = CurvedAnimation(
      parent: _brandController,
      curve: Curves.easeOutCubic,
    );
    _brandFade = curved;
    _brandSlide = Tween<Offset>(
      begin: const Offset(0.18, 0.45),
      end: Offset.zero,
    ).animate(curved);
    _brandScale = Tween<double>(begin: 0.85, end: 1.0).animate(curved);
    _brandController.forward();
    _loadData();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _newsPageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.getLiveMeets(),
        widget.repository
            .getNewsFeed(limit: 15)
            .catchError((_) => <TyfNewsItem>[]),
      ]);
      if (mounted) {
        setState(() {
          _liveMeets = results[0] as List<LiveMeetSummary>;
          _newsFeed = results[1] as List<TyfNewsItem>;
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
            ? Column(
                children: [
                  _buildBrandBar(c),
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: c.cyan,
                      ),
                    ),
                  ),
                ],
              )
            : _errorMessage != null && _liveMeets.isEmpty && _newsFeed.isEmpty
                ? Column(
                    children: [
                      _buildBrandBar(c),
                      Expanded(
                        child: Center(
                          child: EmptyStateWidget(
                            title: 'Veriler Yüklenemedi',
                            message: _errorMessage!,
                            icon: Icons.cloud_off_outlined,
                            actionText: 'Tekrar Dene',
                            onAction: _loadData,
                          ),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    color: c.cyan,
                    onRefresh: _loadData,
                    child: ListView(
                      padding: EdgeInsets.only(bottom: 100 + bottomInset),
                      children: [
                        _buildBrandBar(c),
                        const SizedBox(height: 14),
                        if (_newsFeed.isNotEmpty)
                          _buildHeroAnnouncements(c, palette),
                        const SizedBox(height: 16),
                        _buildToolCards(c),
                        const SizedBox(height: 14),
                        _buildSearchPill(c),
                        if (_liveMeets.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _buildLiveFeed(c),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 1. ANİMASYONLU LOGO & UYGULAMA ADI
  // ═════════════════════════════════════════════════════════════

  Widget _buildBrandBar(_PoolColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: FadeTransition(
        opacity: _brandFade,
        child: SlideTransition(
          position: _brandSlide,
          child: ScaleTransition(
            scale: _brandScale,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontFamily: AppTextStyles.displayFontFamily,
                            fontFamilyFallback:
                                AppTextStyles.fontFamilyFallback,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                          children: [
                            TextSpan(
                              text: 'Kulva',
                              style: TextStyle(color: c.textPrimary),
                            ),
                            TextSpan(
                              text: 'R',
                              style: TextStyle(color: c.coral),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Yüzme Platformu',
                        style: _display(
                          11.5,
                          weight: FontWeight.w600,
                          color: c.cyan,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _newsFeed.isNotEmpty
                      ? () {
                          _newsPageController.animateToPage(
                            0,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      : null,
                  tooltip: 'Duyurular',
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    size: 24,
                    color: c.textPrimary,
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
  // 2. KAYDIRILIR KOYU DUYURULAR HERO BANDI
  // ═════════════════════════════════════════════════════════════

  static const _trMonths = [
    'OCA',
    'ŞUB',
    'MAR',
    'NİS',
    'MAY',
    'HAZ',
    'TEM',
    'AĞU',
    'EYL',
    'EKİ',
    'KAS',
    'ARA',
  ];

  ({String day, String month})? _extractDayMonth(TyfNewsItem item) {
    final raw = item.baslangicTarihi.trim().isNotEmpty
        ? item.baslangicTarihi.trim()
        : item.guncellenmeTarihi.trim();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return (day: '${dt.day}', month: '${_trMonths[dt.month - 1]} $yy');
  }

  String? _formatAgeRange(TyfNewsItem item) {
    final min = item.minYas;
    final max = item.maxYas;
    if (min != null && max != null) {
      return min == max ? '$min Yaş' : '$min–$max Yaş';
    }
    if (min != null) return '$min+ Yaş';
    if (max != null) return '$max Yaş ve Altı';
    final raw = item.yasGrubu.trim();
    return raw.isNotEmpty ? raw : null;
  }

  Widget _buildHeroAnnouncements(_PoolColors c, AppColorPalette palette) {
    final total = _newsFeed.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.navy,
              Color.lerp(c.navy, const Color(0xFF194566), 0.55)!,
            ],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 218,
              child: PageView.builder(
                controller: _newsPageController,
                itemCount: total,
                onPageChanged: (idx) => setState(() => _newsPageIndex = idx),
                itemBuilder: (context, index) {
                  final item = _newsFeed[index];
                  return _FlippableAnnouncementCard(
                    key: ValueKey('news_${item.id}_$index'),
                    item: item,
                    index: index,
                    total: total,
                    colors: c,
                    dayMonth: _extractDayMonth(item),
                    ageRange: _formatAgeRange(item),
                    onOpenDetail: (item.ozet.isNotEmpty || item.onemliNotlar.isNotEmpty)
                        ? () => showAnnouncementDetailSheet(
                              context,
                              title: item.baslik,
                              subtitle: [
                                if (item.tarihMetni.isNotEmpty) item.tarihMetni,
                                if (item.sehirYer.isNotEmpty) item.sehirYer,
                              ].join(' • '),
                              tags: [
                                item.turEtiketi,
                                if (_formatAgeRange(item) != null)
                                  _formatAgeRange(item)!,
                                if (item.havuz.isNotEmpty) item.havuz,
                              ],
                              summary: item.ozet,
                              notes: item.onemliNotlar,
                              onOpenPdf: item.pdfUrl.isNotEmpty
                                  ? () => _launchPdfUrl(item.pdfUrl)
                                  : null,
                            )
                        : null,
                    onOpenPdf: item.pdfUrl.isNotEmpty
                        ? () => _launchPdfUrl(item.pdfUrl)
                        : null,
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
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 3. ARAÇ KARTLARI (2x2 Koyu Lacivert Grid: Barajlar, Top 25, Takvim, Kulüpler)
  // ═════════════════════════════════════════════════════════════

  Widget _buildToolCards(_PoolColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionTileCard(
                  colors: c,
                  number: '01',
                  icon: Icons.timer_outlined,
                  accentColor: c.cyan,
                  title: 'BARAJLAR',
                  subtitle: 'A / B baraj süreleri',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BarajlarScreen(repository: widget.repository),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTileCard(
                  colors: c,
                  number: '02',
                  icon: Icons.emoji_events_outlined,
                  accentColor: c.coral,
                  title: 'TOP 25',
                  subtitle: 'Branş ve yaş sıralaması',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RankingsScreen(repository: widget.repository),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionTileCard(
                  colors: c,
                  number: '03',
                  icon: Icons.calendar_month_outlined,
                  accentColor: c.cyan,
                  title: 'TAKVİM',
                  subtitle: 'Yarış takvimi',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            EventCalendarScreen(repository: widget.repository),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: SelectedClubService.instance,
                  builder: (context, _) {
                    final club = SelectedClubService.instance;
                    final subtitle = club.hasSelectedClub
                        ? StringUtils.toTitleCase(club.clubName!)
                        : 'Kulüp ara ve incele';
                    return _ActionTileCard(
                      colors: c,
                      number: '04',
                      icon: Icons.groups_outlined,
                      accentColor: const Color(0xFF7DD3FC),
                      title: 'KULÜPLER',
                      subtitle: subtitle,
                      onTap: _openClubSearch,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPill(_PoolColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: c.border, width: 1),
        ),
        child: InkWell(
          onTap: _openSearchModal,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, size: 21, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sporcu ara',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      14.5,
                      weight: FontWeight.w400,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // 7. CANLI AKIŞ (Düz Liste Satırları)
  // ═════════════════════════════════════════════════════════════

  Widget _buildLiveFeed(_PoolColors c) {
    final items = _liveMeets.take(3).toList();
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
                '${items.length} yarış',
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
    LiveMeetSummary live,
  ) {
    final city = StringUtils.toTitleCase(live.city.trim());
    final subtitleText = [
      if (live.date.trim().isNotEmpty) live.date.trim(),
      if (city.isNotEmpty) city,
    ].join(' · ');

    return InkWell(
      onTap: () {
        if (widget.onOpenLiveMeet != null) {
          widget.onOpenLiveMeet!(live.id);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveMeetDetailScreen(
              live: live,
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
                    StringUtils.toTitleCase(live.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _display(
                      14.5,
                      weight: FontWeight.w700,
                      color: c.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (subtitleText.isNotEmpty) ...[
                    const SizedBox(height: 3),
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTileCard extends StatelessWidget {
  const _ActionTileCard({
    required this.colors,
    required this.number,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final _PoolColors colors;
  final String number;
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.navy,
              Color.lerp(c.navy, const Color(0xFF1A3E5C), 0.6)!,
            ],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 120,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 28, color: accentColor),
                      Text(
                        number,
                        style: _num(
                          12,
                          weight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _display(
                                15.5,
                                weight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _display(
                                11.5,
                                weight: FontWeight.w500,
                                color: Colors.white.withAlpha(232),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white.withAlpha(190),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// DÖNEN DUYURU KARTI (3D Flip Animasyonu + Arka Yüz Detayları)
// ═══════════════════════════════════════════════════════════════

class _FlippableAnnouncementCard extends StatefulWidget {
  const _FlippableAnnouncementCard({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.colors,
    required this.dayMonth,
    required this.ageRange,
    this.onOpenDetail,
    this.onOpenPdf,
  });

  final TyfNewsItem item;
  final int index;
  final int total;
  final _PoolColors colors;
  final ({String day, String month})? dayMonth;
  final String? ageRange;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenPdf;

  @override
  State<_FlippableAnnouncementCard> createState() =>
      _FlippableAnnouncementCardState();
}

class _FlippableAnnouncementCardState extends State<_FlippableAnnouncementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  bool _isFlipped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _isFlipped = !_isFlipped;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleFlip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final angle = _animation.value * math.pi;
          final showBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(math.pi),
                    child: _buildBack(),
                  )
                : _buildFront(),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    final item = widget.item;
    final c = widget.colors;
    final isMilli = item.belgeTuru == 'MILLI_TAKIM';
    final dotColor = isMilli ? c.coral : c.cyan;
    final cityUpper = StringUtils.toTurkishUpper(item.sehirYer.trim());
    final turUpper = StringUtils.toTurkishUpper(item.turEtiketi);
    final topLabel = cityUpper.isNotEmpty ? '$turUpper · $cityUpper' : turUpper;
    final metaParts = <String>[
      if (item.tarihMetni.isNotEmpty) item.tarihMetni,
      if (widget.ageRange != null) widget.ageRange!,
      if (item.barajSayisi > 0) '${item.barajSayisi} Baraj',
    ];
    final metaLine =
        metaParts.isNotEmpty ? metaParts.join(' · ') : 'Resmi Duyuru';

    return Stack(
      children: [
        if (widget.dayMonth != null)
          Positioned(
            right: 12,
            top: 18,
            bottom: 12,
            child: IgnorePointer(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.dayMonth!.day,
                    style: _num(
                      84,
                      weight: FontWeight.w800,
                      color: Colors.white.withAlpha(38),
                      height: 0.88,
                    ),
                  ),
                  Text(
                    widget.dayMonth!.month,
                    style: _display(
                      22,
                      weight: FontWeight.w800,
                      color: c.cyan.withAlpha(78),
                      letterSpacing: 3,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
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
                    '${widget.index + 1} / ${widget.total}',
                    style: _num(
                      12,
                      weight: FontWeight.w600,
                      color: Colors.white.withAlpha(210),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  StringUtils.toTurkishUpper(item.baslik),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _display(
                    19,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.14,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              if (item.sehirYer.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.cyan.withAlpha(36),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.cyan.withAlpha(90)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_rounded, size: 14, color: c.cyan),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.sehirYer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _display(
                            12.5,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
              ],
              Text(
                metaLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _display(
                  12,
                  weight: FontWeight.w500,
                  color: Colors.white.withAlpha(235),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Material(
                    color: c.coral,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: _toggleFlip,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
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
                  if (widget.onOpenPdf != null) ...[
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.white.withAlpha(38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(
                          color: Colors.white.withAlpha(170),
                          width: 1.2,
                        ),
                      ),
                      child: InkWell(
                        onTap: widget.onOpenPdf,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 16,
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
  }

  Widget _buildBack() {
    final item = widget.item;
    final c = widget.colors;
    final tags = <String>[
      item.turEtiketi,
      if (item.revizyonEtiketi.isNotEmpty) item.revizyonEtiketi,
      if (item.havuz.isNotEmpty) item.havuz,
      if (widget.ageRange != null) widget.ageRange!,
      if (item.barajSayisi > 0) '${item.barajSayisi} Baraj',
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cyan.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tags.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: i == 0
                                ? c.coral.withAlpha(45)
                                : Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tags[i],
                            style: _display(
                              11,
                              weight: FontWeight.w700,
                              color: i == 0 ? c.coral : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _toggleFlip,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flip_to_front_rounded, size: 14, color: c.cyan),
                      const SizedBox(width: 4),
                      Text(
                        'Ön yüz',
                        style: _display(
                          11.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: item.ozet.isNotEmpty
                  ? Text(
                      FormattedSummaryView.plainPreview(item.ozet),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _display(
                        12.5,
                        weight: FontWeight.w400,
                        color: Colors.white.withAlpha(225),
                        height: 1.4,
                      ),
                    )
                  : item.onemliNotlar.isNotEmpty
                      ? Text(
                          '• ${item.onemliNotlar.join('\n• ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: _display(
                            12,
                            weight: FontWeight.w400,
                            color: Colors.white.withAlpha(205),
                            height: 1.4,
                          ),
                        )
                      : Text(
                          item.baslik,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: _display(
                            13.5,
                            weight: FontWeight.w600,
                            color: Colors.white.withAlpha(220),
                            height: 1.4,
                          ),
                        ),
            ),
          ),
          if (widget.onOpenDetail != null || widget.onOpenPdf != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.onOpenDetail != null)
                  Expanded(
                    child: Material(
                      color: Colors.white.withAlpha(24),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: widget.onOpenDetail,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.article_outlined,
                                size: 15,
                                color: c.cyan,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Tamamını Oku',
                                style: _display(
                                  12,
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.onOpenDetail != null && widget.onOpenPdf != null)
                  const SizedBox(width: 8),
                if (widget.onOpenPdf != null)
                  Expanded(
                    child: Material(
                      color: c.coral,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: widget.onOpenPdf,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 15,
                                color: Color(0xFF0F273B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PDF Aç',
                                style: _display(
                                  12,
                                  weight: FontWeight.w700,
                                  color: const Color(0xFF0F273B),
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
          ],
        ],
      ),
    );
  }
}

/// Sporcu Arama Delegesi
class _SwimSearchDelegate extends SearchDelegate {
  final SwimRepository repository;

  _SwimSearchDelegate({
    required this.repository,
  });

  @override
  String get searchFieldLabel => 'Sporcu ara...';

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
      future: repository.searchGlobal(query.trim(), type: 'athlete'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.hasError) {
          return const Center(child: Text('Sonuç bulunamadı.'));
        }

        final athletes = snapshot.data!.athletes;

        if (athletes.isEmpty) {
          return const Center(child: Text('Eşleşen sporcu bulunamadı.'));
        }

        return ListView(
          children: [
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
        );
      },
    );
  }
}
