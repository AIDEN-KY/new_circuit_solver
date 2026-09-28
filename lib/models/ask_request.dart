class AskRequest {
  const AskRequest({
    required this.imageBase64,
    required this.cropBox,
    required this.rotationDegrees,
    this.subject = 'circuit',
    this.inputMode = 'photo',
    this.description = '',
    this.clarificationText = '',
    this.clientRequestId,
  });

  final String imageBase64;
  final Map<String, num> cropBox;
  final int rotationDegrees;
  final String subject;
  final String inputMode;
  final String description;
  final String clarificationText;
  final String? clientRequestId;

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
      inputMode: json['input_mode'] as String? ?? 'photo',
      description: json['description'] as String? ?? '',
      clarificationText: json['clarification_text'] as String? ?? '',
      clientRequestId: json['client_request_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'image_base64': imageBase64,
        'crop_box': cropBox,
        'rotation_degrees': rotationDegrees,
        'subject': subject,
        'input_mode': inputMode,
        'description': description,
        'clarification_text': clarificationText,
        if (clientRequestId != null) 'client_request_id': clientRequestId,
      };
}
