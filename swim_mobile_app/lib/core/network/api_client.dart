import 'package:dio/dio.dart';
import '../config/api_config.dart';

/// Mobil API İçin Merkezi HTTP İstemcisi
class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ApiConfig.appKeyHeader: ApiConfig.appKeyValue,
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // İstek başlıkları ve parametre loglama
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // Başarılı yanıt
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          // Merkezi hata işleme
          return handler.next(e);
        },
      ),
    );
  }

  Dio get dio => _dio;

  /// GET İsteği
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }
}

