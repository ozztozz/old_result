# TYF Yüzme Mobil Uygulaması: Ürün ve Teknik Şartnamesi (v6)

Bu doküman, Flutter tabanlı iOS ve Android uygulaması ile bu uygulamayı besleyen bağımsız mobil REST API'sini (`/api/v1/`) ve resmi tasarım sistemi olan **SwimDesign** kurallarını kapsayan kesinleşmiş teknik şartnamedir.

---

## 1. Vizyon, Kapsam ve Temel Prensipler

### 1.1 Amaç
Türkiye Yüzme Federasyonu (TYF) müsabaka sonuçlarını, canlı start ve netice listelerini, sporcu kariyer verilerini (kişisel en iyi dereceler, baraj durumları, gelişim) ve kulüp bilgilerini sporcular, veliler, antrenörler ve kulüp yöneticileri için cep telefonunda hızlı, güvenilir ve okunaklı biçimde sunmak.

### 1.2 Kullanım Senaryoları
- **Veli:** Çocuğunun sıradaki yarışını (seri ve kulvar) takip eder, yarış yaklaşırken bildirim alır, sonucu resmî sıralamayla görür ve paylaşır.
- **Antrenör:** Takımındaki sporcuların programını ve sonuçlarını toplu izler, giriş ve çıkış derecesi farkını analiz eder.
- **Sporcu:** Kişisel en iyi derecelerini (PB), puanlarını ve baraj durumunu inceler.
- **Kulüp Yöneticisi:** Müsabaka bazında kulüp puanını ve madalya özetini izler.

### 1.3 Kapsam Sınırı (Strict Decoupling)
1. **Mobil uygulama bağımsız bir projedir:** Django şablonlarına ve HTML web arayüzüne bağımlı değildir; ayrı bir Flutter reposunda/klasöründe geliştirilir.
2. **Mobil API bağımsızdır:** Django içinde ayrı bir `mobile_api` uygulaması olarak kurulur (`/api/v1/`), web'in HTML render mantığına dokunulmaz.
3. **Ağır işler yalnızca sunucudadır:** PDF ayrıştırma, Gemini Flash Lite yapay zekâ modelleri, arka plan tarama (Cloud Runner / Cron) ve doğrudan veritabanı yönetimi mobil projenin dışındadır. İstemci yalnızca hazır JSON verisini alır, önbelleğe alır ve gösterir.

### 1.4 Kapsam Dışı (v1)
- Kullanıcı hesabı ve giriş (Favoriler cihazda `drift` ile tutulur).
- Yeni canlı yarış ekleme veya veri düzeltme (Sunucu tarafı işidir).
- Sosyal özellikler (yorum, mesajlaşma vb.).

---

## 2. Mimari ve Teknoloji Yığını

```
TYF kaynakları (PDF / canlı portal)
        │
        ▼
[Ayrıştırıcı + Canlı Tarayıcı (Gemini)]  ──►  [SQLite (WAL)]
                                                    │
                                  ┌─────────────────┴───────────────┐
                                  ▼                                 ▼
                          [Web Arayüzü]                  [mobile_api /api/v1/]
                          (HTML Şablonlar)                 │  ▲ Sunucu Önbelleği (10-15 sn)
                                                           │  │ ETag / 304
                                                  CDN / Ters Vekil (TLS)
                                                           ▼
                                               [Flutter İstemci (iOS/Android)]
                                                Dio · Cubit · Drift (Yerel DB)
```

### 2.1 Teknoloji Seçimleri

| Katman | Seçim | Gerekçe / Not |
| :-- | :-- | :-- |
| **Framework** | Flutter 3.2x+, Dart 3.x | iOS & Android, tablet uyumlu responsive düzen |
| **Durum Yönetimi** | `flutter_bloc` (Cubit) | Öngörülebilir, test edilebilir tek yönlü veri akışı |
| **Ağ Katmanı** | `dio` + cache interceptor | Keep-Alive, ETag desteği, jitter'lı yeniden deneme |
| **Modeller** | `freezed` + `json_serializable` | Tip güvenli ve değişmez (immutable) DTO modelleri |
| **Yerel Depolama** | `drift` (SQLite) + `shared_preferences` | Yüzme verisi ilişkisel olduğundan ve katılımcı listesini 0 ms gecikmeyle filtrelemek için Drift kullanılır. |
| **Navigasyon** | `go_router` | Alt menü, deep link, universal link desteği |
| **Grafik** | `fl_chart` | Derece gelişim ve dağılım grafikleri |
| **Tasarım Sistemi** | SwimDesign (Material 3) | Açık & Koyu tema, Shimmer skeleton loading, Pull-to-refresh |

