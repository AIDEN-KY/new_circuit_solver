import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/ask_request.dart';
import '../models/ask_response.dart';
import '../models/backend_health.dart';
import '../utils/error_handler.dart';

class ApiService {
  ApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: ApiConfig.connectTimeout,
              sendTimeout: ApiConfig.sendTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
              headers: const <String, dynamic>{'Accept': 'application/json'},
            ));

  final Dio _dio;

  Future<BackendHealth> checkHealth() async {
    if (!ApiConfig.hasValidBaseUrl) {
      throw const AppException('尚未配置有效的后端地址，请先前往设置。');
    }
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        ApiConfig.healthUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return BackendHealth.fromJson(_parseResponse(response.data));
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<AskResponse> ask(AskRequest request) async {
    if (!ApiConfig.hasValidBaseUrl) {
      throw const AppException('尚未配置有效的后端地址，请先前往设置。');
    }
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        ApiConfig.askUrl,
        data: request.toJson(),
      );
      return AskResponse.fromJson(_parseResponse(response.data));
    } catch (error) {
      throw ErrorHandler.toAppException(error);
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
