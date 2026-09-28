class SpiceNetlist {
  const SpiceNetlist({
    this.raw = '',
    this.elements = const <String>[],
    this.validationPassed = false,
    this.validationMessages = const <String>[],
  });

  final String raw;
  final List<String> elements;
  final bool validationPassed;
  final List<String> validationMessages;

  factory SpiceNetlist.fromJson(Map<String, dynamic> json) => SpiceNetlist(
        raw: json['raw'] as String? ?? '',
        elements: (json['elements'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic value) => value.toString())
            .toList(),
        validationPassed: json['validation_passed'] as bool? ?? false,
        validationMessages:
            (json['validation_messages'] as List<dynamic>? ?? <dynamic>[])
                .map((dynamic value) => value.toString())
                .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'raw': raw,
        'elements': elements,
        'validation_passed': validationPassed,
        'validation_messages': validationMessages,
      };
}
