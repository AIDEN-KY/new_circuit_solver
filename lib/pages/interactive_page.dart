import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ask_provider.dart';
import 'loading_page.dart';

class InteractivePage extends StatefulWidget {
  const InteractivePage({required this.imagePath, required this.cropBox, required this.rotationDegrees, super.key});

  final String imagePath;
  final Map<String, num> cropBox;
  final int rotationDegrees;

  @override
  State<InteractivePage> createState() => _InteractivePageState();
}

class _InteractivePageState extends State<InteractivePage> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _answers = <String>[];
  static const List<String> _questions = <String>[
    '题目要求求什么量？',
    '请补充电源、元件数值和单位。',
    '请描述元件之间的连接关系或电流方向。',
  ];

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _addAnswer() {
    final String value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() { _answers.add(value); _controller.clear(); });
  }

  Future<void> _finish() async {
    if (_answers.isEmpty) return;
    context.read<AskProvider>().prepareQuestion(
      imagePath: widget.imagePath,
      cropBox: widget.cropBox,
      rotationDegrees: widget.rotationDegrees,
      inputMode: 'interactive',
      clarificationText: _answers.join('\n'),
    );
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const LoadingPage()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('补充电路信息')),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(_questions[_answers.length.clamp(0, _questions.length - 1).toInt()], style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      if (_answers.isNotEmpty) ..._answers.map((String value) => Card(child: ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(value)))),
      const Spacer(),
      TextField(controller: _controller, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: '补充一条信息', hintText: '例如：R2=20Ω，电流方向向左')),
      const SizedBox(height: 10),
      Row(children: <Widget>[Expanded(child: OutlinedButton(onPressed: _addAnswer, child: const Text('继续补充'))), const SizedBox(width: 12), Expanded(child: ElevatedButton(onPressed: _answers.isEmpty ? null : _finish, child: const Text('生成网表并求解')))]),
    ]))),
  );
}
