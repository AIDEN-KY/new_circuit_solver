import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/ask_provider.dart';
import '../widgets/mixed_latex_text.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String message = _controller.text.trim();
    if (message.isEmpty) return;
    _controller.clear();
    await context.read<AskProvider>().sendChat(message);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AskProvider>(
      builder: (BuildContext context, AskProvider provider, Widget? child) {
        return Scaffold(
          appBar: AppBar(title: const Text('继续追问')),
          body: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                Expanded(child: _messages(provider)),
                _composer(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _messages(AskProvider provider) {
    final List<ChatMessage> messages = provider.chatMessages;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            '你可以补充看不清的阻值、方向或题目条件，也可以要求 AI 重新核对某一步。AI 会结合原题图片和当前答案继续分析。',
            style: TextStyle(color: Color(0xFF1E40AF), height: 1.45),
          ),
        ),
        if (provider.response?.netlist.validationPassed == true) ...<Widget>[
          const SizedBox(height: 8),
          const Row(
            children: <Widget>[
              Icon(Icons.link_rounded, size: 18, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Expanded(child: Text('本对话已绑定当前 SPICE 网表；修改参数时会先校验，再重新求解。', style: TextStyle(color: Color(0xFF1E40AF)))),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (messages.isEmpty) ...<Widget>[
          _suggestion('图中 R2 的阻值是 20Ω，请据此重新计算。'),
          _suggestion('请重新检查电路连接关系和电流方向。'),
          _suggestion('我不理解第 2 步，请详细解释。'),
        ],
        for (final ChatMessage message in messages) _bubble(message),
        if (provider.sendingChat)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: <Widget>[
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('AI 正在重新核对题目…'),
              ],
            ),
          ),
        if (provider.chatError != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(provider.chatError!, style: const TextStyle(color: Color(0xFF991B1B))),
          ),
      ],
    );
  }

  Widget _suggestion(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            label: Text(text),
            onPressed: () => _controller.text = text,
          ),
        ),
      );

  Widget _bubble(ChatMessage message) {
    final bool user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: user ? const Color(0xFF3157E7) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: user ? null : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: MixedLatexText(
          message.content,
          style: TextStyle(
            color: user ? Colors.white : const Color(0xFF334155),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _composer(AskProvider provider) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !provider.sendingChat,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '补充条件或询问解题步骤',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: '发送',
              onPressed: provider.sendingChat ? null : _send,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      );
}
