import 'package:flutter/material.dart';

import '../config/api_config.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const Text('后端接口', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Base URL', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text('填写服务器根地址，不要包含 /api/v1/ask。', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
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
                  ],
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
                child: const Column(
                  children: <Widget>[
                    ListTile(leading: Icon(Icons.electrical_services_rounded), title: Text('电路识图搜题'), subtitle: Text('circuit_solver')),
                    Divider(height: 1),
                    ListTile(leading: Icon(Icons.numbers_rounded), title: Text('版本号'), trailing: Text('1.0.0')),
                    Divider(height: 1),
                    ListTile(leading: Icon(Icons.school_outlined), title: Text('当前支持'), trailing: Text('电工学电路图')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
