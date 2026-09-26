import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/history_item.dart';
import '../services/history_service.dart';
import '../providers/ask_provider.dart';
import '../utils/error_handler.dart';
import 'result_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  static const String routeName = '/history';

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _service = HistoryService.instance;
  List<HistoryItem> _items = <HistoryItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<HistoryItem> items = await _service.getHistory();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = ErrorHandler.messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(HistoryItem item) async {
    setState(() {
      _items.removeWhere((HistoryItem value) => value.id == item.id);
      _error = null;
    });
    try {
      await _service.deleteHistory(item.id);
    } catch (error) {
      if (mounted) {
        setState(() => _error = ErrorHandler.messageFor(error));
        await _load();
      }
    }
  }

  Future<void> _clear() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('清空历史记录'),
            content: const Text('全部历史记录和应用内保存的图片都会被删除。'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await _service.clearHistory();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = ErrorHandler.messageFor(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: <Widget>[
          if (_items.isNotEmpty)
            IconButton(onPressed: _clear, tooltip: '清空', icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _centerState(
        Icons.error_outline_rounded,
        '历史记录加载失败',
        _error!,
        ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('重试')),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 120),
            _centerState(Icons.history_rounded, '还没有历史记录', '完成一次识别后，答案和题目图片会保存在这里。', null),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_error == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          if (_error != null && index == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFEF2F2),
              child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B))),
            );
          }
          final HistoryItem item = _items[index - (_error == null ? 0 : 1)];
          return Dismissible(
            key: ValueKey<String>(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) => _delete(item),
            child: _card(item),
          );
        },
      ),
    );
  }

  Widget _card(HistoryItem item) {
    final File file = File(item.imagePath);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        context.read<AskProvider>().openHistory(item);
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const ResultPage()),
        );
      },
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 86,
              height: 86,
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _missingImage())
                  : _missingImage(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('求解答案', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                const SizedBox(height: 5),
                Text(item.finalAnswer, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 9),
                Text(_date(item.createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
      ),
    );
  }

  Widget _missingImage() => const ColoredBox(
        color: Color(0xFFF1F5F9),
        child: Center(child: Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8))),
      );

  Widget _centerState(IconData icon, String title, String message, Widget? action) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 62, color: const Color(0xFF94A3B8)),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
              if (action != null) ...<Widget>[const SizedBox(height: 20), action],
            ],
          ),
        ),
      );

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