---

## 3. Ekranlar ve Akışlar

Uygulamada 4 sekmeli alt menü bulunur: **Ana Sayfa, Müsabakalar, Canlı, Favoriler.**

### Ekran 1: Ana Sayfa ve Arama
- Üstte devam eden aktif canlı yarış bildirimi ("Canlı Yarış Devam Ediyor").
- Son müsabakaların yatay kart listesi (Şehir, tarih, havuz tipi, yarış sayısı).
- Arama Çubuğu: 2 karakterden sonra 250 ms debounce ile sporcu, kulüp ve müsabaka önerileri.
- Favori sporcuların durum rozetleri (`/athletes/summary/?ids=...` ile tek toplu istekle).

### Ekran 2: Müsabaka Listesi ve Detayı
- **Liste:** Yıl ve şehir filtreli müsabaka kartları.
- **Detay Bilgi Kartı:** Şehir, tarih aralığı, havuz tipi (`25m` / `50m`), sporcu ve kulüp sayısı.
- **Yarış Numarası Seçici:** Yatay kaydırılabilir butonlar (`Yarış 1 · 50m Serbest`).
- **Bağımlı Filtreleme (0 ms Gecikme):** Müsabakanın katılımcı listesi (`/meets/{id}/participants/`) tek seferde indirilip cihaz hafızasında (Drift) tutulur. Kulüp seçildiğinde sporcu listesi istemcide anında daralır.
- **Durum Filtresi:** Tümü, Sonuçlananlar, Bekleyenler.
- **Sonuç Kartları:** Sıra, sporcu, kulüp, seri, kulvar, derece, puan, baraj rozeti (`A1`, `B2`).

### Ekran 3: Sporcu Profili & Kariyer Karnesi
- Ad-soyad, doğum yılı, yarış yaşı, güncel kulüp ve okul.
- **Havuz Tipi (Course) Sekmeli PB Tablosu:** 25m (Kısa Kulvar) ve 50m (Uzun Kulvar) ayrımıyla; Serbest, Sırtüstü, Kurbağalama, Kelebek, Karışık branşlarında en iyi dereceler, tarihler ve puanlar.
- **Kariyer İstatistikleri:** Toplam yarış, kürsü/madalya oranı, geçilen baraj sayısı.
- **Değerlendirme Özeti:** Kural tabanlı üretilen scout analiz metni.
- **Yarış Geçmişi:** Stil, mesafe ve yıl filtreli liste.
- **Kulüp Tarihçesi:** Kronolojik lisans geçmişi.

### Ekran 4: Canlı Yarış İzleyici (Live Viewer)
- Aktif canlı yarış listesi ve start/sonuç ilerleme yüzdesi.
- Seri ve kulvar bazında anlık durum (`Bekleniyor` / resmi derece ve sıra).
- Ön planda 30 sn periyodik yenileme (±5 sn jitter ile), pull-to-refresh; arka plana geçince polling durur.
- Her zaman görünen "X dk önce güncellendi" etiketi.

### Ekran 5: Favorilerim (Mobil Özel)
- Veliler ve antrenörler için tek tıkla sporcu/kulüp yıldızlama.
- Her favori için son derece, sıradaki yarış ve PB özeti.
- Çevrimdışıyken Drift yerel veritabanından anında açılır.

---

## 4. Mobil REST API Sözleşmesi (`/api/v1/`)

### 4.1 Genel Standartlar
- **Adlandırma:** İngilizce `snake_case`. (Örn: `athlete_id`, `event_no`, `time_cs`).
- **Kodlama & Tarih:** UTF-8, Gzip. ISO 8601 UTC (`2026-10-30T12:00:00Z`), yerel tarihler `YYYY-MM-DD`.
- **Önbellek:** Tüm GET yanıtlarında `ETag`; istemci `If-None-Match` gönderir, değişmediyse `304 Not Modified`.
- **Güvenlik & Doğrulama:** `X-App-Key` başlığı ve IP başına rate limiting.

### 4.2 Süre, Durum ve Havuz Modeli

