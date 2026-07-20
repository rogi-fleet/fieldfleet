import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/property.dart';
import '../utils/app_logger.dart';

/// Service for managing properties within projects.
class PropertyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _propertiesCollection =>
      _firestore.collection('properties');

  /// Create a new property
  Future<String> createProperty(Property property) async {
    try {
      final docRef = _propertiesCollection.doc();
      final propertyData = property.copyWith(id: docRef.id).toJson();
      await docRef.set(propertyData);

      AppLogger.info('Property created', metadata: {
        'propertyId': docRef.id,
        'projectId': property.projectId,
      });

      return docRef.id;
    } catch (e) {
      AppLogger.error('Failed to create property', error: e);
      rethrow;
    }
  }

  /// Update an existing property
  Future<void> updateProperty(Property property) async {
    try {
      final propertyData = property.copyWith(updatedAt: DateTime.now()).toJson();
      await _propertiesCollection.doc(property.id).update(propertyData);

      AppLogger.info('Property updated', metadata: {'propertyId': property.id});
    } catch (e) {
      AppLogger.error('Failed to update property', error: e);
      rethrow;
    }
  }

  /// Delete a property
  Future<void> deleteProperty(String propertyId) async {
    try {
      await _propertiesCollection.doc(propertyId).delete();

      AppLogger.info('Property deleted', metadata: {'propertyId': propertyId});
    } catch (e) {
      AppLogger.error('Failed to delete property', error: e);
      rethrow;
    }
  }

  /// Get a single property by ID
  Future<Property?> getProperty(String propertyId) async {
    try {
      final doc = await _propertiesCollection.doc(propertyId).get();
      if (!doc.exists) return null;
      return Property.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      AppLogger.error('Failed to get property', error: e);
      return null;
    }
  }

  /// Watch a single property (real-time updates)
  Stream<Property?> watchProperty(String propertyId) {
    return _propertiesCollection.doc(propertyId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Property.fromJson(
          snapshot.data() as Map<String, dynamic>, snapshot.id);
    });
  }

  /// Get all properties for a project (real-time stream)
  Stream<List<Property>> getProperties(String projectId, {String? workspaceId}) {
    var query = _propertiesCollection
        .where('projectId', isEqualTo: projectId);
    
    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return _dedupeById(
        snapshot.docs
          .map((doc) =>
              Property.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList(),
      );
    });
  }

  /// Get properties by workspace
  Stream<List<Property>> getPropertiesByWorkspace(String workspaceId) {
    return _propertiesCollection
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return _dedupeById(
        snapshot.docs
          .map((doc) =>
              Property.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList(),
      );
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
      String projectId, String identifier, String? excludePropertyId, {String? workspaceId}) async {
    try {
      var query = _propertiesCollection
          .where('projectId', isEqualTo: projectId)
          .where('identifier', isEqualTo: identifier);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();

      // If editing, exclude the current property
      if (excludePropertyId != null) {
        // Return true (unique) if all matching docs belong to the excluded property
        final otherProperties = snapshot.docs.where((doc) => doc.id != excludePropertyId);
        return otherProperties.isEmpty;
      }

      return snapshot.docs.isEmpty;
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
      await _propertiesCollection.doc(propertyId).update({
        'status': 'archived',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

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
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (areaCount != null) updates['areaCount'] = areaCount;
      if (dryAreaCount != null) updates['dryAreaCount'] = dryAreaCount;
      if (contentsCount != null) updates['contentsCount'] = contentsCount;

      await _propertiesCollection.doc(propertyId).update(updates);
    } catch (e) {
      AppLogger.error('Failed to update property stats', error: e);
      rethrow;
    }
  }

  /// Increment area count
  Future<void> incrementAreaCount(String propertyId, {bool isDry = false}) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'areaCount': FieldValue.increment(1),
        if (isDry) 'dryAreaCount': FieldValue.increment(1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to increment area count', error: e);
      rethrow;
    }
  }

  /// Decrement area count
  Future<void> decrementAreaCount(String propertyId, {bool wasDry = false}) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'areaCount': FieldValue.increment(-1),
        if (wasDry) 'dryAreaCount': FieldValue.increment(-1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to decrement area count', error: e);
      rethrow;
    }
  }

  /// Increment contents count
  Future<void> incrementContentsCount(String propertyId) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'contentsCount': FieldValue.increment(1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to increment contents count', error: e);
      rethrow;
    }
  }

  /// Decrement contents count
  Future<void> decrementContentsCount(String propertyId) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'contentsCount': FieldValue.increment(-1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to decrement contents count', error: e);
      rethrow;
    }
  }

  /// Update dry area count when an area's dry status changes
  Future<void> updateDryAreaCount(String propertyId, bool becameDry) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'dryAreaCount': FieldValue.increment(becameDry ? 1 : -1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      AppLogger.error('Failed to update dry area count', error: e);
      rethrow;
    }
  }
}
