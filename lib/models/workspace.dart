import 'package:cloud_firestore/cloud_firestore.dart';
import 'company_type.dart';

/// System of measurement for workspace-scoped formatting (e.g. temperature units in field forms).
enum UnitSystem {
  imperial('imperial'),
  metric('metric');

  final String value;
  const UnitSystem(this.value);

  static UnitSystem fromValue(String? value) {
    return UnitSystem.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UnitSystem.imperial,
    );
  }
}

/// Team size options for onboarding
enum TeamSize {
  solo(1, '1 (Just me)'),
  small(2, '2-5'),
  medium(3, '6-10'),
  large(4, '11-25'),
  enterprise(5, '26+');

  final int value;
  final String label;
  const TeamSize(this.value, this.label);

  static TeamSize fromValue(int value) {
    return TeamSize.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TeamSize.solo,
    );
  }
}

class Workspace {
  final String id;
  final String name;
  final String ownerId;
  final String? avatarUrl; // URL to workspace avatar image
  final CompanyType? companyType; // Type of company/business
  final String?
  projectTerminology; // Custom label for "Projects" (e.g., "Jobs", "Sites")
  final int?
  startingProjectSerialNumber; // Starting value for project serial numbers
  final double? hourlyRate; // Default hourly rate for the workspace
  final double? weeklyWage; // Default weekly wage for the workspace

  // Default tax settings for documents
  final bool defaultTaxEnabled;
  final String defaultTaxName;
  final double defaultTaxRate;

  // AI Persona fields
  final String? aiPersonaName;
  final String? aiPersonaAvatar;
  final String? aiPersonaStyle;
  final String? aiPersonaContext;

  /// List of enabled project tab IDs. Empty list means all tabs enabled.
  /// Available top-level tabs: 'overview', 'info' (Properties), 'tasks',
  /// 'financials', 'selections', 'inventory', 'messages', 'files'. Legacy
  /// IDs ('time-tracking', 'plans', 'specifications', 'change-orders',
  /// 'work-orders', 'subcontracts', 'notes', 'daily-logs',
  /// 'inspections', 'punch-list', 'warranties', 'assets', 'materials') still
  /// resolve via normalization but land on the consolidated tab that now
  /// hosts them.
  final List<String> enabledProjectTabs;

  /// List of enabled navigation tab IDs. Empty list means all enabled.
  /// Available: 'projects', 'tasks', 'customers', 'financials', 'vendors',
  /// 'timesheets', 'team', 'assets', 'vehicles', 'reports', 'catalog'
  final List<String> enabledNavigationTabs;

  /// Whether to show only business days (Mon-Fri) in schedule/Gantt views
  final bool showBusinessDaysOnly;

  // Company Address fields
  final String? companyAddress;
  final String? companyCity;
  final String? companyState;
  final String? companyZipCode;
  final String? companyCountry;
  final String? website;

  // Currency (ISO 4217 code, defaults to 'USD' for backward compatibility)
  final String currencyCode;
  final String timezone;
  final UnitSystem unitSystem;

