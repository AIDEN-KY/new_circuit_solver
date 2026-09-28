import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../models/app_config.dart';
import '../services/app_config_service.dart';

class AppConfigProvider extends ChangeNotifier {
  AppConfigProvider({AppConfigService? service})
      : _service = service ?? AppConfigService();

  final AppConfigService _service;
  AppConfigModel? config;
  bool loading = false;
  bool usingCache = false;

  bool get maintenanceMode => config?.maintenanceMode ?? false;
  bool get requiresUpgrade => config != null &&
      _compareVersions(AppEnvironment.version, config!.minSupportedVersion) < 0;
  bool get canSolve => !maintenanceMode && !requiresUpgrade;

  Future<void> initialize() async {
    config ??= await _service.loadCached();
    usingCache = config != null;
    notifyListeners();
    if (!ApiConfig.hasValidBaseUrl) return;
    loading = true;
    notifyListeners();
    try {
      config = await _service.fetch();
      usingCache = false;
    } catch (_) {
      // 网络失败时保留最近一次成功缓存，避免公告和版本策略突然消失。
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => initialize();

  static int _compareVersions(String left, String right) {
    final List<int> a = left.split('+').first.split('.').map((String value) => int.tryParse(value) ?? 0).toList();
    final List<int> b = right.split('+').first.split('.').map((String value) => int.tryParse(value) ?? 0).toList();
    for (int index = 0; index < (a.length > b.length ? a.length : b.length); index++) {
      final int av = index < a.length ? a[index] : 0;
      final int bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
