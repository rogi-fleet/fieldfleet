import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/custom_field_definition.dart';
import '../../models/custom_field_type.dart';
import '../../utils/app_logger.dart';

/// Supabase CRUD for [CustomFieldDefinition]s.
///
/// Definitions are workspace-scoped. The `key` field is generated here as
/// a stable surrogate (UUID-derived nanoid-style 10-char slug) and never
/// derived from the user-supplied label — see docs/plans/custom-fields.md.
///
/// In-place type changes are deliberately impossible via [updateDefinition]
/// (the SQL CHECK on `type` plus the omission of `type` from the update
/// payload). To change a field's type, archive and re-create.
class SupabaseCustomFieldDefinitionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  /// Generate a stable, URL-safe surrogate key. Format: `fld_<8-char-hex>`.
  /// 32 bits of entropy is more than enough for the 50-field-per-workspace
  /// cap; the leading `fld_` makes the key recognizable in jsonb dumps and
  /// rules out accidental collision with built-in column names.
  static String generateKey() {
    final raw = _uuid.v4().replaceAll('-', '');
    return 'fld_${raw.substring(0, 8)}';
  }

  /// All definitions for a workspace + entity, sorted by [sortOrder].
  /// [includeArchived] is on by default for the settings screen; pickers
  /// for end-user forms should pass false.
  Future<List<CustomFieldDefinition>> listDefinitions({
    required String workspaceId,
    String entityType = 'project',
    bool includeArchived = true,
  }) async {
    final rows = await _supabase
        .from('custom_field_definitions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('entity_type', entityType)
        .order('sort_order')
        .order('created_at');

    final all = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CustomFieldDefinition.fromRow)
        .toList();
    return includeArchived
        ? all
        : all.where((d) => !d.isArchived).toList();
  }

  /// Create a new definition. [key] is generated server-side; [sortOrder]
  /// defaults to "after the highest active sort_order", so newly added
  /// fields appear at the bottom of the list.
  Future<CustomFieldDefinition> createDefinition({
    required String workspaceId,
    required String entityType,
    required String label,
    required CustomFieldType type,
    String? fieldGroup,
    List<String>? options,
    dynamic defaultValue,
    bool isRequired = false,
    bool showInForm = true,
    bool groupable = false,
    String? createdBy,
  }) async {
    final nextOrder = await _nextSortOrder(workspaceId, entityType);

    final payload = {
      'workspace_id': workspaceId,
      'entity_type': entityType,
      'key': generateKey(),
      'label': label.trim(),
      'field_group': fieldGroup?.trim().isEmpty ?? true
          ? null
          : fieldGroup!.trim(),
      'type': type.wireName,
      'options': options == null
          ? null
          : <String, dynamic>{'items': options},
      'default_value': defaultValue,
      'is_required': isRequired,
      'show_in_form': showInForm,
      'groupable': groupable,
      'sort_order': nextOrder,
      if (createdBy != null) 'created_by': createdBy,
    };

    final response = await _supabase
        .from('custom_field_definitions')
        .insert(payload)
        .select()
        .single();

    AppLogger.info('Created custom field definition', metadata: {
      'definitionId': response['id'],
      'workspaceId': workspaceId,
      'entityType': entityType,
      'type': type.wireName,
    });

    return CustomFieldDefinition.fromRow(response);
  }

  /// Update an existing definition. `key` and `type` are immutable — to
  /// change type, archive + create a new field.
  Future<void> updateDefinition({
    required String id,
    String? label,
    String? fieldGroup,
    bool clearFieldGroup = false,
    List<String>? options,
    bool clearOptions = false,
    dynamic defaultValue,
    bool clearDefaultValue = false,
    bool? isRequired,
    bool? showInForm,
    bool? groupable,
  }) async {
    final updates = <String, dynamic>{};
    if (label != null) updates['label'] = label.trim();
    if (clearFieldGroup) {
      updates['field_group'] = null;
    } else if (fieldGroup != null) {
      final trimmed = fieldGroup.trim();
      updates['field_group'] = trimmed.isEmpty ? null : trimmed;
    }
    if (clearOptions) {
      updates['options'] = null;
    } else if (options != null) {
      updates['options'] = <String, dynamic>{'items': options};
    }
    if (clearDefaultValue) {
      updates['default_value'] = null;
    } else if (defaultValue != null) {
      updates['default_value'] = defaultValue;
    }
    if (isRequired != null) updates['is_required'] = isRequired;
    if (showInForm != null) updates['show_in_form'] = showInForm;
    if (groupable != null) updates['groupable'] = groupable;
    if (updates.isEmpty) return;

    await _supabase
        .from('custom_field_definitions')
        .update(updates)
        .eq('id', id);
  }

  Future<void> archiveDefinition(String id) async {
    await _supabase.from('custom_field_definitions').update({
      'archived_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> restoreDefinition(String id) async {
    await _supabase
        .from('custom_field_definitions')
        .update({'archived_at': null})
        .eq('id', id);
  }

  /// Bulk reorder. Caller passes the desired [orderedIds] (active defs
  /// only, in display order); this rewrites their `sort_order` to match.
  /// Archived defs keep their existing order — they don't render in the
  /// reorderable list.
  ///
  /// Implemented as N updates rather than a single `UPDATE … FROM (VALUES …)`
  /// because PostgREST doesn't expose multi-row updates with per-row values
  /// without a custom RPC. N is bounded by the soft cap (50).
  Future<void> reorderDefinitions(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _supabase
          .from('custom_field_definitions')
          .update({'sort_order': i})
          .eq('id', orderedIds[i]);
    }
  }

  /// Existing distinct group names in this workspace+entity, for the
  /// autocomplete in the Add Field dialog. Excludes archived defs and the
  /// implicit null/"Other" bucket.
  Future<List<String>> listFieldGroups({
    required String workspaceId,
    String entityType = 'project',
  }) async {
    final rows = await _supabase
        .from('custom_field_definitions')
        .select('field_group')
        .eq('workspace_id', workspaceId)
        .eq('entity_type', entityType)
        .isFilter('archived_at', null)
        .not('field_group', 'is', null);

    final seen = <String>{};
    final out = <String>[];
    for (final row in rows as List) {
      final g = row['field_group'] as String?;
      if (g == null || g.isEmpty) continue;
      if (seen.add(g)) out.add(g);
    }
    out.sort();
    return out;
  }

  /// Active count for the current workspace+entity. UI uses this to surface
  /// the soft-cap warning before the server-side trigger rejects the insert.
  Future<int> getActiveCount({
    required String workspaceId,
    String entityType = 'project',
  }) async {
    final result = await _supabase
        .from('custom_field_definitions')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('entity_type', entityType)
        .isFilter('archived_at', null)
        .count();
    return result.count;
  }

  /// Populate the side-table for an existing definition that was just
  /// promoted to `groupable=true`. Returns the number of project rows
  /// written. Idempotent.
  ///
  /// The settings UI calls this immediately after flipping groupable on
  /// so existing projects show up in reports — without it, only future
  /// project saves would be indexed.
  Future<int> backfillGroupableField(String definitionId) async {
    final result = await _supabase.rpc(
      'backfill_groupable_field',
      params: {'p_definition_id': definitionId},
    );
    return (result as int?) ?? 0;
  }

  Future<int> _nextSortOrder(String workspaceId, String entityType) async {
    final rows = await _supabase
        .from('custom_field_definitions')
        .select('sort_order')
        .eq('workspace_id', workspaceId)
        .eq('entity_type', entityType)
        .order('sort_order', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return 0;
    final top = rows.first['sort_order'] as int? ?? 0;
    return top + 1;
  }
}
