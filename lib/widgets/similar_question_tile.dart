import 'package:flutter/material.dart';

import '../models/similar_question.dart';

class SimilarQuestionTile extends StatelessWidget {
  const SimilarQuestionTile({required this.question, super.key});

  final SimilarQuestion question;

  @override
  Widget build(BuildContext context) {
    final int percent = (question.similarity.clamp(0, 1) * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            backgroundColor: Color(0xFFEFF6FF),
            child: Icon(Icons.quiz_outlined, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(question.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(question.questionId, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Text('$percent%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        ],
      ),
    );
  }
}
