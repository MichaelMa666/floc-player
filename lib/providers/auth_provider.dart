import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service);

  final AuthService _service;

  bool _loading = false;
  Object? _error;

  bool get isAuthenticated => _service.hasValidToken;
  bool get loading => _loading;
  Object? get error => _error;
  String? get token => _service.token;

  Future<void> ensureAuthenticated() async {
    if (isAuthenticated) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.refresh();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
