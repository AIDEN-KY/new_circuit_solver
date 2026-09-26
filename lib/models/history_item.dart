import 'ask_response.dart';

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.imagePath,
    required this.finalAnswer,
    required this.createdAt,
    this.response,
    this.cropBox,
    this.rotationDegrees = 0,
  });

  final String id;
  final String imagePath;
  final String finalAnswer;
  final DateTime createdAt;
  final AskResponse? response;
  final Map<String, num>? cropBox;
  final int rotationDegrees;

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String? ?? '',
        imagePath: json['image_path'] as String? ?? '',
        finalAnswer: json['final_answer'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        response: json['response'] is Map
            ? AskResponse.fromJson(
                Map<String, dynamic>.from(json['response'] as Map),
              )
            : null,
        cropBox: json['crop_box'] is Map
            ? Map<String, num>.from(json['crop_box'] as Map)
            : null,
        rotationDegrees: (json['rotation_degrees'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'image_path': imagePath,
        'final_answer': finalAnswer,
        'created_at': createdAt.toIso8601String(),
        if (response != null) 'response': response!.toJson(),
        if (cropBox != null) 'crop_box': cropBox,
        'rotation_degrees': rotationDegrees,
      };
}
