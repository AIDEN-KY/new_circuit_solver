import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'home_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool success = await context
        .read<AuthProvider>()
        .register(_username.text, _password.text);
    if (!mounted || !success) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      HomePage.routeName,
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const Text(
              '注册即赠送3次真实搜题',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '测试阶段使用用户名登录。请设置不易猜测的密码。',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            if (auth.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(auth.errorMessage!),
              ),
            ],
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _username,
                    enabled: !auth.loading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                      helperText: '3—32位，可使用中英文、数字、_ 和 -',
                    ),
                    validator: (String? value) {
                      final String text = value?.trim() ?? '';
                      if (text.length < 3 || text.length > 32) {
                        return '用户名长度应为3—32位';
                      }
                      if (!RegExp(r'^[A-Za-z0-9_\-\u4e00-\u9fff]+$')
                          .hasMatch(text)) {
                        return '用户名包含不支持的字符';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !auth.loading,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirm,
                    enabled: !auth.loading,
                    obscureText: _obscure,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '确认密码',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                    validator: (String? value) =>
                        value != _password.text ? '两次输入的密码不一致' : null,
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: auth.loading ? null : _submit,
                    child: auth.loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('注册并登录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
