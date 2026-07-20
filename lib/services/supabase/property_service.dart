import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../utils/app_logger.dart';

/// Supabase service for managing properties within projects.
class SupabasePropertyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new property
  Future<String> createProperty(Property property) async {
    try {
      final now = DateTime.now();
      final propertyData = _toDbFormat(property);
      propertyData['created_at'] = now.toIso8601String();
      propertyData['updated_at'] = now.toIso8601String();

      final response = await _supabase
          .from('properties')
          .insert(propertyData)
          .select('id')
          .single();

      AppLogger.info('Property created', metadata: {
        'propertyId': response['id'],
        'projectId': property.projectId,
      });

      return response['id'];
    } catch (e) {
      AppLogger.error('Failed to create property', error: e);
      rethrow;
    }
  }

  /// Update an existing property
  Future<void> updateProperty(Property property) async {
    try {
      final propertyData = _toDbFormat(property);
      propertyData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('properties')
          .update(propertyData)
          .eq('id', property.id);

      AppLogger.info('Property updated', metadata: {'propertyId': property.id});
    } catch (e) {
      AppLogger.error('Failed to update property', error: e);
      rethrow;
    }
  }

  /// Delete a property
  Future<void> deleteProperty(String propertyId) async {
    try {
      await _supabase.from('properties').delete().eq('id', propertyId);

      AppLogger.info('Property deleted', metadata: {'propertyId': propertyId});
    } catch (e) {
      AppLogger.error('Failed to delete property', error: e);
      rethrow;
    }
  }

  /// Get a single property by ID
  Future<Property?> getProperty(String propertyId) async {
    try {
      final response = await _supabase
          .from('properties')
          .select()
          .eq('id', propertyId)
          .maybeSingle();

      if (response == null) return null;
      return _toProperty(response);
    } catch (e) {
      AppLogger.error('Failed to get property', error: e);
      return null;
    }
  }

  /// Watch a single property (real-time updates)
  Stream<Property?> watchProperty(String propertyId) {
    return _supabase
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('id', propertyId)
        .map((data) {
          if (data.isEmpty) return null;
          return _toProperty(data.first);
        });
  }

  /// Get all properties for a project (real-time stream)
  Stream<List<Property>> getProperties(String projectId, {String? workspaceId}) {
    return _supabase
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('created_at', ascending: true)
        .map((data) {
          var properties = _dedupeById(
            data.map((row) => _toProperty(row)).toList(),
          );
          if (workspaceId != null) {
            properties = properties
                .where((p) => p.workspaceId == workspaceId)
                .toList();
          }
          return properties;
        });
  }

  /// Get properties by workspace
  Stream<List<Property>> getPropertiesByWorkspace(String workspaceId) {
    return _supabase
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false)
        .map((data) {
          return _dedupeById(data.map((row) => _toProperty(row)).toList());
        });
  }

  List<Property> _dedupeById(List<Property> properties) {
    final seenIds = <String>{};
    final deduped = <Property>[];
    for (final property in properties) {
      if (seenIds.add(property.id)) {
        deduped.add(property);
      }
    }
    return deduped;
  }

  /// Check if identifier is unique within a project
  Future<bool> isIdentifierUnique(
      String projectId, String identifier, String? excludePropertyId,
      {String? workspaceId}) async {
    try {
      var query = _supabase
          .from('properties')
          .select('id')
          .eq('project_id', projectId)
          .eq('identifier', identifier);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;

      if (excludePropertyId != null) {
        // Return true (unique) if all matching rows belong to the excluded property
        final otherProperties = response.where((row) => row['id'] != excludePropertyId);
        return otherProperties.isEmpty;
      }

      return response.isEmpty;
    } catch (e) {
      AppLogger.error('Failed to check identifier uniqueness', error: e);
      return false;
    }
  }

  /// Duplicate a property
  Future<String> duplicateProperty(
      String propertyId, String newIdentifier) async {
    try {
      final original = await getProperty(propertyId);
      if (original == null) {
        throw Exception('Property not found');
      }

      final now = DateTime.now();
      final duplicate = original.copyWith(
        id: '',
        identifier: newIdentifier,
        name: '${original.name} (Copy)',
        areaCount: 0,
        dryAreaCount: 0,
        contentsCount: 0,
        createdAt: now,
        updatedAt: now,
      );

      return await createProperty(duplicate);
    } catch (e) {
      AppLogger.error('Failed to duplicate property', error: e);
      rethrow;
    }
  }

  /// Archive a property (set status to archived)
  Future<void> archiveProperty(String propertyId) async {
    try {
      await _supabase.from('properties').update({
        'status': 'archived',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', propertyId);

      AppLogger.info('Property archived', metadata: {'propertyId': propertyId});
    } catch (e) {
      AppLogger.error('Failed to archive property', error: e);
      rethrow;
    }
  }

  /// Update property statistics (area counts)
  Future<void> updatePropertyStats(
    String propertyId, {
    int? areaCount,
    int? dryAreaCount,
    int? contentsCount,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (areaCount != null) updates['area_count'] = areaCount;
      if (dryAreaCount != null) updates['dry_area_count'] = dryAreaCount;
      if (contentsCount != null) updates['contents_count'] = contentsCount;

      await _supabase.from('properties').update(updates).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to update property stats', error: e);
      rethrow;
    }
  }

  /// Increment area count
  Future<void> incrementAreaCount(String propertyId, {bool isDry = false}) async {
    try {
      // Get current values first
      final current = await getProperty(propertyId);
      if (current == null) return;

      final updates = <String, dynamic>{
        'area_count': current.areaCount + 1,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (isDry) {
        updates['dry_area_count'] = current.dryAreaCount + 1;
      }

      await _supabase.from('properties').update(updates).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to increment area count', error: e);
      rethrow;
    }
  }

  /// Decrement area count
  Future<void> decrementAreaCount(String propertyId, {bool wasDry = false}) async {
    try {
      final current = await getProperty(propertyId);
      if (current == null) return;

      final updates = <String, dynamic>{
        'area_count': (current.areaCount - 1).clamp(0, double.infinity).toInt(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (wasDry) {
        updates['dry_area_count'] =
            (current.dryAreaCount - 1).clamp(0, double.infinity).toInt();
      }

      await _supabase.from('properties').update(updates).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to decrement area count', error: e);
      rethrow;
    }
  }

  /// Increment contents count
  Future<void> incrementContentsCount(String propertyId) async {
    try {
      final current = await getProperty(propertyId);
      if (current == null) return;

      await _supabase.from('properties').update({
        'contents_count': current.contentsCount + 1,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to increment contents count', error: e);
      rethrow;
    }
  }

  /// Decrement contents count
  Future<void> decrementContentsCount(String propertyId) async {
    try {
      final current = await getProperty(propertyId);
      if (current == null) return;

      await _supabase.from('properties').update({
        'contents_count':
            (current.contentsCount - 1).clamp(0, double.infinity).toInt(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to decrement contents count', error: e);
      rethrow;
    }
  }

  /// Update dry area count when an area's dry status changes
  Future<void> updateDryAreaCount(String propertyId, bool becameDry) async {
    try {
      final current = await getProperty(propertyId);
      if (current == null) return;

      final newCount = becameDry
          ? current.dryAreaCount + 1
          : (current.dryAreaCount - 1).clamp(0, double.infinity).toInt();

      await _supabase.from('properties').update({
        'dry_area_count': newCount,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', propertyId);
    } catch (e) {
      AppLogger.error('Failed to update dry area count', error: e);
      rethrow;
    }
  }

  /// Convert database row to Property
  Property _toProperty(Map<String, dynamic> row) {
    return Property(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      identifier: row['identifier'] as String,
      floor: row['floor'] as String?,
      occupant: row['occupant'] as String?,
      status: row['status'] != null
          ? PropertyStatus.fromString(row['status'] as String)
          : PropertyStatus.pending,
      notes: row['notes'] as String?,
      areaCount: row['area_count'] as int? ?? 0,
      dryAreaCount: row['dry_area_count'] as int? ?? 0,
      contentsCount: row['contents_count'] as int? ?? 0,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
      createdBy: row['created_by'] as String?,
    );
  }

  /// Convert Property to database format (snake_case)
  Map<String, dynamic> _toDbFormat(Property property) {
    return {
      'project_id': property.projectId,
      'workspace_id': property.workspaceId,
      'identifier': property.identifier,
      'name': property.name,
      'floor': property.floor,
      'occupant': property.occupant,
      'status': property.status.toDbValue(),
      'area_count': property.areaCount,
      'dry_area_count': property.dryAreaCount,
      'contents_count': property.contentsCount,
      'notes': property.notes,
      'created_by': property.createdBy,
    };
  }
}
