---
description: Apple Health / Strava tarzı minimalist spor gösterge paneli tasarım sistemi kuralları
globs: swim_mobile_app/**/*.dart
---

# TYF Swim Mobile App - Tasarım Sistemi Kuralları

Bu Flutter projesinde Apple Health/Strava tarzı minimalist bir spor gösterge paneli dili kullanılmaktadır.

- **Arka Plan Rengi:** Daima `#F8FAFC` (`AppColors.background`).
- **Yüzey / Kartlar:** Daima beyaz `Colors.white` (`AppColors.surface`).
- **Ana Metinler & Rakamlar:** Daima `#0F172A` (`AppColors.textPrimary` / `AppTextStyles.metricLarge`).
- **İkincil Etiketler:** Daima `#64748B` (`AppColors.textSecondary` / `AppTextStyles.cardSubtitle`).
- **Pasif / Tarih / Metraj:** Daima `#94A3B8` (`AppColors.textMuted` / `AppTextStyles.labelMuted`).
- **Tek Vurgu Rengi (Accent):** Daima `#4F46E5` (`AppColors.accent`) — yalnızca aktif tab, seçili filtre veya zirve derece için.
- **Durum Rengi (Başarı / Canlı):** Daima `#10B981` (`AppColors.statusLive` / `AppColors.statusSuccess`).
- **Çerçeveler:** Daima `#E2E8F0`, 1.0px (`AppBorders.border` / `Border.all(color: Color(0xFFE2E8F0), width: 1.0)`).
- **Köşe Yuvarlaklıkları:** Standart `BorderRadius.circular(14)` veya `16` (`AppBorders.cell` / `AppBorders.panel`).
- **Ayırıcı Çizgiler:** Daima `Divider(color: Color(0xFFF1F5F9), thickness: 1.0)` (`AppBorders.divider()`).

Gereksiz renkli çiplerden ve kutu karmaşasından kaçınılmalı, tipografik sütunlar ve dikey ayırıcı çizgilerle monokrom bir veri hiyerarşisi kurulmalıdır.
Tüm bileşenler `lib/core/theme/` (`app_colors.dart`, `app_typography.dart`, `app_decorations.dart`) ve `lib/shared/widgets/` (`AppScaffold`, `StrokeTelemetryRow`, `StatusBadge`, `LiveBadge`, `ModernRaceCard`, `HeroRaceCard`) üzerinden merkezi olarak yönetilmelidir.

