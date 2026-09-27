import '../models/ask_request.dart';
import '../models/ask_response.dart';

class MockService {
  const MockService();

  Future<AskResponse> ask(AskRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return AskResponse.fromJson(<String, dynamic>{
      'request_id': 'req_mock_${DateTime.now().millisecondsSinceEpoch}',
      'source': 'mock',
      'confidence': 'high',
      'final_answer': 'I = 0.4A',
      'final_answer_latex': r'I = 0.4\text{A}',
      'steps': <Map<String, dynamic>>[
        <String, dynamic>{
          'step_number': 1,
          'title': '识别电路',
          'content': r'图中电源电压为 $12\mathrm{V}$，$R_1=10\Omega$，$R_2=20\Omega$，两个电阻串联。',
          'latex': r'R_1 = 10\Omega,\quad R_2 = 20\Omega',
        },
        <String, dynamic>{
          'step_number': 2,
          'title': '计算总电阻',
          'content': '串联电路的总电阻等于各电阻阻值之和。',
          'latex': r'R = R_1 + R_2 = 30\Omega',
        },
        <String, dynamic>{
          'step_number': 3,
          'title': '应用欧姆定律',
          'content': '用电源电压除以总电阻，得到电路电流。',
          'latex': r'I = \frac{U}{R} = \frac{12V}{30\Omega} = 0.4A',
        },
      ],
      'knowledge_points': <String>['欧姆定律', '串联电路', '等效电阻'],
      'unit_check': <String, dynamic>{
        'expected_unit': 'A',
        'actual_unit': 'A',
        'passed': true,
        'note': '',
      },
      'similar_questions': <Map<String, dynamic>>[
        <String, dynamic>{
          'question_id': 'q_1002',
          'title': '并联电路求总电流',
          'similarity': 0.82,
        },
        <String, dynamic>{
          'question_id': 'q_1018',
          'title': '串联电路中的电压分配',
          'similarity': 0.76,
        },
      ],
      'uncertain': <String>['R2 的阻值可能为 20Ω 或 200Ω，请核对原题图片。'],
      'disclaimer': '本结果由 AI 辅助生成，请核对关键条件。',
    });
  }
}