  // Onboarding fields
  final int? teamSize; // TeamSize enum value (1-5)
  final List<String> goals; // Selected goals from onboarding
  final bool onboardingCompleted;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Get the full company address as a single formatted string
  String? get fullCompanyAddress {
    final parts = <String>[];
    if (companyAddress != null && companyAddress!.isNotEmpty) {
      parts.add(companyAddress!);
    }
    final cityStateParts = <String>[];
    if (companyCity != null && companyCity!.isNotEmpty) {
      cityStateParts.add(companyCity!);
    }
    if (companyState != null && companyState!.isNotEmpty) {
      cityStateParts.add(companyState!);
    }
    if (cityStateParts.isNotEmpty) {
      parts.add(cityStateParts.join(', '));
    }
    if (companyZipCode != null && companyZipCode!.isNotEmpty) {
      parts.add(companyZipCode!);
    }
    if (companyCountry != null && companyCountry!.isNotEmpty) {
      parts.add(companyCountry!);
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// Default tabs for new workspaces. Consolidated layout: Notes lives
  /// under 'overview'; Plans / Specifications / Daily Logs / Inspections /
  /// Punch List / Warranties live under 'files'; Change Orders / Work
  /// Orders / Subcontracts live under 'financials'; Time tracking lives
  /// under 'tasks'. Properties ('info') retains its own top-level tab.
  static const List<String> defaultTabs = [
    'overview',
    'info',
    'tasks',
    'financials',
    'selections',
    'inventory',
    'messages',
    'files',
  ];

  Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    this.avatarUrl,
    this.companyType,
    this.projectTerminology,
    this.startingProjectSerialNumber,
    this.enabledProjectTabs = const [],
    this.enabledNavigationTabs = const [],
    this.showBusinessDaysOnly = false,
    this.companyAddress,
    this.companyCity,
    this.companyState,
    this.companyZipCode,
    this.companyCountry,
    this.website,
    this.currencyCode = 'USD',
    this.timezone = 'UTC',
    this.unitSystem = UnitSystem.imperial,
    this.teamSize,
    this.goals = const [],
    this.onboardingCompleted = false,
    this.hourlyRate,
    this.weeklyWage,
    this.defaultTaxEnabled = true,
    this.defaultTaxName = 'Tax',
    this.defaultTaxRate = 0,
    this.aiPersonaName,
    this.aiPersonaAvatar,
    this.aiPersonaStyle,
    this.aiPersonaContext,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json, String id) {
    return Workspace(
      id: id,
      name: json['name'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      companyType: json['companyType'] != null
          ? CompanyType.fromString(json['companyType'] as String)
          : null,
      projectTerminology: json['projectTerminology'] as String?,
      startingProjectSerialNumber: json['startingProjectSerialNumber'] as int?,
      enabledProjectTabs: json['enabledProjectTabs'] != null
          ? List<String>.from(json['enabledProjectTabs'] as List)
          : const [],
      enabledNavigationTabs: json['enabledNavigationTabs'] != null
          ? List<String>.from(json['enabledNavigationTabs'] as List)
          : const [],
      showBusinessDaysOnly: json['showBusinessDaysOnly'] as bool? ?? false,
      companyAddress: json['companyAddress'] as String?,
      companyCity: json['companyCity'] as String?,
      companyState: json['companyState'] as String?,
      companyZipCode: json['companyZipCode'] as String?,
      companyCountry: json['companyCountry'] as String?,
      website: json['website'] as String?,
      currencyCode: json['currencyCode'] as String? ?? 'USD',
      timezone: json['timezone'] as String? ?? 'UTC',
      unitSystem: UnitSystem.fromValue(
        json['unitSystem'] as String? ?? json['unit_system'] as String?,
      ),
      teamSize: json['teamSize'] as int?,
      goals: json['goals'] != null
          ? List<String>.from(json['goals'] as List)
          : const [],
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      hourlyRate: (json['hourlyRate'] ?? json['hourly_rate'] as num?)
          ?.toDouble(),
      weeklyWage: (json['weeklyWage'] ?? json['weekly_wage'] as num?)
          ?.toDouble(),
      defaultTaxEnabled: json['defaultTaxEnabled'] as bool? ??
          json['default_tax_enabled'] as bool? ??
          true,
      defaultTaxName: json['defaultTaxName'] as String? ??
          json['default_tax_name'] as String? ??
          'Tax',
      defaultTaxRate:
          (json['defaultTaxRate'] ?? json['default_tax_rate'] as num?)
                  ?.toDouble() ??
              0,
      aiPersonaName: json['aiPersonaName'] as String? ??
          json['ai_persona_name'] as String?,
      aiPersonaAvatar: json['aiPersonaAvatar'] as String? ??
          json['ai_persona_avatar'] as String?,
      aiPersonaStyle: json['aiPersonaStyle'] as String? ??
          json['ai_persona_style'] as String?,
      aiPersonaContext: json['aiPersonaContext'] as String? ??
          json['ai_persona_context'] as String?,
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
    );
  }

  /// Parse timestamp from either Firestore Timestamp, DateTime, or ISO string
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    // Handle fake timestamp with toDate() method
    try {
      return value.toDate();
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ownerId': ownerId,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (companyType != null) 'companyType': companyType!.name,
      if (projectTerminology != null) 'projectTerminology': projectTerminology,
      if (startingProjectSerialNumber != null)
        'startingProjectSerialNumber': startingProjectSerialNumber,
      if (enabledProjectTabs.isNotEmpty)
        'enabledProjectTabs': enabledProjectTabs,
      if (enabledNavigationTabs.isNotEmpty)
        'enabledNavigationTabs': enabledNavigationTabs,
      'showBusinessDaysOnly': showBusinessDaysOnly,
      if (companyAddress != null) 'companyAddress': companyAddress,
      if (companyCity != null) 'companyCity': companyCity,
      if (companyState != null) 'companyState': companyState,
      if (companyZipCode != null) 'companyZipCode': companyZipCode,
      if (companyCountry != null) 'companyCountry': companyCountry,
      if (website != null) 'website': website,
      'currencyCode': currencyCode,
      'timezone': timezone,
      'unitSystem': unitSystem.value,
      if (teamSize != null) 'teamSize': teamSize,
      if (goals.isNotEmpty) 'goals': goals,
      'onboardingCompleted': onboardingCompleted,
      'hourly_rate': hourlyRate,
      'weekly_wage': weeklyWage,
      'default_tax_enabled': defaultTaxEnabled,
      'default_tax_name': defaultTaxName,
      'default_tax_rate': defaultTaxRate,
      if (aiPersonaName != null) 'aiPersonaName': aiPersonaName,
      if (aiPersonaAvatar != null) 'aiPersonaAvatar': aiPersonaAvatar,
      if (aiPersonaStyle != null) 'aiPersonaStyle': aiPersonaStyle,
      if (aiPersonaContext != null) 'aiPersonaContext': aiPersonaContext,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Workspace copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? avatarUrl,
    CompanyType? companyType,
    String? projectTerminology,
    int? startingProjectSerialNumber,
    List<String>? enabledProjectTabs,
    List<String>? enabledNavigationTabs,
    bool? showBusinessDaysOnly,
    String? companyAddress,
    String? companyCity,
    String? companyState,
    String? companyZipCode,
    String? companyCountry,
    String? website,
    String? currencyCode,
    String? timezone,
    UnitSystem? unitSystem,
    int? teamSize,
    List<String>? goals,
    bool? onboardingCompleted,
    double? hourlyRate,
    double? weeklyWage,
    bool? defaultTaxEnabled,
    String? defaultTaxName,
    double? defaultTaxRate,
    String? aiPersonaName,
    String? aiPersonaAvatar,
    String? aiPersonaStyle,
    String? aiPersonaContext,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      companyType: companyType ?? this.companyType,
      projectTerminology: projectTerminology ?? this.projectTerminology,
      startingProjectSerialNumber:
          startingProjectSerialNumber ?? this.startingProjectSerialNumber,
      enabledProjectTabs: enabledProjectTabs ?? this.enabledProjectTabs,
      enabledNavigationTabs:
          enabledNavigationTabs ?? this.enabledNavigationTabs,
      showBusinessDaysOnly: showBusinessDaysOnly ?? this.showBusinessDaysOnly,
      companyAddress: companyAddress ?? this.companyAddress,
      companyCity: companyCity ?? this.companyCity,
      companyState: companyState ?? this.companyState,
      companyZipCode: companyZipCode ?? this.companyZipCode,
      companyCountry: companyCountry ?? this.companyCountry,
      website: website ?? this.website,
      currencyCode: currencyCode ?? this.currencyCode,
      timezone: timezone ?? this.timezone,
      unitSystem: unitSystem ?? this.unitSystem,
      teamSize: teamSize ?? this.teamSize,
      goals: goals ?? this.goals,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      weeklyWage: weeklyWage ?? this.weeklyWage,
      defaultTaxEnabled: defaultTaxEnabled ?? this.defaultTaxEnabled,
      defaultTaxName: defaultTaxName ?? this.defaultTaxName,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      aiPersonaName: aiPersonaName ?? this.aiPersonaName,
      aiPersonaAvatar: aiPersonaAvatar ?? this.aiPersonaAvatar,
      aiPersonaStyle: aiPersonaStyle ?? this.aiPersonaStyle,
      aiPersonaContext: aiPersonaContext ?? this.aiPersonaContext,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
