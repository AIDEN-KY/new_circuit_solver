class SolutionStep {
  const SolutionStep({
    required this.stepNumber,
    required this.title,
    required this.content,
    required this.latex,
  });

  final int stepNumber;
  final String title;
  final String content;
  final String latex;

  factory SolutionStep.fromJson(Map<String, dynamic> json) => SolutionStep(
        stepNumber: (json['step_number'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        latex: json['latex'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'step_number': stepNumber,
        'title': title,
        'content': content,
        'latex': latex,
      };
}
