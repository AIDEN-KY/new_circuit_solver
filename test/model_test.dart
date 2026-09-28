import 'package:circuit_solver/models/ask_request.dart';
import 'package:circuit_solver/models/account_activity.dart';
import 'package:circuit_solver/models/ask_response.dart';
import 'package:circuit_solver/models/backend_health.dart';
import 'package:circuit_solver/models/app_config.dart';
import 'package:circuit_solver/models/chat_message.dart';
import 'package:circuit_solver/models/history_item.dart';
import 'package:circuit_solver/models/spice_netlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AskRequest uses backend field names', () {
    const AskRequest request = AskRequest(
      imageBase64: 'data:image/jpeg;base64,abc',
      cropBox: <String, num>{'x': 1, 'y': 2, 'w': 3, 'h': 4},
      rotationDegrees: 0,
      clientRequestId: 'request-0001',
    );
    expect(request.toJson()['image_base64'], startsWith('data:image/jpeg'));
    expect(request.toJson()['subject'], 'circuit');
    expect(request.toJson()['client_request_id'], 'request-0001');
  });

  test('AskRequest serializes the three input modes', () {
    const AskRequest request = AskRequest(
      imageBase64: '',
      cropBox: <String, num>{'x': 0, 'y': 0, 'w': 1, 'h': 1},
      rotationDegrees: 90,
      inputMode: 'interactive',
      description: '',
      clarificationText: 'R2=20Ω',
    );
    final Map<String, dynamic> json = request.toJson();
    expect(json['input_mode'], 'interactive');
    expect(json['clarification_text'], 'R2=20Ω');
    expect(AskRequest.fromJson(json).inputMode, 'interactive');
  });

  test('AskResponse keeps validated SPICE netlist', () {
    final AskResponse response = AskResponse.fromJson(<String, dynamic>{
      'request_id': 'req_netlist',
      'source': 'ai',
      'confidence': 'high',
      'final_answer': 'I=1A',
      'steps': <dynamic>[],
      'knowledge_points': <dynamic>[],
      'unit_check': <String, dynamic>{'passed': true},
      'similar_questions': <dynamic>[],
      'uncertain': <dynamic>[],
      'disclaimer': '',
      'netlist': <String, dynamic>{
        'raw': 'V1 in 0 DC 12\nR1 in 0 12\n.op\n.end',
        'elements': <String>['V1 in 0 DC 12', 'R1 in 0 12'],
        'validation_passed': true,
        'validation_messages': <dynamic>[],
      },
    });
    expect(response.netlist.validationPassed, isTrue);
    expect(SpiceNetlist.fromJson(response.netlist.toJson()).raw, contains('.end'));
  });

  test('AskResponse parses nested values', () {
    final AskResponse response = AskResponse.fromJson(<String, dynamic>{
      'request_id': 'req_1',
      'source': 'ai',
      'confidence': 'high',
      'final_answer': 'I = 1A',
      'final_answer_latex': 'I = 1A',
      'steps': <Map<String, dynamic>>[
        <String, dynamic>{
          'step_number': 1,
          'title': '计算',
          'content': '使用欧姆定律',
          'latex': 'I=U/R',
        },
      ],
      'knowledge_points': <String>['欧姆定律'],
      'unit_check': <String, dynamic>{
        'expected_unit': 'A',
        'actual_unit': 'A',
        'passed': true,
        'note': '',
      },
      'similar_questions': <dynamic>[],
      'uncertain': <dynamic>[],
      'disclaimer': '请核对',
    });
    expect(response.steps.single.stepNumber, 1);
    expect(response.unitCheck.passed, isTrue);
  });

  test('BackendHealth parses safe service status', () {
    final BackendHealth health = BackendHealth.fromJson(<String, dynamic>{
      'status': 'ok',
      'version': '0.2.0',
      'ai_provider': 'deepseek',
      'ai_model': 'deepseek-flash',
      'ai_configured': true,
      'library_questions': 0,
      'auth_required': true,
    });
    expect(health.isReady, isTrue);
    expect(health.aiProvider, 'deepseek');
    expect(health.libraryQuestions, 0);
    expect(health.authRequired, isTrue);
  });

  test('HistoryItem keeps the complete result and crop context', () {
    final AskResponse response = AskResponse.fromJson(<String, dynamic>{
      'request_id': 'req_history',
      'source': 'ai',
      'confidence': 'medium',
      'final_answer': 'U = 7V',
      'final_answer_latex': r'U=7\mathrm{V}',
      'steps': <dynamic>[],
      'knowledge_points': <dynamic>[],
      'unit_check': <String, dynamic>{
        'expected_unit': 'V',
        'actual_unit': 'V',
        'passed': true,
        'note': '',
      },
      'similar_questions': <dynamic>[],
      'uncertain': <dynamic>[],
      'disclaimer': '请核对',
    });
    final HistoryItem restored = HistoryItem.fromJson(
      HistoryItem(
        id: 'history_1',
        imagePath: '/tmp/question.jpg',
        finalAnswer: response.finalAnswer,
        createdAt: DateTime(2026, 9, 27),
        response: response,
        cropBox: const <String, num>{'x': 1, 'y': 2, 'w': 3, 'h': 4},
        rotationDegrees: 90,
      ).toJson(),
    );
    expect(restored.response?.requestId, 'req_history');
    expect(restored.cropBox?['w'], 3);
    expect(restored.rotationDegrees, 90);
  });

  test('ChatMessage uses backend roles', () {
    const ChatMessage message = ChatMessage(role: 'user', content: 'R2 是 20Ω');
    expect(ChatMessage.fromJson(message.toJson()).isUser, isTrue);
  });

  test('AccountActivity parses server-side quota changes', () {
    final AccountActivity activity = AccountActivity.fromJson(
      <String, dynamic>{
        'id': 1,
        'event_type': 'register_bonus',
        'free_uses_delta': 3,
        'balance_fen_delta': 0,
        'created_at': 1790438400,
      },
    );
    expect(activity.title, '新用户赠送');
    expect(activity.freeUsesDelta, 3);
    expect(activity.isPositive, isTrue);
  });

  test('AppConfig parses dynamic announcement and version policy', () {
    final AppConfigModel config = AppConfigModel.fromJson(<String, dynamic>{
      'announcement_enabled': true,
      'announcement_title': '内测公告',
      'announcement_message': '测试期间请反馈问题',
      'maintenance_mode': false,
      'maintenance_message': '维护中',
      'support_message': '联系管理员',
      'qq_group': '123456',
      'initial_free_uses': 3,
      'min_supported_version': '1.7.0',
      'latest_version': '1.7.0',
      'download_url': 'https://example.test/app.apk',
      'revision': 2,
    });
    expect(config.announcementEnabled, isTrue);
    expect(config.minSupportedVersion, '1.7.0');
    expect(config.revision, 2);
  });
}
