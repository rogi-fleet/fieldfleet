import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../models/company_type.dart';
import '../../utils/app_logger.dart';
import '../../utils/timezone_options.dart';
import 'field_form_service.dart';
import 'settings_audit_service.dart';

class SupabaseWorkspaceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseSettingsAuditService _settingsAuditService =
      SupabaseSettingsAuditService();
  static const String _workspaceAvatarBucket =
      SupabaseConfig.workspaceLogosBucket;

  Future<String> createWorkspace({
    required String name,
    required String ownerId,
    required CompanyType companyType,
    String? projectTerminology,
    int? startingProjectSerialNumber,
    List<String>? enabledProjectTabs,
    String? companyAddress,
    String? companyCity,
    String? companyState,
    String? companyZipCode,
    String? companyCountry,
    String? website,
    String currencyCode = 'USD',
    String timezone = TimezoneOptions.defaultTimezone,
    String unitSystem = 'imperial',
    double? hourlyRate,
    double? weeklyWage,
    bool defaultTaxEnabled = true,
    String defaultTaxName = 'Tax',
    double? defaultTaxRate,
  }) async {
    try {
      final effectiveProjectTerminology =
          projectTerminology ?? companyType.defaultProjectTerminology;
      final effectiveEnabledTabs =
          enabledProjectTabs ?? companyType.defaultEnabledTabs;

      final now = DateTime.now();

      final workspaceData = {
        'name': name,
        'owner_id': ownerId,
        'company_type': companyType.name,
        'project_terminology': effectiveProjectTerminology,
        if (startingProjectSerialNumber != null)
          'starting_project_serial_number': startingProjectSerialNumber,
        if (effectiveEnabledTabs.isNotEmpty)
          'enabled_project_tabs': effectiveEnabledTabs,
        if (companyAddress != null) 'company_address': companyAddress,
        if (companyCity != null) 'company_city': companyCity,
        if (companyState != null) 'company_state': companyState,
        if (companyZipCode != null) 'company_zip_code': companyZipCode,
        if (companyCountry != null) 'company_country': companyCountry,
        if (website != null) 'website': website,
        'currency_code': currencyCode,
        'timezone': timezone,
        'unit_system': unitSystem,
        if (hourlyRate != null) 'hourly_rate': hourlyRate,
        if (weeklyWage != null) 'weekly_wage': weeklyWage,
        'default_tax_enabled': defaultTaxEnabled,
        'default_tax_name': defaultTaxName,
        if (defaultTaxRate != null) 'default_tax_rate': defaultTaxRate,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await _supabase
          .from('workspaces')
          .insert(workspaceData)
          .select()
          .single();

      final workspaceId = response['id'] as String;

      // Add owner as admin member
      await _supabase.from('workspace_members').insert({
        'workspace_id': workspaceId,
        'user_id': ownerId,
        'role': 'admin',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await _seedCoreDocumentTemplates(workspaceId, ownerId);
      await _seedCoreWorkflowTemplates(workspaceId, ownerId);
      await _seedDefaultFieldFormTemplates(workspaceId, ownerId);
      await _seedCustomerTypes(workspaceId);
      await _seedVendorTypes(workspaceId);
      await _seedCostCategories(workspaceId);

      AppLogger.info(
        'Workspace created',
        metadata: {
          'workspaceId': workspaceId,
          'name': name,
          'ownerId': ownerId,
        },
      );

      return workspaceId;
    } catch (e) {
      AppLogger.error('Failed to create workspace', error: e);
      rethrow;
    }
  }

  Future<void> _seedCoreDocumentTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await _supabase.rpc(
        'seed_core_document_templates',
        params: {'p_workspace_id': workspaceId, 'p_created_by': createdBy},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to seed core document templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _seedCoreWorkflowTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await _supabase.rpc(
        'seed_core_workflow_templates',
        params: {'p_workspace_id': workspaceId, 'p_created_by': createdBy},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to seed core workflow templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _seedDefaultFieldFormTemplates(
    String workspaceId,
    String createdBy,
  ) async {
    try {
      await FieldFormService().generateDefaultTemplates(
        workspaceId: workspaceId,
        createdBy: createdBy,
      );
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Failed to seed default field form templates',
        metadata: {
          'workspaceId': workspaceId,
          'createdBy': createdBy,
          'error': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _seedCustomerTypes(String workspaceId) async {
    try {
      await _supabase.rpc(
        'seed_customer_types_for_workspace',
        params: {'p_workspace_id': workspaceId},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to seed customer types',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
    }
  }

  Future<void> _seedVendorTypes(String workspaceId) async {
    try {
      await _supabase.rpc(
        'seed_vendor_types_for_workspace',
        params: {'p_workspace_id': workspaceId},
      );
      await _supabase.rpc(
        'seed_vendor_categories_for_workspace',
        params: {'p_workspace_id': workspaceId},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to seed vendor types',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
    }
  }

  /// Seeds the standard cost categories (mirrors the signup path) so budget
  /// items and vendor-bill categorisation work in workspaces created after
  /// signup.
  Future<void> _seedCostCategories(String workspaceId) async {
    try {
      final existing = await _supabase
          .from('cost_categories')
          .select('id')
          .eq('workspace_id', workspaceId)
          .limit(1);
      if ((existing as List).isNotEmpty) return;

      const categories = [
        ('Materials', '#3B82F6'),
        ('Labor', '#10B981'),
        ('Equipment', '#F59E0B'),
        ('Subcontractor', '#8B5CF6'),
        ('Permits & Fees', '#EF4444'),
        ('Overhead', '#6B7280'),
      ];

      final now = DateTime.now().toIso8601String();
      await _supabase.from('cost_categories').insert([
        for (final (name, color) in categories)
          {
            'workspace_id': workspaceId,
            'name': name,
            'color': color,
            'is_default': true,
            'created_at': now,
            'updated_at': now,
          },
      ]);
    } catch (e) {
      AppLogger.warning(
        'Failed to seed cost categories',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
    }
  }

  Future<void> updateWorkspace({
    required String workspaceId,
    required String name,
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
    String? unitSystem,
    double? hourlyRate,
    double? weeklyWage,
    bool? defaultTaxEnabled,
    String? defaultTaxName,
    double? defaultTaxRate,
    String? aiPersonaName,
    String? aiPersonaAvatar,
    String? aiPersonaStyle,
    String? aiPersonaContext,
    List<String>? goals,
    int? teamSize,
    Set<String>? touchedFields,
  }) async {
    try {
      final now = DateTime.now();
      final previousWorkspace = await _supabase
          .from('workspaces')
          .select()
          .eq('id', workspaceId)
          .maybeSingle();

      final updates = <String, dynamic>{'updated_at': now.toIso8601String()};

      bool shouldUpdate(String field) {
        return touchedFields == null || touchedFields.contains(field);
      }

      if (shouldUpdate('name')) {
        updates['name'] = name;
      }

      if (shouldUpdate('companyType') && companyType != null) {
        updates['company_type'] = companyType.name;
      }

      if (shouldUpdate('projectTerminology')) {
        updates['project_terminology'] = projectTerminology;
      } else if (projectTerminology != null) {
        updates['project_terminology'] = projectTerminology;
      }

      if (shouldUpdate('startingProjectSerialNumber')) {
        updates['starting_project_serial_number'] = startingProjectSerialNumber;
      } else if (startingProjectSerialNumber != null) {
        updates['starting_project_serial_number'] = startingProjectSerialNumber;
      }

      if (shouldUpdate('enabledProjectTabs')) {
        updates['enabled_project_tabs'] = enabledProjectTabs ?? [];
      } else if (touchedFields == null) {
        updates['enabled_project_tabs'] = enabledProjectTabs ?? [];
      }

      if (shouldUpdate('enabledNavigationTabs')) {
        updates['enabled_navigation_tabs'] = enabledNavigationTabs ?? [];
      } else if (touchedFields == null) {
        updates['enabled_navigation_tabs'] = enabledNavigationTabs ?? [];
      }

      if (shouldUpdate('showBusinessDaysOnly') &&
          showBusinessDaysOnly != null) {
        updates['show_business_days_only'] = showBusinessDaysOnly;
      } else if (showBusinessDaysOnly != null) {
        updates['show_business_days_only'] = showBusinessDaysOnly;
      }

      if (shouldUpdate('companyAddress')) {
        updates['company_address'] = companyAddress;
      } else if (touchedFields == null) {
        updates['company_address'] = companyAddress;
      }
      if (shouldUpdate('companyCity')) {
        updates['company_city'] = companyCity;
      } else if (touchedFields == null) {
        updates['company_city'] = companyCity;
      }
      if (shouldUpdate('companyState')) {
        updates['company_state'] = companyState;
      } else if (touchedFields == null) {
        updates['company_state'] = companyState;
      }
      if (shouldUpdate('companyZipCode')) {
        updates['company_zip_code'] = companyZipCode;
      } else if (touchedFields == null) {
        updates['company_zip_code'] = companyZipCode;
      }
      if (shouldUpdate('companyCountry')) {
        updates['company_country'] = companyCountry;
      } else if (touchedFields == null) {
        updates['company_country'] = companyCountry;
      }
      if (shouldUpdate('website')) {
        updates['website'] = website;
      } else if (touchedFields == null) {
        updates['website'] = website;
      }

      if (shouldUpdate('currencyCode') && currencyCode != null) {
        updates['currency_code'] = currencyCode;
      } else if (currencyCode != null) {
        updates['currency_code'] = currencyCode;
      }

      if (shouldUpdate('timezone') && timezone != null) {
        updates['timezone'] = timezone;
      } else if (timezone != null) {
        updates['timezone'] = timezone;
      }

      if (shouldUpdate('unitSystem') && unitSystem != null) {
        updates['unit_system'] = unitSystem;
      } else if (unitSystem != null) {
        updates['unit_system'] = unitSystem;
      }

      if (shouldUpdate('hourlyRate')) {
        updates['hourly_rate'] = hourlyRate;
      } else if (hourlyRate != null) {
        updates['hourly_rate'] = hourlyRate;
      }
      if (shouldUpdate('weeklyWage')) {
        updates['weekly_wage'] = weeklyWage;
      } else if (weeklyWage != null) {
        updates['weekly_wage'] = weeklyWage;
      }

      if (shouldUpdate('defaultTaxEnabled') && defaultTaxEnabled != null) {
        updates['default_tax_enabled'] = defaultTaxEnabled;
      }
      if (shouldUpdate('defaultTaxName')) {
        updates['default_tax_name'] = defaultTaxName;
      } else if (defaultTaxName != null) {
        updates['default_tax_name'] = defaultTaxName;
      }
      if (shouldUpdate('defaultTaxRate')) {
        updates['default_tax_rate'] = defaultTaxRate;
      } else if (defaultTaxRate != null) {
        updates['default_tax_rate'] = defaultTaxRate;
      }

      if (shouldUpdate('aiPersonaName')) {
        updates['ai_persona_name'] = aiPersonaName;
      } else if (aiPersonaName != null) {
        updates['ai_persona_name'] = aiPersonaName;
      }
      if (shouldUpdate('aiPersonaAvatar') && aiPersonaAvatar != null) {
        updates['ai_persona_avatar'] = aiPersonaAvatar;
      } else if (aiPersonaAvatar != null) {
        updates['ai_persona_avatar'] = aiPersonaAvatar;
      }
      if (shouldUpdate('aiPersonaStyle') && aiPersonaStyle != null) {
        updates['ai_persona_style'] = aiPersonaStyle;
      } else if (aiPersonaStyle != null) {
        updates['ai_persona_style'] = aiPersonaStyle;
      }
      if (shouldUpdate('aiPersonaContext')) {
        updates['ai_persona_context'] = aiPersonaContext;
      } else if (aiPersonaContext != null) {
        updates['ai_persona_context'] = aiPersonaContext;
      }

      if (shouldUpdate('goals') && goals != null) {
        updates['goals'] = goals;
      } else if (goals != null) {
        updates['goals'] = goals;
      }
      if (shouldUpdate('teamSize') && teamSize != null) {
        updates['team_size'] = teamSize;
      } else if (teamSize != null) {
        updates['team_size'] = teamSize;
      }

      final updatedWorkspace = await _supabase
          .from('workspaces')
          .update(updates)
          .eq('id', workspaceId)
          .select()
          .maybeSingle();

      if (updates.containsKey('starting_project_serial_number') &&
          startingProjectSerialNumber != null &&
          startingProjectSerialNumber > 0) {
        await _syncProjectSerialCounter(
          workspaceId: workspaceId,
          startingProjectSerialNumber: startingProjectSerialNumber,
        );
      }

      final auditedKeys = updates.keys.where((k) => k != 'updated_at').toList();
      final beforeData = <String, dynamic>{};
      final afterData = <String, dynamic>{};
      for (final key in auditedKeys) {
        beforeData[key] = previousWorkspace?[key];
        afterData[key] = updatedWorkspace?[key];
      }

      await _settingsAuditService.logEvent(
        workspaceId: workspaceId,
        targetType: 'workspace',
        targetId: workspaceId,
        eventType: 'workspace.updated',
        beforeData: beforeData,
        afterData: afterData,
      );

      AppLogger.info(
        'Workspace updated',
        metadata: {'workspaceId': workspaceId, 'name': name},
      );
    } catch (e) {
      AppLogger.error('Failed to update workspace', error: e);
      rethrow;
    }
  }

  Future<void> _syncProjectSerialCounter({
    required String workspaceId,
    required int startingProjectSerialNumber,
  }) async {
    final counterId = '${workspaceId}_project_serial';
    final desiredCounterValue = startingProjectSerialNumber - 1;

    final existingCounter = await _supabase
        .from('counters')
        .select('current_value')
        .eq('id', counterId)
        .maybeSingle();
    final existingCounterValue = existingCounter?['current_value'] as int? ?? 0;

    final projects = await _supabase
        .from('projects')
        .select('serial_number')
        .eq('workspace_id', workspaceId);

    final numericPattern = RegExp(r'^\d+$');
    int maxNumericProjectSerial = 0;
    for (final row in projects) {
      final rawSerial = row['serial_number'];
      if (rawSerial is! String) continue;
      final serial = rawSerial.trim();
      if (!numericPattern.hasMatch(serial)) continue;
      final parsed = int.tryParse(serial);
      if (parsed != null && parsed > maxNumericProjectSerial) {
        maxNumericProjectSerial = parsed;
      }
    }

    var nextCounterValue = desiredCounterValue;
    if (existingCounterValue > nextCounterValue) {
      nextCounterValue = existingCounterValue;
    }
    if (maxNumericProjectSerial > nextCounterValue) {
      nextCounterValue = maxNumericProjectSerial;
    }

    await _supabase.from('counters').upsert({
      'id': counterId,
      'workspace_id': workspaceId,
      'counter_type': 'project_serial',
      'current_value': nextCounterValue,
      'updated_at': DateTime.now().toIso8601String(),
    });

    AppLogger.info(
      'Synced project serial counter',
      metadata: {
        'workspaceId': workspaceId,
        'startingProjectSerialNumber': startingProjectSerialNumber,
        'counterValue': nextCounterValue,
      },
    );
  }

  Stream<Map<String, dynamic>?> getWorkspace(String workspaceId) {
    return _supabase
        .from('workspaces')
        .stream(primaryKey: ['id'])
        .eq('id', workspaceId)
        .map(
          (data) => data.isNotEmpty ? _transformToCamelCase(data.first) : null,
        );
  }

  /// Transform snake_case keys to camelCase for compatibility with the UI
  Map<String, dynamic> _transformToCamelCase(Map<String, dynamic> data) {
    return {
      'id': data['id'],
      'name': data['name'],
      'ownerId': data['owner_id'],
      'companyType': data['company_type'],
      'projectTerminology': data['project_terminology'],
      'startingProjectSerialNumber': data['starting_project_serial_number'],
      'enabledProjectTabs': data['enabled_project_tabs'],
      'enabledNavigationTabs': data['enabled_navigation_tabs'],
      'showBusinessDaysOnly': data['show_business_days_only'],
      'companyAddress': data['company_address'],
      'companyCity': data['company_city'],
      'companyState': data['company_state'],
      'companyZipCode': data['company_zip_code'],
      'companyCountry': data['company_country'],
      'website': data['website'],
      'currencyCode': data['currency_code'],
      'timezone': data['timezone'] ?? TimezoneOptions.defaultTimezone,
      'unitSystem': data['unit_system'] ?? 'imperial',
      'hourlyRate': (data['hourly_rate'] as num?)?.toDouble(),
      'weeklyWage': (data['weekly_wage'] as num?)?.toDouble(),
      'defaultTaxEnabled': data['default_tax_enabled'] as bool? ?? true,
      'defaultTaxName': data['default_tax_name'] as String? ?? 'Tax',
      'defaultTaxRate': (data['default_tax_rate'] as num?)?.toDouble() ?? 0,
      'aiPersonaName': data['ai_persona_name'],
      'aiPersonaAvatar': data['ai_persona_avatar'],
      'aiPersonaStyle': data['ai_persona_style'],
      'aiPersonaContext': data['ai_persona_context'],
      'avatarUrl': data['avatar_url'],
      'createdAt': data['created_at'],
      'updatedAt': data['updated_at'],
    };
  }

  /// Upload workspace avatar image
  Future<String> uploadWorkspaceAvatar(
    String workspaceId,
    Uint8List imageBytes,
    String fileName,
  ) async {
    try {
      // Validate file size (max 5MB)
      if (imageBytes.length > 5 * 1024 * 1024) {
        throw Exception('Image must be less than 5MB');
      }

      // Validate file type
      final lowerFileName = fileName.toLowerCase();
      if (!lowerFileName.endsWith('.jpg') &&
          !lowerFileName.endsWith('.jpeg') &&
          !lowerFileName.endsWith('.png') &&
          !lowerFileName.endsWith('.heic') &&
          !lowerFileName.endsWith('.webp')) {
        throw Exception('Only JPEG, PNG, HEIC, and WebP images are allowed');
      }

      // Delete existing avatar if exists
      final workspaceData = await _supabase
          .from('workspaces')
          .select('avatar_url')
          .eq('id', workspaceId)
          .maybeSingle();

      final existingAvatarUrl = workspaceData?['avatar_url'] as String?;
      if (existingAvatarUrl != null) {
        try {
          final oldPath = _extractStoragePath(existingAvatarUrl);
          if (oldPath != null) {
            await _supabase.storage.from(_workspaceAvatarBucket).remove([
              oldPath,
            ]);
          }
        } catch (e) {
          AppLogger.warning(
            'Error deleting old workspace avatar',
            metadata: {'workspaceId': workspaceId, 'error': e.toString()},
          );
        }
      }

      // Upload to Supabase Storage (unique path per upload for cache-busting)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'workspaces/$workspaceId/avatar_$timestamp.jpg';
      await _supabase.storage.from(_workspaceAvatarBucket).uploadBinary(
            storagePath,
            imageBytes,
            fileOptions: FileOptions(
              contentType: _getContentType(lowerFileName),
              cacheControl: '31536000',
            ),
          );

      final downloadUrl = _supabase.storage
          .from(_workspaceAvatarBucket)
          .getPublicUrl(storagePath);

      await _supabase.from('workspaces').update({
        'avatar_url': downloadUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workspaceId);

      AppLogger.info(
        'Workspace avatar uploaded',
        metadata: {'workspaceId': workspaceId},
      );

      return downloadUrl;
    } catch (e) {
      AppLogger.error(
        'Failed to upload workspace avatar',
        error: e,
        metadata: {'workspaceId': workspaceId},
      );
      throw Exception('Failed to upload workspace avatar: $e');
    }
  }

  /// Delete workspace avatar
  Future<void> deleteWorkspaceAvatar(
    String workspaceId,
    String avatarUrl,
  ) async {
    try {
      final path = _extractStoragePath(avatarUrl);
      if (path != null) {
        await _supabase.storage.from(_workspaceAvatarBucket).remove([path]);
        AppLogger.info(
          'Deleted workspace avatar from storage',
          metadata: {'workspaceId': workspaceId},
        );
      }

      await _supabase.from('workspaces').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', workspaceId);

      AppLogger.info(
        'Workspace avatar removed',
        metadata: {'workspaceId': workspaceId},
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to delete workspace avatar',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
      try {
        await _supabase.from('workspaces').update({
          'avatar_url': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', workspaceId);
      } catch (updateError) {
        AppLogger.error(
          'Failed to update workspace after avatar deletion error',
          error: updateError,
          metadata: {'workspaceId': workspaceId},
        );
      }
    }
  }

  String? _extractStoragePath(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_workspaceAvatarBucket);
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(bucketIndex + 1).join('/');
      }
      final legacyAvatarsBucketIndex = pathSegments.indexOf('avatars');
      if (legacyAvatarsBucketIndex >= 0 &&
          legacyAvatarsBucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(legacyAvatarsBucketIndex + 1).join('/');
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _getContentType(String fileName) {
    if (fileName.endsWith('.png')) return 'image/png';
    if (fileName.endsWith('.webp')) return 'image/webp';
    if (fileName.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}
