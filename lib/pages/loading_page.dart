import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ask_provider.dart';
import 'result_page.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  AskProvider? _provider;
  bool _started = false;
  bool _navigated = false;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_provider?.isLoading ?? false)) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider ??= context.read<AskProvider>()..addListener(_onChanged);
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _provider?.submitPreparedQuestion(),
      );
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _provider?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (_provider?.status != AskStatus.success || _navigated || !mounted) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const ResultPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AskProvider>(
      builder: (BuildContext context, AskProvider provider, Widget? child) {
        return PopScope(
          canPop: !provider.isLoading,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !provider.isLoading,
              title: const Text('识别题目'),
            ),
            body: provider.status == AskStatus.error
                ? _errorState(provider)
                : _loadingState(provider),
          ),
        );
      },
    );
  }

  Widget _loadingState(AskProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 108,
                      height: 108,
                      child: CircularProgressIndicator(
                        value: provider.progress == 0 ? null : provider.progress,
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFFE2E8F0),
                      ),
                    ),
                    const Icon(Icons.electrical_services_rounded, size: 42, color: Color(0xFF2563EB)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(provider.statusMessage, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                provider.useMock
                    ? '正在准备演示结果，请稍候。'
                    : '两阶段识图和推理通常需要 30～60 秒，请保持此页面开启。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: provider.progress == 0 ? null : provider.progress),
              const SizedBox(height: 10),
              Text(
                '已用时 ${_formatElapsed(_elapsedSeconds)} · 进度为估算值',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              if (!provider.useMock) ...<Widget>[
                const SizedBox(height: 24),
                _stageList(provider),
              ],
            ],
          ),
        ),
      );

  Widget _errorState(AskProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFFDC2626)),
              const SizedBox(height: 18),
              const Text('识别失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(provider.errorMessage ?? '请稍后重试。', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  _navigated = false;
                  setState(() => _elapsedSeconds = 0);
                  provider.retry();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新识别'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.crop_rounded),
                label: const Text('返回重新框选'),
              ),
            ],
          ),
        ),
      );

  String _formatElapsed(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _stageList(AskProvider provider) {
    const List<(AskStatus, String)> stages = <(AskStatus, String)>[
      (AskStatus.uploading, '上传题目'),
      (AskStatus.recognizingCircuit, '识别题干与拓扑'),
      (AskStatus.solvingCircuit, '推导计算'),
      (AskStatus.validatingResult, '一致性检查'),
      (AskStatus.savingHistory, '保存结果'),
    ];
    final int current = stages.indexWhere(
      (item) => item.$1 == provider.status,
    );
    return Column(
      children: List<Widget>.generate(stages.length, (int index) {
        final bool completed = current >= 0 && index < current;
        final bool active = index == current;
        final Color color = completed || active
            ? const Color(0xFF3157E7)
            : const Color(0xFFCBD5E1);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: <Widget>[
              Icon(
                completed
                    ? Icons.check_circle_rounded
                    : active
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 10),
              Text(
                stages[index].$2,
                style: TextStyle(
                  color: active ? const Color(0xFF172033) : color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
