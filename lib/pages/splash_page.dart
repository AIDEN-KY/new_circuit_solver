import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/app_config_provider.dart';
import 'home_page.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const String routeName = '/';

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _openHome();
  }

  Future<void> _openHome() async {
    await Future.wait<void>(<Future<void>>[
      Future<void>.delayed(const Duration(seconds: 2)),
      context.read<AuthProvider>().initialize(),
      context.read<AppConfigProvider>().initialize(),
    ]);
    if (!mounted) return;
    final AuthProvider auth = context.read<AuthProvider>();
    await Navigator.of(context).pushReplacementNamed(
      ApiConfig.useMock || auth.isAuthenticated
          ? HomePage.routeName
          : LoginPage.routeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF2563EB),
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Icon(
                    Icons.electrical_services_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
              SizedBox(height: 24),
              Text(
                '电路识图搜题',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 8),
              Text(
                '拍下电路题，快速查看求解步骤',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              SizedBox(height: 34),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                '正在检查应用配置',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
