import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ask_provider.dart';
import 'loading_page.dart';

class DescriptionPage extends StatefulWidget {
  const DescriptionPage({required this.imagePath, required this.cropBox, required this.rotationDegrees, super.key});

  final String imagePath;
  final Map<String, num> cropBox;
  final int rotationDegrees;

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    context.read<AskProvider>().prepareQuestion(
          imagePath: widget.imagePath,
          cropBox: widget.cropBox,
          rotationDegrees: widget.rotationDegrees,
          inputMode: 'description',
          description: text,
        );
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const LoadingPage()));
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('补充题目描述')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('图片识别不清时，请描述元件、连接关系和已知数值。', style: TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 16),
              Expanded(child: TextField(controller: _controller, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(hintText: '例如：电源12V，R1和R2串联，求R2电流…', alignLabelWithHint: true))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _submitting ? null : _submit, icon: const Icon(Icons.auto_awesome), label: const Text('生成网表并开始求解'))),
            ]),
          ),
        ),
      );
}
