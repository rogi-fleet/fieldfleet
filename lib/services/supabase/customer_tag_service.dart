import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer_tag.dart';
import '../../utils/app_logger.dart';

/// Supabase implementation of CustomerTagService
class SupabaseCustomerTagService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new tag
  Future<String> createTag({
    required String workspaceId,
    required String name,
    required String color,
    String? description,
  }) async {
    try {
      final now = DateTime.now();

      final response = await _supabase.from('customer_tags').insert({
        'workspace_id': workspaceId,
        'name': name.trim(),
        'color': color,
        'description': description?.trim(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).select('id').single();

      AppLogger.info('Created customer tag', metadata: {
        'tagId': response['id'],
        'workspaceId': workspaceId,
        'name': name,
      });

      return response['id'];
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create customer tag', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get all tags for a workspace
  Stream<List<CustomerTag>> getTags(String workspaceId) {
    return _supabase
        .from('customer_tags')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('name')
        .map((data) {
          return data.map((row) => _toCustomerTag(row)).toList();
        });
  }

  /// Get a single tag by ID
  Future<CustomerTag?> getTag(String workspaceId, String tagId) async {
    try {
      final response = await _supabase
          .from('customer_tags')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('id', tagId)
          .maybeSingle();

      if (response == null) return null;
      return _toCustomerTag(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get customer tag', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Get multiple tags by their IDs
  Future<List<CustomerTag>> getTagsByIds(String workspaceId, List<String> tagIds) async {
    if (tagIds.isEmpty) return [];

    try {
      final response = await _supabase
          .from('customer_tags')
          .select()
          .eq('workspace_id', workspaceId)
          .inFilter('id', tagIds);

      return response.map((row) => _toCustomerTag(row)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get tags by IDs', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Update a tag
  Future<void> updateTag(
    String workspaceId,
    String tagId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final dbUpdates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      updates.forEach((key, value) {
        dbUpdates[_toSnakeCase(key)] = value;
      });

      await _supabase
          .from('customer_tags')
          .update(dbUpdates)
          .eq('workspace_id', workspaceId)
          .eq('id', tagId);

      AppLogger.info('Updated customer tag', metadata: {
        'tagId': tagId,
        'workspaceId': workspaceId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update customer tag', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a tag (also removes it from all customers)
  Future<void> deleteTag(String workspaceId, String tagId) async {
    try {
      // Find all customers with this tag
      final customers = await _supabase
          .from('customers')
          .select('id, tag_ids')
          .eq('workspace_id', workspaceId);

      // Remove tag from customers that have it
      for (final customer in customers) {
        final tagIds = List<String>.from(customer['tag_ids'] ?? []);
        if (tagIds.contains(tagId)) {
          tagIds.remove(tagId);
          await _supabase.from('customers').update({
            'tag_ids': tagIds,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', customer['id']);
        }
      }

      // Delete the tag
      await _supabase
          .from('customer_tags')
          .delete()
          .eq('workspace_id', workspaceId)
          .eq('id', tagId);

      AppLogger.info('Deleted customer tag', metadata: {
        'tagId': tagId,
        'workspaceId': workspaceId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete customer tag', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get usage count for a tag
  Future<int> getTagUsageCount(String workspaceId, String tagId) async {
    try {
      final customers = await _supabase
          .from('customers')
          .select('id')
          .eq('workspace_id', workspaceId)
          .contains('tag_ids', [tagId]);

      return customers.length;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get tag usage count', error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  /// Convert database row to CustomerTag
  CustomerTag _toCustomerTag(Map<String, dynamic> row) {
    return CustomerTag(
      id: row['id'],
      workspaceId: row['workspace_id'],
      name: row['name'],
      color: row['color'],
      description: row['description'],
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
    );
  }

  /// Convert camelCase to snake_case
  String _toSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }
}
