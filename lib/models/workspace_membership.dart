import 'user_role.dart';
import 'workspace.dart';

/// Result object for listing user's workspaces with membership details
class WorkspaceMembership {
  final String membershipId; // workspace_member document ID
  final String workspaceId;
  final String workspaceName;
  final String? avatarUrl; // URL to workspace avatar image
  final UserRole role;
  final String? roleName;
  final DateTime joinedAt;
  final bool isActive; // If this is the currently active workspace
  final String? projectTerminology;
  final List<String> enabledNavigationTabs;
  final bool showBusinessDaysOnly;
  final String currencyCode;
  final String timezone;
  final UnitSystem unitSystem;
  final double? hourlyRate;
  final double? defaultHourlyRate;
  final double? weeklyWage;
  final double? defaultWeeklyWage;
  final Map<String, String> modulePermissions;

  // Default tax settings
  final bool defaultTaxEnabled;
  final String defaultTaxName;
  final double defaultTaxRate;

  // AI Persona fields
  final String? aiPersonaName;
  final String? aiPersonaAvatar;
  final String? aiPersonaStyle;
  final String? aiPersonaContext;

  // Workspace onboarding state. Drives the post-login redirect for new owners
  // so they don't skip /onboarding when they sign in via password instead of
  // following the email-verification link.
  final bool onboardingCompleted;

  WorkspaceMembership({
    required this.membershipId,
    required this.workspaceId,
    required this.workspaceName,
    this.avatarUrl,
    required this.role,
    this.roleName,
    required this.joinedAt,
    this.isActive = false,
    this.projectTerminology,
    this.enabledNavigationTabs = const [],
    this.showBusinessDaysOnly = false,
    this.currencyCode = 'USD',
    this.timezone = 'UTC',
    this.unitSystem = UnitSystem.imperial,
    this.hourlyRate,
    this.defaultHourlyRate,
    this.weeklyWage,
    this.defaultWeeklyWage,
    this.modulePermissions = const {},
    this.defaultTaxEnabled = true,
    this.defaultTaxName = 'Tax',
    this.defaultTaxRate = 0,
    this.aiPersonaName,
    this.aiPersonaAvatar,
    this.aiPersonaStyle,
    this.aiPersonaContext,
    this.onboardingCompleted = true,
  });

  WorkspaceMembership copyWith({
    String? membershipId,
    String? workspaceId,
    String? workspaceName,
    String? avatarUrl,
    UserRole? role,
    String? roleName,
    DateTime? joinedAt,
    bool? isActive,
    String? projectTerminology,
    List<String>? enabledNavigationTabs,
    bool? showBusinessDaysOnly,
    String? currencyCode,
    String? timezone,
    UnitSystem? unitSystem,
    double? hourlyRate,
    double? defaultHourlyRate,
    double? weeklyWage,
    double? defaultWeeklyWage,
    Map<String, String>? modulePermissions,
    bool? defaultTaxEnabled,
    String? defaultTaxName,
    double? defaultTaxRate,
    String? aiPersonaName,
    String? aiPersonaAvatar,
    String? aiPersonaStyle,
    String? aiPersonaContext,
    bool? onboardingCompleted,
  }) {
    return WorkspaceMembership(
      membershipId: membershipId ?? this.membershipId,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      roleName: roleName ?? this.roleName,
      joinedAt: joinedAt ?? this.joinedAt,
      isActive: isActive ?? this.isActive,
      projectTerminology: projectTerminology ?? this.projectTerminology,
      enabledNavigationTabs:
          enabledNavigationTabs ?? this.enabledNavigationTabs,
      showBusinessDaysOnly: showBusinessDaysOnly ?? this.showBusinessDaysOnly,
      currencyCode: currencyCode ?? this.currencyCode,
      timezone: timezone ?? this.timezone,
      unitSystem: unitSystem ?? this.unitSystem,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      defaultHourlyRate: defaultHourlyRate ?? this.defaultHourlyRate,
      weeklyWage: weeklyWage ?? this.weeklyWage,
      defaultWeeklyWage: defaultWeeklyWage ?? this.defaultWeeklyWage,
      modulePermissions: modulePermissions ?? this.modulePermissions,
      defaultTaxEnabled: defaultTaxEnabled ?? this.defaultTaxEnabled,
      defaultTaxName: defaultTaxName ?? this.defaultTaxName,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      aiPersonaName: aiPersonaName ?? this.aiPersonaName,
      aiPersonaAvatar: aiPersonaAvatar ?? this.aiPersonaAvatar,
      aiPersonaStyle: aiPersonaStyle ?? this.aiPersonaStyle,
      aiPersonaContext: aiPersonaContext ?? this.aiPersonaContext,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  String get displayRoleName {
    final trimmed = roleName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return role.displayName;
  }
}
