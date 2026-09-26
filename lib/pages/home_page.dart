import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../providers/ask_provider.dart';
import '../utils/error_handler.dart';
import 'crop_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const String routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;
  bool _isUpdatingMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ApiConfig.useMock || !ApiConfig.hasValidBaseUrl) return;
      context.read<AskProvider>().checkBackendHealth();
    });
  }

  Future<void> _pick(ImageSource source) async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 100,
        requestFullMetadata: false,
      );
      if (!mounted || file == null) return;
      context.read<AskProvider>().reset();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CropPage(imagePath: file.path),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = ErrorHandler.messageFor(error));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _setMock(bool value) async {
    if (_isUpdatingMode) return;
    setState(() {
      _isUpdatingMode = true;
      _error = null;
    });
    try {
      await context.read<AskProvider>().setUseMock(value);
    } catch (error) {
      if (mounted) setState(() => _error = ErrorHandler.messageFor(error));
    } finally {
      if (mounted) setState(() => _isUpdatingMode = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.pushNamed(context, SettingsPage.routeName);
    if (!mounted) return;
    final AskProvider provider = context.read<AskProvider>();
    if (!provider.useMock && ApiConfig.hasValidBaseUrl) {
      await provider.checkBackendHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AskProvider>(
      builder: (BuildContext context, AskProvider provider, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('电路搜题'),
            actions: <Widget>[
              if (AppEnvironment.showDeveloperTools)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '内部测试版',
                        style: TextStyle(
                          color: Color(0xFF9A5B00),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      _introCard(),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _messageCard(_error!, true),
                      ],
                      if (!provider.useMock && !ApiConfig.hasValidBaseUrl) ...<Widget>[
                        const SizedBox(height: 14),
                        _messageCard('尚未配置真实接口地址，请先前往设置。', true),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        '开始搜题',
                        style: TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _actionButton(
                        icon: Icons.photo_camera_rounded,
                        title: '拍照搜题',
                        subtitle: '使用相机拍摄电路题目',
                        filled: true,
                        onTap: _isPicking ? null : () => _pick(ImageSource.camera),
                      ),
                      const SizedBox(height: 14),
                      _actionButton(
                        icon: Icons.photo_library_outlined,
                        title: '从相册选择',
                        subtitle: '选择已有的电路题图片',
                        filled: false,
                        onTap: _isPicking ? null : () => _pick(ImageSource.gallery),
                      ),
                      const SizedBox(height: 22),
                      if (AppEnvironment.showDeveloperTools)
                        _mockCard(provider),
                      if (!provider.useMock) ...<Widget>[
                        const SizedBox(height: 14),
                        _realServiceCard(provider),
                      ],
                      const SizedBox(height: 22),
                      _tipsCard(),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Text(
                    provider.useMock
                        ? 'Mock 模式不消耗次数'
                        : provider.quotaLoaded
                            ? '今日剩余 ${provider.dailyRemaining} / ${AskProvider.dailyLimit} 次'
                            : '正在读取今日额度',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (int index) {
              if (index == 1) {
                Navigator.pushNamed(context, HistoryPage.routeName);
              } else if (index == 2) {
                _openSettings();
              }
            },
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history_rounded),
                label: '历史',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _introCard() => Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF3157E7), Color(0xFF6B7CFF)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x33FFFFFF),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.electrical_services_rounded, color: Colors.white, size: 30),
                  ),
                ),
                Spacer(),
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFCFD7FF)),
              ],
            ),
            SizedBox(height: 22),
            Text(
              '拍下电路题，逐步看懂解法',
              style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              '框选题目区域，获取答案、步骤、知识点与相似题。',
              style: TextStyle(color: Color(0xFFE3E7FF), height: 1.5),
            ),
          ],
        ),
      );

  Widget _tipsCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E9F2)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE8EDFF),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(9),
                child: Icon(Icons.center_focus_strong_rounded, color: Color(0xFF3157E7)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('拍摄小技巧', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 5),
                  Text(
                    '保持画面清晰、光线均匀，并完整拍下电路图和题目条件。',
                    style: TextStyle(color: Color(0xFF667085), height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final Color background = filled ? const Color(0xFF3157E7) : Colors.white;
    final Color foreground = filled ? Colors.white : const Color(0xFF0F172A);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: filled ? null : Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: <Widget>[
              if (_isPicking && onTap == null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: foreground, strokeWidth: 3),
                )
              else
                Icon(icon, color: foreground, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: filled ? Colors.white70 : const Color(0xFF64748B))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mockCard(AskProvider provider) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.science_outlined),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('使用 Mock 数据', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('无需后端即可体验完整流程', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ),
            if (_isUpdatingMode)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Switch(value: provider.useMock, onChanged: _setMock),
          ],
        ),
      );

  Widget _realServiceCard(AskProvider provider) {
    final health = provider.backendHealth;
    final bool ready = health?.isReady ?? false;
    final Color color = ready
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    final String title = provider.checkingBackend
        ? '正在检测真实服务'
        : ready
            ? '后端已连接，AI 配置完整'
            : '真实服务尚未就绪';
    final String subtitle = provider.checkingBackend
        ? '正在连接 ${ApiConfig.baseUrl}'
        : ready
            ? '${health!.aiProvider}/${health.aiModel} · 题库 ${health.libraryQuestions} 道'
            : (provider.backendHealthError ??
                (ApiConfig.hasValidBaseUrl ? '点击重试连接' : '请先在设置中填写后端地址'));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: <Widget>[
          if (provider.checkingBackend)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            )
          else
            Icon(ready ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          if (!provider.checkingBackend && ApiConfig.hasValidBaseUrl)
            IconButton(
              tooltip: '重新检测',
              onPressed: provider.checkBackendHealth,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }

  Widget _messageCard(String message, bool error) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? const Color(0xFFDC2626) : const Color(0xFF15803D)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      );
}
