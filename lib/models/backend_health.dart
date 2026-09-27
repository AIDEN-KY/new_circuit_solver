class BackendHealth {
  const BackendHealth({
    required this.status,
    required this.version,
    required this.aiProvider,
    required this.aiModel,
    required this.aiConfigured,
    required this.libraryQuestions,
    required this.authRequired,
  });

  final String status;
  final String version;
  final String aiProvider;
  final String aiModel;
  final bool aiConfigured;
  final int libraryQuestions;
  final bool authRequired;

  bool get isReady => status == 'ok' && aiConfigured;

  factory BackendHealth.fromJson(Map<String, dynamic> json) {
    return BackendHealth(
      status: json['status']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      aiProvider: json['ai_provider']?.toString() ?? '',
      aiModel: json['ai_model']?.toString() ?? '',
      aiConfigured: json['ai_configured'] == true,
      libraryQuestions: (json['library_questions'] as num?)?.toInt() ?? 0,
      authRequired: json['auth_required'] == true,
    );
  }
}
