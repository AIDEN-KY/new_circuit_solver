import 'package:flutter/foundation.dart';

/// 集中区分内部测试版与正式用户版，避免把调试入口暴露给普通用户。
class AppEnvironment {
  AppEnvironment._();

  static const String name = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'tester' : 'developer',
  );

  static const String productionBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isProduction => name == 'production';

  static bool get isTester => name == 'tester';

  static bool get showDeveloperTools => !isProduction;

  static String get versionLabel => isProduction ? '正式版' : '内部测试版';
}
