import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/ambient_canvas.dart';
import '../../core/components/app_skeleton.dart';
import '../../core/components/empty_state_widget.dart';
import '../../core/components/section_header.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/models/meet.dart';
import '../../data/repositories/swim_repository.dart';
import '../athletes/athlete_profile_screen.dart';
import '../meets/meet_search_screen.dart';

/// Kulüp Profili, İletişim/Sosyal Medya Kartı ve Sporcuları
class ClubDetailScreen extends StatefulWidget {
  final int clubId;
  final String clubName;
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;

  const ClubDetailScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.repository,
    this.onMeetSelected,
  });

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  bool _isLoading = true;
  String? _error;
  ClubDetailModel? _detail;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.getClubDetail(widget.clubId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(
      trimmed.startsWith('http://') ||
              trimmed.startsWith('https://') ||
              trimmed.startsWith('tel:')
          ? trimmed
          : 'https://$trimmed',
    );
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı açılamadı')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final displayTitle = StringUtils.toTitleCase(
      _detail?.name ?? widget.clubName,
    );

    return Scaffold(
      backgroundColor: palette.background,
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(palette, displayTitle),
              Expanded(child: _buildBody(palette)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppColorPalette palette, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          GlassCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Geri',
            onTap: () => Navigator.of(context).pop(),
          ),
          AppSpacing.h12,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: SelectedClubService.instance,
            builder: (context, _) {
              final isSelected = SelectedClubService.instance.matches(
                _detail?.name ?? widget.clubName,
                widget.clubId,
              );
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  if (isSelected) {
                    await SelectedClubService.instance.clearClub();
                  } else {
                    await SelectedClubService.instance.setClub(
                      id: widget.clubId,
                      name: _detail?.name ?? widget.clubName,
                    );
                  }
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? palette.statusWarning.withValues(alpha: 0.14)
                        : palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? palette.statusWarning.withValues(alpha: 0.4)
                          : palette.border,
                    ),
                  ),
                  child: Icon(
                    isSelected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 20,
                    color: isSelected
                        ? palette.statusWarning
                        : palette.textSecondary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppColorPalette palette) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppSkeletonList(
          itemCount: 4,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppSkeleton(height: 92),
          ),
        ),
      );
    }

    if (_error != null || _detail == null) {
      return EmptyStateWidget(
        icon: Icons.wifi_off_rounded,
        title: 'Kulüp bilgileri alınamadı',
        message: 'Bağlantınızı kontrol edip tekrar deneyin.',
        actionText: 'Tekrar Dene',
        onAction: _loadDetail,
      );
    }

    final club = _detail!;
    return RefreshIndicator(
      onRefresh: _loadDetail,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _buildHeaderCard(palette, club),
          if (club.hasContactInfo) ...[
            AppSpacing.vMd,
            _buildContactCard(palette, club),
          ],
          AppSpacing.vLg,
          SectionHeader(
            title: 'Kulüp Sporcuları',
            trailingText: club.swimmers.isNotEmpty
                ? 'En aktif ${club.swimmers.length} sporcu'
                : null,
          ),
          AppSpacing.vSm,
          if (club.swimmers.isEmpty)
            SoftGlassPanel(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Kayıtlı sporcu bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
            )
          else
            ...club.swimmers.map((s) => _buildSwimmerTile(palette, s)),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(AppColorPalette palette, ClubDetailModel club) {
    final displayName = StringUtils.toTitleCase(club.name);
    final dateRange = (club.firstRaceDate != null || club.lastRaceDate != null)
        ? '${club.firstRaceDate ?? '-'} → ${club.lastRaceDate ?? '-'}'
        : null;

    return SoftGlassPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (club.isSchool ? palette.infoCyan : palette.accent)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  club.isSchool ? Icons.school_rounded : Icons.shield_rounded,
                  size: 24,
                  color: club.isSchool ? palette.infoCyan : palette.accent,
                ),
              ),
              AppSpacing.h12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          icon: club.isSchool
                              ? Icons.school_outlined
                              : Icons.verified_outlined,
                          label: club.isSchool ? 'Okul Takımı' : 'Resmî Kulüp',
                          color: club.isSchool
                              ? palette.infoCyan
                              : palette.statusSuccess,
                        ),
                        if (club.city != null)
                          _InfoChip(
                            icon: Icons.location_on_outlined,
                            label: StringUtils.toTitleCase(club.city!),
                            color: palette.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayName,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (dateRange != null) ...[
            AppSpacing.vSm,
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Faaliyet: $dateRange',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          AppSpacing.vMd,
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Sporcu',
                  value: '${club.athleteCount}',
                  color: palette.primary,
                  palette: palette,
                ),
              ),
              AppSpacing.hSm,
              Expanded(
                child: _StatBox(
                  label: 'Toplam Yarış',
                  value: '${club.raceCount}',
                  color: palette.statusSuccess,
                  palette: palette,
                ),
              ),
            ],
          ),
          AppSpacing.vMd,
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MeetSearchScreen(
                      repository: widget.repository,
                      initialClub: club.name,
                      onMeetSelected: widget.onMeetSelected,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.pool_rounded, size: 18),
              label: const Text('Kulübün Müsabakalarını Gör'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.primary,
                side: BorderSide(color: palette.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(AppColorPalette palette, ClubDetailModel club) {
    final hasAddress = club.address != null || club.googleMapsUrl != null;
    final hasLinks =
        club.website != null || club.instagram != null || club.facebook != null;

    return SoftGlassPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.contact_phone_outlined,
                    size: 18,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'İletişim ve Sosyal Medya',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              if (club.contactUpdatedAt != null &&
                  club.contactUpdatedAt!.length >= 10)
                Text(
                  club.contactUpdatedAt!.substring(0, 10),
                  style: TextStyle(
                    fontFamily: AppTextStyles.monoFontFamily,
                    fontSize: 11,
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
          if (hasAddress) ...[
            AppSpacing.vMd,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ContactIconBox(
                  icon: Icons.location_on_rounded,
                  color: palette.primary,
                ),
                AppSpacing.h12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADRES',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (club.address != null)
                        Text(
                          club.address!,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            height: 1.4,
                            color: palette.textPrimary,
                          ),
                        ),
                      if (club.googleMapsUrl != null) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _openExternalUrl(club.googleMapsUrl!),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 15,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Google Maps\'te Aç',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: palette.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (club.phone != null) ...[
            AppSpacing.vMd,
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openExternalUrl('tel:${club.phone!}'),
              child: Row(
                children: [
                  _ContactIconBox(
                    icon: Icons.phone_rounded,
                    color: palette.statusSuccess,
                  ),
                  AppSpacing.h12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TELEFON',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          club.phone!,
                          style: TextStyle(
                            fontFamily: AppTextStyles.monoFontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.call_made_rounded,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ],
          if (hasLinks) ...[
            AppSpacing.vMd,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (club.website != null)
                  _SocialActionChip(
                    icon: Icons.language_rounded,
                    label: 'Web Sitesi',
                    color: palette.primary,
                    onTap: () => _openExternalUrl(club.website!),
                  ),
                if (club.instagram != null)
                  _SocialActionChip(
                    icon: Icons.camera_alt_outlined,
                    label: 'Instagram',
                    color: const Color(0xFFE1306C),
                    onTap: () => _openExternalUrl(club.instagram!),
                  ),
                if (club.facebook != null)
                  _SocialActionChip(
                    icon: Icons.facebook_rounded,
                    label: 'Facebook',
                    color: const Color(0xFF1877F2),
                    onTap: () => _openExternalUrl(club.facebook!),
                  ),
              ],
            ),
          ],
          if (club.latitude != null && club.longitude != null) ...[
            AppSpacing.vMd,
            _buildMiniMapBox(palette, club),
          ],
          if (club.instagram != null) ...[
            AppSpacing.vSm,
            _buildInstagramPreviewBox(palette, club),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniMapBox(AppColorPalette palette, ClubDetailModel club) {
    final lat = club.latitude!.toStringAsFixed(5);
    final lon = club.longitude!.toStringAsFixed(5);
    final mapsTarget =
        club.googleMapsUrl ?? 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openExternalUrl(mapsTarget),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.pin_drop_rounded,
                size: 22,
                color: Color(0xFFEA4335),
              ),
            ),
            AppSpacing.h12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Google Maps Konumu',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$lat, $lon · Yol tarifi için dokunun',
                    style: TextStyle(
                      fontFamily: AppTextStyles.monoFontFamily,
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 17, color: palette.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildInstagramPreviewBox(
    AppColorPalette palette,
    ClubDetailModel club,
  ) {
    final igUrl = club.instagram!.trim();
    final clean = igUrl.replaceAll(RegExp(r'/+$'), '').split('?').first;
    final segment = clean.split('/').last.replaceFirst('@', '');
    final handle =
        (segment.isNotEmpty && !segment.toLowerCase().contains('instagram.com'))
        ? '@$segment'
        : StringUtils.toTitleCase(club.name);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openExternalUrl(igUrl),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFE1306C).withValues(alpha: 0.10),
              const Color(0xFF833AB4).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE1306C).withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFCAF45), Color(0xFFE1306C), Color(0xFF833AB4)],
                ),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            AppSpacing.h12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Resmî Instagram Profili',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              size: 17,
              color: Color(0xFFE1306C),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwimmerTile(AppColorPalette palette, ClubSwimmerSummary swimmer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftGlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AthleteProfileScreen(
                athleteId: swimmer.id,
                athleteName: swimmer.name,
                repository: widget.repository,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    StringUtils.toTitleCase(swimmer.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (swimmer.birthYear != null) '${swimmer.birthYear}',
                      swimmer.isActive ? 'Aktif' : 'Geçmiş',
                    ].join(' · '),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${swimmer.raceCount} yarış',
                style: TextStyle(
                  fontFamily: AppTextStyles.monoFontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: palette.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppColorPalette palette;

  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTextStyles.monoFontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _ContactIconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _SocialActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SocialActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
