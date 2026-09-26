import 'package:shared_preferences/shared_preferences.dart';

import 'app_environment.dart';

class ApiConfig {
  ApiConfig._();

  static const String _baseUrlKey = 'api_base_url';
  static const String _useMockKey = 'use_mock_data';

  static String baseUrl = '';
  static bool useMock = true;

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
  // 本地视觉模型在低配置电脑上可能需要数分钟，连接与上传仍保持 30 秒限制。
  static const Duration receiveTimeout = Duration(minutes: 8);

  static String get askUrl => '$baseUrl/api/v1/ask';

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
    useMock = preferences.getBool(_useMockKey) ?? true;
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
