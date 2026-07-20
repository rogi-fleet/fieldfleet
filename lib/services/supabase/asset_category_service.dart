import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/asset_category_config.dart';
import '../../utils/app_logger.dart';

/// Workspace-scoped CRUD over the `asset_categories` table.
///
/// Mirrors [SupabaseCustomerTypeService] in shape: streamed list for
/// the settings screen, named lookup for hot paths (form dropdown,
/// card icon resolution).
class SupabaseAssetCategoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Live stream of categories for one workspace, ordered as the owner
  /// has arranged them.
  Stream<List<AssetCategoryConfig>> streamCategories(String workspaceId) {
    return _supabase
        .from('asset_categories')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('sort_order')
        .map((data) => data.map(AssetCategoryConfig.fromJson).toList());
  }

  /// One-shot fetch — used during exports and other non-reactive flows.
  Future<List<AssetCategoryConfig>> getCategories(String workspaceId) async {
    final rows = await _supabase
        .from('asset_categories')
        .select()
        .eq('workspace_id', workspaceId)
        .order('sort_order');
    return (rows as List)
        .map((r) => AssetCategoryConfig.fromJson(r))
        .toList();
  }

  Future<String> create({
    required String workspaceId,
    required String name,
    required String color,
    required String iconName,
  }) async {
    try {
      final order = await _nextSortOrder(workspaceId);
      final row = await _supabase
          .from('asset_categories')
          .insert({
            'workspace_id': workspaceId,
            'name': name.trim(),
            'color': color,
            'icon': iconName,
            'sort_order': order,
            'is_default': false,
          })
          .select('id')
          .single();
      return row['id'] as String;
    } catch (e, stack) {
      AppLogger.error('Failed to create asset category',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Rename + recolor + re-icon in one go. If [renameAssetsTo] is set we
  /// also update any `assets.category` rows that still carry the old
  /// name, so the lookup-by-name stays consistent.
  Future<void> update({
    required String workspaceId,
    required String id,
    required String oldName,
    required String newName,
    String? color,
    String? iconName,
  }) async {
    try {
      final updates = <String, dynamic>{'name': newName.trim()};
      if (color != null) updates['color'] = color;
      if (iconName != null) updates['icon'] = iconName;

      await _supabase
          .from('asset_categories')
          .update(updates)
          .eq('id', id);

      if (newName.trim() != oldName) {
        await _supabase
            .from('assets')
            .update({'category': newName.trim()})
            .eq('workspace_id', workspaceId)
            .eq('category', oldName);
      }
    } catch (e, stack) {
      AppLogger.error('Failed to update asset category',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a category. Reassigns any assets that reference it to
  /// [reassignTo] (default: 'Other'). Refuses to remove the only
  /// remaining category for safety.
  Future<void> delete({
    required String workspaceId,
    required String id,
    required String name,
    String reassignTo = 'Other',
  }) async {
    try {
      final remaining = await _supabase
          .from('asset_categories')
          .select('id')
          .eq('workspace_id', workspaceId);
      if ((remaining as List).length <= 1) {
        throw Exception('Cannot delete the last category');
      }

      // Reassign before deleting so existing assets land in a real
      // category rather than NULLing into the table default.
      await _supabase
          .from('assets')
          .update({'category': reassignTo})
          .eq('workspace_id', workspaceId)
          .eq('category', name);

      await _supabase.from('asset_categories').delete().eq('id', id);
    } catch (e, stack) {
      AppLogger.error('Failed to delete asset category',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Apply a new ordering. Caller passes the desired [orderedIds]; we
  /// rewrite `sort_order` to match the index in the list.
  Future<void> reorder(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    for (var i = 0; i < orderedIds.length; i++) {
      await _supabase
          .from('asset_categories')
          .update({'sort_order': i})
          .eq('id', orderedIds[i]);
    }
  }

  Future<int> _nextSortOrder(String workspaceId) async {
    final rows = await _supabase
        .from('asset_categories')
        .select('sort_order')
        .eq('workspace_id', workspaceId)
        .order('sort_order', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return 0;
    return ((rows.first['sort_order'] as int?) ?? 0) + 1;
  }
}
