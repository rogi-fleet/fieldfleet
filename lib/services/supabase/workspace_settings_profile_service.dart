import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/workspace_settings_profile.dart';
import '../../utils/app_logger.dart';
import '../workspace_settings_profile_service.dart';
import 'settings_audit_service.dart';

class SupabaseWorkspaceSettingsProfileService
    extends WorkspaceSettingsProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseSettingsAuditService _auditService =
      SupabaseSettingsAuditService();

  @override
  Future<List<WorkspaceSettingsProfile>> getProfiles({
    required String workspaceId,
  }) async {
    final rows = await _supabase
        .from('workspace_settings_profiles')
        .select()
        .eq('workspace_id', workspaceId)
        .order('name', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(WorkspaceSettingsProfile.fromJson)
        .toList();
  }

  @override
  Future<WorkspaceSettingsProfile> createFromCurrentWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Profile name is required');
    }

    final workspace = await _supabase
        .from('workspaces')
        .select(
          'project_terminology, enabled_project_tabs, enabled_navigation_tabs, show_business_days_only, currency_code, timezone, hourly_rate, weekly_wage, default_tax_enabled, default_tax_name, default_tax_rate',
        )
        .eq('id', workspaceId)
        .single();

    final inserted = await _supabase
        .from('workspace_settings_profiles')
        .insert({
          'workspace_id': workspaceId,
          'name': trimmedName,
          'project_terminology': workspace['project_terminology'],
          'enabled_project_tabs':
              workspace['enabled_project_tabs'] ?? <String>[],
          'enabled_navigation_tabs':
              workspace['enabled_navigation_tabs'] ?? <String>[],
          'show_business_days_only':
              workspace['show_business_days_only'] ?? false,
          'currency_code': workspace['currency_code'] ?? 'USD',
          'timezone': workspace['timezone'] ?? 'UTC',
          'hourly_rate': workspace['hourly_rate'],
          'weekly_wage': workspace['weekly_wage'],
          'default_tax_enabled':
              workspace['default_tax_enabled'] ?? true,
          'default_tax_name':
              workspace['default_tax_name'] ?? 'Tax',
          'default_tax_rate': workspace['default_tax_rate'] ?? 0,
          'created_by': _supabase.auth.currentUser?.id,
        })
        .select()
        .single();

    await _auditService.logEvent(
      workspaceId: workspaceId,
      targetType: 'workspace_settings_profile',
      targetId: inserted['id'] as String,
      eventType: 'workspace_settings_profile.created',
      beforeData: null,
      afterData: {
        'name': inserted['name'],
        'project_terminology': inserted['project_terminology'],
        'enabled_project_tabs': inserted['enabled_project_tabs'],
        'enabled_navigation_tabs': inserted['enabled_navigation_tabs'],
        'show_business_days_only': inserted['show_business_days_only'],
        'currency_code': inserted['currency_code'],
        'timezone': inserted['timezone'],
        'hourly_rate': inserted['hourly_rate'],
        'weekly_wage': inserted['weekly_wage'],
        'default_tax_enabled': inserted['default_tax_enabled'],
        'default_tax_name': inserted['default_tax_name'],
        'default_tax_rate': inserted['default_tax_rate'],
      },
    );

    return WorkspaceSettingsProfile.fromJson(inserted);
  }

  @override
  Future<void> renameProfile({
    required String profileId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Profile name is required');
    }

    final previous = await _supabase
        .from('workspace_settings_profiles')
        .select('workspace_id, name')
        .eq('id', profileId)
        .single();

    final updated = await _supabase
        .from('workspace_settings_profiles')
        .update({'name': trimmedName})
        .eq('id', profileId)
        .select('name')
        .single();

    await _auditService.logEvent(
      workspaceId: previous['workspace_id'] as String,
      targetType: 'workspace_settings_profile',
      targetId: profileId,
      eventType: 'workspace_settings_profile.renamed',
      beforeData: {'name': previous['name']},
      afterData: {'name': updated['name']},
    );
  }

  @override
  Future<void> deleteProfile({required String profileId}) async {
    final previous = await _supabase
        .from('workspace_settings_profiles')
        .select()
        .eq('id', profileId)
        .maybeSingle();

    if (previous == null) {
      return;
    }

    await _supabase
        .from('workspace_settings_profiles')
        .delete()
        .eq('id', profileId);

    await _auditService.logEvent(
      workspaceId: previous['workspace_id'] as String,
      targetType: 'workspace_settings_profile',
      targetId: profileId,
      eventType: 'workspace_settings_profile.deleted',
      beforeData: {
        'name': previous['name'],
        'project_terminology': previous['project_terminology'],
        'enabled_project_tabs': previous['enabled_project_tabs'],
        'enabled_navigation_tabs': previous['enabled_navigation_tabs'],
        'show_business_days_only': previous['show_business_days_only'],
        'currency_code': previous['currency_code'],
        'timezone': previous['timezone'],
        'hourly_rate': previous['hourly_rate'],
        'weekly_wage': previous['weekly_wage'],
      },
      afterData: null,
    );
  }

  @override
  Future<void> applyProfile({
    required String workspaceId,
    required String profileId,
  }) async {
    try {
      final profile = await _supabase
          .from('workspace_settings_profiles')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('id', profileId)
          .single();

      final before = await _supabase
          .from('workspaces')
          .select(
            'project_terminology, enabled_project_tabs, enabled_navigation_tabs, show_business_days_only, currency_code, timezone, hourly_rate, weekly_wage, default_tax_enabled, default_tax_name, default_tax_rate',
          )
          .eq('id', workspaceId)
          .single();

      final updates = {
        'project_terminology': profile['project_terminology'],
        'enabled_project_tabs': profile['enabled_project_tabs'] ?? <String>[],
        'enabled_navigation_tabs':
            profile['enabled_navigation_tabs'] ?? <String>[],
        'show_business_days_only': profile['show_business_days_only'] ?? false,
        'currency_code': profile['currency_code'] ?? 'USD',
        'timezone': profile['timezone'] ?? 'UTC',
        'hourly_rate': profile['hourly_rate'],
        'weekly_wage': profile['weekly_wage'],
        'default_tax_enabled': profile['default_tax_enabled'] ?? true,
        'default_tax_name': profile['default_tax_name'] ?? 'Tax',
        'default_tax_rate': profile['default_tax_rate'] ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final after = await _supabase
          .from('workspaces')
          .update(updates)
          .eq('id', workspaceId)
          .select(
            'project_terminology, enabled_project_tabs, enabled_navigation_tabs, show_business_days_only, currency_code, timezone, hourly_rate, weekly_wage, default_tax_enabled, default_tax_name, default_tax_rate',
          )
          .single();

      await _auditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace_settings_profile',
        targetId: profileId,
        eventType: 'workspace_settings_profile.applied',
        beforeData: {'workspace': before, 'profile_name': profile['name']},
        afterData: {'workspace': after, 'profile_name': profile['name']},
      );
    } catch (e) {
      AppLogger.error('Failed to apply workspace settings profile', error: e);
      rethrow;
    }
  }
}
