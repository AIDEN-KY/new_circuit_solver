import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/account_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/settings_page.dart';
import 'pages/splash_page.dart';
import 'providers/ask_provider.dart';
import 'providers/auth_provider.dart';

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, AskProvider>(
          create: (_) => AskProvider(),
          update: (_, AuthProvider auth, AskProvider? ask) {
            final AskProvider provider = ask ?? AskProvider();
            provider.onRealAskSucceeded = auth.refreshProfile;
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: '电路识图搜题',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3157E7),
            primary: const Color(0xFF3157E7),
            secondary: const Color(0xFF00A58E),
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Color(0xFFF5F7FB),
            foregroundColor: Color(0xFF172033),
            titleTextStyle: TextStyle(
              color: Color(0xFF172033),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFDCE2EF)),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF3157E7),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFFE8EDFF),
            elevation: 0,
          ),
        ),
        initialRoute: SplashPage.routeName,
        routes: <String, WidgetBuilder>{
          SplashPage.routeName: (_) => const SplashPage(),
          HomePage.routeName: (_) => const HomePage(),
          HistoryPage.routeName: (_) => const HistoryPage(),
          SettingsPage.routeName: (_) => const SettingsPage(),
          LoginPage.routeName: (_) => const LoginPage(),
          RegisterPage.routeName: (_) => const RegisterPage(),
          AccountPage.routeName: (_) => const AccountPage(),
        },
      ),
    );
  }
}
