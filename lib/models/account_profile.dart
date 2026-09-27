class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.username,
    required this.freeUsesRemaining,
    required this.balanceFen,
    required this.solvePriceFen,
  });

  final String id;
  final String username;
  final int freeUsesRemaining;
  final int balanceFen;
  final int solvePriceFen;

  double get balanceYuan => balanceFen / 100;
  double get solvePriceYuan => solvePriceFen / 100;
  bool get canSolve => freeUsesRemaining > 0 || balanceFen >= solvePriceFen;

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
        id: json['id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        freeUsesRemaining: json['free_uses_remaining'] as int? ?? 0,
        balanceFen: json['balance_fen'] as int? ?? 0,
        solvePriceFen: json['solve_price_fen'] as int? ?? 10,
      );
}
