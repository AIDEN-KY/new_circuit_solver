import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ask_response.dart';
import '../models/solution_step.dart';
import '../providers/ask_provider.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/latex_text.dart';
import '../widgets/similar_question_tile.dart';
import '../widgets/step_card.dart';
import 'home_page.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  static const MethodChannel _shareChannel = MethodChannel('circuit_solver/share');
  bool _sharing = false;

  String _text(AskResponse response) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('电路题求解结果')
      ..writeln()
      ..writeln('答案：${response.finalAnswer}');
    if (response.steps.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('解题步骤：');
      for (final SolutionStep step in response.steps) {
        buffer.writeln('${step.stepNumber}. ${step.title}：${step.content}');
      }
    }
    if (response.knowledgePoints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('知识点：${response.knowledgePoints.join('、')}');
    }
    if (response.disclaimer.isNotEmpty) buffer.writeln('\n${response.disclaimer}');
    return buffer.toString().trim();
  }

  Future<void> _copy(AskResponse response) async {
    await Clipboard.setData(ClipboardData(text: _text(response)));
    if (mounted) _message('答案已复制');
  }

  Future<void> _share(AskResponse response) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _shareChannel.invokeMethod<void>('shareText', <String, String>{
        'subject': '电路题求解结果',
        'text': _text(response),
      });
    } on PlatformException catch (error) {
      if (mounted) _message(error.message ?? '无法调起系统分享');
    } on MissingPluginException {
      if (mounted) _message('系统分享组件未正确配置');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _home() {
    context.read<AskProvider>().reset();
    Navigator.of(context).popUntil(
      (Route<dynamic> route) =>
          route.settings.name == HomePage.routeName || route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AskProvider>(
      builder: (BuildContext context, AskProvider provider, Widget? child) {
        final AskResponse? response = provider.response;
        return Scaffold(
          appBar: AppBar(
            title: const Text('求解结果'),
            actions: response == null
                ? null
                : <Widget>[
                    IconButton(
                      tooltip: '复制答案',
                      onPressed: () => _copy(response),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    IconButton(
                      tooltip: '分享答案',
                      onPressed: _sharing ? null : () => _share(response),
                      icon: _sharing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.share_rounded),
                    ),
                  ],
          ),
          body: response == null ? _empty(provider) : _result(provider, response),
        );
      },
    );
  }

  Widget _empty(AskProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.find_in_page_outlined, size: 64, color: Color(0xFF94A3B8)),
              const SizedBox(height: 16),
              const Text('暂无求解结果', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(provider.errorMessage ?? '请返回首页选择题目图片。'),
              const SizedBox(height: 20),
              ElevatedButton.icon(onPressed: _home, icon: const Icon(Icons.home_outlined), label: const Text('返回首页')),
            ],
          ),
        ),
      );

  Widget _result(AskProvider provider, AskResponse response) {
    return SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                _answer(response),
                if (provider.historyWarning != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _notice(provider.historyWarning!, const Color(0xFFFFFBEB), const Color(0xFF92400E)),
                ],
                if (response.steps.isNotEmpty) ...<Widget>[
                  _title(Icons.format_list_numbered_rounded, '解题步骤'),
                  for (final SolutionStep step in response.steps)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: StepCard(step: step)),
                ],
                if (response.knowledgePoints.isNotEmpty) ...<Widget>[
                  _title(Icons.menu_book_outlined, '知识点'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: response.knowledgePoints
                        .map((String value) => Chip(label: Text(value), backgroundColor: const Color(0xFFEFF6FF)))
                        .toList(),
                  ),
                ],
                _title(Icons.straighten_outlined, '单位检查'),
                _unit(response),
                if (response.uncertain.isNotEmpty) ...<Widget>[
                  _title(Icons.warning_amber_rounded, '需要核对'),
                  _notice(response.uncertain.join('\n'), const Color(0xFFFFFBEB), const Color(0xFF92400E)),
                ],
                if (response.similarQuestions.isNotEmpty) ...<Widget>[
                  _title(Icons.quiz_outlined, '相似题'),
                  for (final question in response.similarQuestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SimilarQuestionTile(question: question),
                    ),
                ],
                if (response.disclaimer.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 20),
                  _notice(response.disclaimer, const Color(0xFFF1F5F9), const Color(0xFF64748B)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
            child: Row(
              children: <Widget>[
                Expanded(child: OutlinedButton.icon(onPressed: () => _copy(response), icon: const Icon(Icons.copy_rounded), label: const Text('复制'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(onPressed: _home, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('继续搜题'))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _answer(AskResponse response) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: <Color>[Color(0xFF1D4ED8), Color(0xFF2563EB)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[const Expanded(child: Text('最终答案', style: TextStyle(color: Color(0xFFDBEAFE), fontWeight: FontWeight.w600))), ConfidenceBadge(confidence: response.confidence)]),
            const SizedBox(height: 18),
            SelectableText(response.finalAnswer.isEmpty ? '未返回明确答案' : response.finalAnswer, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            if (response.finalAnswerLatex.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              LatexText(
                response.finalAnswerLatex,
                color: Colors.white,
                fontSize: 24,
              ),
            ],
          ],
        ),
      );

  Widget _title(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Row(children: <Widget>[Icon(icon, color: const Color(0xFF2563EB)), const SizedBox(width: 8), Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
      );

  Widget _unit(AskResponse response) {
    final bool passed = response.unitCheck.passed;
    return _notice(
      '${passed ? '单位检查通过' : '单位可能不一致'}\n预期：${response.unitCheck.expectedUnit}　实际：${response.unitCheck.actualUnit}${response.unitCheck.note.isEmpty ? '' : '\n${response.unitCheck.note}'}',
      passed ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
      passed ? const Color(0xFF166534) : const Color(0xFF92400E),
    );
  }

  Widget _notice(String text, Color background, Color foreground) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: foreground, height: 1.5)),
      );
}
