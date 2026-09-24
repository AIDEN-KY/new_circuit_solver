import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'providers/ask_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ApiConfig.initialize();
  } catch (_) {
    // 配置读取失败时仍以默认 Mock 模式启动。
  }
  runApp(const CircuitSolverApp());
}

class CircuitSolverApp extends StatelessWidget {
  const CircuitSolverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AskProvider>(
      create: (_) => AskProvider(),
      child: MaterialApp(
        title: '电路识图搜题',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Color(0xFF0F172A),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        initialRoute: SplashPage.routeName,
        routes: <String, WidgetBuilder>{
          SplashPage.routeName: (_) => const SplashPage(),
          HomePage.routeName: (_) => const HomePage(),
          HistoryPage.routeName: (_) => const HistoryPage(),
          SettingsPage.routeName: (_) => const SettingsPage(),
        },
      ),
    );
  }
}