#### Yüzme Süre Gösterim Kuralı (Client-side Formatting)
API'den süreler **centisaniye cinsinden tam sayı** döner (`time_cs: 2845`). Mobil istemci bunu şu uluslararası yüzme standardına göre biçimlendirir:
- 1 dakikanın altı: `28.45` (başında `00:` olmaz).
- 1 dakikanın üstü: `1:02.34` (dakika tek haneliyse başında sıfır olmaz).
- 1 saatin üstü (açık su): `1:02:15.40`.

#### Durumlar ve Tipler
- `result_status`: `OK`, `DQ`, `DNS`, `DNF`, `WAITING`. (DQ/DNS durumlarında `time_cs` `null` döner).
- `course`: `"SC"` (25m - Kısa Kulvar), `"LC"` (50m - Uzun Kulvar).
- `qualifying_standard`: `{"passed": true, "badge": "A1"}` veya `null`.
- `source`: `"official"` veya `"live"`.
- `stroke`: `free`, `back`, `breast`, `fly`, `medley`.
- `gender`: `F`, `M`, `all`.

### 4.3 Endpoint Listesi

| Metot | Yol | Açıklama |
| :-- | :-- | :-- |
| `GET` | `/config/` | Minimum uygulama sürümü, bakım modu, özellik bayrakları |
| `GET` | `/search/?q=&type=` | Genel arama (sporcu, kulüp, müsabaka) |
| `GET` | `/meets/` | Müsabaka listesi (`cursor`, `page_size`, `year`, `city`, `q`) |
| `GET` | `/meets/{id}/` | Müsabaka genel bilgileri ve yarış programı (`events`) |
| `GET` | `/meets/{id}/participants/` | Katılan kulüpler ve sporcular (Gzip sıkıştırmalı, bağımlı filtre için) |
| `GET` | `/meets/{id}/results/` | Filtrelenmiş yarış sonuçları (`event_no`, `club_id`, `athlete_id`, `status`, `cursor`) |
| `GET` | `/athletes/{id}/` | Profil, kariyer özeti, 25m ve 50m PB tablosu, scout notu |
| `GET` | `/athletes/{id}/races/` | Sporcunun yarış geçmişi (`stroke`, `distance`, `year`, `course`, `cursor`) |
| `GET` | `/athletes/{id}/clubs/` | Kulüp lisans tarihçesi |
| `GET` | `/athletes/summary/?ids=1,2,3` | Favoriler için toplu özet (en fazla 50 ID) |
| `GET` | `/live/` | Aktif ve son tamamlanan canlı yarışların ilerleme durumu |
| `GET` | `/live/{id}/feed/` | Canlı start/sonuç akışı (`event_no`, `status`, `since`) |

---

## 5. Tasarım Sistemi: SwimDesign

Yön: **derin okyanus mavisi, tek bir turkuaz vurgu ve serin gri-beyaz yüzeyler.** Gradyan, gölge ve süs yoktur; ağırlık süre rakamlarındadır.

### 5.1 Tasarım Prensipleri
1. **Veri ön planda:** Süreler ve sıralamalar en büyük ve en yüksek kontrastlı öğedir.
2. **Az ve anlamlı renk:** Renk süs değil, durum bildirir.
3. **Renk tek başına anlam taşımaz:** Her duruma ikon ve etiket eşlik eder (WCAG AA).
4. **Sade yüzeyler:** Gölge yerine (`elevation: 0`) 1 dp ince kenarlık ve yüzey tonu farkı kullanılır.

### 5.2 Renk Paleti ve Token Tablosu

