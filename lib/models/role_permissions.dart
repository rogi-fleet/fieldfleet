import '../utils/module_permissions.dart';
import 'user_role.dart';

/// Wraps a workspace role template's permission data and provides
/// all permission-checking methods previously hardcoded on [UserRole].
///
/// When [isAdmin] is true, all permission checks return true.
class RolePermissions {
  final String? roleTemplateId;
  final String roleName;
  final bool isAdmin;
  final Map<String, String> modulePermissions;
  final String defaultInterfaceMode;
  /// Legacy role-enum value from workspace_members.role. Used as a fallback
  /// for admin-tier checks when the template's is_admin flag is false but
  /// the member is on the legacy 'admin' or 'master_admin' enum (which
  /// is how pre-expansion workspaces still encode admins).
  final UserRole? legacyMemberRole;

  const RolePermissions({
    this.roleTemplateId,
    required this.roleName,
    required this.isAdmin,
    required this.modulePermissions,
    this.defaultInterfaceMode = 'manager',
    this.legacyMemberRole,
  });

  // ---------------------------------------------------------------------------
  // Module-level access
  // ---------------------------------------------------------------------------

  String _moduleLevel(String module) =>
      modulePermissions[module.toLowerCase()] ?? 'none';

  bool hasModuleAccess(String module, String requiredLevel) {
    if (isAdmin) return true;
    final actual = _moduleLevel(module);
    if (requiredLevel == 'write') return actual == 'write';
    if (requiredLevel == 'read') return actual == 'read' || actual == 'write';
    return true; // 'none' always passes
  }

  // ---------------------------------------------------------------------------
  // Permission getters (mirror the old UserRole API)
  // ---------------------------------------------------------------------------

  bool get canManageUsers =>
      isAdmin ||
      legacyMemberRole == UserRole.admin ||
      legacyMemberRole == UserRole.masterAdmin;

  bool get canCreateProjects => isAdmin || _moduleLevel('projects') == 'write';

  bool get canEditProjects => isAdmin || _moduleLevel('projects') == 'write';

  bool get canDeleteProjects => isAdmin;

  bool get canCreateTasks => isAdmin || _moduleLevel('tasks') == 'write';

  bool get canEditTasks => isAdmin || _moduleLevel('tasks') == 'write';

  bool get canDeleteTasks => isAdmin || _moduleLevel('tasks') == 'write';

  bool get canUploadFiles => isAdmin || _moduleLevel('documents') != 'none';

  bool get canDeleteFiles => isAdmin || _moduleLevel('documents') == 'write';

  bool get canAccessSettings => isAdmin || _moduleLevel('settings') != 'none';

  /// True when the role has any (read or write) access to a financial module.
  /// Gates company-level financial views so roles with no financial access
  /// (e.g. field technicians) can't reach it via a direct URL even though the
  /// nav hides it. Admin and PM-tier roles (read access) pass.
  bool get canViewFinancials =>
      isAdmin ||
      _moduleLevel('reports') != 'none' ||
      _moduleLevel('budget') != 'none' ||
      _moduleLevel('customer_invoices') != 'none' ||
      _moduleLevel('vendor_bills') != 'none' ||
      _moduleLevel('estimating') != 'none';

  bool get isReadOnly {
    if (isAdmin) return false;
    return modulePermissions.values.every(
      (level) => level == 'none' || level == 'read',
    );
  }

  bool get isClientMode {
    if (isAdmin) return false;
    // Client-like if only projects+documents are readable and nothing else
    final hasWriteAnywhere = modulePermissions.values.any((l) => l == 'write');
    final hasTeamAccess = _moduleLevel('team') != 'none';
    return !hasWriteAnywhere && !hasTeamAccess;
  }

  // ---------------------------------------------------------------------------
  // Legacy role mapping (for backward compat with code still using UserRole)
  // ---------------------------------------------------------------------------

  UserRole get legacyRole {
    if (isAdmin) return UserRole.admin;
    if (isClientMode) return UserRole.client;
    // If has write access to projects and budget → PM-like
    if (_moduleLevel('projects') == 'write' &&
        _moduleLevel('tasks') == 'write' &&
        _moduleLevel('budget') == 'write') {
      return UserRole.projectManager;
    }
    return UserRole.fieldTechnician;
  }

  // ---------------------------------------------------------------------------
  // Factory constructors
  // ---------------------------------------------------------------------------

  /// Create from a role template JSON map (as returned by Supabase).
  /// Pass [legacyMemberRole] from workspace_members.role so admin-tier
  /// fallbacks still work when the template's is_admin flag drifts.
  factory RolePermissions.fromTemplateJson(
    Map<String, dynamic> json, {
    UserRole? legacyMemberRole,
  }) {
    return RolePermissions(
      roleTemplateId: json['id'] as String?,
      roleName: (json['name'] as String?) ?? 'Unknown',
      isAdmin: json['is_admin'] as bool? ?? false,
      modulePermissions: normalizeModulePermissions(
        json['module_permissions'] != null
            ? Map<String, String>.from(json['module_permissions'] as Map)
            : const {},
      ),
      defaultInterfaceMode:
          (json['default_interface_mode'] as String?) ?? 'manager',
      legacyMemberRole: legacyMemberRole,
    );
  }

  /// Create from a legacy [UserRole] enum (fallback when no template exists).
  factory RolePermissions.fromLegacyRole(UserRole role) {
    final isAdminTier =
        role == UserRole.admin || role == UserRole.masterAdmin;
    return RolePermissions(
      roleName: role.displayName,
      isAdmin: isAdminTier,
      modulePermissions: defaultPermissionsForRole(role),
      defaultInterfaceMode: role == UserRole.fieldTechnician
          ? 'field'
          : 'manager',
      legacyMemberRole: role,
    );
  }
}
