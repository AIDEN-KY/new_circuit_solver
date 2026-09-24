import 'package:circuit_solver/models/ask_request.dart';
import 'package:circuit_solver/models/ask_response.dart';
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
}
