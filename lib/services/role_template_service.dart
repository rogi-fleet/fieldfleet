import '../models/user_role.dart';
import '../models/workspace_role_template.dart';
import '../utils/module_permissions.dart';

class TemplateMemberSummary {
  final String userId;
  final String? displayName;
  final String email;

  const TemplateMemberSummary({
    required this.userId,
    required this.displayName,
    required this.email,
  });
}

class TemplateUsage {
  final int memberCount;
  final int pendingInvitationCount;

  const TemplateUsage({
    required this.memberCount,
    required this.pendingInvitationCount,
  });

  static const TemplateUsage empty = TemplateUsage(
    memberCount: 0,
    pendingInvitationCount: 0,
  );
}

class RoleTemplateService {
  Future<List<WorkspaceRoleTemplate>> getTemplates({
    required String workspaceId,
  }) async {
    return _buildFallbackTemplates(workspaceId);
  }

  Future<WorkspaceRoleTemplate?> getTemplateById({
    required String templateId,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<WorkspaceRoleTemplate> createTemplate({
    required String workspaceId,
    required String name,
    UserRole? role,
    required Map<String, String> modulePermissions,
    bool isAdmin = false,
    String defaultInterfaceMode = 'manager',
    String? description,
    String? color,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<void> updateTemplate({
    required String templateId,
    String? name,
    UserRole? role,
    bool clearRole = false,
    Map<String, String>? modulePermissions,
    bool? isAdmin,
    String? defaultInterfaceMode,
    String? description,
    bool clearDescription = false,
    String? color,
    bool clearColor = false,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<void> deleteTemplate({required String templateId}) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<WorkspaceRoleTemplate> cloneTemplate({
    required String templateId,
    required String newName,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<int> getMemberCountForTemplate({
    required String templateId,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  Future<List<TemplateMemberSummary>> getMembersForTemplate({
    required String templateId,
  }) async {
    throw UnsupportedError('Role templates are only supported on Supabase.');
  }

  /// Return per-template member + pending-invitation counts for a workspace.
  Future<Map<String, TemplateUsage>> getUsageCounts({
    required String workspaceId,
  }) async {
    return const {};
  }

  List<WorkspaceRoleTemplate> fallbackTemplates(String workspaceId) {
    return _buildFallbackTemplates(workspaceId);
  }

  List<WorkspaceRoleTemplate> _buildFallbackTemplates(String workspaceId) {
    final now = DateTime.now();
    return UserRole.values.map((role) {
      return WorkspaceRoleTemplate(
        id: '${workspaceId}_${role.name}',
        workspaceId: workspaceId,
        name: role.displayName,
        role: role,
        modulePermissions: defaultPermissionsForRole(role),
        isSystem: true,
        isAdmin: role == UserRole.masterAdmin,
        defaultInterfaceMode:
            role == UserRole.fieldTechnician ? 'field' : 'manager',
        createdBy: null,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
  }
}
