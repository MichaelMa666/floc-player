import 'package:dio/dio.dart';

/// 单次重试到下一个备用域名。仅对网络层错误（连接/超时）生效，
/// 业务错误（code != 0）不会触发切换。成功后将 Dio 的 baseUrl 粘性切到新域名。
class HostFailoverInterceptor extends Interceptor {
  HostFailoverInterceptor({required this.dio, required this.hosts});

  final Dio dio;
  final List<String> hosts;

  static const _retriedKey = '_host_failover_retried';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.requestOptions.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    if (!_isNetworkError(err)) return handler.next(err);

    final currentIdx = hosts.indexOf(dio.options.baseUrl);
    if (currentIdx < 0 || currentIdx + 1 >= hosts.length) {
      return handler.next(err);
    }
    final nextHost = hosts[currentIdx + 1];

    try {
      final retryOpts = err.requestOptions.copyWith(
        baseUrl: nextHost,
        extra: {...err.requestOptions.extra, _retriedKey: true},
      );
      final resp = await dio.fetch(retryOpts);
      dio.options.baseUrl = nextHost;
      handler.resolve(resp);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _isNetworkError(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout;
  }
}
