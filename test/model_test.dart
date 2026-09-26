import 'package:circuit_solver/models/ask_request.dart';
import 'package:circuit_solver/models/ask_response.dart';
import 'package:circuit_solver/models/backend_health.dart';
import 'package:circuit_solver/models/chat_message.dart';
import 'package:circuit_solver/models/history_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AskRequest uses backend field names', () {
    const AskRequest request = AskRequest(
      imageBase64: 'data:image/jpeg;base64,abc',
      cropBox: <String, num>{'x': 1, 'y': 2, 'w': 3, 'h': 4},
      rotationDegrees: 0,
    );
    expect(request.toJson()['image_base64'], startsWith('data:image/jpeg'));
    expect(request.toJson()['subject'], 'circuit');
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
      'library_questions': 3,
    });
    expect(health.isReady, isTrue);
    expect(health.aiProvider, 'deepseek');
    expect(health.libraryQuestions, 3);
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
}
