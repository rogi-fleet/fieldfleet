import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_role.dart';
import '../../models/workspace_role_template.dart';
import '../../utils/app_logger.dart';
import '../../utils/module_permissions.dart';
import '../../utils/user_facing_error.dart';
import '../role_template_service.dart';
import 'settings_audit_service.dart';

class SupabaseRoleTemplateService extends RoleTemplateService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseSettingsAuditService _settingsAuditService =
      SupabaseSettingsAuditService();

  @override
  Future<List<WorkspaceRoleTemplate>> getTemplates({
    required String workspaceId,
  }) async {
    try {
      final response = await _supabase
          .from('workspace_role_templates')
          .select()
          .eq('workspace_id', workspaceId)
          .order('is_system', ascending: false)
          .order('name', ascending: true);

      final templates = (response as List)
          .cast<Map<String, dynamic>>()
          .map(WorkspaceRoleTemplate.fromJson)
          .toList();

      if (templates.isNotEmpty) {
        return templates;
      }

      return fallbackTemplates(workspaceId);
    } catch (e) {
      AppLogger.warning(
        'Failed to fetch workspace role templates; using fallback defaults',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
      return fallbackTemplates(workspaceId);
    }
  }

  @override
  Future<WorkspaceRoleTemplate?> getTemplateById({
    required String templateId,
  }) async {
    try {
      final response = await _supabase
          .from('workspace_role_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (response == null) return null;
      return WorkspaceRoleTemplate.fromJson(response);
    } catch (e) {
      AppLogger.error('Failed to get role template by ID', error: e);
      return null;
    }
  }

  @override
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
    final normalized = normalizeModulePermissions(modulePermissions);
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw Exception('Template name is required');
    }

    try {
      final inserted = await _supabase
          .from('workspace_role_templates')
          .insert({
            'workspace_id': workspaceId,
            'name': trimmedName,
            'role': _roleToDb(role),
            'module_permissions': normalized,
            'is_system': false,
            'is_admin': isAdmin,
            'default_interface_mode': defaultInterfaceMode,
            'description': description,
            'color': color,
            'created_by': _supabase.auth.currentUser?.id,
          })
          .select()
          .single();

      final template = WorkspaceRoleTemplate.fromJson(inserted);

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'role_template',
        targetId: template.id,
        eventType: 'role_template.created',
        beforeData: null,
        afterData: {
          'name': template.name,
          'role': _roleToDb(template.role),
          'module_permissions': template.modulePermissions,
          'is_admin': template.isAdmin,
          'is_system': template.isSystem,
        },
      );

      return template;
    } catch (e) {
      AppLogger.error('Failed to create role template', error: e);
      rethrow;
    }
  }

  @override
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
    try {
      final previous = await _supabase
          .from('workspace_role_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (previous == null) {
        throw Exception('Template not found');
      }

      // Guard: removing admin from this template must leave at least one
      // other admin in the workspace, otherwise nobody can administer it.
      if (isAdmin == false && previous['is_admin'] == true) {
        final otherAdmins = await _countWorkspaceAdminsExcludingTemplate(
          workspaceId: previous['workspace_id'] as String,
          excludedTemplateId: templateId,
        );
        if (otherAdmins == 0) {
          throw UserFacingException(
            'Cannot remove admin access from this role — the workspace '
            'would have no admins left. Promote another member first.',
          );
        }
      }

      final updates = <String, dynamic>{};

      if (name != null) {
        final trimmedName = name.trim();
        if (trimmedName.isEmpty) {
          throw Exception('Template name is required');
        }
        updates['name'] = trimmedName;
      }

      if (clearRole) {
        updates['role'] = null;
      } else if (role != null) {
        updates['role'] = _roleToDb(role);
      }

      if (modulePermissions != null) {
        updates['module_permissions'] = normalizeModulePermissions(
          modulePermissions,
        );
      }

      if (isAdmin != null) {
        updates['is_admin'] = isAdmin;
      }

      if (defaultInterfaceMode != null) {
        updates['default_interface_mode'] = defaultInterfaceMode;
      }

      if (clearDescription) {
        updates['description'] = null;
      } else if (description != null) {
        updates['description'] = description;
      }

      if (clearColor) {
        updates['color'] = null;
      } else if (color != null) {
        updates['color'] = color;
      }

      if (updates.isEmpty) {
        return;
      }

      final updated = await _supabase
          .from('workspace_role_templates')
          .update(updates)
          .eq('id', templateId)
          .select()
          .single();

      await _settingsAuditService.logEvent(
        workspaceId: previous['workspace_id'] as String,
        targetType: 'role_template',
        targetId: templateId,
        eventType: 'role_template.updated',
        beforeData: {
          'name': previous['name'],
          'role': previous['role'],
          'module_permissions': previous['module_permissions'],
          'is_admin': previous['is_admin'],
          'default_interface_mode': previous['default_interface_mode'],
          'description': previous['description'],
          'is_system': previous['is_system'],
        },
        afterData: {
          'name': updated['name'],
          'role': updated['role'],
          'module_permissions': updated['module_permissions'],
          'is_admin': updated['is_admin'],
          'default_interface_mode': updated['default_interface_mode'],
          'description': updated['description'],
          'is_system': updated['is_system'],
        },
      );
    } catch (e) {
      AppLogger.error('Failed to update role template', error: e);
      rethrow;
    }
  }

  @override
  Future<void> deleteTemplate({required String templateId}) async {
    try {
      final previous = await _supabase
          .from('workspace_role_templates')
          .select()
          .eq('id', templateId)
          .maybeSingle();

      if (previous == null) {
        return;
      }

      if (previous['is_system'] == true) {
        throw Exception('System templates cannot be deleted');
      }

      // Guard: deleting an admin template must not leave the workspace
      // without any admins. Callers reassign members before delete, so at
      // this point `excludedTemplateId` effectively skips any stragglers
      // still on this template.
      if (previous['is_admin'] == true) {
        final otherAdmins = await _countWorkspaceAdminsExcludingTemplate(
          workspaceId: previous['workspace_id'] as String,
          excludedTemplateId: templateId,
        );
        if (otherAdmins == 0) {
          throw UserFacingException(
            'Cannot delete this role — it is the only source of admin '
            'access in the workspace. Promote another member to admin '
            'first, or reassign these members to another admin role.',
          );
        }
      }

      await _supabase
          .from('workspace_role_templates')
          .delete()
          .eq('id', templateId);

      await _settingsAuditService.logEvent(
        workspaceId: previous['workspace_id'] as String,
        targetType: 'role_template',
        targetId: templateId,
        eventType: 'role_template.deleted',
        beforeData: {
          'name': previous['name'],
          'role': previous['role'],
          'module_permissions': previous['module_permissions'],
          'is_system': previous['is_system'],
        },
        afterData: null,
      );
    } catch (e) {
      AppLogger.error('Failed to delete role template', error: e);
      rethrow;
    }
  }

  @override
  Future<WorkspaceRoleTemplate> cloneTemplate({
    required String templateId,
    required String newName,
  }) async {
    try {
      final source = await _supabase
          .from('workspace_role_templates')
          .select()
          .eq('id', templateId)
          .single();

      final template = WorkspaceRoleTemplate.fromJson(source);
      return createTemplate(
        workspaceId: template.workspaceId,
        name: newName,
        role: template.role,
        modulePermissions: template.modulePermissions,
        isAdmin: template.isAdmin,
        defaultInterfaceMode: template.defaultInterfaceMode,
        description: template.description,
        color: template.color,
      );
    } catch (e) {
      AppLogger.error('Failed to clone role template', error: e);
      rethrow;
    }
  }

  @override
  Future<int> getMemberCountForTemplate({
    required String templateId,
  }) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('role_template_id', templateId);

      return (response as List).length;
    } catch (e) {
      AppLogger.error('Failed to get member count for template', error: e);
      return 0;
    }
  }

  @override
  Future<List<TemplateMemberSummary>> getMembersForTemplate({
    required String templateId,
  }) async {
    try {
      final memberRows = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('role_template_id', templateId);

      final userIds = (memberRows as List)
          .map((row) => (row as Map<String, dynamic>)['user_id'] as String)
          .toList();

      if (userIds.isEmpty) return const [];

      final userRows = await _supabase
          .from('users')
          .select('id, email, display_name')
          .inFilter('id', userIds);

      return (userRows as List).map((row) {
        final map = row as Map<String, dynamic>;
        return TemplateMemberSummary(
          userId: map['id'] as String,
          displayName: map['display_name'] as String?,
          email: (map['email'] as String?) ?? '',
        );
      }).toList();
    } catch (e) {
      AppLogger.error('Failed to get members for template', error: e);
      return const [];
    }
  }

  @override
  Future<Map<String, TemplateUsage>> getUsageCounts({
    required String workspaceId,
  }) async {
    try {
      final memberRows = await _supabase
          .from('workspace_members')
          .select('role_template_id')
          .eq('workspace_id', workspaceId)
          .not('role_template_id', 'is', null);

      final inviteRows = await _supabase
          .from('workspace_invitations')
          .select('role_template_id')
          .eq('workspace_id', workspaceId)
          .eq('status', 'pending')
          .not('role_template_id', 'is', null);

      final members = <String, int>{};
      for (final row in (memberRows as List)) {
        final id = (row as Map<String, dynamic>)['role_template_id'] as String?;
        if (id == null) continue;
        members[id] = (members[id] ?? 0) + 1;
      }
      final invites = <String, int>{};
      for (final row in (inviteRows as List)) {
        final id = (row as Map<String, dynamic>)['role_template_id'] as String?;
        if (id == null) continue;
        invites[id] = (invites[id] ?? 0) + 1;
      }

      final ids = {...members.keys, ...invites.keys};
      return {
        for (final id in ids)
          id: TemplateUsage(
            memberCount: members[id] ?? 0,
            pendingInvitationCount: invites[id] ?? 0,
          ),
      };
    } catch (e) {
      AppLogger.error('Failed to load role template usage counts', error: e);
      return const {};
    }
  }

  /// Count distinct admin members in [workspaceId], skipping any members
  /// currently assigned to [excludedTemplateId]. A user is considered admin
  /// via either the legacy `role='admin'` value or an admin role template.
  Future<int> _countWorkspaceAdminsExcludingTemplate({
    required String workspaceId,
    required String excludedTemplateId,
  }) async {
    final legacyAdmins = await _supabase
        .from('workspace_members')
        .select('user_id, role_template_id')
        .eq('workspace_id', workspaceId)
        .eq('role', 'admin');

    final templateAdmins = await _supabase
        .from('workspace_members')
        .select(
          'user_id, role_template_id, workspace_role_templates!inner(is_admin)',
        )
        .eq('workspace_id', workspaceId)
        .eq('workspace_role_templates.is_admin', true);

    final adminIds = <String>{};
    for (final row in (legacyAdmins as List)) {
      if (row['role_template_id'] != excludedTemplateId) {
        adminIds.add(row['user_id'] as String);
      }
    }
    for (final row in (templateAdmins as List)) {
      if (row['role_template_id'] != excludedTemplateId) {
        adminIds.add(row['user_id'] as String);
      }
    }
    return adminIds.length;
  }

  String? _roleToDb(UserRole? role) {
    switch (role) {
      case UserRole.masterAdmin:
        return 'master_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'field_technician';
      case UserRole.client:
        return 'client';
      case UserRole.vendor:
        return 'vendor';
      case null:
        return null;
    }
  }
}
