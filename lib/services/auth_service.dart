import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../models/account_profile.dart';
import '../models/account_activity.dart';
import '../utils/error_handler.dart';

class AuthResult {
  const AuthResult({required this.token, required this.profile});

  final String token;
  final AccountProfile profile;
}

class AuthService {
  AuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: ApiConfig.connectTimeout,
              sendTimeout: ApiConfig.sendTimeout,
              receiveTimeout: const Duration(seconds: 30),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
              headers: const <String, dynamic>{'Accept': 'application/json'},
            ));

  static const String _tokenKey = 'account_access_token';
  static String? accessToken;

  final Dio _dio;

  static Map<String, dynamic> get authorizationHeaders {
    final String? token = accessToken;
    return <String, dynamic>{
      'X-App-Version': AppEnvironment.version,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<String?> loadToken() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    accessToken = preferences.getString(_tokenKey);
    return accessToken;
  }

  Future<AuthResult> register(String username, String password) =>
      _authenticate(ApiConfig.registerUrl, username, password);

  Future<AuthResult> login(String username, String password) =>
      _authenticate(ApiConfig.loginUrl, username, password);

  Future<AccountProfile> getProfile() async {
    _requireConfiguration();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConfig.accountUrl,
        options: Options(headers: authorizationHeaders),
      );
      return AccountProfile.fromJson(_parseResponse(response.data));
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<List<AccountActivity>> getActivities() async {
    _requireConfiguration();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConfig.accountActivitiesUrl,
        options: Options(headers: authorizationHeaders),
      );
      final dynamic data = response.data;
      if (data is! List) {
        throw const AppException('服务器返回的账户明细格式不正确。');
      }
      return data
          .whereType<Map>()
          .map((Map item) => AccountActivity.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
    } catch (error) {
      if (error is AppException) rethrow;
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<void> logout() async {
    try {
      if (ApiConfig.hasValidBaseUrl && accessToken != null) {
        await _dio.post<dynamic>(
          ApiConfig.logoutUrl,
          options: Options(headers: authorizationHeaders),
        );
      }
    } catch (_) {
      // 服务端暂时不可达时也允许清除本机会话。
    } finally {
      await clearToken();
    }
  }

  Future<void> clearToken() async {
    accessToken = null;
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
  }

  Future<AuthResult> _authenticate(
    String url,
    String username,
    String password,
  ) async {
    _requireConfiguration();
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        url,
        data: <String, dynamic>{'username': username, 'password': password},
        options: Options(headers: authorizationHeaders),
      );
      final Map<String, dynamic> json = _parseResponse(response.data);
      final String token = json['access_token'] as String? ?? '';
      if (token.isEmpty || json['account'] is! Map) {
        throw const AppException('服务器返回的登录信息不完整。');
      }
      accessToken = token;
      final SharedPreferences preferences = await SharedPreferences.getInstance();
      await preferences.setString(_tokenKey, token);
      return AuthResult(
        token: token,
        profile: AccountProfile.fromJson(
          Map<String, dynamic>.from(json['account'] as Map),
        ),
      );
    } catch (error) {
      if (error is AppException) rethrow;
      throw ErrorHandler.toAppException(error);
    }
  }

  void _requireConfiguration() {
    if (!ApiConfig.hasValidBaseUrl) {
      throw const AppException('尚未配置有效的后端地址，请先前往设置。');
    }
  }

  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      final dynamic decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const AppException('服务器返回的数据格式不正确。');
  }
}
