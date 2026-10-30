import 'package:flutter/material.dart';
import '../../core/theme/swim_colors.dart';

/// Yuvarlak ikon butonu (Geri, favori, ayarlar vb.)
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final Color iconColor;

  const RoundIconButton(
    this.icon, {
    super.key,
    this.onTap,
    this.size = 44,
    this.color = Colors.white,
    this.iconColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

/// Profil başlık bileşeni (Avatar, isim, kulüp, rozet)
class ProfileHeader extends StatelessWidget {
  final String name;
  final String address;
  final ImageProvider? avatar;
  final String? initials;
  final VoidCallback? onBadgeTap;
  final IconData badgeIcon;
  final Color badgeBg;
  final Color badgeIconColor;

  const ProfileHeader({
    super.key,
    required this.name,
    required this.address,
    this.avatar,
    this.initials,
    this.onBadgeTap,
    this.badgeIcon = Icons.star_rounded,
    this.badgeBg = AppColors.ink,
    this.badgeIconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.lavender,
              backgroundImage: avatar,
              child: avatar == null
                  ? (initials != null && initials!.isNotEmpty
                      ? Text(
                          initials!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        )
                      : const Icon(Icons.person, size: 36, color: AppColors.ink))
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                onTap: onBadgeTap,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                  child: Icon(badgeIcon, size: 14, color: badgeIconColor),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// İstatistik kartı (24dp radius, yuvarlak pastel ikon başlığı, etiket ve değer)
class StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String value;

  const StatCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
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
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Menü ve Liste Satırı (Yuvarlak 44dp ikon, başlık, alt başlık, isteğe bağlı trailing ve ayırıcı)
class MenuTile extends StatelessWidget {
  final IconData icon;
  final Color? iconBg;
  final String title;
  final String subtitle;
  final bool showDivider;
  final VoidCallback? onTap;
  final Widget? trailing;

  const MenuTile({
    super.key,
    required this.icon,
    this.iconBg,
    required this.title,
    required this.subtitle,
    this.showDivider = true,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg ?? Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 20, color: AppColors.ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else
                  const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 0.6, color: Color(0xFFE2E7E4)),
      ],
    );
  }
}
