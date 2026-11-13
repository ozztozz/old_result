/// Mobil API Yapılandırma ve Temel Ayarları
class ApiConfig {
  /// Oracle Cloud Üretim Ortamı Base URL
  static const String prodBaseUrl = 'https://yuzme.duckdns.org/api/v1';

  /// Yerel Emülatör / Test Ortamı Base URL
  static const String localBaseUrl = 'http://10.0.2.2:8000/api/v1';

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const bool _useLocalApi = bool.fromEnvironment('USE_LOCAL_API');

  /// Aktif Base URL (--dart-define=API_BASE_URL=... veya USE_LOCAL_API=true ile geçersiz kılınabilir)
  static String baseUrl = _envBaseUrl.isNotEmpty
      ? _envBaseUrl
      : (_useLocalApi ? localBaseUrl : prodBaseUrl);

  /// Güvenlik ve Temel İstemci Doğrulama Başlığı
  static const String appKeyHeader = 'X-App-Key';
  static const String appKeyValue = String.fromEnvironment(
    'APP_KEY',
    defaultValue: 'swim-mobile-v1-client',
  );

  /// Zaman Aşımı Süreleri
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}

