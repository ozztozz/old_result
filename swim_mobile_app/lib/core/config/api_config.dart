/// Mobil API Yapılandırma ve Temel Ayarları
class ApiConfig {
  /// Oracle Cloud Üretim Ortamı Base URL
  static const String prodBaseUrl = 'https://yuzme.duckdns.org/api/v1';

  /// Yerel Emülatör / Test Ortamı Base URL
  static const String localBaseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Aktif Base URL (Gerektiğinde ortam değişkeni veya toggle ile değiştirilebilir)
  static String baseUrl = prodBaseUrl;

  /// Güvenlik ve Temel İstemci Doğrulama Başlığı
  static const String appKeyHeader = 'X-App-Key';
  static const String appKeyValue = 'swim-mobile-v1-client';

  /// Zaman Aşımı Süreleri
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}

