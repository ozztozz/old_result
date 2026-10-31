---
description: Katı Tasarım Sistemi (Design System) ve Bileşen Odaklı Geliştirme (Component-Driven Development) Kuralları
globs: swim_mobile_app/**/*.dart
---

# TYF Swim Mobile App — Tasarım Sistemi ve Mimari Kuralları

Bu Flutter projesinde tüm UI geliştirmeleri katı bir "Design System" (Tasarım Sistemi) ve "Component-Driven Development" (Bileşen Odaklı Geliştirme) mimarisine göre yapılacaktır. Ekranlarda serbest stil tanımlamaları kesinlikle yasaktır.

Yeni bir özellik, ekran veya bileşen yazarken şu kurallara kesinlikle uyulmalıdır:

---

### 1. Hardcoded Değer Yasağı
- Ekran ve widget dosyalarında doğrudan renk (`Color(...)`), sabit boşluk (`SizedBox(height: 16)`), keyfi padding veya doğrudan `BorderRadius` tanımlanamaz.
- Tüm bu değerler merkezi token sınıflarından (`AppSpacing`, `AppRadius`, `AppColors`) veya dinamik tema üzerinden (`context.palette` / `Theme.of(context)`) okunmalıdır.

### 2. Katmanlı Mimari Hiyerarşisi
UI geliştirmeleri şu 4 katmana göre inşa edilir:
1. **Design Tokens (`lib/core/theme/tokens/`):**
   - `app_spacing.dart`: Sabit boşluklar (`AppSpacing.vSm`, `AppSpacing.hMd`, `AppSpacing.cardPadding` vb.).
   - `app_radius.dart`: Köşe yuvarlatma sabitleri (`AppRadius.cardRadius`, `AppRadius.buttonRadius` vb.).
   - `app_color_palette.dart`: Çoklu palet ve tema renkleri soyutlaması (`AppColorPalette`, `LightColorPalette`, `DarkColorPalette`, `context.palette`).
   - `app_colors.dart`: Temel palet sabitleri ve geriye dönük uyumluluk takma adları.
   - `app_typography.dart`: Tabular rakamlar, spor paneli metrikleri ve başlık hiyerarşisi (`AppTextStyles`).
2. **Global ThemeData (`lib/core/theme/app_theme.dart`):**
   - Material 3 tabanlı merkezi tema (`AppTheme.light`, `AppTheme.dark`).
   - `FilledButton`, `OutlinedButton`, `TextField`, `Card`, `AppBar`, `Divider`, `Chip` gibi standart bileşenlerin stilleri burada tanımlanır.
3. **Atomik UI Bileşenleri (`lib/core/components/` veya `lib/shared/widgets/`):**
   - Projeye özel kartlar (`AppCard`), durum butonları (`AppButton`), yüklenme iskeletleri (`AppSkeleton`) ve boş durum şablonları (`EmptyStateWidget`) bu dizinde tekil olarak üretilir.
4. **Ekranlar (`lib/features/.../presentation/views/` veya `lib/features/.../*_screen.dart`):**
   - Ekranlar sadece bu hazır bileşenleri ve düzenleme (layout) kurallarını kullanarak bir araya getirilen bir montaj hattıdır. Ekran içerisinde sıfırdan stil, kutu süslemesi veya keyfi renk tanımlanmaz.

### 3. Çoklu Palet & Dinamik Tema Desteği
- Renk şemaları soyut `AppColorPalette` arayüzü ve `ThemeExtension` (`AppPaletteExtension`) üzerinden yönetilir.
- Ekranlar veya widget'lar renk ihtiyacında `context.palette.<color>` getter'ını kullanır.
- Açık/Koyu mod veya farklı yarış/kulüp renk paletlerine geçişlerde ekran kodu değiştirilmez; sadece palet nesnesi değişir.
