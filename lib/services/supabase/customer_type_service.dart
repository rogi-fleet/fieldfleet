import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer_type_config.dart';
import '../../utils/app_logger.dart';

/// Supabase service for managing workspace-configurable customer types.
class SupabaseCustomerTypeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all customer types for a workspace, ordered by sort_order.
  Stream<List<CustomerTypeConfig>> getCustomerTypes(String workspaceId) {
    return _supabase
        .from('customer_types')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('sort_order')
        .map((data) {
          return data.map((row) => CustomerTypeConfig.fromJson(row)).toList();
        });
  }

  /// Get a single customer type by name (for lookups).
  Future<CustomerTypeConfig?> getCustomerTypeByName(
    String workspaceId,
    String name,
  ) async {
    try {
      final response = await _supabase
          .from('customer_types')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('name', name)
          .maybeSingle();

      if (response == null) return null;
      return CustomerTypeConfig.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get customer type by name',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Create a new customer type.
  Future<String> createCustomerType({
    required String workspaceId,
    required String name,
    required String color,
    String? description,
    int? sortOrder,
  }) async {
    try {
      final now = DateTime.now();

      // If no sort_order provided, put it at the end
      final order = sortOrder ??
          await _getNextSortOrder(workspaceId);

      final response = await _supabase.from('customer_types').insert({
        'workspace_id': workspaceId,
        'name': name.trim(),
        'color': color,
        'description': description?.trim(),
        'sort_order': order,
        'is_default': false,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      AppLogger.info('Created customer type', metadata: {
        'typeId': response['id'],
        'workspaceId': workspaceId,
        'name': name,
      });

      return response['id'];
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create customer type',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update a customer type.
  Future<void> updateCustomerType(
    String workspaceId,
    String typeId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final dbUpdates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Map camelCase keys to snake_case for DB
      updates.forEach((key, value) {
        dbUpdates[_toSnakeCase(key)] = value;
      });

      await _supabase
          .from('customer_types')
          .update(dbUpdates)
          .eq('workspace_id', workspaceId)
          .eq('id', typeId);

      AppLogger.info('Updated customer type', metadata: {
        'typeId': typeId,
        'workspaceId': workspaceId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update customer type',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Atomically update a customer type (name, color, description) and cascade
  /// name changes to all customers in one transaction.
  Future<void> fullUpdateCustomerType({
    required String workspaceId,
    required String typeId,
    required String oldName,
    required String newName,
    String? color,
    String? description,
  }) async {
    try {
      await _supabase.rpc('update_customer_type_full', params: {
        'p_workspace_id': workspaceId,
        'p_type_id': typeId,
        'p_old_name': oldName,
        'p_new_name': newName.trim(),
        'p_color': color,
        'p_description': description,
      });

      AppLogger.info('Updated customer type', metadata: {
        'typeId': typeId,
        'oldName': oldName,
        'newName': newName,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update customer type',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a customer type. Customers with this type will keep their
  /// current value but it won't appear in dropdowns anymore.
  Future<void> deleteCustomerType(String workspaceId, String typeId) async {
    try {
      await _supabase
          .from('customer_types')
          .delete()
          .eq('workspace_id', workspaceId)
          .eq('id', typeId);

      AppLogger.info('Deleted customer type', metadata: {
        'typeId': typeId,
        'workspaceId': workspaceId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete customer type',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get usage count for a customer type.
  Future<int> getTypeUsageCount(String workspaceId, String typeName) async {
    try {
      final customers = await _supabase
          .from('customers')
          .select('id')
          .eq('workspace_id', workspaceId)
          .eq('customer_type', typeName)
          .eq('is_active', true);

      return customers.length;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get customer type usage count',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  /// Ensure default types exist for a workspace (called on first access).
  Future<void> ensureDefaults(String workspaceId) async {
    try {
      await _supabase.rpc('seed_customer_types_for_workspace', params: {
        'p_workspace_id': workspaceId,
      });
    } catch (e) {
      AppLogger.warning('Failed to seed customer type defaults',
          metadata: {'error': e.toString()});
    }
  }

  Future<int> _getNextSortOrder(String workspaceId) async {
    try {
      final response = await _supabase
          .from('customer_types')
          .select('sort_order')
          .eq('workspace_id', workspaceId)
          .order('sort_order', ascending: false)
          .limit(1);

      if (response.isEmpty) return 0;
      return (response.first['sort_order'] as int) + 1;
    } catch (_) {
      return 0;
    }
  }

  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }
}
