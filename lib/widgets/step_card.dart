import 'package:flutter/material.dart';

import '../models/solution_step.dart';
import 'latex_text.dart';

class StepCard extends StatelessWidget {
  const StepCard({required this.step, super.key});

  final SolutionStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF2563EB),
            child: Text('${step.stepNumber}', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(step.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (step.content.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText(step.content, style: const TextStyle(height: 1.5, color: Color(0xFF475569))),
                ],
                if (step.latex.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: LatexText(
                      step.latex,
                      color: const Color(0xFF1E40AF),
                      fontSize: 17,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
