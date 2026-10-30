# TYF Yüzme Mobil Uygulaması (Flutter Client)

Bu proje, Django tabanlı **Yüzme Sonuçları ve Canlı Takip Sistemi**'nin Flutter ile geliştirilmiş resmi mobil istemcisidir.

## Özellikler

1. **Ana Sayfa & Keşfet:** Güncel müsabakalar, aktif canlı yarış bildirimi, anlık sporcu/kulüp arama (autocomplete).
2. **Müsabaka Detayı & Yarış Sonuçları:**
   - Yarış numarası rozetleri (`Yarış 1 · 50m Serbest`).
   - Sadece o müsabakaya katılan kulüp ve sporculardan seçim yapılabilen **0 ms gecikmeli bağımlı filtreler**.
   - Durum filtreleri (`Tümü`, `Sonuçlananlar`, `Bekleyenler`).
   - Resmi derece, seri/kulvar, FINA puanı ve baraj rozetleri (`A1`, `B2`).
3. **Sporcu Profili & Kariyer Karnesi:**
   - 25m (Kısa Kulvar) ve 50m (Uzun Kulvar) sekmeli Kişisel En İyi Dereceler (PB) tablosu.
   - Podyum / kürsü başarı oranı, geçilen baraj sayısı ve scout performans özeti.
   - Kronolojik tüm yarış geçmişi.
4. **Canlı Yarış İzleyici:**
   - Devam eden canlı yarış oturumlarının start ve netice listesi ilerleme takibi.
5. **Favorilerim & Hızlı Takip:**
   - Veliler ve antrenörler için sporcuları favoriye ekleme ve son derecelerini tek ekranda izleme.

## Başlangıç ve Çalıştırma

### Gereksinimler
- Flutter SDK (3.2x veya üzeri)
- Android Studio / Xcode

### Bağımlılıkları Yükleme
```bash
cd swim_mobile_app
flutter pub get
```

### Çalıştırma (Android Emülatör / iOS Simülatör / Gerçek Cihaz)
```bash
# Canlı Oracle Cloud sunucusuna bağlanarak çalıştırır (https://yuzme.duckdns.org/api/v1)
flutter run

# Yerel Django backend'ine bağlanmak için lib/core/config/api_config.dart dosyasında:
# ApiConfig.baseUrl = ApiConfig.localBaseUrl;
```

## Mimari ve Dizin Yapısı

- `lib/core/config/`: API uç nokta tanımları (`/api/v1/`) ve zaman aşımları.
- `lib/core/network/`: Dio HTTP istemcisi, Keep-Alive ve ETag desteği.
- `lib/core/theme/`: Yüzme teması, açık ve koyu mod, durum renkleri.
- `lib/core/utils/`: Uluslararası yüzme süre formatlayıcısı (`SwimTimeFormatter`).
- `lib/data/models/`: Tip güvenli DTO modelleri (`Meet`, `Athlete`, `RaceResult`, `LiveMeet`).
- `lib/data/repositories/`: API isteklerini ve veri akışını yöneten `SwimRepository`.
- `lib/features/`: Kullanıcı ekranları (`home`, `meets`, `athletes`, `live`, `favorites`).
