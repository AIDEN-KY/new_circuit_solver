class AskRequest {
  const AskRequest({
    required this.imageBase64,
    required this.cropBox,
    required this.rotationDegrees,
    this.subject = 'circuit',
  });

  final String imageBase64;
  final Map<String, num> cropBox;
  final int rotationDegrees;
  final String subject;

  factory AskRequest.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> box = Map<String, dynamic>.from(
      json['crop_box'] as Map? ?? <String, dynamic>{},
    );
    num readNumber(dynamic value) =>
        value is num ? value : num.tryParse('$value') ?? 0;

    return AskRequest(
      imageBase64: json['image_base64'] as String? ?? '',
      cropBox: <String, num>{
        'x': readNumber(box['x']),
        'y': readNumber(box['y']),
        'w': readNumber(box['w']),
        'h': readNumber(box['h']),
      },
      rotationDegrees: readNumber(json['rotation_degrees']).toInt(),
      subject: json['subject'] as String? ?? 'circuit',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'image_base64': imageBase64,
        'crop_box': cropBox,
        'rotation_degrees': rotationDegrees,
        'subject': subject,
      };
}
