import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/ask_request.dart';
import '../models/ask_response.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';
import '../services/mock_service.dart';
import '../utils/error_handler.dart';
import '../utils/image_utils.dart';

enum AskStatus { idle, preparingImage, uploading, savingHistory, success, error }

class AskProvider extends ChangeNotifier {
  AskProvider({
    ApiService? apiService,
    MockService? mockService,
    HistoryService? historyService,
  })  : _apiService = apiService ?? ApiService(),
        _mockService = mockService ?? const MockService(),
        _historyService = historyService ?? HistoryService.instance {
    unawaited(_loadQuota());
  }

  static const int dailyLimit = 5;
  static const String _dateKey = 'daily_quota_date';
  static const String _remainingKey = 'daily_quota_remaining';

  final ApiService _apiService;
  final MockService _mockService;
  final HistoryService _historyService;

  AskStatus status = AskStatus.idle;
  AskResponse? response;
  String? errorMessage;
  String? historyWarning;
  String? imagePath;
  Map<String, num>? cropBox;
  int rotationDegrees = 0;
  int dailyRemaining = dailyLimit;
  bool quotaLoaded = false;

  bool get useMock => ApiConfig.useMock;
  bool get isLoading => <AskStatus>{
        AskStatus.preparingImage,
        AskStatus.uploading,
        AskStatus.savingHistory,
      }.contains(status);

  double get progress => switch (status) {
        AskStatus.preparingImage => 0.2,
        AskStatus.uploading => 0.65,
        AskStatus.savingHistory => 0.9,
        AskStatus.success => 1,
        _ => 0,
      };

  String get statusMessage => switch (status) {
        AskStatus.preparingImage => '正在压缩题目图片',
        AskStatus.uploading => useMock ? '正在生成模拟结果' : '正在识别并求解',
        AskStatus.savingHistory => '正在保存历史记录',
        AskStatus.success => '识别完成',
        AskStatus.error => errorMessage ?? '识别失败',
        AskStatus.idle => '等待开始识别',
      };

  Future<void> setUseMock(bool value) async {
    await ApiConfig.updateUseMock(value);
    notifyListeners();
  }

  void prepareQuestion({
    required String imagePath,
    required Map<String, num> cropBox,
    int rotationDegrees = 0,
  }) {
    this.imagePath = imagePath;
    this.cropBox = Map<String, num>.from(cropBox);
    this.rotationDegrees = rotationDegrees;
    response = null;
    errorMessage = null;
    historyWarning = null;
    status = AskStatus.idle;
    notifyListeners();
  }

  Future<void> submitPreparedQuestion() async {
    if (isLoading) return;
    final String? sourcePath = imagePath;
    final Map<String, num>? selectedBox = cropBox;
    if (sourcePath == null || sourcePath.isEmpty || selectedBox == null) {
      _setError('没有可识别的题目，请返回首页重新选择。');
      return;
    }
    if (!useMock && dailyRemaining <= 0) {
      _setError('今天的 5 次真实识别额度已用完，请明天再试。');
      return;
    }

    response = null;
    errorMessage = null;
    historyWarning = null;
    status = AskStatus.preparingImage;
    notifyListeners();

    try {
      final PreparedImage image =
          await ImageUtils.compressAndEncode(sourcePath);
      final AskRequest request = AskRequest(
        imageBase64: image.dataUri,
        cropBox: _scaleCropBox(selectedBox, image),
        rotationDegrees: rotationDegrees,
        subject: 'circuit',
      );
      status = AskStatus.uploading;
      notifyListeners();
      final AskResponse result = useMock
          ? await _mockService.ask(request)
          : await _apiService.ask(request);
      response = result;
      status = AskStatus.savingHistory;
      notifyListeners();
      try {
        await _historyService.addHistory(
          id: '${result.requestId}_${DateTime.now().millisecondsSinceEpoch}',
          imagePath: image.filePath,
          finalAnswer: result.finalAnswer,
        );
      } catch (error) {
        historyWarning = '答案已生成，但历史记录保存失败：${ErrorHandler.messageFor(error)}';
      }
      if (!useMock) await _consumeQuota();
      status = AskStatus.success;
      notifyListeners();
    } catch (error) {
      _setError(ErrorHandler.messageFor(error));
    }
  }

  Future<void> retry() => submitPreparedQuestion();

  void reset() {
    status = AskStatus.idle;
    response = null;
    errorMessage = null;
    historyWarning = null;
    imagePath = null;
    cropBox = null;
    rotationDegrees = 0;
    notifyListeners();
  }

  Map<String, num> _scaleCropBox(
    Map<String, num> box,
    PreparedImage image,
  ) {
    final double scaleX = image.width / image.originalWidth;
    final double scaleY = image.height / image.originalHeight;
    final double x = (box['x'] ?? 0) * scaleX;
    final double y = (box['y'] ?? 0) * scaleY;
    final double safeX = x.clamp(0, math.max(0, image.width - 1)).toDouble();
    final double safeY = y.clamp(0, math.max(0, image.height - 1)).toDouble();
    final double width = ((box['w'] ?? 1) * scaleX)
        .clamp(1, math.max(1, image.width - safeX))
        .toDouble();
    final double height = ((box['h'] ?? 1) * scaleY)
        .clamp(1, math.max(1, image.height - safeY))
        .toDouble();
    return <String, num>{
      'x': safeX.round(),
      'y': safeY.round(),
      'w': width.round(),
      'h': height.round(),
    };
  }

  Future<void> _loadQuota() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String today = _formatDate(DateTime.now());
      if (preferences.getString(_dateKey) != today) {
        dailyRemaining = dailyLimit;
        await preferences.setString(_dateKey, today);
        await preferences.setInt(_remainingKey, dailyLimit);
      } else {
        dailyRemaining = (preferences.getInt(_remainingKey) ?? dailyLimit)
            .clamp(0, dailyLimit)
            .toInt();
      }
    } catch (_) {
      // 本地额度读取失败时使用默认值，不阻塞搜题流程。
      dailyRemaining = dailyLimit;
    } finally {
      quotaLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _consumeQuota() async {
    if (dailyRemaining <= 0) return;
    dailyRemaining--;
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(_dateKey, _formatDate(DateTime.now()));
    await preferences.setInt(_remainingKey, dailyRemaining);
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _setError(String message) {
    errorMessage = message;
    status = AskStatus.error;
    notifyListeners();
  }
}
