import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/customer_tag.dart';
import '../utils/app_logger.dart';

class CustomerTagService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new tag
  Future<String> createTag({
    required String workspaceId,
    required String name,
    required String color,
    String? description,
  }) async {
    try {
      final tag = CustomerTag(
        id: '', // Will be set by Firestore
        workspaceId: workspaceId,
        name: name.trim(),
        color: color,
        description: description?.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (!tag.validate()) {
        throw Exception('Invalid tag data');
      }

      final docRef = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('customerTags')
          .add(tag.toJson());

      AppLogger.info('Created customer tag', metadata: {
        'tagId': docRef.id,
        'workspaceId': workspaceId,
        'name': name,
      });

      return docRef.id;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create customer tag',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get all tags for a workspace
  Stream<List<CustomerTag>> getTags(String workspaceId) {
    return _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('customerTags')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CustomerTag.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Get a single tag by ID
  Future<CustomerTag?> getTag(String workspaceId, String tagId) async {
    try {
      final doc = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('customerTags')
          .doc(tagId)
          .get();

      if (!doc.exists) return null;
      return CustomerTag.fromJson(doc.data()!, doc.id);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get customer tag',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // Get multiple tags by their IDs
  Future<List<CustomerTag>> getTagsByIds(
      String workspaceId, List<String> tagIds) async {
    if (tagIds.isEmpty) return [];

    try {
      final tags = <CustomerTag>[];
      
      // Firestore has a limit of 10 items in 'whereIn', so batch them
      for (int i = 0; i < tagIds.length; i += 10) {
        final batch = tagIds.skip(i).take(10).toList();
        final snapshot = await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('customerTags')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        tags.addAll(
          snapshot.docs.map((doc) => CustomerTag.fromJson(doc.data(), doc.id)),
        );
      }

      return tags;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get tags by IDs',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Update a tag
  Future<void> updateTag(String workspaceId, String tagId,
      Map<String, dynamic> updates) async {
    try {
      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());

      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('customerTags')
          .doc(tagId)
          .update(updates);

      AppLogger.info('Updated customer tag', metadata: {
        'tagId': tagId,
        'workspaceId': workspaceId,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update customer tag',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Delete a tag (also removes it from all customers)
  Future<void> deleteTag(String workspaceId, String tagId) async {
    try {
      // First, remove this tag from all customers
      final customersSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('customers')
          .where('tagIds', arrayContains: tagId)
          .get();

      final batch = _firestore.batch();

      // Remove tag from customers
      for (final doc in customersSnapshot.docs) {
        batch.update(doc.reference, {
          'tagIds': FieldValue.arrayRemove([tagId]),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Delete the tag
      batch.delete(
        _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('customerTags')
            .doc(tagId),
      );

      await batch.commit();

      AppLogger.info('Deleted customer tag', metadata: {
        'tagId': tagId,
        'workspaceId': workspaceId,
        'customersAffected': customersSnapshot.docs.length,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete customer tag',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get usage count for a tag
  Future<int> getTagUsageCount(String workspaceId, String tagId) async {
    try {
      final snapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('customers')
          .where('tagIds', arrayContains: tagId)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get tag usage count',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }
}
