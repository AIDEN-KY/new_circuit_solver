class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.imagePath,
    required this.finalAnswer,
    required this.createdAt,
  });

  final String id;
  final String imagePath;
  final String finalAnswer;
  final DateTime createdAt;

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        imagePath: json['image_path'] as String? ?? '',
        finalAnswer: json['final_answer'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'image_path': imagePath,
        'final_answer': finalAnswer,
        'created_at': createdAt.toIso8601String(),
      };
}
