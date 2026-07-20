import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/property_contents.dart';
import '../models/contents_status.dart';
import '../utils/app_logger.dart';
import 'property_service.dart';

/// Service for managing property contents items.
class PropertyContentsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PropertyService _propertyService = PropertyService();

  CollectionReference get _contentsCollection =>
      _firestore.collection('property_contents');

  /// Create a new contents item
  Future<String> createContents(PropertyContents contents) async {
    try {
      final docRef = _contentsCollection.doc();
      final contentsData = contents.copyWith(id: docRef.id).toJson();
      await docRef.set(contentsData);

      // Update property contents count
      await _propertyService.incrementContentsCount(contents.propertyId);

      AppLogger.info('Contents item created', metadata: {
        'contentsId': docRef.id,
        'propertyId': contents.propertyId,
      });

      return docRef.id;
    } catch (e) {
      AppLogger.error('Failed to create contents item', error: e);
      rethrow;
    }
  }

  /// Update an existing contents item
  Future<void> updateContents(PropertyContents contents) async {
    try {
      final contentsData = contents.copyWith(updatedAt: DateTime.now()).toJson();
      await _contentsCollection.doc(contents.id).update(contentsData);

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
      await _contentsCollection.doc(contentsId).delete();

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
      final doc = await _contentsCollection.doc(contentsId).get();
      if (!doc.exists) return null;
      return PropertyContents.fromJson(
          doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      AppLogger.error('Failed to get contents item', error: e);
      return null;
    }
  }

  /// Get all contents for a property (real-time stream)
  Stream<List<PropertyContents>> getContentsByProperty(String propertyId, {String? workspaceId}) {
    var query = _contentsCollection
        .where('propertyId', isEqualTo: propertyId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              PropertyContents.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Get contents for a specific area (real-time stream)
  Stream<List<PropertyContents>> getContentsByArea(String areaId, {String? workspaceId}) {
    var query = _contentsCollection
        .where('areaId', isEqualTo: areaId);

    if (workspaceId != null) {
      query = query.where('workspaceId', isEqualTo: workspaceId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) =>
              PropertyContents.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }

  /// Find contents by barcode
  Future<PropertyContents?> findByBarcode(
      String workspaceId, String barcode) async {
    try {
      final snapshot = await _contentsCollection
          .where('workspaceId', isEqualTo: workspaceId)
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      return PropertyContents.fromJson(
          doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      AppLogger.error('Failed to find contents by barcode', error: e);
      return null;
    }
  }

  /// Get contents statistics for a property
  Future<Map<String, int>> getContentsStats(String propertyId, {String? workspaceId}) async {
    try {
      var query = _contentsCollection
          .where('propertyId', isEqualTo: propertyId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();

      final items = snapshot.docs
          .map((doc) =>
              PropertyContents.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

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
      await _contentsCollection.doc(contentsId).update({
        'status': status.name,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

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
      final batch = _firestore.batch();
      final now = Timestamp.fromDate(DateTime.now());

      for (final id in contentsIds) {
        batch.update(_contentsCollection.doc(id), {
          'status': status.name,
          'updatedAt': now,
        });
      }

      await batch.commit();

      AppLogger.info('Bulk contents status updated',
          metadata: {'count': contentsIds.length, 'status': status.name});
    } catch (e) {
      AppLogger.error('Failed to bulk update contents status', error: e);
      rethrow;
    }
  }

  /// Get contents grouped by status
  Future<Map<ContentsStatus, List<PropertyContents>>> getContentsGroupedByStatus(
      String propertyId, {String? workspaceId}) async {
    try {
      var query = _contentsCollection
          .where('propertyId', isEqualTo: propertyId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();

      final items = snapshot.docs
          .map((doc) =>
              PropertyContents.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

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
}
