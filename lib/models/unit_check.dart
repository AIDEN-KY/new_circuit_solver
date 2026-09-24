class UnitCheck {
  const UnitCheck({
    required this.expectedUnit,
    required this.actualUnit,
    required this.passed,
    required this.note,
  });

  final String expectedUnit;
  final String actualUnit;
  final bool passed;
  final String note;

  factory UnitCheck.fromJson(Map<String, dynamic> json) => UnitCheck(
        expectedUnit: json['expected_unit'] as String? ?? '',
        actualUnit: json['actual_unit'] as String? ?? '',
        passed: json['passed'] as bool? ?? false,
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'expected_unit': expectedUnit,
        'actual_unit': actualUnit,
        'passed': passed,
        'note': note,
      };
}