| Token | Açık tema | Koyu tema | Anlam / Kullanım |
| :-- | :-- | :-- | :-- |
| `background` | `#F6F9FB` | `#0B141C` | Ekran ana arka planı |
| `surface` | `#FFFFFF` | `#121E28` | Kart ve panel yüzeyi |
| `textPrimary` | `#0B1B2B` | `#E6EEF4` | Ana başlık ve yüksek kontrastlı metin |
| `textSecondary` | `#5B6B7A` | `#9BB0C0` | İkincil metin, kulüp ve detaylar |
| `outline` | `#DCE5EC` | `#24323E` | 1 dp ince kart ve chip kenarlıkları |
| `primary` | `#0A5C99` | `#5FB3F0` | Okyanus mavisi (Ana marka ve süre rengi) |
| `accent` | `#1AA6B7` | `#4DD0E1` | Turkuaz (Yalnızca küçük detaylar ve 25m etiketi) |
| `success` | `#1B7F4B` | `#5CCB8A` | Sonuçlandı ve baraj geçildi durumu |
| `pending` | `#B26A00` | `#F2B84B` | Bekleniyor durumu |
| `pendingBg` | `#FFF4DD` | `#2A2210` | Bekleniyor durum rozet zemin tonu |
| `danger` | `#B3261E` | `#FF8A80` | DQ, DNS, DNF ve canlı yarış etiketi |
| `pb` | `#00838F` | `#4DD0E1` | **Yeni Kişisel En İyi (PB)** rozeti (Yıldız ikonu ile) |
| `medalGold` | `#C9A227` | `#C9A227` | 1. sıra kürsü ve madalya rengi |
| `medalSilver` | `#9AA5B1` | `#9AA5B1` | 2. sıra kürsü ve madalya rengi |
| `medalBronze` | `#B0713A` | `#B0713A` | 3. sıra kürsü ve madalya rengi |

### 5.3 Durum Rozetleri (SwimStatusBadge)
- **Sonuçlandı:** `success` ikon ve etiket, hafif tonlu zemin: `✓ Sonuçlandı`
- **Bekleniyor:** `pending` ikon, `pendingBg` zemin: `⏱ Bekleniyor`
- **DQ / DNS / DNF:** `danger` ikon ve etiket: `✕ DQ`
- **Yeni PB:** `pb` rengi ve yıldız ikonu: `★ Yeni PB` (Asla yeşil ile karıştırılmaz)
- **Baraj geçildi:** `success` ikon: `✓ Baraj A1`
- **Geçici (canlı):** Nötr kenarlıklı rozet: `Geçici (Canlı)`

### 5.4 Tipografi ve Taşma Koruması
- **Yazı tipi:** `Inter` (Yerel `assets/fonts/Inter/` olarak gömülür, çevrimdışı FOUT engellenir).
- **İmza Süre Stili (`timeDisplay`):** `22 sp`, `w700`, `FontFeature.tabularFigures()`.
- **Erişilebilirlik Taşma Koruması:** Dinamik sistem font ölçeği %130-%150'ye çıkarıldığında sürenin karttan taşmasını önlemek için süre hücresinde `FittedBox(fit: BoxFit.scaleDown)` zorunludur.

### 5.5 Flutter `ThemeExtension` Mimarisi
Durum renkleri `ThemeExtension<SwimColors>` içinde tanımlanır; widget'lar `context.swimColors.pb` şeklinde tip güvenli ve tema geçişlerinde yumuşak `lerp` animasyonuyla çalışır.

### 5.6 Bileşen Galerisi (Component Gallery)
Uygulamada tüm rozetlerin, kartların, madalya renklerinin ve font ölçek test slider'ının tek ekranda incelenebildiği gizli bir bileşen galerisi (`ComponentGalleryScreen`) yer alır.

---

## 6. Uygulama Geliştirme Yol Haritası

```
[Adım 1: Django mobile_api]  ──►  [Adım 2: Flutter İskeleti & SwimDesign]  ──►  [Adım 3: Ekranlar & Drift]
- /api/v1/ rotaları              - flutter create swim_mobile_app               - Müsabaka & Bağımlı Filtre
- Serializers (time_cs, PB)      - SwimColors (ThemeExtension) & SwimTheme      - Sporcu Profili & 25m/50m PB
- X-App-Key & ETag               - SwimResultCard & SwimStatusBadge             - Canlı Yarış & Favoriler
```

- **Adım 1:** Django içinde bağımsız `mobile_api` uygulamasını kurup `/api/v1/` endpoint'lerini devreye almak ve test etmek. *(TAMAMLANDI)*
- **Adım 2:** Bağımsız `swim_mobile_app` Flutter projesini oluşturup SwimDesign sistemini (`SwimColors`, `SwimTheme`, `SwimResultCard`, `SwimStatusBadge`, `ComponentGalleryScreen`) hazırlamak. *(TAMAMLANDI)*
- **Adım 3:** Kullanıcı ekranlarını (Müsabaka, Sporcu, Canlı, Favoriler) bu tasarım sistemine tam entegre etmek. *(TAMAMLANDI)*
