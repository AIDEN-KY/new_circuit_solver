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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_provider == null) {
      _provider = context.read<AskProvider>()..addListener(_onChanged);
    }
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _provider?.submitPreparedQuestion(),
      );
    }
  }

  @override
  void dispose() {
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
              const Text('正在分析电路结构和题目条件，请稍候。', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: provider.progress == 0 ? null : provider.progress),
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
}
