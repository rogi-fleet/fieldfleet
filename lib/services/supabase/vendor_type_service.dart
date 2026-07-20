import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer_type_config.dart';
import '../../utils/app_logger.dart';

/// Supabase service for managing workspace-configurable vendor types and categories.
/// Reuses [CustomerTypeConfig] since the schema is identical.
class SupabaseVendorTypeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Vendor Types ──────────────────────────────────────────────────────

  Stream<List<CustomerTypeConfig>> getVendorTypes(String workspaceId) {
    return _supabase
        .from('vendor_types')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('sort_order')
        .map((data) => data.map((row) => CustomerTypeConfig.fromJson(row)).toList());
  }

  Future<String> createVendorType({
    required String workspaceId,
    required String name,
    required String color,
    String? description,
  }) async {
    try {
      final order = await _getNextSortOrder(workspaceId, 'vendor_types');
      final now = DateTime.now();

      final response = await _supabase.from('vendor_types').insert({
        'workspace_id': workspaceId,
        'name': name.trim(),
        'color': color,
        'description': description?.trim(),
        'sort_order': order,
        'is_default': false,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      return response['id'];
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create vendor type', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> updateVendorType(String workspaceId, String typeId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from('vendor_types')
          .update({...updates, 'updated_at': DateTime.now().toIso8601String()})
          .eq('workspace_id', workspaceId)
          .eq('id', typeId);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update vendor type', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> fullUpdateVendorType({
    required String workspaceId, required String typeId,
    required String oldName, required String newName,
    String? color, String? description,
  }) async {
    try {
      await _supabase.rpc('update_vendor_type_full', params: {
        'p_workspace_id': workspaceId, 'p_type_id': typeId,
        'p_old_name': oldName, 'p_new_name': newName.trim(),
        'p_color': color, 'p_description': description,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update vendor type', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> deleteVendorType(String workspaceId, String typeId) async {
    try {
      await _supabase.from('vendor_types').delete()
          .eq('workspace_id', workspaceId).eq('id', typeId);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete vendor type', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<int> getVendorTypeUsageCount(String workspaceId, String typeName) async {
    try {
      final rows = await _supabase.from('vendors').select('id')
          .eq('workspace_id', workspaceId).eq('vendor_type', typeName).eq('is_active', true);
      return rows.length;
    } catch (e) {
      return 0;
    }
  }

  // ── Vendor Categories ─────────────────────────────────────────────────

  Stream<List<CustomerTypeConfig>> getVendorCategories(String workspaceId) {
    return _supabase
        .from('vendor_categories')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('sort_order')
        .map((data) => data.map((row) => CustomerTypeConfig.fromJson(row)).toList());
  }

  Future<String> createVendorCategory({
    required String workspaceId,
    required String name,
    required String color,
    String? description,
  }) async {
    try {
      final order = await _getNextSortOrder(workspaceId, 'vendor_categories');
      final now = DateTime.now();

      final response = await _supabase.from('vendor_categories').insert({
        'workspace_id': workspaceId,
        'name': name.trim(),
        'color': color,
        'description': description?.trim(),
        'sort_order': order,
        'is_default': false,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      return response['id'];
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create vendor category', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> updateVendorCategory(String workspaceId, String catId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from('vendor_categories')
          .update({...updates, 'updated_at': DateTime.now().toIso8601String()})
          .eq('workspace_id', workspaceId)
          .eq('id', catId);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update vendor category', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> fullUpdateVendorCategory({
    required String workspaceId, required String catId,
    required String oldName, required String newName,
    String? color, String? description,
  }) async {
    try {
      await _supabase.rpc('update_vendor_category_full', params: {
        'p_workspace_id': workspaceId, 'p_category_id': catId,
        'p_old_name': oldName, 'p_new_name': newName.trim(),
        'p_color': color, 'p_description': description,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update vendor category', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> deleteVendorCategory(String workspaceId, String catId) async {
    try {
      await _supabase.from('vendor_categories').delete()
          .eq('workspace_id', workspaceId).eq('id', catId);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete vendor category', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<int> getVendorCategoryUsageCount(String workspaceId, String catName) async {
    try {
      final rows = await _supabase.from('vendors').select('id')
          .eq('workspace_id', workspaceId).eq('category', catName).eq('is_active', true);
      return rows.length;
    } catch (e) {
      return 0;
    }
  }

  // ── Seeding ───────────────────────────────────────────────────────────

  Future<void> ensureDefaults(String workspaceId) async {
    try {
      await _supabase.rpc('seed_vendor_types_for_workspace', params: {'p_workspace_id': workspaceId});
      await _supabase.rpc('seed_vendor_categories_for_workspace', params: {'p_workspace_id': workspaceId});
    } catch (e) {
      AppLogger.warning('Failed to seed vendor type defaults', metadata: {'error': e.toString()});
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<int> _getNextSortOrder(String workspaceId, String table) async {
    try {
      final response = await _supabase.from(table).select('sort_order')
          .eq('workspace_id', workspaceId).order('sort_order', ascending: false).limit(1);
      if (response.isEmpty) return 0;
      return (response.first['sort_order'] as int) + 1;
    } catch (_) {
      return 0;
    }
  }
}
