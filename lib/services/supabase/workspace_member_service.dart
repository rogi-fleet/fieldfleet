import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/role_permissions.dart';
import '../../models/workspace_member.dart';
import '../../models/workspace.dart';
import '../../models/workspace_membership.dart';
import '../../models/user_role.dart';
import '../../utils/app_logger.dart';
import '../../utils/module_permissions.dart';
import '../../utils/user_facing_error.dart';
import 'settings_audit_service.dart';

class SupabaseWorkspaceMemberService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseSettingsAuditService _settingsAuditService =
      SupabaseSettingsAuditService();

  /// Add a member to a workspace
  Future<void> addMember({
    required String workspaceId,
    required String userId,
    required UserRole role,
    String? roleTemplateId,
    String? invitedBy,
  }) async {
    try {
      // Check if member already exists
      final existingMember = await isMember(workspaceId, userId);
      if (existingMember) {
        throw Exception('User is already a member of this workspace');
      }

      final now = DateTime.now();
      double? defaultHourlyRate;
      double? defaultWeeklyWage;
      try {
        final workspaceDefaults = await _supabase
            .from('workspaces')
            .select('hourly_rate, weekly_wage')
            .eq('id', workspaceId)
            .maybeSingle();
        if (workspaceDefaults != null) {
          defaultHourlyRate = (workspaceDefaults['hourly_rate'] as num?)
              ?.toDouble();
          defaultWeeklyWage = (workspaceDefaults['weekly_wage'] as num?)
              ?.toDouble();
        }
      } catch (e) {
        AppLogger.warning(
          'Failed to load workspace default wages',
          metadata: {'workspaceId': workspaceId, 'error': e.toString()},
        );
      }

      final insertedMember = await _supabase
          .from('workspace_members')
          .insert({
            'workspace_id': workspaceId,
            'user_id': userId,
            'role': _roleToString(role),
            if (roleTemplateId != null) 'role_template_id': roleTemplateId,
            'invited_by': invitedBy,
            if (defaultHourlyRate != null) 'hourly_rate': defaultHourlyRate,
            if (defaultWeeklyWage != null) 'weekly_wage': defaultWeeklyWage,
            'created_at': now.toIso8601String(),
          })
          .select()
          .maybeSingle();

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.added',
        beforeData: null,
        afterData: insertedMember != null
            ? {
                'role': insertedMember['role'],
                'hourly_rate': insertedMember['hourly_rate'],
                'weekly_wage': insertedMember['weekly_wage'],
                'module_permissions': insertedMember['module_permissions'],
              }
            : {
                'role': _roleToString(role),
                'hourly_rate': defaultHourlyRate,
                'weekly_wage': defaultWeeklyWage,
              },
      );

      await _notifyWorkspaceMemberJoined(
        workspaceId: workspaceId,
        joinedUserId: userId,
        joinedRole: _roleToString(role),
      );

      AppLogger.info(
        'Member added to workspace',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'role': role.toString(),
        },
      );
    } catch (e) {
      AppLogger.error('Failed to add member', error: e);
      rethrow;
    }
  }

  Future<void> _notifyWorkspaceMemberJoined({
    required String workspaceId,
    required String joinedUserId,
    required String joinedRole,
  }) async {
    try {
      await _supabase.rpc(
        'create_workspace_member_join_notifications',
        params: {
          'p_workspace_id': workspaceId,
          'p_joined_user_id': joinedUserId,
          'p_joined_role': joinedRole,
        },
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to create workspace member join notifications',
        metadata: {
          'workspaceId': workspaceId,
          'joinedUserId': joinedUserId,
          'joinedRole': joinedRole,
          'error': e.toString(),
        },
      );
    }
  }

  /// Remove a member from a workspace
  Future<void> removeMember({
    required String workspaceId,
    required String userId,
  }) async {
    try {
      final previousMember = await _supabase
          .from('workspace_members')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      // Check if this is the last admin
      final isLastAdmin = await _isLastAdmin(workspaceId, userId);
      if (isLastAdmin) {
        throw UserFacingException(
          'Cannot remove the last admin. Promote another member to admin first.',
        );
      }

      await _supabase
          .from('workspace_members')
          .delete()
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId);

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.removed',
        beforeData: previousMember != null
            ? {
                'role': previousMember['role'],
                'hourly_rate': previousMember['hourly_rate'],
                'weekly_wage': previousMember['weekly_wage'],
                'module_permissions': previousMember['module_permissions'],
              }
            : null,
        afterData: null,
      );

      AppLogger.info(
        'Member removed from workspace',
        metadata: {'workspaceId': workspaceId, 'userId': userId},
      );
    } catch (e) {
      AppLogger.error('Failed to remove member', error: e);
      rethrow;
    }
  }

  /// Update a member's role in a workspace
  Future<void> updateMemberRole({
    required String workspaceId,
    required String userId,
    required UserRole newRole,
  }) async {
    try {
      final previousMember = await _supabase
          .from('workspace_members')
          .select('role')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      final currentRole = await getUserRole(workspaceId, userId);

      if (currentRole == UserRole.masterAdmin &&
          newRole != UserRole.masterAdmin) {
        final isLastMaster = await _isLastMasterAdmin(workspaceId, userId);
        if (isLastMaster) {
          throw UserFacingException(
            'Cannot demote the last Master Admin. Promote another member to '
            'Master Admin first.',
          );
        }
      }

      if (currentRole == UserRole.admin && newRole != UserRole.admin) {
        final isLastAdmin = await _isLastAdmin(workspaceId, userId);
        if (isLastAdmin) {
          throw UserFacingException(
            'Cannot demote the last admin. Promote another member to admin first.',
          );
        }
      }

      final updatedMember = await _supabase
          .from('workspace_members')
          .update({
            'role': _roleToString(newRole),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .select('role')
          .maybeSingle();

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.role_updated',
        beforeData: {'role': previousMember?['role']},
        afterData: {'role': updatedMember?['role'] ?? _roleToString(newRole)},
      );

      AppLogger.info(
        'Member role updated',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'newRole': newRole.toString(),
        },
      );
    } catch (e) {
      AppLogger.error('Failed to update member role', error: e);
      rethrow;
    }
  }

  /// Get all members of a workspace
  Stream<List<WorkspaceMember>> getWorkspaceMembers(String workspaceId) {
    return _supabase
        .from('workspace_members')
        .stream(primaryKey: ['workspace_id', 'user_id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map(
          (data) => data
              .map(
                (row) => WorkspaceMember.fromJson(
                  _toFirestoreFormat(row),
                  '${row['workspace_id']}_${row['user_id']}',
                ),
              )
              .toList(),
        );
  }

  /// Get all workspaces a user belongs to
  Future<List<WorkspaceMembership>> getUserWorkspaces(String userId) async {
    try {
      print('getUserWorkspaces: Querying for userId=$userId');

      final membershipData = await _supabase
          .from('workspace_members')
          .select(
            '*, workspaces(id, name, avatar_url, project_terminology, enabled_navigation_tabs, show_business_days_only, currency_code, timezone, hourly_rate, weekly_wage, default_tax_enabled, default_tax_name, default_tax_rate, ai_persona_name, ai_persona_avatar, ai_persona_style, ai_persona_context, onboarding_completed), workspace_role_templates(id, name, is_admin, module_permissions)',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      print(
        'getUserWorkspaces: Found ${membershipData.length} membership documents',
      );

      final workspaces = <WorkspaceMembership>[];

      for (final row in membershipData as List) {
        final workspaceData = row['workspaces'];
        if (workspaceData != null) {
          final role = _stringToRole(row['role'] as String?);
          final templateData =
              row['workspace_role_templates'] as Map<String, dynamic>?;
          final templateIsAdmin = templateData?['is_admin'] as bool? ?? false;
          final modulePermissions = normalizeModulePermissions(
            templateIsAdmin
                ? <String, String>{
                    'projects': 'write',
                    'tasks': 'write',
                    'budget': 'write',
                    'documents': 'write',
                    'team': 'write',
                    'settings': 'write',
                  }
                : templateData?['module_permissions'] != null
                ? Map<String, String>.from(
                    templateData!['module_permissions'] as Map,
                  )
                : row['module_permissions'] != null
                ? Map<String, String>.from(row['module_permissions'] as Map)
                : defaultPermissionsForRole(role),
          );
          workspaces.add(
            WorkspaceMembership(
              membershipId: row['id'].toString(),
              workspaceId: row['workspace_id'] as String,
              workspaceName:
                  workspaceData['name'] as String? ?? 'Unnamed Workspace',
              avatarUrl: workspaceData['avatar_url'] as String?,
              role: role,
              roleName: templateData?['name'] as String?,
              joinedAt: row['created_at'] != null
                  ? DateTime.parse(row['created_at'])
                  : DateTime.now(),
              projectTerminology:
                  workspaceData['project_terminology'] as String?,
              enabledNavigationTabs:
                  workspaceData['enabled_navigation_tabs'] != null
                  ? List<String>.from(
                      workspaceData['enabled_navigation_tabs'] as List,
                    )
                  : const [],
              showBusinessDaysOnly:
                  workspaceData['show_business_days_only'] as bool? ?? false,
              currencyCode: workspaceData['currency_code'] as String? ?? 'USD',
              timezone: workspaceData['timezone'] as String? ?? 'UTC',
              unitSystem: UnitSystem.fromValue(
                workspaceData['unit_system'] as String?,
              ),
              hourlyRate: (row['hourly_rate'] as num?)?.toDouble(),
              defaultHourlyRate: (workspaceData['hourly_rate'] as num?)
                  ?.toDouble(),
              weeklyWage: (row['weekly_wage'] as num?)?.toDouble(),
              defaultWeeklyWage: (workspaceData['weekly_wage'] as num?)
                  ?.toDouble(),
              modulePermissions: modulePermissions,
              defaultTaxEnabled:
                  workspaceData['default_tax_enabled'] as bool? ?? true,
              defaultTaxName:
                  workspaceData['default_tax_name'] as String? ?? 'Tax',
              defaultTaxRate:
                  (workspaceData['default_tax_rate'] as num?)?.toDouble() ?? 0,
              aiPersonaName: workspaceData['ai_persona_name'] as String?,
              aiPersonaAvatar: workspaceData['ai_persona_avatar'] as String?,
              aiPersonaStyle: workspaceData['ai_persona_style'] as String?,
              aiPersonaContext: workspaceData['ai_persona_context'] as String?,
              onboardingCompleted:
                  workspaceData['onboarding_completed'] as bool? ?? true,
            ),
          );
        }
      }

      print('getUserWorkspaces: Returning ${workspaces.length} workspaces');
      return workspaces;
    } catch (e) {
      print('getUserWorkspaces: Error - $e');
      AppLogger.error('Failed to get user workspaces', error: e);
      return [];
    }
  }

  /// Check if a user is a member of a workspace
  Future<bool> isMember(String workspaceId, String userId) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      AppLogger.error('Failed to check membership', error: e);
      return false;
    }
  }

  /// Get a user's role in a workspace
  Future<UserRole?> getUserRole(String workspaceId, String userId) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select('role')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return _stringToRole(response['role'] as String?);
    } catch (e) {
      AppLogger.error('Failed to get user role', error: e);
      return null;
    }
  }

  /// Get a user's role, permissions, and interface mode in a single query.
  /// Returns a record with all three values to avoid multiple round-trips.
  Future<({UserRole? role, RolePermissions? permissions, String interfaceMode})>
  getMemberRoleData(String workspaceId, String userId) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select(
            'role, interface_mode, module_permissions, role_template_id, workspace_role_templates(id, name, role, is_admin, module_permissions, default_interface_mode)',
          )
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return (role: null, permissions: null, interfaceMode: 'manager');
      }

      final role = _stringToRole(response['role'] as String?);
      final templateData =
          response['workspace_role_templates'] as Map<String, dynamic>?;
      final interfaceMode =
          (response['interface_mode'] as String?) ??
          (templateData?['default_interface_mode'] as String?) ??
          (role == UserRole.fieldTechnician ? 'field' : 'manager');
      final memberPermissions = response['module_permissions'] != null
          ? Map<String, String>.from(response['module_permissions'] as Map)
          : const <String, String>{};

      final permissions = _resolveRolePermissions(
        templateData: templateData,
        memberPermissions: memberPermissions,
        legacyRole: role,
        defaultInterfaceMode: interfaceMode,
      );
      final resolvedRole =
          _stringToRoleOrNull(templateData?['role'] as String?) ??
          permissions.legacyRole;

      return (
        role: resolvedRole,
        permissions: permissions,
        interfaceMode: interfaceMode,
      );
    } catch (e) {
      AppLogger.error('Failed to get member role data', error: e);
      return (role: null, permissions: null, interfaceMode: 'manager');
    }
  }

  /// Get a user's role permissions from their role template
  Future<RolePermissions?> getUserRolePermissions(
    String workspaceId,
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select(
            'role, module_permissions, role_template_id, workspace_role_templates(id, name, role, is_admin, module_permissions, default_interface_mode)',
          )
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      final role = _stringToRole(response['role'] as String?);
      final templateData =
          response['workspace_role_templates'] as Map<String, dynamic>?;
      final memberPermissions = response['module_permissions'] != null
          ? Map<String, String>.from(response['module_permissions'] as Map)
          : const <String, String>{};

      return _resolveRolePermissions(
        templateData: templateData,
        memberPermissions: memberPermissions,
        legacyRole: role,
        defaultInterfaceMode: role == UserRole.fieldTechnician
            ? 'field'
            : 'manager',
      );
    } catch (e) {
      AppLogger.error('Failed to get user role permissions', error: e);
      return null;
    }
  }

  /// Update a member's role template
  Future<void> updateMemberRoleTemplate({
    required String workspaceId,
    required String userId,
    required String roleTemplateId,
  }) async {
    try {
      final previousMember = await _supabase
          .from('workspace_members')
          .select('role, role_template_id, workspace_role_templates(is_admin)')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      // Check if demoting from admin
      final previousTemplate =
          previousMember?['workspace_role_templates'] as Map<String, dynamic>?;
      final wasAdmin =
          previousMember?['role'] == 'admin' ||
          (previousTemplate?['is_admin'] as bool? ?? false);

      // Get the new template to determine legacy role
      final template = await _supabase
          .from('workspace_role_templates')
          .select(
            'id, workspace_id, name, role, is_admin, module_permissions, default_interface_mode',
          )
          .eq('id', roleTemplateId)
          .single();

      if (template['workspace_id'] != workspaceId) {
        throw UserFacingException(
          'Cannot assign a role template from another workspace.',
        );
      }

      final newIsAdmin = template['is_admin'] as bool? ?? false;

      final previousLegacyRole = previousMember?['role'] as String?;
      final newLegacyRole = template['role'] as String?;
      if (previousLegacyRole == 'master_admin' &&
          newLegacyRole != 'master_admin') {
        final isLastMaster = await _isLastMasterAdmin(workspaceId, userId);
        if (isLastMaster) {
          throw UserFacingException(
            'Cannot demote the last Master Admin. Promote another member to '
            'Master Admin first.',
          );
        }
      }

      if (wasAdmin && !newIsAdmin) {
        final isLast = await _isLastAdmin(workspaceId, userId);
        if (isLast) {
          throw UserFacingException(
            'Cannot demote the last admin. Promote another member to admin first.',
          );
        }
      }

      // Determine legacy role column value
      final templateRole = template['role'] as String?;
      final legacyRole =
          templateRole ??
          _roleToString(RolePermissions.fromTemplateJson(template).legacyRole);

      final updatedMember = await _supabase
          .from('workspace_members')
          .update({
            'role_template_id': roleTemplateId,
            'role': legacyRole,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .select('role, role_template_id')
          .maybeSingle();

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.role_template_updated',
        beforeData: {
          'role': previousMember?['role'],
          'role_template_id': previousMember?['role_template_id'],
        },
        afterData: {
          'role': updatedMember?['role'] ?? legacyRole,
          'role_template_id':
              updatedMember?['role_template_id'] ?? roleTemplateId,
        },
      );

      AppLogger.info(
        'Member role template updated',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'roleTemplateId': roleTemplateId,
        },
      );
    } catch (e) {
      AppLogger.error('Failed to update member role template', error: e);
      rethrow;
    }
  }

  /// Check if a user is the only member holding the Master Admin tier in a
  /// workspace. Master Admin is the only role that manages users and billing,
  /// so the workspace must never drop to zero of them.
  Future<bool> _isLastMasterAdmin(String workspaceId, String userId) async {
    try {
      final rows = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .eq('role', 'master_admin');
      final ids = (rows as List)
          .map((m) => (m as Map<String, dynamic>)['user_id'] as String)
          .toSet();
      return ids.contains(userId) && ids.length == 1;
    } catch (e) {
      AppLogger.error('Failed to check if last master admin', error: e);
      return false;
    }
  }

  /// Check if a user is the last admin in a workspace.
  /// Fetches only admin members (legacy role='admin') and members with
  /// admin role templates, keeping data transfer minimal.
  Future<bool> _isLastAdmin(String workspaceId, String userId) async {
    try {
      // Fetch members who are admins via legacy role
      final legacyAdmins = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .eq('role', 'admin');

      // Fetch members who are admins via role template (using inner join)
      final templateAdmins = await _supabase
          .from('workspace_members')
          .select('user_id, workspace_role_templates!inner(is_admin)')
          .eq('workspace_id', workspaceId)
          .eq('workspace_role_templates.is_admin', true);

      // Merge unique admin user IDs
      final adminIds = <String>{
        ...((legacyAdmins as List).map((m) => m['user_id'] as String)),
        ...((templateAdmins as List).map((m) => m['user_id'] as String)),
      };

      return adminIds.contains(userId) && adminIds.length == 1;
    } catch (e) {
      AppLogger.error('Failed to check if last admin', error: e);
      return false;
    }
  }

  /// Get member count for a workspace
  Future<int> getMemberCount(String workspaceId) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select()
          .eq('workspace_id', workspaceId);

      return (response as List).length;
    } catch (e) {
      AppLogger.error('Failed to get member count', error: e);
      return 0;
    }
  }

  /// Update a member's skills
  Future<void> updateMemberSkills({
    required String workspaceId,
    required String userId,
    required List<String> skillIds,
  }) async {
    try {
      final previousMember = await _supabase
          .from('workspace_members')
          .select('skill_ids')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      final updatedMember = await _supabase
          .from('workspace_members')
          .update({
            'skill_ids': skillIds,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .select('skill_ids')
          .maybeSingle();

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.skills_updated',
        beforeData: {'skill_ids': previousMember?['skill_ids']},
        afterData: {'skill_ids': updatedMember?['skill_ids'] ?? skillIds},
      );

      AppLogger.info(
        'Member skills updated',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'skillCount': skillIds.length,
        },
      );
    } catch (e) {
      AppLogger.error('Failed to update member skills', error: e);
      rethrow;
    }
  }

  /// Get a member's interface mode
  Future<String> getMemberInterfaceMode(
    String workspaceId,
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('workspace_members')
          .select('interface_mode')
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();
      return (response?['interface_mode'] as String?) ?? 'manager';
    } catch (e) {
      AppLogger.warning(
        'Failed to get member interface mode, defaulting to manager',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'error': e.toString(),
        },
      );
      return 'manager';
    }
  }

  /// Update a member's settings (hourly rate, module permissions, and interface mode)
  Future<void> updateMemberSettings({
    required String workspaceId,
    required String userId,
    double? hourlyRate,
    double? weeklyWage,
    Map<String, String>? modulePermissions,
    String? interfaceMode,
  }) async {
    try {
      final previousMember = await _supabase
          .from('workspace_members')
          .select(
            'hourly_rate, weekly_wage, module_permissions, interface_mode',
          )
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .maybeSingle();

      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (hourlyRate != null) {
        updates['hourly_rate'] = hourlyRate;
      }
      if (weeklyWage != null) {
        updates['weekly_wage'] = weeklyWage;
      }

      if (modulePermissions != null) {
        updates['module_permissions'] = modulePermissions;
      }

      if (interfaceMode != null) {
        updates['interface_mode'] = interfaceMode;
      }

      final updatedMember = await _supabase
          .from('workspace_members')
          .update(updates)
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .select(
            'hourly_rate, weekly_wage, module_permissions, interface_mode',
          )
          .maybeSingle();

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_member',
        targetId: userId,
        eventType: 'workspace_member.settings_updated',
        beforeData: {
          'hourly_rate': previousMember?['hourly_rate'],
          'weekly_wage': previousMember?['weekly_wage'],
          'module_permissions': previousMember?['module_permissions'],
          'interface_mode': previousMember?['interface_mode'],
        },
        afterData: {
          'hourly_rate': updatedMember?['hourly_rate'],
          'weekly_wage': updatedMember?['weekly_wage'],
          'module_permissions': updatedMember?['module_permissions'],
          'interface_mode': updatedMember?['interface_mode'],
        },
      );

      AppLogger.info(
        'Member settings updated',
        metadata: {
          'workspaceId': workspaceId,
          'userId': userId,
          'hasHourlyRate': hourlyRate != null,
          'hasWeeklyWage': weeklyWage != null,
          'hasPermissions': modulePermissions != null,
          'hasInterfaceMode': interfaceMode != null,
        },
      );
    } catch (e) {
      AppLogger.error('Failed to update member settings', error: e);
      rethrow;
    }
  }

  String _roleToString(UserRole role) {
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
    }
  }

  UserRole _stringToRole(String? role) {
    switch (role) {
      case 'master_admin':
        return UserRole.masterAdmin;
      case 'admin':
        return UserRole.admin;
      case 'project_manager':
        return UserRole.projectManager;
      case 'field_technician':
        return UserRole.fieldTechnician;
      case 'client':
        return UserRole.client;
      case 'vendor':
        return UserRole.vendor;
      default:
        return UserRole.fieldTechnician;
    }
  }

  UserRole? _stringToRoleOrNull(String? role) {
    switch (role) {
      case 'master_admin':
        return UserRole.masterAdmin;
      case 'admin':
        return UserRole.admin;
      case 'project_manager':
        return UserRole.projectManager;
      case 'field_technician':
        return UserRole.fieldTechnician;
      case 'client':
        return UserRole.client;
      case 'vendor':
        return UserRole.vendor;
      default:
        return null;
    }
  }

  RolePermissions _resolveRolePermissions({
    required Map<String, dynamic>? templateData,
    required Map<String, String> memberPermissions,
    required UserRole legacyRole,
    required String defaultInterfaceMode,
  }) {
    if (templateData != null) {
      return RolePermissions.fromTemplateJson(
        templateData,
        legacyMemberRole: legacyRole,
      );
    }

    if (memberPermissions.isNotEmpty) {
      final isAdminTier =
          legacyRole == UserRole.admin || legacyRole == UserRole.masterAdmin;
      return RolePermissions(
        roleName: legacyRole.displayName,
        isAdmin: isAdminTier,
        modulePermissions: normalizeModulePermissions(memberPermissions),
        defaultInterfaceMode: defaultInterfaceMode,
        legacyMemberRole: legacyRole,
      );
    }

    return RolePermissions.fromLegacyRole(legacyRole);
  }

  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    // The database uses created_at instead of joined_at
    final createdAt = row['created_at'] != null
        ? Timestamp.fromDate(DateTime.parse(row['created_at']))
        : Timestamp.now();
    final updatedAt = row['updated_at'] != null
        ? Timestamp.fromDate(DateTime.parse(row['updated_at']))
        : createdAt;
    return {
      'workspaceId': row['workspace_id'],
      'userId': row['user_id'],
      'role': row['role'],
      'roleTemplateId': row['role_template_id'],
      'joinedAt': createdAt,
      'invitedBy': row['invited_by'],
      'skillIds': row['skill_ids'],
      'hourlyRate': row['hourly_rate'],
      'weeklyWage': row['weekly_wage'],
      'modulePermissions': row['module_permissions'],
      'interfaceMode': row['interface_mode'],
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
