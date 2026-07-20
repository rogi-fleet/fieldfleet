import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/cost_category.dart';

/// Supabase implementation of CostCategoryService
class SupabaseCostCategoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create default categories for a workspace
  Future<void> createDefaultCategories(String workspaceId) async {
    try {
      final now = DateTime.now();

      for (final category in CostCategory.defaultCategories) {
        await _supabase.from('cost_categories').insert({
          'workspace_id': workspaceId,
          'name': category['name'],
          'color': category['color'],
          'is_default': true,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    } catch (e) {
      throw Exception('Error creating default categories: $e');
    }
  }

  /// Get all categories for a workspace
  Stream<List<CostCategory>> getCategories(String workspaceId) {
    try {
      return _supabase
          .from('cost_categories')
          .stream(primaryKey: ['id'])
          .eq('workspace_id', workspaceId)
          .order('name')
          .map((data) {
            return data.map((row) => _toCostCategory(row)).toList();
          });
    } catch (e) {
      throw Exception('Error fetching cost categories: $e');
    }
  }

  /// Get categories once (non-stream)
  Future<List<CostCategory>> getCategoriesOnce(String workspaceId) async {
    try {
      final response = await _supabase
          .from('cost_categories')
          .select()
          .eq('workspace_id', workspaceId)
          .order('name');

      return response.map((row) => _toCostCategory(row)).toList();
    } catch (e) {
      throw Exception('Error fetching cost categories: $e');
    }
  }

  /// Create a custom category
  Future<String> createCategory(CostCategory category) async {
    try {
      final now = DateTime.now();
      final response = await _supabase.from('cost_categories').insert({
        'workspace_id': category.workspaceId,
        'name': category.name,
        'color': category.color,
        'is_default': category.isDefault,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      return response['id'];
    } catch (e) {
      throw Exception('Error creating cost category: $e');
    }
  }

  /// Update a category
  Future<void> updateCategory(CostCategory category) async {
    try {
      await _supabase.from('cost_categories').update({
        'name': category.name,
        'color': category.color,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', category.id);
    } catch (e) {
      throw Exception('Error updating cost category: $e');
    }
  }

  /// Delete a custom category (cannot delete default categories)
  Future<void> deleteCategory(String categoryId) async {
    try {
      // First check if it's a default category
      final response = await _supabase
          .from('cost_categories')
          .select()
          .eq('id', categoryId)
          .maybeSingle();

      if (response != null && response['is_default'] == true) {
        throw Exception('Cannot delete default categories');
      }

      await _supabase.from('cost_categories').delete().eq('id', categoryId);
    } catch (e) {
      throw Exception('Error deleting cost category: $e');
    }
  }

  /// Get a specific category
  Future<CostCategory?> getCategory(String categoryId) async {
    try {
      final response = await _supabase
          .from('cost_categories')
          .select()
          .eq('id', categoryId)
          .maybeSingle();

      if (response == null) return null;
      return _toCostCategory(response);
    } catch (e) {
      throw Exception('Error fetching cost category: $e');
    }
  }

  /// Check if default categories exist for a workspace
  Future<bool> hasDefaultCategories(String workspaceId) async {
    try {
      final response = await _supabase
          .from('cost_categories')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('is_default', true)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking for default categories: $e');
    }
  }

  /// Convert database row to CostCategory
  CostCategory _toCostCategory(Map<String, dynamic> row) {
    return CostCategory(
      id: row['id'],
      workspaceId: row['workspace_id'],
      name: row['name'],
      color: row['color'],
      isDefault: row['is_default'] ?? false,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
    );
  }
}
