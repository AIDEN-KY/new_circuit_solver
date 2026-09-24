import 'package:flutter/material.dart';

class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({required this.confidence, super.key});

  final String confidence;

  @override
  Widget build(BuildContext context) {
    final (String, Color, Color) style = switch (confidence) {
      'high' => ('高置信度', const Color(0xFF166534), const Color(0xFFDCFCE7)),
      'medium' => ('中等置信度', const Color(0xFF92400E), const Color(0xFFFEF3C7)),
      'low' => ('低置信度', const Color(0xFF991B1B), const Color(0xFFFEE2E2)),
      _ => ('置信度未知', const Color(0xFF475569), const Color(0xFFE2E8F0)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.$3,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        style.$1,
        style: TextStyle(color: style.$2, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
