import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/area.dart';
import '../models/area_status.dart';
import '../utils/app_logger.dart';
import 'property_service.dart';

/// Service for managing areas within properties.
class AreaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PropertyService _propertyService = PropertyService();

  CollectionReference get _areasCollection => _firestore.collection('areas');

  /// Create a new area
  Future<String> createArea(Area area) async {
    try {
      final docRef = _areasCollection.doc();
      final areaData = area.copyWith(id: docRef.id).toJson();
      await docRef.set(areaData);

      // Update property area count
      await _propertyService.incrementAreaCount(
        area.propertyId,
        isDry: area.isDry,
      );

      AppLogger.info('Area created', metadata: {
        'areaId': docRef.id,
        'propertyId': area.propertyId,
      });

      return docRef.id;
    } catch (e) {
      AppLogger.error('Failed to create area', error: e);
      rethrow;
    }
  }

  /// Update an existing area
  Future<void> updateArea(Area area, {Area? previousArea}) async {
    try {
      final areaData = area.copyWith(updatedAt: DateTime.now()).toJson();
      await _areasCollection.doc(area.id).update(areaData);

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
      await _areasCollection.doc(area.id).delete();

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
      final doc = await _areasCollection.doc(areaId).get();
      if (!doc.exists) return null;
      return Area.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      AppLogger.error('Failed to get area', error: e);
      return null;
    }
  }

  /// Watch a single area (real-time updates)
  Stream<Area?> watchArea(String areaId) {
    return _areasCollection.doc(areaId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return Area.fromJson(snapshot.data() as Map<String, dynamic>, snapshot.id);
    });
  }

  /// Get all areas for a property (real-time stream)
  Stream<List<Area>> getAreas(String propertyId, {String? workspaceId}) {
    var query = _areasCollection
        .where('propertyId', isEqualTo: propertyId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Area.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get areas by project
  Stream<List<Area>> getAreasByProject(String projectId, {String? workspaceId}) {
    var query = _areasCollection
        .where('projectId', isEqualTo: projectId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Area.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get affected areas for a property
  Stream<List<Area>> getAffectedAreas(String propertyId, {String? workspaceId}) {
    var query = _areasCollection
        .where('propertyId', isEqualTo: propertyId)
        .where('isAffected', isEqualTo: true);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query.snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Area.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Mark an area as dry
  Future<void> markAreaDry(String areaId, String propertyId) async {
    try {
      await _areasCollection.doc(areaId).update({
        'status': AreaStatus.dry.toDbValue(),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

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
      await _areasCollection.doc(areaId).update({
        'trend': trend,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      AppLogger.info('Area trend updated',
          metadata: {'areaId': areaId, 'trend': trend});
    } catch (e) {
      AppLogger.error('Failed to update area trend', error: e);
      rethrow;
    }
  }

  /// Get area summary for a property
  Future<Map<String, int>> getAreaSummary(String propertyId, {String? workspaceId}) async {
    try {
      var query = _areasCollection
          .where('propertyId', isEqualTo: propertyId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();

      final areas = snapshot.docs
          .map((doc) => Area.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

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
}
