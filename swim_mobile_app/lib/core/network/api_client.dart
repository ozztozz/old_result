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

