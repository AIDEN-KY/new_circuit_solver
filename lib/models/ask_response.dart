import 'similar_question.dart';
import 'solution_step.dart';
import 'unit_check.dart';

class AskResponse {
  const AskResponse({
    required this.requestId,
    required this.source,
    required this.confidence,
    required this.finalAnswer,
    required this.finalAnswerLatex,
    required this.steps,
    required this.knowledgePoints,
    required this.unitCheck,
    required this.similarQuestions,
    required this.uncertain,
    required this.disclaimer,
  });

  final String requestId;
  final String source;
  final String confidence;
  final String finalAnswer;
  final String finalAnswerLatex;
  final List<SolutionStep> steps;
  final List<String> knowledgePoints;
  final UnitCheck unitCheck;
  final List<SimilarQuestion> similarQuestions;
  final List<String> uncertain;
  final String disclaimer;

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    List<T> parseObjects<T>(
      dynamic value,
      T Function(Map<String, dynamic>) parser,
    ) {
      final List<dynamic> values = value as List<dynamic>? ?? <dynamic>[];
      return values
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) =>
              parser(Map<String, dynamic>.from(item)))
          .toList();
    }

    List<String> parseStrings(dynamic value) =>
        (value as List<dynamic>? ?? <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList();

    return AskResponse(
      requestId: json['request_id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'low',
      finalAnswer: json['final_answer'] as String? ?? '',
      finalAnswerLatex: json['final_answer_latex'] as String? ?? '',
      steps: parseObjects(json['steps'], SolutionStep.fromJson),
      knowledgePoints: parseStrings(json['knowledge_points']),
      unitCheck: UnitCheck.fromJson(Map<String, dynamic>.from(
        json['unit_check'] as Map? ?? <String, dynamic>{},
      )),
      similarQuestions:
          parseObjects(json['similar_questions'], SimilarQuestion.fromJson),
      uncertain: parseStrings(json['uncertain']),
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'source': source,
        'confidence': confidence,
        'final_answer': finalAnswer,
        'final_answer_latex': finalAnswerLatex,
        'steps': steps.map((SolutionStep value) => value.toJson()).toList(),
        'knowledge_points': knowledgePoints,
        'unit_check': unitCheck.toJson(),
        'similar_questions': similarQuestions
            .map((SimilarQuestion value) => value.toJson())
            .toList(),
        'uncertain': uncertain,
        'disclaimer': disclaimer,
      };
}
