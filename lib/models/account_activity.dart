class AccountActivity {
  const AccountActivity({
    required this.id,
    required this.eventType,
    required this.freeUsesDelta,
    required this.balanceFenDelta,
    required this.createdAt,
  });

  final int id;
  final String eventType;
  final int freeUsesDelta;
  final int balanceFenDelta;
  final DateTime createdAt;

  factory AccountActivity.fromJson(Map<String, dynamic> json) =>
      AccountActivity(
        id: json['id'] as int? ?? 0,
        eventType: json['event_type'] as String? ?? '',
        freeUsesDelta: json['free_uses_delta'] as int? ?? 0,
        balanceFenDelta: json['balance_fen_delta'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['created_at'] as int? ?? 0) * 1000,
        ),
      );

  String get title {
    switch (eventType) {
      case 'register_bonus':
        return '新用户赠送';
      case 'solve_reserved':
        return '搜题额度预扣';
      case 'solve_committed':
        return '搜题完成';
      case 'solve_refunded':
        return '失败自动退回';
      case 'recharge':
        return '充值到账';
      case 'adjustment':
        return '额度调整';
      default:
        return '账户变动';
    }
  }

  bool get isPositive => freeUsesDelta > 0 || balanceFenDelta > 0;
}
