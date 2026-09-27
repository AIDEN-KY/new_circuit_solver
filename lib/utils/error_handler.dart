import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ErrorHandler {
  ErrorHandler._();

  static String messageFor(Object error) => toAppException(error).message;

  static AppException toAppException(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return _fromDio(error);
    if (error is SocketException) {
      return const AppException('网络连接失败，请检查网络后重试。');
    }
    if (error is FileSystemException) {
      return const AppException('本地文件读写失败，请检查存储空间。');
    }
    if (error is PlatformException) {
      const Set<String> cameraCodes = <String>{
        'camera_access_denied',
        'camera_access_denied_without_prompt',
        'camera_access_restricted',
      };
      const Set<String> photoCodes = <String>{
        'photo_access_denied',
        'photo_access_restricted',
      };
      if (cameraCodes.contains(error.code)) {
        return const AppException('没有相机权限，请在系统设置中允许使用相机。');
      }
      if (photoCodes.contains(error.code)) {
        return const AppException('没有相册权限，请在系统设置中允许访问照片。');
      }
      return AppException(error.message ?? '系统操作失败，请稍后重试。');
    }
    if (error is FormatException) {
      return const AppException('图片或服务器数据格式不正确。');
    }
    return const AppException('操作失败，请稍后重试。');
  }

  static AppException _fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return const AppException('连接服务器超时，请检查网络。');
      case DioExceptionType.sendTimeout:
        return const AppException('图片上传超时，请检查网络。');
      case DioExceptionType.receiveTimeout:
        return const AppException('服务器响应超时，请稍后重试。');
      case DioExceptionType.transformTimeout:
        return const AppException('服务器数据处理超时，请稍后重试。');
      case DioExceptionType.connectionError:
        return const AppException('无法连接服务器，请检查网络和后端地址。');
      case DioExceptionType.badCertificate:
        return const AppException('服务器证书校验失败。');
      case DioExceptionType.cancel:
        return const AppException('请求已取消。');
      case DioExceptionType.badResponse:
        final int? code = error.response?.statusCode;
        final String? serverMessage = _serverMessage(error.response?.data);
        if (code == 400) {
          return AppException(serverMessage ?? '请求参数无效，请重新框选。');
        }
        if (code == 401) return AppException(serverMessage ?? '登录已失效，请重新登录。');
        if (code == 402) {
          return AppException(serverMessage ?? '剩余搜题次数不足，请联系内测管理员。');
        }
        if (code == 403) return const AppException('当前账号无权执行此操作。');
        if (code == 409) return AppException(serverMessage ?? '该账号信息已存在。');
        if (code == 404) return const AppException('未找到识别接口，请检查后端地址。');
        if (code == 413) return const AppException('上传图片过大。');
        if (code == 429) return const AppException('请求过于频繁，请稍后再试。');
        if (code != null && code >= 500) {
          return AppException(serverMessage ?? '服务器暂时不可用，请稍后重试。');
        }
        return AppException('服务器返回异常${code == null ? '' : '（$code）'}。');
      case DioExceptionType.unknown:
        return const AppException('网络请求失败，请稍后重试。');
    }
  }

  static String? _serverMessage(dynamic data) {
    if (data is Map) {
      final dynamic detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    }
    return null;
  }
}
