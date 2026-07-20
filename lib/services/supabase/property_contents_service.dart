import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/property_contents.dart';
import '../../models/contents_status.dart';
import '../../utils/app_logger.dart';
import 'property_service.dart';

/// Supabase service for managing property contents items.
class SupabasePropertyContentsService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabasePropertyService _propertyService = SupabasePropertyService();

  /// Create a new contents item
  Future<String> createContents(PropertyContents contents) async {
    try {
      final now = DateTime.now();
      final contentsData = _toDbFormat(contents);
      contentsData['created_at'] = now.toIso8601String();
      contentsData['updated_at'] = now.toIso8601String();

      final response = await _supabase
          .from('property_contents')
          .insert(contentsData)
          .select('id')
          .single();

      // Update property contents count
      await _propertyService.incrementContentsCount(contents.propertyId);

      AppLogger.info('Contents item created', metadata: {
        'contentsId': response['id'],
        'propertyId': contents.propertyId,
      });

      return response['id'];
    } catch (e) {
      AppLogger.error('Failed to create contents item', error: e);
      rethrow;
    }
  }

  /// Update an existing contents item
  Future<void> updateContents(PropertyContents contents) async {
    try {
      final contentsData = _toDbFormat(contents);
      contentsData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('property_contents')
          .update(contentsData)
          .eq('id', contents.id);

      AppLogger.info('Contents item updated',
          metadata: {'contentsId': contents.id});
    } catch (e) {
      AppLogger.error('Failed to update contents item', error: e);
      rethrow;
    }
  }

  /// Delete a contents item
  Future<void> deleteContents(String contentsId, String propertyId) async {
    try {
      await _supabase.from('property_contents').delete().eq('id', contentsId);

      // Update property contents count
      await _propertyService.decrementContentsCount(propertyId);

      AppLogger.info('Contents item deleted',
          metadata: {'contentsId': contentsId});
    } catch (e) {
      AppLogger.error('Failed to delete contents item', error: e);
      rethrow;
    }
  }

  /// Get a single contents item by ID
  Future<PropertyContents?> getContents(String contentsId) async {
    try {
      final response = await _supabase
          .from('property_contents')
          .select()
          .eq('id', contentsId)
          .maybeSingle();

      if (response == null) return null;
      return _toPropertyContents(response);
    } catch (e) {
      AppLogger.error('Failed to get contents item', error: e);
      return null;
    }
  }

  /// Get all contents for a property (real-time stream)
  Stream<List<PropertyContents>> getContentsByProperty(String propertyId,
      {String? workspaceId}) {
    return _supabase
        .from('property_contents')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .order('created_at', ascending: false)
        .map((data) {
          var contents = data.map((row) => _toPropertyContents(row)).toList();
          if (workspaceId != null) {
            contents =
                contents.where((c) => c.workspaceId == workspaceId).toList();
          }
          return contents;
        });
  }

  /// Get contents for a specific area (real-time stream)
  Stream<List<PropertyContents>> getContentsByArea(String areaId,
      {String? workspaceId}) {
    return _supabase
        .from('property_contents')
        .stream(primaryKey: ['id'])
        .eq('area_id', areaId)
        .order('created_at', ascending: false)
        .map((data) {
          var contents = data.map((row) => _toPropertyContents(row)).toList();
          if (workspaceId != null) {
            contents =
                contents.where((c) => c.workspaceId == workspaceId).toList();
          }
          return contents;
        });
  }

  /// Find contents by barcode
  Future<PropertyContents?> findByBarcode(
      String workspaceId, String barcode) async {
    try {
      final response = await _supabase
          .from('property_contents')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('barcode', barcode)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return _toPropertyContents(response);
    } catch (e) {
      AppLogger.error('Failed to find contents by barcode', error: e);
      return null;
    }
  }

  /// Get contents statistics for a property
  Future<Map<String, int>> getContentsStats(String propertyId,
      {String? workspaceId}) async {
    try {
      var query = _supabase
          .from('property_contents')
          .select()
          .eq('property_id', propertyId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;

      final items = response.map((row) => _toPropertyContents(row)).toList();

      final stats = <String, int>{
        'total': items.length,
        'totalQuantity': items.fold(0, (sum, item) => sum + item.quantity),
      };

      // Count by status
      for (final status in ContentsStatus.values) {
        stats[status.name] = items.where((i) => i.status == status).length;
      }

      return stats;
    } catch (e) {
      AppLogger.error('Failed to get contents stats', error: e);
      return {'total': 0, 'totalQuantity': 0};
    }
  }

  /// Update contents status
  Future<void> updateStatus(String contentsId, ContentsStatus status) async {
    try {
      await _supabase.from('property_contents').update({
        'status': status.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', contentsId);

      AppLogger.info('Contents status updated',
          metadata: {'contentsId': contentsId, 'status': status.name});
    } catch (e) {
      AppLogger.error('Failed to update contents status', error: e);
      rethrow;
    }
  }

  /// Bulk update status for multiple items
  Future<void> bulkUpdateStatus(
      List<String> contentsIds, ContentsStatus status) async {
    try {
      final now = DateTime.now().toIso8601String();

      for (final id in contentsIds) {
        await _supabase.from('property_contents').update({
          'status': status.name,
          'updated_at': now,
        }).eq('id', id);
      }

      AppLogger.info('Bulk contents status updated',
          metadata: {'count': contentsIds.length, 'status': status.name});
    } catch (e) {
      AppLogger.error('Failed to bulk update contents status', error: e);
      rethrow;
    }
  }

  /// Get contents grouped by status
  Future<Map<ContentsStatus, List<PropertyContents>>> getContentsGroupedByStatus(
      String propertyId,
      {String? workspaceId}) async {
    try {
      var query = _supabase
          .from('property_contents')
          .select()
          .eq('property_id', propertyId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;

      final items = response.map((row) => _toPropertyContents(row)).toList();

      final grouped = <ContentsStatus, List<PropertyContents>>{};
      for (final status in ContentsStatus.values) {
        grouped[status] = items.where((i) => i.status == status).toList();
      }

      return grouped;
    } catch (e) {
      AppLogger.error('Failed to get contents grouped by status', error: e);
      return {};
    }
  }

  /// Convert database row to PropertyContents
  PropertyContents _toPropertyContents(Map<String, dynamic> row) {
    return PropertyContents.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'projectId': row['project_id'],
      'workspaceId': row['workspace_id'],
      'propertyId': row['property_id'],
      'areaId': row['area_id'],
      'name': row['name'],
      'description': row['description'],
      'category': row['category'],
      'quantity': row['quantity'],
      'condition': row['condition'],
      'status': row['status'],
      'barcode': row['barcode'],
      'estimatedValue': row['estimated_value'],
      'actualValue': row['actual_value'],
      'photoUrls': row['photo_urls'],
      'notes': row['notes'],
      'createdBy': row['created_by'],
      'createdAt': row['created_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['created_at']))
          : Timestamp.now(),
      'updatedAt': row['updated_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['updated_at']))
          : Timestamp.now(),
    };
  }

  /// Convert PropertyContents to database format (snake_case)
  Map<String, dynamic> _toDbFormat(PropertyContents contents) {
    final json = contents.toJson();
    return {
      'project_id': json['projectId'],
      'workspace_id': json['workspaceId'],
      'property_id': json['propertyId'],
      'area_id': json['areaId'],
      'name': json['name'],
      'description': json['description'],
      'category': json['category'],
      'quantity': json['quantity'],
      'condition': json['condition'],
      'status': json['status'],
      'barcode': json['barcode'],
      'estimated_value': json['estimatedValue'],
      'actual_value': json['actualValue'],
      'photo_urls': json['photoUrls'],
      'notes': json['notes'],
      'created_by': json['createdBy'],
    };
  }
}
