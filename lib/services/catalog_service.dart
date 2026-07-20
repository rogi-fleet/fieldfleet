import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/catalog_item.dart';
import '../models/budget_item.dart';

class CatalogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<CatalogItem>> getCatalogItems(String workspaceId) {
    return _firestore
        .collection('catalog_items')
        .where('workspaceId', isEqualTo: workspaceId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CatalogItem.fromJson(doc.data(), doc.id))
            .toList());
  }

  Future<void> addCatalogItem(String workspaceId, CatalogItem item) async {
    await _firestore
        .collection('catalog_items')
        .add(item.toJson());
  }

  Future<void> updateCatalogItem(String workspaceId, CatalogItem item) async {
    await _firestore
        .collection('catalog_items')
        .doc(item.id)
        .update(item.toJson());
  }

  Future<void> deleteCatalogItem(String workspaceId, String itemId) async {
    await _firestore
        .collection('catalog_items')
        .doc(itemId)
        .delete();
  }

  Future<void> copyBudgetItemsToCatalog({
    required List<BudgetItem> budgetItems,
    required String workspaceId,
  }) async {
    final batch = _firestore.batch();
    final now = DateTime.now();

    for (final budgetItem in budgetItems) {
      final docRef = _firestore.collection('catalog_items').doc();

      final unitPrice = budgetItem.approvedPrice;
      final unitCost = budgetItem.projectedCost;
      final markup = CatalogItem.calculateMarkup(unitCost, unitPrice);
      final margin = CatalogItem.calculateMargin(unitCost, unitPrice);

      final catalogItem = CatalogItem(
        id: docRef.id,
        workspaceId: workspaceId,
        name: budgetItem.name,
        description: budgetItem.description,
        unit: null,
        unitCost: unitCost,
        unitPrice: unitPrice,
        markup: markup,
        margin: margin,
        isTaxable: true,
        costTypeName: null,
        costCodeName: null,
        imageUrl: null,
        category: null,
        sku: null,
        createdAt: now,
        updatedAt: now,
      );

      batch.set(docRef, catalogItem.toJson());
    }

    await batch.commit();
  }
}
