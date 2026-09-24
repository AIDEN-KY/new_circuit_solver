class SimilarQuestion {
  const SimilarQuestion({
    required this.questionId,
    required this.title,
    required this.similarity,
  });

  final String questionId;
  final String title;
  final double similarity;

  factory SimilarQuestion.fromJson(Map<String, dynamic> json) =>
      SimilarQuestion(
        questionId: json['question_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question_id': questionId,
        'title': title,
        'similarity': similarity,
      };
}
