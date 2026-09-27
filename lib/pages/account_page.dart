import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../models/account_activity.dart';
import '../models/account_profile.dart';
import '../providers/auth_provider.dart';
import 'home_page.dart';
import 'login_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  static const String routeName = '/account';

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil(
      ApiConfig.useMock ? HomePage.routeName : LoginPage.routeName,
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _copyUserId(BuildContext context, String userId) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('用户ID已复制')),
    );
  }

  Future<void> _refreshAccount(BuildContext context) async {
    await context.read<AuthProvider>().refreshProfile();
    if (!context.mounted) return;
    final AuthProvider auth = context.read<AuthProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          auth.errorMessage == null ? '剩余次数已刷新' : auth.errorMessage!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    final AccountProfile? profile = auth.profile;
    final List<AccountActivity> visibleActivities =
        _visibleActivities(auth.activities);
    return Scaffold(
      appBar: AppBar(title: const Text('我的账号')),
      body: SafeArea(
        top: false,
        child: profile == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.person_off_outlined, size: 54),
                      const SizedBox(height: 12),
                      const Text('当前未登录'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          LoginPage.routeName,
                        ),
                        child: const Text('前往登录'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: auth.refreshProfile,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFF3157E7), Color(0xFF6B7CFF)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        children: <Widget>[
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.person_rounded,
                                color: Colors.white, size: 36),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(profile.username,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                    )),
                                const SizedBox(height: 4),
                                const Text('Circuit Solver 用户',
                                    style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 10),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        '用户ID：${profile.id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '复制用户ID',
                                      onPressed: () =>
                                          _copyUserId(context, profile.id),
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _metric(
                      '剩余搜题次数',
                      '${profile.freeUsesRemaining} 次',
                      Icons.confirmation_number_outlined,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        '本测试版不提供App内付款。需要增加次数时，请向内测管理员提供上方用户ID；管理员人工处理后，点击下方按钮即可生效。识别失败会自动退回次数。',
                        style: TextStyle(height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: auth.loading
                          ? null
                          : () => _refreshAccount(context),
                      icon: auth.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('刷新剩余次数'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '额度明细',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (auth.errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          auth.errorMessage!,
                          style: const TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ...visibleActivities.map(_activityTile),
                    if (visibleActivities.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          '暂无额度变动记录，下拉页面可刷新。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: auth.loading ? null : () => _logout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('退出登录'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  List<AccountActivity> _visibleActivities(List<AccountActivity> activities) =>
      activities
          .where((AccountActivity item) =>
              item.freeUsesDelta != 0 || item.balanceFenDelta != 0)
          .take(20)
          .toList(growable: false);

  Widget _activityTile(AccountActivity activity) {
    final bool positive = activity.isPositive;
    final Color color =
        positive ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(
              positive ? Icons.add_rounded : Icons.remove_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activity.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTime(activity.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _activityValue(activity),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  String _activityValue(AccountActivity activity) {
    if (activity.freeUsesDelta != 0) {
      final String sign = activity.freeUsesDelta > 0 ? '+' : '';
      return '$sign${activity.freeUsesDelta} 次';
    }
    final String sign = activity.balanceFenDelta > 0 ? '+' : '-';
    return '$sign¥${(activity.balanceFenDelta.abs() / 100).toStringAsFixed(2)}';
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Widget _metric(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: const Color(0xFF3157E7)),
            const SizedBox(height: 12),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      );
}
