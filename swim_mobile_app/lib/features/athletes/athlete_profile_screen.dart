import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';
import '../../core/theme/swim_theme.dart';
import '../../core/utils/swim_time_formatter.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/athlete.dart';
import '../../shared/widgets/swim_status_badge.dart';
import '../../shared/widgets/swim_design_components.dart';

/// Sporcu Profili, 25m/50m PB Tablosu ve Kariyer Karnesi
class AthleteProfileScreen extends StatefulWidget {
  final int athleteId;
  final String athleteName;
  final SwimRepository repository;

  const AthleteProfileScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
    required this.repository,
  });

  @override
  State<AthleteProfileScreen> createState() => _AthleteProfileScreenState();
}

class _AthleteProfileScreenState extends State<AthleteProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  AthleteDetail? _athlete;
  List<AthleteRaceHistoryItem> _raceHistory = [];
  bool _isFavorite = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAthleteData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAthleteData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getAthleteDetail(widget.athleteId),
        widget.repository.getAthleteRaces(widget.athleteId, page: 1),
      ]);
      if (mounted) {
        setState(() {
          _athlete = results[0] as AthleteDetail;
          _raceHistory = results[1] as List<AthleteRaceHistoryItem>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFavorite
              ? 'Sporcu favorilere eklendi.'
              : 'Sporcu favorilerden çıkarıldı.',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _athlete == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Sporcu bilgileri yüklenemedi.',
                          style: TextStyle(color: AppColors.ink),
                        ),
                        const SizedBox(height: 12),
                        RoundIconButton(
                          Icons.arrow_back,
                          onTap: () => Navigator.maybePop(context),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Üst Bar (Geri ve Favori Butonları)
                        _buildTopBar(),
                        const SizedBox(height: 20),

                        // 2. Profil Başlık Kartı
                        _buildProfileHeader(_athlete!),
                        const SizedBox(height: 20),

                        // 3. İstatistik Kartları (3'lü Yatay Izgara)
                        _buildStatCards(_athlete!.stats),
                        const SizedBox(height: 20),

                        // 4. Scout Değerlendirme Notu
                        if (_athlete!.scoutNote.isNotEmpty) ...[
                          _buildScoutNoteCard(_athlete!.scoutNote),
                          const SizedBox(height: 20),
                        ],

                        // 5. Kişisel En İyi Dereceler (PB Sekmeli Kart)
                        _buildPbSection(_athlete!),
                        const SizedBox(height: 24),

                        // 6. Son Yarış Geçmişi (MenuTile Tasarımı)
                        _buildRaceHistorySection(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RoundIconButton(
          Icons.arrow_back,
          onTap: () => Navigator.maybePop(context),
        ),
        RoundIconButton(
          _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          color: _isFavorite ? AppColors.lime : Colors.white,
          iconColor: AppColors.ink,
          onTap: _toggleFavorite,
        ),
      ],
    );
  }

  Widget _buildProfileHeader(AthleteDetail a) {
    final initials = a.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final parts = <String>[];
    if (a.clubName != null && a.clubName!.isNotEmpty) {
      parts.add(a.clubName!);
    } else {
      parts.add('Ferdi Sporcu');
    }

    if (a.birthYear != null) {
      parts.add('${a.birthYear} Doğumlu');
    }
    if (a.age != null) {
      parts.add('${a.age} Yaşında');
    }

    final subtitle = parts.join(' · ');

    return ProfileHeader(
      name: a.name,
      address: subtitle,
      initials: initials,
      badgeIcon: _isFavorite ? Icons.star_rounded : Icons.check,
      badgeBg: _isFavorite ? AppColors.lime : AppColors.ink,
      badgeIconColor: _isFavorite ? AppColors.ink : Colors.white,
      onBadgeTap: _toggleFavorite,
    );
  }

  Widget _buildStatCards(AthleteStats stats) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.pool_rounded,
            iconBg: AppColors.mint,
            label: 'Toplam Yarış',
            value: '${stats.totalRaces}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            icon: Icons.emoji_events_rounded,
            iconBg: AppColors.teal,
            label: 'Podyum / Kürsü',
            value: '${stats.podiumCount} (%${stats.podiumRate})',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            icon: Icons.bolt_rounded,
            iconBg: AppColors.lavender,
            label: 'Geçilen Baraj',
            value: '${stats.standardsPassed}',
          ),
        ),
      ],
    );
  }

  Widget _buildScoutNoteCard(String note) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.lime,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_rounded,
              size: 20,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scout Analiz Notu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPbSection(AthleteDetail a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kişisel En İyi (PB)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: AppColors.ink,
                  unselectedLabelColor: AppColors.muted,
                  labelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(text: '50m (Uzun)'),
                    Tab(text: '25m (Kısa)'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPbList(a.pbs50m, '50m Uzun Kulvar'),
                _buildPbList(a.pbs25m, '25m Kısa Kulvar'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPbList(List<PersonalBest> pbs, String courseName) {
    if (pbs.isEmpty) {
      return Center(
        child: Text(
          '$courseName için kayıtlı PB derecesi bulunmuyor.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: pbs.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.6,
        color: Color(0xFFE2E7E4),
      ),
      itemBuilder: (context, index) {
        final pb = pbs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${pb.distance}m ${pb.strokeLabel}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const SwimStatusBadge.pb(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pb.date} · ${pb.meetName}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    SwimTimeFormatter.formatCs(pb.timeCs),
                    style: SwimTheme.timeDisplaySmall.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (pb.points != null)
                    Text(
                      '${pb.points} Puan',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRaceHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Son Yarışlar',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        if (_raceHistory.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Kayıtlı yarış geçmişi bulunamadı.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          )
        else ...() {
            final recent = _raceHistory.take(8).toList();
            return recent.asMap().entries.map((entry) {
              final index = entry.key;
              final r = entry.value;
              final isLast = index == recent.length - 1;
              return MenuTile(
                icon: Icons.water_drop_outlined,
                iconBg: Colors.white,
                title: '${r.distance}m ${r.strokeLabel}',
                subtitle: '${r.meetName} · ${r.date}',
                showDivider: !isLast,
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      SwimTimeFormatter.formatCs(r.timeCs),
                      style: SwimTheme.timeDisplaySmall.copyWith(
                        color: AppColors.ink,
                        fontSize: 14,
                      ),
                    ),
                    if (r.rank.isNotEmpty)
                      Text(
                        '#${r.rank} Sıra',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              );
            });
          }(),
      ],
    );
  }
}
