import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cost_item.dart';

class CostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new cost item
  Future<String> createCostItem(CostItem costItem) async {
    try {
      final docRef = await _firestore.collection('cost_items').add(costItem.toJson());
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating cost item: $e');
    }
  }

  // Get all cost items for a project
  Stream<List<CostItem>> getCostItems(String projectId, {String? workspaceId}) {
    try {
      var query = _firestore
          .collection('cost_items')
          .where('projectId', isEqualTo: projectId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          return CostItem.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      throw Exception('Error fetching cost items: $e');
    }
  }

  // Get cost items by type
  Stream<List<CostItem>> getCostItemsByType(
    String projectId,
    CostItemType type, {
    String? workspaceId,
  }) {
    try {
      var query = _firestore
          .collection('cost_items')
          .where('projectId', isEqualTo: projectId)
          .where('type', isEqualTo: type.name);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          return CostItem.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      throw Exception('Error fetching cost items by type: $e');
    }
  }

  // Get cost items by category
  Stream<List<CostItem>> getCostItemsByCategory(
    String projectId,
    String categoryId, {
    String? workspaceId,
  }) {
    try {
      var query = _firestore
          .collection('cost_items')
          .where('projectId', isEqualTo: projectId)
          .where('categoryId', isEqualTo: categoryId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          return CostItem.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      throw Exception('Error fetching cost items by category: $e');
    }
  }

  // Update a cost item
  Future<void> updateCostItem(CostItem costItem) async {
    try {
      await _firestore
          .collection('cost_items')
          .doc(costItem.id)
          .update(costItem.toJson());
    } catch (e) {
      throw Exception('Error updating cost item: $e');
    }
  }

  // Delete a cost item
  Future<void> deleteCostItem(String costItemId) async {
    try {
      await _firestore.collection('cost_items').doc(costItemId).delete();
    } catch (e) {
      throw Exception('Error deleting cost item: $e');
    }
  }

  // Calculate cost totals for a project
  Future<Map<String, double>> calculateCostTotals(
    String projectId, {
    String? workspaceId,
  }) async {
    try {
      var query = _firestore
          .collection('cost_items')
          .where('projectId', isEqualTo: projectId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      final snapshot = await query.get();
      final items = snapshot.docs.map((doc) {
        return CostItem.fromJson(doc.data(), doc.id);
      }).toList();

      double materialCosts = 0.0;
      double laborCosts = 0.0;

      for (final item in items) {
        if (item.type == CostItemType.material) {
          materialCosts += item.totalCost;
        } else if (item.type == CostItemType.labor) {
          laborCosts += item.totalCost;
        }
      }

      return {
        'materialCosts': materialCosts,
        'laborCosts': laborCosts,
        'totalCosts': materialCosts + laborCosts,
      };
    } catch (e) {
      throw Exception('Error calculating cost totals: $e');
    }
  }

  // Calculate total costs with markup
  Future<Map<String, double>> calculateCostTotalsWithMarkup(
    String projectId,
    double materialMarkupPercent,
    double laborMarkupPercent, {
    String? workspaceId,
  }) async {
    try {
      final totals = await calculateCostTotals(projectId, workspaceId: workspaceId);

      final materialCosts = totals['materialCosts'] ?? 0.0;
      final laborCosts = totals['laborCosts'] ?? 0.0;

      final materialMarkup = materialCosts * (materialMarkupPercent / 100);
      final laborMarkup = laborCosts * (laborMarkupPercent / 100);

      final totalWithMarkup = materialCosts + laborCosts + materialMarkup + laborMarkup;

      return {
        'materialCosts': materialCosts,
        'laborCosts': laborCosts,
        'materialMarkup': materialMarkup,
        'laborMarkup': laborMarkup,
        'totalCosts': materialCosts + laborCosts,
        'totalWithMarkup': totalWithMarkup,
      };
    } catch (e) {
      throw Exception('Error calculating cost totals with markup: $e');
    }
  }
}
