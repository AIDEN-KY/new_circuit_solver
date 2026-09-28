class AppConfigModel {
  const AppConfigModel({
    required this.announcementEnabled,
    required this.announcementTitle,
    required this.announcementMessage,
    required this.maintenanceMode,
    required this.maintenanceMessage,
    required this.supportMessage,
    required this.qqGroup,
    required this.initialFreeUses,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.revision,
  });

  final bool announcementEnabled;
  final String announcementTitle;
  final String announcementMessage;
  final bool maintenanceMode;
  final String maintenanceMessage;
  final String supportMessage;
  final String qqGroup;
  final int initialFreeUses;
  final String minSupportedVersion;
  final String latestVersion;
  final String downloadUrl;
  final int revision;

  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
        announcementEnabled: json['announcement_enabled'] == true,
        announcementTitle: json['announcement_title']?.toString() ?? '',
        announcementMessage: json['announcement_message']?.toString() ?? '',
        maintenanceMode: json['maintenance_mode'] == true,
        maintenanceMessage: json['maintenance_message']?.toString() ?? '服务维护中，请稍后再试。',
        supportMessage: json['support_message']?.toString() ?? '',
        qqGroup: json['qq_group']?.toString() ?? '',
        initialFreeUses: (json['initial_free_uses'] as num?)?.toInt() ?? 3,
        minSupportedVersion: json['min_supported_version']?.toString() ?? '1.0.0',
        latestVersion: json['latest_version']?.toString() ?? '1.7.0',
        downloadUrl: json['download_url']?.toString() ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'announcement_enabled': announcementEnabled,
        'announcement_title': announcementTitle,
        'announcement_message': announcementMessage,
        'maintenance_mode': maintenanceMode,
        'maintenance_message': maintenanceMessage,
        'support_message': supportMessage,
        'qq_group': qqGroup,
        'initial_free_uses': initialFreeUses,
        'min_supported_version': minSupportedVersion,
        'latest_version': latestVersion,
        'download_url': downloadUrl,
        'revision': revision,
      };
}
