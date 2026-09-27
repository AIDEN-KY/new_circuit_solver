import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../providers/ask_provider.dart';
import '../providers/auth_provider.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'settings_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  static const String routeName = '/login';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool success = await context
        .read<AuthProvider>()
        .login(_username.text, _password.text);
    if (!mounted || !success) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      HomePage.routeName,
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _useMock() async {
    await context.read<AskProvider>().setUseMock(true);
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      HomePage.routeName,
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _openSettings() async {
    await Navigator.pushNamed(context, SettingsPage.routeName);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: <Widget>[
          IconButton(
            tooltip: '服务设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.electrical_services_rounded,
                        size: 64, color: Color(0xFF3157E7)),
                    const SizedBox(height: 18),
                    const Text(
                      '欢迎回来',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '登录后使用服务端题库与 AI 搜题',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    if (!ApiConfig.hasValidBaseUrl) ...<Widget>[
                      const SizedBox(height: 18),
                      _notice('尚未配置后端地址，请先点击右上角设置。'),
                    ],
                    if (auth.errorMessage != null) ...<Widget>[
                      const SizedBox(height: 18),
                      _notice(auth.errorMessage!, error: true),
                    ],
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _username,
                      enabled: !auth.loading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (String? value) {
                        final int length = value?.trim().length ?? 0;
                        return length < 3 ? '用户名至少3个字符' : null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !auth.loading,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (String? value) =>
                          (value?.length ?? 0) < 8 ? '密码至少8个字符' : null,
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: auth.loading || !ApiConfig.hasValidBaseUrl
                          ? null
                          : _submit,
                      child: auth.loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('登录'),
                    ),
                    TextButton(
                      onPressed: auth.loading
                          ? null
                          : () => Navigator.pushNamed(
                                context,
                                RegisterPage.routeName,
                              ),
                      child: const Text('没有账号？注册并领取3次免费搜题'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: auth.loading ? null : _useMock,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('进入 Mock 演示模式'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text),
      );
}
