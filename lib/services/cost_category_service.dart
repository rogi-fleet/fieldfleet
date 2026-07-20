import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cost_category.dart';

class CostCategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create default categories for a workspace
  Future<void> createDefaultCategories(String workspaceId) async {
    try {
      final batch = _firestore.batch();
      final now = DateTime.now();

      for (final category in CostCategory.defaultCategories) {
        final docRef = _firestore.collection('cost_categories').doc();
        final costCategory = CostCategory(
          id: docRef.id,
          workspaceId: workspaceId,
          name: category['name']!,
          color: category['color']!,
          isDefault: true,
          createdAt: now,
          updatedAt: now,
        );
        batch.set(docRef, costCategory.toJson());
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Error creating default categories: $e');
    }
  }

  // Get all categories for a workspace
  Stream<List<CostCategory>> getCategories(String workspaceId) {
    try {
      return _firestore
          .collection('cost_categories')
          .where('workspaceId', isEqualTo: workspaceId)
          .orderBy('name')
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return CostCategory.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      throw Exception('Error fetching cost categories: $e');
    }
  }

  // Create a custom category
  Future<String> createCategory(CostCategory category) async {
    try {
      final docRef = await _firestore.collection('cost_categories').add(category.toJson());
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating cost category: $e');
    }
  }

  // Update a category
  Future<void> updateCategory(CostCategory category) async {
    try {
      await _firestore
          .collection('cost_categories')
          .doc(category.id)
          .update(category.toJson());
    } catch (e) {
      throw Exception('Error updating cost category: $e');
    }
  }

  // Delete a custom category (cannot delete default categories)
  Future<void> deleteCategory(String categoryId) async {
    try {
      // First check if it's a default category
      final doc = await _firestore.collection('cost_categories').doc(categoryId).get();
      if (doc.exists) {
        final category = CostCategory.fromJson(doc.data()!, doc.id);
        if (category.isDefault) {
          throw Exception('Cannot delete default categories');
        }
      }

      await _firestore.collection('cost_categories').doc(categoryId).delete();
    } catch (e) {
      throw Exception('Error deleting cost category: $e');
    }
  }

  // Get a specific category
  Future<CostCategory?> getCategory(String categoryId) async {
    try {
      final doc = await _firestore.collection('cost_categories').doc(categoryId).get();
      if (doc.exists) {
        return CostCategory.fromJson(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching cost category: $e');
    }
  }

  // Check if default categories exist for a workspace
  Future<bool> hasDefaultCategories(String workspaceId) async {
    try {
      final snapshot = await _firestore
          .collection('cost_categories')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking for default categories: $e');
    }
  }
}
