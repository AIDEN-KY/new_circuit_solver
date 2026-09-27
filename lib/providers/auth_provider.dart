import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/account_profile.dart';
import '../models/account_activity.dart';
import '../services/auth_service.dart';
import '../utils/error_handler.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? service}) : _service = service ?? AuthService();

  final AuthService _service;

  AccountProfile? profile;
  List<AccountActivity> activities = const <AccountActivity>[];
  bool initialized = false;
  bool loading = false;
  String? errorMessage;

  bool get isAuthenticated => profile != null && AuthService.accessToken != null;

  Future<void> initialize() async {
    if (initialized) return;
    loading = true;
    notifyListeners();
    try {
      final String? token = await _service.loadToken();
      if (token != null && ApiConfig.hasValidBaseUrl) {
        profile = await _service.getProfile();
        try {
          activities = await _service.getActivities();
        } catch (error) {
          // 明细加载失败不应让有效登录失效。
          errorMessage = ErrorHandler.messageFor(error);
        }
      }
    } catch (error) {
      errorMessage = ErrorHandler.messageFor(error);
      await _service.clearToken();
      profile = null;
      activities = const <AccountActivity>[];
    } finally {
      initialized = true;
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) =>
      _authenticate(() => _service.login(username.trim(), password));

  Future<bool> register(String username, String password) =>
      _authenticate(() => _service.register(username.trim(), password));

  Future<void> refreshProfile() async {
    if (AuthService.accessToken == null || !ApiConfig.hasValidBaseUrl) return;
    try {
      profile = await _service.getProfile();
      errorMessage = null;
      try {
        activities = await _service.getActivities();
      } catch (error) {
        // 余额与次数仍可正常显示，用户可以稍后下拉重试明细。
        errorMessage = ErrorHandler.messageFor(error);
      }
      notifyListeners();
    } catch (error) {
      errorMessage = ErrorHandler.messageFor(error);
      notifyListeners();
    }
  }

  Future<void> logout() async {
    loading = true;
    notifyListeners();
    await _service.logout();
    profile = null;
    activities = const <AccountActivity>[];
    loading = false;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> _authenticate(Future<AuthResult> Function() operation) async {
    if (loading) return false;
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final AuthResult result = await operation();
      profile = result.profile;
      try {
        activities = await _service.getActivities();
      } catch (error) {
        // 登录成功优先，明细接口短暂失败不阻断进入首页。
        errorMessage = ErrorHandler.messageFor(error);
      }
      return true;
    } catch (error) {
      errorMessage = ErrorHandler.messageFor(error);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
