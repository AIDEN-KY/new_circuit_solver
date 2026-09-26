import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../providers/ask_provider.dart';
import '../utils/error_handler.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: ApiConfig.baseUrl);
  bool _saving = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final String text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入完整的 http:// 或 https:// 地址';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ApiConfig.updateBaseUrl(_controller.text);
      if (mounted) context.read<AskProvider>().clearBackendHealth();
      _controller.text = ApiConfig.baseUrl;
      if (mounted) {
        setState(() {
          _isError = false;
          _message = ApiConfig.baseUrl.isEmpty ? '地址已清空，真实接口暂不可用。' : '后端地址已保存。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = ErrorHandler.messageFor(error);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _save();
    if (!mounted || _isError || !ApiConfig.hasValidBaseUrl) return;
    await context.read<AskProvider>().checkBackendHealth();
  }

  @override
  Widget build(BuildContext context) {
    final AskProvider provider = context.watch<AskProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (AppEnvironment.showDeveloperTools) ...<Widget>[
                const Text('测试服务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Base URL', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      '填写服务器根地址，不要包含 /api/v1/ask。安卓模拟器访问本机可填写 '
                      'http://10.0.2.2:8000；真机需要填写电脑的局域网地址。DeepSeek密钥只配置在后端。',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _controller,
                      validator: _validate,
                      enabled: !_saving,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link_rounded),
                        hintText: '例如：https://example.com',
                      ),
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? '正在保存' : '保存设置'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving || provider.checkingBackend
                          ? null
                          : _testConnection,
                      icon: provider.checkingBackend
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: Text(
                        provider.checkingBackend ? '正在检测连接' : '保存并检测连接',
                      ),
                    ),
                  ],
                ),
                ),
                if (provider.backendHealth != null ||
                    provider.backendHealthError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _backendStatusCard(provider),
                ],
              ] else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cloud_done_outlined),
                    title: Text('在线服务'),
                    subtitle: Text('服务地址由应用统一配置，用户无需修改'),
                  ),
                ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_message!),
                ),
              ],
              const SizedBox(height: 28),
              const Text('关于应用', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Column(
                  children: <Widget>[
                    const ListTile(leading: Icon(Icons.electrical_services_rounded), title: Text('电路识图搜题'), subtitle: Text('circuit_solver')),
                    const Divider(height: 1),
                    const ListTile(leading: Icon(Icons.numbers_rounded), title: Text('版本号'), trailing: Text('1.4.0')),
                    const Divider(height: 1),
                    const ListTile(leading: Icon(Icons.school_outlined), title: Text('当前支持'), trailing: Text('电工学电路图')),
                    const Divider(height: 1),
                    ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('版本类型'), trailing: Text(AppEnvironment.versionLabel)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendStatusCard(AskProvider provider) {
    final health = provider.backendHealth;
    final bool ready = health?.isReady ?? false;
    final bool online = health != null;
    final Color color = ready
        ? const Color(0xFF15803D)
        : online
            ? const Color(0xFFB45309)
            : const Color(0xFFDC2626);
    final String title = ready
        ? '后端已连接，AI 配置完整'
        : online
            ? '后端在线，但 AI 尚未配置完整'
            : '无法连接后端';
    final String detail = health == null
        ? (provider.backendHealthError ?? '连接失败')
        : 'API ${health.version} · ${health.aiProvider}/${health.aiModel}\n'
            '可发布题库 ${health.libraryQuestions} 道';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(ready ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
