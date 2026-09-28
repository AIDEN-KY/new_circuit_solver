import 'package:shared_preferences/shared_preferences.dart';

import 'app_environment.dart';

class ApiConfig {
  ApiConfig._();

  static const String _baseUrlKey = 'api_base_url';
  static const String _useMockKey = 'use_mock_data';
  static const String _testerRealModeMigrationKey =
      'tester_real_mode_migration_v1';

  static String baseUrl = '';
  static bool useMock = true;

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
  // 本地视觉模型在低配置电脑上可能需要数分钟，连接与上传仍保持 30 秒限制。
  static const Duration receiveTimeout = Duration(minutes: 8);

  static String get askUrl => '$baseUrl/api/v1/ask';
  static String get healthUrl => '$baseUrl/api/v1/health';
  static String get appConfigUrl => '$baseUrl/api/v1/app-config';
  static String get chatUrl => '$baseUrl/api/v1/chat';
  static String get registerUrl => '$baseUrl/api/v1/auth/register';
  static String get loginUrl => '$baseUrl/api/v1/auth/login';
  static String get logoutUrl => '$baseUrl/api/v1/auth/logout';
  static String get accountUrl => '$baseUrl/api/v1/account/me';
  static String get accountActivitiesUrl =>
      '$baseUrl/api/v1/account/activities';

  static bool get hasValidBaseUrl {
    final Uri? uri = Uri.tryParse(baseUrl);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<void> initialize() async {
    if (AppEnvironment.isProduction) {
      baseUrl = _normalize(AppEnvironment.productionBaseUrl);
      useMock = false;
      return;
    }
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    baseUrl = _normalize(preferences.getString(_baseUrlKey) ?? '');
    // 测试包默认走真实后端，避免用户已经配置 DeepSeek 却无意间看到固定 Mock 答案。
    // 开发调试包仍保留 Mock 默认值，便于离线开发和 UI 调试。
    // 1.6.0 之前的测试包可能已经保存了 Mock 状态，这里只迁移一次；
    // 迁移完成后用户仍可在首页手动切回 Mock 模式。
    final bool migrated =
        preferences.getBool(_testerRealModeMigrationKey) ?? false;
    if (AppEnvironment.isTester && !migrated) {
      await preferences.setBool(_useMockKey, false);
      await preferences.setBool(_testerRealModeMigrationKey, true);
      useMock = false;
    } else {
      useMock = preferences.getBool(_useMockKey) ?? !AppEnvironment.isTester;
    }
  }

  static Future<void> updateBaseUrl(String value) async {
    if (AppEnvironment.isProduction) {
      throw StateError('正式版不允许修改服务地址');
    }
    final String normalized = _normalize(value);
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, normalized);
    baseUrl = normalized;
  }

  static Future<void> updateUseMock(bool value) async {
    if (AppEnvironment.isProduction) {
      throw StateError('正式版不允许切换 Mock 模式');
    }
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setBool(_useMockKey, value);
    useMock = value;
  }

  static String _normalize(String value) {
    String result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
