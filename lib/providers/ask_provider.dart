import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/ask_request.dart';
import '../models/ask_response.dart';
import '../models/backend_health.dart';
import '../models/chat_message.dart';
import '../models/history_item.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';
import '../services/mock_service.dart';
import '../utils/error_handler.dart';
import '../utils/image_utils.dart';

enum AskStatus {
  idle,
  preparingImage,
  uploading,
  recognizingCircuit,
  solvingCircuit,
  validatingResult,
  savingHistory,
  success,
  error,
}

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
  Timer? _stageTimer;

  AskStatus status = AskStatus.idle;
  AskResponse? response;
  String? errorMessage;
  String? historyWarning;
  String? imagePath;
  Map<String, num>? cropBox;
  int rotationDegrees = 0;
  int dailyRemaining = dailyLimit;
  bool quotaLoaded = false;
  BackendHealth? backendHealth;
  String? backendHealthError;
  bool checkingBackend = false;
  final List<ChatMessage> chatMessages = <ChatMessage>[];
  bool sendingChat = false;
  String? chatError;

  bool get useMock => ApiConfig.useMock;
  bool get hasQuestionContext =>
      response != null && imagePath != null && cropBox != null;
  bool get isLoading => <AskStatus>{
        AskStatus.preparingImage,
        AskStatus.uploading,
        AskStatus.recognizingCircuit,
        AskStatus.solvingCircuit,
        AskStatus.validatingResult,
        AskStatus.savingHistory,
      }.contains(status);

  double get progress => switch (status) {
        AskStatus.preparingImage => 0.2,
        AskStatus.uploading => 0.3,
        AskStatus.recognizingCircuit => 0.45,
        AskStatus.solvingCircuit => 0.68,
        AskStatus.validatingResult => 0.86,
        AskStatus.savingHistory => 0.94,
        AskStatus.success => 1,
        _ => 0,
      };

  String get statusMessage => switch (status) {
        AskStatus.preparingImage => '正在压缩题目图片',
        AskStatus.uploading => useMock ? '正在生成模拟结果' : '正在上传题目',
        AskStatus.recognizingCircuit => '正在识别题干和电路结构',
        AskStatus.solvingCircuit => '正在推导并计算答案',
        AskStatus.validatingResult => '正在检查步骤和最终答案',
        AskStatus.savingHistory => '正在保存历史记录',
        AskStatus.success => '识别完成',
        AskStatus.error => errorMessage ?? '识别失败',
        AskStatus.idle => '等待开始识别',
      };

  Future<void> setUseMock(bool value) async {
    await ApiConfig.updateUseMock(value);
    notifyListeners();
    if (!value && ApiConfig.hasValidBaseUrl) {
      unawaited(checkBackendHealth());
    }
  }

  Future<void> checkBackendHealth() async {
    if (checkingBackend) return;
    checkingBackend = true;
    backendHealth = null;
    backendHealthError = null;
    notifyListeners();
    try {
      backendHealth = await _apiService.checkHealth();
    } catch (error) {
      backendHealthError = ErrorHandler.messageFor(error);
    } finally {
      checkingBackend = false;
      notifyListeners();
    }
  }

  void clearBackendHealth() {
    backendHealth = null;
    backendHealthError = null;
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
    chatMessages.clear();
    chatError = null;
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
      final bool requestUsesMock = useMock;
      if (!requestUsesMock) _startRealProgress();
      final AskResponse result = requestUsesMock
          ? await _mockService.ask(request)
          : await _apiService.ask(request);
      _stopRealProgress();
      response = result;
      status = AskStatus.savingHistory;
      notifyListeners();
      try {
        await _historyService.addHistory(
          id: '${result.requestId}_${DateTime.now().millisecondsSinceEpoch}',
          imagePath: image.filePath,
          response: result,
          cropBox: request.cropBox,
          rotationDegrees: request.rotationDegrees,
        );
      } catch (error) {
        historyWarning = '答案已生成，但历史记录保存失败：${ErrorHandler.messageFor(error)}';
      }
      if (!requestUsesMock) {
        try {
          await _consumeQuota();
        } catch (error) {
          _appendHistoryWarning(
            '答案已生成，但本次额度记录失败：${ErrorHandler.messageFor(error)}',
          );
        }
      }
      status = AskStatus.success;
      notifyListeners();
    } catch (error) {
      _stopRealProgress();
      _setError(ErrorHandler.messageFor(error));
    }
  }

  Future<void> retry() => submitPreparedQuestion();

  void openHistory(HistoryItem item) {
    response = item.response ?? _legacyHistoryResponse(item);
    imagePath = item.imagePath;
    cropBox = item.cropBox;
    rotationDegrees = item.rotationDegrees;
    errorMessage = null;
    historyWarning = item.response == null
        ? '这是一条旧版记录，仅保存了图片和最终答案。'
        : null;
    chatMessages.clear();
    chatError = null;
    status = AskStatus.success;
    notifyListeners();
  }

  Future<void> sendChat(String value) async {
    final String message = value.trim();
    final AskResponse? original = response;
    if (message.isEmpty || sendingChat) return;
    if (original == null || imagePath == null || cropBox == null) {
      chatError = '这条记录缺少原题上下文，无法继续追问。';
      notifyListeners();
      return;
    }
    final List<ChatMessage> history = List<ChatMessage>.from(chatMessages);
    chatMessages.add(ChatMessage(role: 'user', content: message));
    sendingChat = true;
    chatError = null;
    notifyListeners();
    try {
      if (useMock) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        chatMessages.add(const ChatMessage(
          role: 'assistant',
          content: r'这是演示回复。真实模式下，我会结合原图和你的补充条件重新核对 $R_1$、$U$ 与计算结果。',
        ));
      } else {
        final AskRequest request = await _createRequest();
        final ChatMessage answer = await _apiService.chat(
          request: request,
          originalResponse: original,
          messages: history,
          message: message,
        );
        chatMessages.add(answer);
      }
    } catch (error) {
      chatError = ErrorHandler.messageFor(error);
    } finally {
      sendingChat = false;
      notifyListeners();
    }
  }

  void reset() {
    status = AskStatus.idle;
    response = null;
    errorMessage = null;
    historyWarning = null;
    chatMessages.clear();
    chatError = null;
    imagePath = null;
    cropBox = null;
    rotationDegrees = 0;
    notifyListeners();
  }

  Map<String, num> _scaleCropBox(
    Map<String, num> box,
    PreparedImage image,
  ) {
    final bool quarterTurn = rotationDegrees == 90 || rotationDegrees == 270;
    final int targetWidth = quarterTurn ? image.height : image.width;
    final int targetHeight = quarterTurn ? image.width : image.height;
    final double scaleX = quarterTurn
        ? image.height / image.originalHeight
        : image.width / image.originalWidth;
    final double scaleY = quarterTurn
        ? image.width / image.originalWidth
        : image.height / image.originalHeight;
    final double x = (box['x'] ?? 0) * scaleX;
    final double y = (box['y'] ?? 0) * scaleY;
    final double safeX = x.clamp(0, math.max(0, targetWidth - 1)).toDouble();
    final double safeY = y.clamp(0, math.max(0, targetHeight - 1)).toDouble();
    final double width = ((box['w'] ?? 1) * scaleX)
        .clamp(1, math.max(1, targetWidth - safeX))
        .toDouble();
    final double height = ((box['h'] ?? 1) * scaleY)
        .clamp(1, math.max(1, targetHeight - safeY))
        .toDouble();
    return <String, num>{
      'x': safeX.round(),
      'y': safeY.round(),
      'w': width.round(),
      'h': height.round(),
    };
  }

  Future<AskRequest> _createRequest() async {
    final PreparedImage image = await ImageUtils.compressAndEncode(imagePath!);
    return AskRequest(
      imageBase64: image.dataUri,
      cropBox: _scaleCropBox(cropBox!, image),
      rotationDegrees: rotationDegrees,
      subject: 'circuit',
    );
  }

  AskResponse _legacyHistoryResponse(HistoryItem item) => AskResponse.fromJson(
        <String, dynamic>{
          'request_id': item.id,
          'source': 'library',
          'confidence': 'low',
          'final_answer': item.finalAnswer,
          'final_answer_latex': '',
          'steps': <dynamic>[],
          'knowledge_points': <dynamic>[],
          'unit_check': <String, dynamic>{
            'expected_unit': '',
            'actual_unit': '',
            'passed': true,
            'note': '旧版历史记录未保存单位检查信息。',
          },
          'similar_questions': <dynamic>[],
          'uncertain': <dynamic>['旧版记录未保存完整解题步骤。'],
          'disclaimer': '该记录由旧版本保存，仅可查看当时的最终答案。',
        },
      );

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

  void _appendHistoryWarning(String message) {
    historyWarning = historyWarning == null
        ? message
        : '$historyWarning\n$message';
  }

  void _startRealProgress() {
    _stopRealProgress();
    int elapsedSeconds = 0;
    _stageTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      elapsedSeconds++;
      final AskStatus nextStatus = switch (elapsedSeconds) {
        >= 25 => AskStatus.validatingResult,
        >= 7 => AskStatus.solvingCircuit,
        >= 2 => AskStatus.recognizingCircuit,
        _ => AskStatus.uploading,
      };
      if (!isLoading || status == AskStatus.savingHistory) {
        _stopRealProgress();
        return;
      }
      if (status != nextStatus) {
        status = nextStatus;
        notifyListeners();
      }
    });
  }

  void _stopRealProgress() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  @override
  void dispose() {
    _stopRealProgress();
    super.dispose();
  }
}
