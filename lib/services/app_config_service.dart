import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../models/app_config.dart';

class AppConfigService {
  AppConfigService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _cacheKey = 'public_app_config_v1';
  final Dio _dio;

  Future<AppConfigModel?> loadCached() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? value = preferences.getString(_cacheKey);
    if (value == null) return null;
    try {
      return AppConfigModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<AppConfigModel> fetch() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      ApiConfig.appConfigUrl,
      options: Options(headers: const <String, dynamic>{
        'Accept': 'application/json',
        'X-App-Version': AppEnvironment.version,
      }),
    );
    final AppConfigModel value = AppConfigModel.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_cacheKey, jsonEncode(value.toJson()));
    return value;
  }
}
