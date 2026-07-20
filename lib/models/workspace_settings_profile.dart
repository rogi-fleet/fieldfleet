class WorkspaceSettingsProfile {
  final String id;
  final String workspaceId;
  final String name;
  final String? projectTerminology;
  final List<String> enabledProjectTabs;
  final List<String> enabledNavigationTabs;
  final bool showBusinessDaysOnly;
  final String currencyCode;
  final String timezone;
  final double? hourlyRate;
  final double? weeklyWage;
  final bool defaultTaxEnabled;
  final String defaultTaxName;
  final double defaultTaxRate;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkspaceSettingsProfile({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.projectTerminology,
    required this.enabledProjectTabs,
    required this.enabledNavigationTabs,
    required this.showBusinessDaysOnly,
    required this.currencyCode,
    required this.timezone,
    required this.hourlyRate,
    required this.weeklyWage,
    this.defaultTaxEnabled = true,
    this.defaultTaxName = 'Tax',
    this.defaultTaxRate = 0,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkspaceSettingsProfile.fromJson(Map<String, dynamic> row) {
    return WorkspaceSettingsProfile(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: (row['name'] as String? ?? '').trim(),
      projectTerminology: row['project_terminology'] as String?,
      enabledProjectTabs: row['enabled_project_tabs'] != null
          ? List<String>.from(row['enabled_project_tabs'] as List)
          : const [],
      enabledNavigationTabs: row['enabled_navigation_tabs'] != null
          ? List<String>.from(row['enabled_navigation_tabs'] as List)
          : const [],
      showBusinessDaysOnly: row['show_business_days_only'] as bool? ?? false,
      currencyCode: row['currency_code'] as String? ?? 'USD',
      timezone: row['timezone'] as String? ?? 'UTC',
      hourlyRate: (row['hourly_rate'] as num?)?.toDouble(),
      weeklyWage: (row['weekly_wage'] as num?)?.toDouble(),
      defaultTaxEnabled: row['default_tax_enabled'] as bool? ?? true,
      defaultTaxName: row['default_tax_name'] as String? ?? 'Tax',
      defaultTaxRate: (row['default_tax_rate'] as num?)?.toDouble() ?? 0,
      createdBy: row['created_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
