import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'host_failover.dart';

class ApiException implements Exception {
  ApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'ApiException($code, $message)';
}

typedef TokenReader = String? Function();
typedef TokenRefresher = Future<void> Function();
typedef HostGetter = String Function();

class ApiClient {
  ApiClient({
    required TokenReader tokenReader,
    required TokenRefresher tokenRefresher,
    required HostGetter hostGetter,
  }) : _tokenReader = tokenReader,
       _tokenRefresher = tokenRefresher,
       _hostGetter = hostGetter {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
        responseType: ResponseType.json,
        headers: {...AppConfig.defaultHeaders},
      ),
    );
    _dio.interceptors.add(_buildBusinessInterceptor());
    _dio.interceptors.add(
      HostFailoverInterceptor(dio: _dio, hosts: AppConfig.apiBaseUrls),
    );
  }

  static const _authRetriedKey = '_token_refresh_retried';

  late final Dio _dio;
  final TokenReader _tokenReader;
  final TokenRefresher _tokenRefresher;
  final HostGetter _hostGetter;

  Dio get dio => _dio;

  Interceptor _buildBusinessInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _tokenReader();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = token;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final data = response.data;
        if (data is Map && data.containsKey('code')) {
          final code = data['code'];
          if (code is int && code != 0) {
            final message = (data['message'] ?? 'unknown error').toString();
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                error: ApiException(code, message),
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
        }
        handler.next(response);
      },
      onError: (err, handler) async {
        final is401 = err.response?.statusCode == 401;
        final alreadyRetried =
            err.requestOptions.extra[_authRetriedKey] == true;
        if (!is401 || alreadyRetried) {
          handler.next(err);
          return;
        }
        try {
          await _tokenRefresher();
        } catch (_) {
          handler.next(err);
          return;
        }
        try {
          final newHost = _hostGetter();
          _dio.options.baseUrl = newHost;
          final retryOpts = err.requestOptions.copyWith(
            baseUrl: newHost,
            extra: {...err.requestOptions.extra, _authRetriedKey: true},
          );
          final resp = await _dio.fetch(retryOpts);
          handler.resolve(resp);
        } on DioException catch (e) {
          handler.next(e);
        }
      },
    );
  }
}
