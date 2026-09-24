import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AskProvider>(
      builder: (BuildContext context, AskProvider provider, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('电路识图搜题'),
            actions: <Widget>[
              IconButton(
                tooltip: '历史记录',
                onPressed: () =>
                    Navigator.pushNamed(context, HistoryPage.routeName),
                icon: const Icon(Icons.history_rounded),
              ),
              IconButton(
                tooltip: '设置',
                onPressed: () =>
                    Navigator.pushNamed(context, SettingsPage.routeName),
                icon: const Icon(Icons.settings_outlined),
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
                      _mockCard(provider),
                      const SizedBox(height: 28),
                      const Icon(
                        Icons.crop_free_rounded,
                        size: 42,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '选择图片后，可手动框住电路图和题目条件',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
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
        );
      },
    );
  }

  Widget _introCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFF2563EB),
              child: Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '上传电工学电路题',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '获取答案、详细步骤、知识点和相似题。',
                    style: TextStyle(color: Color(0xFF475569)),
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
    final Color background = filled ? const Color(0xFF2563EB) : Colors.white;
    final Color foreground = filled ? Colors.white : const Color(0xFF0F172A);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
