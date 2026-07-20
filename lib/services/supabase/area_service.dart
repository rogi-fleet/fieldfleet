import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/area.dart';
import '../../models/area_status.dart';
import '../../utils/app_logger.dart';
import 'property_service.dart';

/// Supabase service for managing areas within properties.
class SupabaseAreaService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabasePropertyService _propertyService = SupabasePropertyService();

  /// Create a new area
  Future<String> createArea(Area area) async {
    try {
      final now = DateTime.now();
      final areaData = _toDbFormat(area);
      areaData['created_at'] = now.toIso8601String();
      areaData['updated_at'] = now.toIso8601String();

      AppLogger.info('Creating area with data', metadata: {
        'propertyId': area.propertyId,
        'workspaceId': area.workspaceId,
        'projectId': area.projectId,
        'name': area.name,
        'areaData': areaData.toString(),
      });

      final response = await _supabase
          .from('areas')
          .insert(areaData)
          .select('id')
          .single();

      AppLogger.info('Area insert response', metadata: {
        'response': response.toString(),
      });

      // Update property area count
      await _propertyService.incrementAreaCount(
        area.propertyId,
        isDry: area.isDry,
      );

      AppLogger.info('Area created successfully', metadata: {
        'areaId': response['id'],
        'propertyId': area.propertyId,
      });

      return response['id'];
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create area', error: e, metadata: {
        'stackTrace': stackTrace.toString(),
      });
      rethrow;
    }
  }

  /// Update an existing area
  Future<void> updateArea(Area area, {Area? previousArea}) async {
    try {
      final areaData = _toDbFormat(area);
      areaData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('areas').update(areaData).eq('id', area.id);

      // Update dry count if status changed
      if (previousArea != null && previousArea.isDry != area.isDry) {
        await _propertyService.updateDryAreaCount(
          area.propertyId,
          area.isDry,
        );
      }

      AppLogger.info('Area updated', metadata: {'areaId': area.id});
    } catch (e) {
      AppLogger.error('Failed to update area', error: e);
      rethrow;
    }
  }

  /// Delete an area
  Future<void> deleteArea(Area area) async {
    try {
      await _supabase.from('areas').delete().eq('id', area.id);

      // Update property area count
      await _propertyService.decrementAreaCount(
        area.propertyId,
        wasDry: area.isDry,
      );

      AppLogger.info('Area deleted', metadata: {'areaId': area.id});
    } catch (e) {
      AppLogger.error('Failed to delete area', error: e);
      rethrow;
    }
  }

  /// Get a single area by ID
  Future<Area?> getArea(String areaId) async {
    try {
      final response = await _supabase
          .from('areas')
          .select()
          .eq('id', areaId)
          .maybeSingle();

      if (response == null) return null;
      return _toArea(response);
    } catch (e) {
      AppLogger.error('Failed to get area', error: e);
      return null;
    }
  }

  /// Watch a single area (real-time updates)
  Stream<Area?> watchArea(String areaId) {
    return _supabase
        .from('areas')
        .stream(primaryKey: ['id'])
        .eq('id', areaId)
        .map((data) {
          if (data.isEmpty) return null;
          return _toArea(data.first);
        });
  }

  /// Get all areas for a property (real-time stream)
  Stream<List<Area>> getAreas(String propertyId, {String? workspaceId}) async* {
    AppLogger.info('getAreas called', metadata: {
      'propertyId': propertyId,
      'workspaceId': workspaceId,
    });

    // First, fetch initial data via regular query
    try {
      var filterQuery = _supabase
          .from('areas')
          .select()
          .eq('property_id', propertyId);

      if (workspaceId != null) {
        filterQuery = filterQuery.eq('workspace_id', workspaceId);
      }

      final initialData = await filterQuery.order('created_at', ascending: true);
      AppLogger.info('getAreas initial fetch result', metadata: {
        'count': initialData.length,
        'data': initialData.toString(),
      });
      yield initialData.map((row) => _toArea(row)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch initial areas', error: e, metadata: {
        'propertyId': propertyId,
        'stackTrace': stackTrace.toString(),
      });
      yield <Area>[];
    }

    // Then subscribe to realtime updates
    AppLogger.info('getAreas subscribing to realtime', metadata: {
      'propertyId': propertyId,
      'filterWorkspaceId': workspaceId,
    });
    yield* _supabase
        .from('areas')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .order('created_at', ascending: true)
        .map((data) {
          AppLogger.info('getAreas realtime update received', metadata: {
            'count': data.length,
            'propertyId': propertyId,
            'rawData': data.map((r) => {'id': r['id'], 'name': r['name'], 'workspace_id': r['workspace_id']}).toList().toString(),
          });
          var areas = data.map((row) => _toArea(row)).toList();
          AppLogger.info('getAreas after conversion', metadata: {
            'areasCount': areas.length,
            'areaWorkspaceIds': areas.map((a) => a.workspaceId).toList().toString(),
            'filterWorkspaceId': workspaceId,
          });
          if (workspaceId != null) {
            final beforeFilter = areas.length;
            areas = areas.where((a) => a.workspaceId == workspaceId).toList();
            AppLogger.info('getAreas after workspace filter', metadata: {
              'before': beforeFilter,
              'after': areas.length,
              'workspaceId': workspaceId,
            });
          }
          return areas;
        });
  }

  /// Get areas by project
  Stream<List<Area>> getAreasByProject(String projectId, {String? workspaceId}) async* {
    // First, fetch initial data via regular query
    try {
      var filterQuery = _supabase
          .from('areas')
          .select()
          .eq('project_id', projectId);

      if (workspaceId != null) {
        filterQuery = filterQuery.eq('workspace_id', workspaceId);
      }

      final initialData = await filterQuery.order('created_at', ascending: true);
      yield initialData.map((row) => _toArea(row)).toList();
    } catch (e) {
      AppLogger.error('Failed to fetch initial areas by project', error: e);
      yield <Area>[];
    }

    // Then subscribe to realtime updates
    yield* _supabase
        .from('areas')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('created_at', ascending: true)
        .map((data) {
          var areas = data.map((row) => _toArea(row)).toList();
          if (workspaceId != null) {
            areas = areas.where((a) => a.workspaceId == workspaceId).toList();
          }
          return areas;
        });
  }

  /// Get affected areas for a property
  Stream<List<Area>> getAffectedAreas(String propertyId, {String? workspaceId}) async* {
    // First, fetch initial data via regular query
    try {
      var query = _supabase
          .from('areas')
          .select()
          .eq('property_id', propertyId)
          .eq('is_affected', true);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final initialData = await query;
      yield initialData.map((row) => _toArea(row)).toList();
    } catch (e) {
      AppLogger.error('Failed to fetch initial affected areas', error: e);
      yield <Area>[];
    }

    // Then subscribe to realtime updates
    yield* _supabase
        .from('areas')
        .stream(primaryKey: ['id'])
        .eq('property_id', propertyId)
        .map((data) {
          var areas = data
              .where((row) => row['is_affected'] == true)
              .map((row) => _toArea(row))
              .toList();
          if (workspaceId != null) {
            areas = areas.where((a) => a.workspaceId == workspaceId).toList();
          }
          return areas;
        });
  }

  /// Mark an area as dry
  Future<void> markAreaDry(String areaId, String propertyId) async {
    try {
      await _supabase.from('areas').update({
        'status': AreaStatus.dry.toDbValue(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', areaId);

      // Update property dry count
      await _propertyService.updateDryAreaCount(propertyId, true);

      AppLogger.info('Area marked as dry', metadata: {'areaId': areaId});
    } catch (e) {
      AppLogger.error('Failed to mark area as dry', error: e);
      rethrow;
    }
  }

  /// Update area trend
  Future<void> updateAreaTrend(String areaId, String trend) async {
    try {
      await _supabase.from('areas').update({
        'trend': trend,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', areaId);

      AppLogger.info('Area trend updated',
          metadata: {'areaId': areaId, 'trend': trend});
    } catch (e) {
      AppLogger.error('Failed to update area trend', error: e);
      rethrow;
    }
  }

  /// Get area summary for a property
  Future<Map<String, int>> getAreaSummary(String propertyId,
      {String? workspaceId}) async {
    try {
      var query = _supabase.from('areas').select().eq('property_id', propertyId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;

      final areas = response.map((row) => _toArea(row)).toList();

      final summary = <String, int>{
        'total': areas.length,
        'affected': areas.where((a) => a.isAffected).length,
        'dry': areas.where((a) => a.isDry).length,
        'drying': areas.where((a) => a.status == AreaStatus.drying).length,
      };

      return summary;
    } catch (e) {
      AppLogger.error('Failed to get area summary', error: e);
      return {'total': 0, 'affected': 0, 'dry': 0, 'drying': 0};
    }
  }

  /// Convert database row to Area
  Area _toArea(Map<String, dynamic> row) {
    return Area.fromJson(_toFirestoreFormat(row), row['id']);
  }

  /// Convert Supabase snake_case to Firestore camelCase format
  Map<String, dynamic> _toFirestoreFormat(Map<String, dynamic> row) {
    return {
      'projectId': row['project_id'],
      'workspaceId': row['workspace_id'],
      'propertyId': row['property_id'],
      'name': row['name'],
      'status': row['status'],
      'isAffected': row['is_affected'],
      'trend': row['trend'],
      'notes': row['notes'],
      'sketchStrokes': row['sketch_strokes'] is List
          ? row['sketch_strokes']
          : const [],
      'createdAt': row['created_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['created_at']))
          : Timestamp.now(),
      'updatedAt': row['updated_at'] != null
          ? Timestamp.fromDate(DateTime.parse(row['updated_at']))
          : Timestamp.now(),
    };
  }

  /// Convert Area to database format (snake_case)
  Map<String, dynamic> _toDbFormat(Area area) {
    final json = area.toJson();
    return {
      'project_id': json['projectId'],
      'workspace_id': json['workspaceId'],
      'property_id': json['propertyId'],
      'name': json['name'],
      'status': json['status'],
      'is_affected': json['isAffected'],
      'trend': json['trend'],
      'notes': json['notes'],
      'sketch_strokes': json['sketchStrokes'] ?? const [],
    };
  }
}
