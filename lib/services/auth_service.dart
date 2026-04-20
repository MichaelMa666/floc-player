import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._prefs)
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
          responseType: ResponseType.json,
          headers: {...AppConfig.defaultHeaders},
        ),
      );

  static const _kToken = 'auth_token';
  static const _kExpired = 'auth_expired';

  final SharedPreferences _prefs;
  final Dio _dio;

  String? _token;
  int? _expiredAtSec;
  Future<void>? _refreshing;

  String? get token => _token;

  String get currentHost => _dio.options.baseUrl;

  bool get hasValidToken {
    if (_token == null || _token!.isEmpty) return false;
    if (_expiredAtSec == null) return true;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return _expiredAtSec! > nowSec;
  }

  Future<void> loadFromPrefs() async {
    _token = _prefs.getString(_kToken);
    _expiredAtSec = _prefs.getInt(_kExpired);
  }

  Future<void> login({
    String account = AppConfig.defaultAccount,
    String code = AppConfig.defaultCode,
    String channel = AppConfig.loginChannel,
  }) async {
    final resp = await _dio.post(
      '/api/v1/auth/login',
      data: {'account': account, 'channel': channel, 'code': code},
    );
    final body = resp.data;
    if (body is! Map || body['code'] != 0) {
      final message = (body is Map ? body['message'] : null) ?? 'login failed';
      throw ApiException(
        body is Map ? (body['code'] as int? ?? -1) : -1,
        message.toString(),
      );
    }
    final data = body['data'] as Map;
    final token = (data['token'] as String?) ?? '';
    final expired = (data['expired'] as num?)?.toInt();
    if (token.isEmpty) {
      throw ApiException(-1, 'empty token in login response');
    }
    _token = token;
    _expiredAtSec = expired;
    await _prefs.setString(_kToken, token);
    if (expired != null) await _prefs.setInt(_kExpired, expired);
  }

  Future<void> handleTokenExpired() async {
    _token = null;
    _expiredAtSec = null;
    await _prefs.remove(_kToken);
    await _prefs.remove(_kExpired);
  }

  /// 串行去重：并发调用共享同一次真实请求。
  /// 从当前 host 起依次尝试所有备用域名，任一成功即返回；全败则抛最后一次异常。
  Future<void> refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _doRefresh() async {
    final current = _dio.options.baseUrl;
    final ordered = <String>[
      current,
      ...AppConfig.apiBaseUrls.where((h) => h != current),
    ];
    Object? lastError;
    for (final host in ordered) {
      _dio.options.baseUrl = host;
      try {
        await login();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('login failed on all hosts');
  }
}
