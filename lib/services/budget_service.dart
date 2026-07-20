import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/budget_item.dart';
import '../models/catalog_item.dart';
import 'cost_service.dart';

class BudgetSummary {
  final double totalApprovedPrice;
  final double totalProjectedCost;
  final double totalCommittedCost;
  final double totalActualCost;
  final double totalInvoiced;
  final double totalCollected;
  final double overallProfit;
  final double overallMargin;
  final int totalItems;
  final int completedItems;

  BudgetSummary({
    required this.totalApprovedPrice,
    required this.totalProjectedCost,
    required this.totalCommittedCost,
    required this.totalActualCost,
    required this.totalInvoiced,
    this.totalCollected = 0.0,
    required this.overallProfit,
    required this.overallMargin,
    required this.totalItems,
    required this.completedItems,
  });

  double get completionPercentage {
    if (totalItems == 0) return 0.0;
    return (completedItems / totalItems) * 100;
  }

  /// Remaining = Approved - Invoiced
  double get totalRemaining => totalApprovedPrice - totalInvoiced;
}

/// Document status summary for a budget item
/// Tracks which documents reference this budget item
class BudgetItemDocumentStatus {
  final String budgetItemId;
  final double quotedAmount; // Amount in pending (draft/sent) proposals - NOT YET SIGNED
  final double approvedAmount; // Amount in SIGNED proposals/agreements (client approved)
  final double pendingQuoteAmount; // Legacy: same as quotedAmount, kept for compatibility
  final double invoicedAmount; // Amount in sent/paid invoices
  final double paidAmount; // Amount in paid invoices
  final int bidRequestCount; // Number of bid requests
  final bool hasPendingBid; // Has bid request in pending/sent status
  
  BudgetItemDocumentStatus({
    required this.budgetItemId,
    this.quotedAmount = 0.0,
    this.approvedAmount = 0.0,
    this.pendingQuoteAmount = 0.0,
    this.invoicedAmount = 0.0,
    this.paidAmount = 0.0,
    this.bidRequestCount = 0,
    this.hasPendingBid = false,
  });
  
  /// True if item has any document linkages
  bool get hasDocuments => 
      quotedAmount > 0 || 
      approvedAmount > 0 ||
      pendingQuoteAmount > 0 || 
      invoicedAmount > 0 || 
      bidRequestCount > 0;
  
  /// Status icon indicator key
  /// Priority: paid > invoiced > approved > quoted > pending_quote > pending_bid
  String get statusKey {
    if (paidAmount > 0) return 'paid';
    if (invoicedAmount > 0) return 'invoiced';
    if (approvedAmount > 0) return 'approved';
    if (quotedAmount > 0) return 'quoted';
    if (pendingQuoteAmount > 0) return 'pending_quote';
    if (hasPendingBid) return 'pending_bid';
    return 'none';
  }
}

class BudgetService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CostService _costService = CostService();

  // Cache for actual cost calculations (5 second TTL)
  final Map<String, _CachedCost> _costCache = {};

  /// Extract line item total from JSON, computing from quantity * unitPrice
  /// when the pre-computed totalPrice key is missing.
  static double _lineItemTotal(Map<String, dynamic> lineItem) {
    final stored = lineItem['totalPrice'] as num?;
    if (stored != null) return stored.toDouble();
    final qty = (lineItem['quantity'] as num?)?.toDouble() ?? 1.0;
    final price = lineItem['unitPrice'] as num?;
    return qty * (price?.toDouble() ?? 0.0);
  }

  // CRUD Operations

  /// Create a new budget item
  Future<String> createBudgetItem(BudgetItem item) async {
    try {
      if (!item.validate()) {
        throw Exception('Invalid budget item data');
      }

      // Validate hierarchy constraints
      if (item.hierarchyLevel > 2) {
        throw Exception('Maximum hierarchy depth is 3 levels (0-2)');
      }

      if (item.parentId != null) {
        final parent = await getBudgetItem(item.parentId!);
        if (parent == null) {
          throw Exception('Parent budget item not found');
        }
        if (parent.hierarchyLevel != item.hierarchyLevel - 1) {
          throw Exception('Invalid hierarchy level for parent');
        }
      }

      final docRef = await _firestore.collection('budget_items').add(item.toJson());
      
      // If added to a parent, update parent totals
      if (item.parentId != null) {
        await _recalculateParentTotals(item.parentId!);
      }
      
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating budget item: $e');
    }
  }

  /// Get all budget items for a project
  Stream<List<BudgetItem>> getBudgetItems(String projectId, {String? workspaceId}) {
    try {
      if (kDebugMode) {
        debugPrint('getBudgetItems: Starting query for projectId=$projectId, workspaceId=$workspaceId');
      }
      var query = _firestore
          .collection('budget_items')
          .where('projectId', isEqualTo: projectId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      return query.orderBy('hierarchyLevel').orderBy('sortOrder').snapshots().handleError((error) {
        if (kDebugMode) {
          debugPrint('getBudgetItems: ERROR in stream - $error');
        }
      }).map((snapshot) {
        if (kDebugMode) {
          debugPrint('getBudgetItems: Snapshot received with ${snapshot.docs.length} items');
        }
        return snapshot.docs.map((doc) {
          return BudgetItem.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('getBudgetItems: ERROR - $e');
      }
      throw Exception('Error fetching budget items: $e');
    }
  }

  /// Get a single budget item by ID
  Future<BudgetItem?> getBudgetItem(String itemId) async {
    try {
      final doc = await _firestore.collection('budget_items').doc(itemId).get();
      if (!doc.exists) return null;
      return BudgetItem.fromJson(doc.data()!, doc.id);
    } catch (e) {
      throw Exception('Error fetching budget item: $e');
    }
  }

  /// Get child items for a parent
  Stream<List<BudgetItem>> getChildItems(String parentId, {String? workspaceId}) {
    try {
      var query = _firestore
          .collection('budget_items')
          .where('parentId', isEqualTo: parentId);

      if (workspaceId != null) {
        query = query.where('workspaceId', isEqualTo: workspaceId);
      }

      return query
          .orderBy('sortOrder')
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return BudgetItem.fromJson(doc.data(), doc.id);
        }).toList();
      });
    } catch (e) {
      throw Exception('Error fetching child items: $e');
    }
  }

  /// Update an existing budget item
  Future<void> updateBudgetItem(BudgetItem item) async {
    try {
      if (!item.validate()) {
        throw Exception('Invalid budget item data');
      }

      await _firestore
          .collection('budget_items')
          .doc(item.id)
          .update(item.toJson());

      // If item has a parent, update parent totals
      if (item.parentId != null) {
        await _recalculateParentTotals(item.parentId!);
      }

      // Invalidate cost cache for this item
      _costCache.remove(item.id);
    } catch (e) {
      throw Exception('Error updating budget item: $e');
    }
  }

  /// Update specific fields of a budget item (for inline editing)
  Future<void> updateBudgetItemField(String itemId, Map<String, dynamic> fields) async {
    try {
      // Add updatedAt timestamp
      fields['updatedAt'] = Timestamp.now();

      await _firestore
          .collection('budget_items')
          .doc(itemId)
          .update(fields);

      // If we updated financial fields, recalculate parent
      if (fields.containsKey('approvedPrice') || fields.containsKey('projectedCost') || fields.containsKey('committedCost')) {
        final item = await getBudgetItem(itemId);
        if (item?.parentId != null) {
          await _recalculateParentTotals(item!.parentId!);
        }
      }

      // Invalidate cost cache for this item
      _costCache.remove(itemId);
    } catch (e) {
      throw Exception('Error updating budget item field: $e');
    }
  }

  /// Delete a budget item (with optional recursive deletion of children)
  Future<void> deleteBudgetItem(String itemId, {bool recursive = true}) async {
    try {
      if (kDebugMode) {
        debugPrint('deleteBudgetItem: Starting delete for itemId=$itemId, recursive=$recursive');
      }

      // Get parentId before deleting for rollup
      final itemToDelete = await getBudgetItem(itemId);
      if (itemToDelete == null) {
        if (kDebugMode) {
          debugPrint('deleteBudgetItem: Item not found, nothing to delete');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('deleteBudgetItem: Found item "${itemToDelete.name}" with workspaceId=${itemToDelete.workspaceId}');
      }
      final parentId = itemToDelete.parentId;

      if (recursive) {
        // Get all children and delete them first
        final childrenSnapshot = await _firestore
            .collection('budget_items')
            .where('parentId', isEqualTo: itemId)
            .where('workspaceId', isEqualTo: itemToDelete.workspaceId)
            .get();

        if (kDebugMode) {
          debugPrint('deleteBudgetItem: Found ${childrenSnapshot.docs.length} children');
        }
        for (final childDoc in childrenSnapshot.docs) {
          await deleteBudgetItem(childDoc.id, recursive: true);
        }
      }

      // Delete the item itself
      await _firestore.collection('budget_items').doc(itemId).delete();

      // If it had a parent, update parent totals
      if (parentId != null) {
        await _recalculateParentTotals(parentId);
      }

      // Remove from cache
      _costCache.remove(itemId);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('deleteBudgetItem: ERROR - $e');
        debugPrint('deleteBudgetItem: Stack trace - $stackTrace');
      }
      throw Exception('Error deleting budget item: $e');
    }
  }

  /// Recalculate totals for a parent group by summing across its children
  Future<void> _recalculateParentTotals(String parentId, {String? workspaceId}) async {
    try {
      // Get the parent first to obtain workspaceId if not provided
      final parentDoc = await _firestore.collection('budget_items').doc(parentId).get();
      if (!parentDoc.exists) return;

      final parent = BudgetItem.fromJson(parentDoc.data()!, parentDoc.id);
      final effectiveWorkspaceId = workspaceId ?? parent.workspaceId;

      final childrenSnapshot = await _firestore
          .collection('budget_items')
          .where('workspaceId', isEqualTo: effectiveWorkspaceId)
          .where('parentId', isEqualTo: parentId)
          .get();

      double totalApprovedPrice = 0;
      double totalProjectedCost = 0;
      double totalCommittedCost = 0;

      for (final doc in childrenSnapshot.docs) {
        final data = doc.data();
        totalApprovedPrice += (data['approvedPrice'] as num?)?.toDouble() ?? 0.0;
        totalProjectedCost += (data['projectedCost'] as num?)?.toDouble() ?? 0.0;
        totalCommittedCost += (data['committedCost'] as num?)?.toDouble() ?? 0.0;
      }

      await _firestore.collection('budget_items').doc(parentId).update({
        'approvedPrice': totalApprovedPrice,
        'projectedCost': totalProjectedCost,
        'committedCost': totalCommittedCost,
        'updatedAt': Timestamp.now(),
      });

      // Recurse up if parent has its own parent
      if (parent.parentId != null) {
        await _recalculateParentTotals(parent.parentId!, workspaceId: effectiveWorkspaceId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error recalculating parent totals: $e');
      }
    }
  }

  // Hierarchy Operations

  /// Reorder items within the same parent
  Future<void> reorderItems(String? parentId, List<String> orderedItemIds) async {
    try {
      final batch = _firestore.batch();

      for (int i = 0; i < orderedItemIds.length; i++) {
        final docRef = _firestore.collection('budget_items').doc(orderedItemIds[i]);
        batch.update(docRef, {
          'sortOrder': i,
          'updatedAt': Timestamp.now(),
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Error reordering items: $e');
    }
  }

  /// Move an item to a different parent
  Future<void> moveItem(String itemId, String? newParentId, int newSortOrder) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) {
        throw Exception('Budget item not found');
      }

      final oldParentId = item.parentId;

      // Validate new parent
      int newHierarchyLevel = 0;
      if (newParentId != null) {
        final newParent = await getBudgetItem(newParentId);
        if (newParent == null) {
          throw Exception('New parent not found');
        }
        newHierarchyLevel = newParent.hierarchyLevel + 1;
      }

      // Update the item
      await _firestore.collection('budget_items').doc(itemId).update({
        'parentId': newParentId,
        'hierarchyLevel': newHierarchyLevel,
        'sortOrder': newSortOrder,
        'updatedAt': Timestamp.now(),
      });

      // Recursively update hierarchy level for all children
      await _updateChildrenHierarchyLevel(itemId, newHierarchyLevel, item.workspaceId);

      // Recalculate totals for old parent (if it exists)
      if (oldParentId != null) {
        await _recalculateParentTotals(oldParentId, workspaceId: item.workspaceId);
      }

      // Recalculate totals for new parent (if it exists)
      if (newParentId != null) {
        await _recalculateParentTotals(newParentId, workspaceId: item.workspaceId);
      }
    } catch (e) {
      throw Exception('Error moving item: $e');
    }
  }

  /// Recursively update hierarchy level for children when parent moves
  Future<void> _updateChildrenHierarchyLevel(String parentId, int parentLevel, String workspaceId) async {
    final childrenSnapshot = await _firestore
        .collection('budget_items')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('parentId', isEqualTo: parentId)
        .get();

    final batch = _firestore.batch();
    for (final childDoc in childrenSnapshot.docs) {
      batch.update(childDoc.reference, {
        'hierarchyLevel': parentLevel + 1,
        'updatedAt': Timestamp.now(),
      });

      // Recursively update grandchildren
      await _updateChildrenHierarchyLevel(childDoc.id, parentLevel + 1, workspaceId);
    }

    await batch.commit();
  }

  // Cost Calculations

  /// Calculate actual cost for a budget item
  Future<double> calculateActualCost(String itemId) async {
    // Check cache first
    final cached = _costCache[itemId];
    if (cached != null && !cached.isExpired) {
      return cached.cost;
    }

    final item = await getBudgetItem(itemId);
    if (item == null) return 0.0;

    double actualCost = 0.0;

    // If item has category, sum CostItems in that category
    if (item.categoryId != null) {
      // Note: We query all cost items for the project/workspace and filter by category in memory
      // to avoid complex queries that might trigger permission errors or require composite indexes
      final costItems = await _costService
          .getCostItems(item.projectId, workspaceId: item.workspaceId)
          .first;

      actualCost = costItems
          .where((cost) => cost.categoryId == item.categoryId)
          .fold(0.0, (total, cost) => total + cost.totalCost);
    }

    // If item has children, add their actual costs
    final children = await getChildItems(item.id, workspaceId: item.workspaceId).first;
    for (final child in children) {
      actualCost += await calculateActualCost(child.id);
    }

    // Cache the result
    _costCache[itemId] = _CachedCost(actualCost, DateTime.now());

    return actualCost;
  }

  /// Calculate invoiced amount for a budget item from all invoices
  Future<double> calculateInvoicedAmount(String itemId, String workspaceId) async {
    try {
      // Get the item to find its project
      final item = await getBudgetItem(itemId);
      if (item == null) return 0.0;

      // Query invoices for this project ONLY
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('projectId', isEqualTo: item.projectId)
          .get();

      double totalInvoiced = 0.0;
      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'paid' || status == 'sent') {
          final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            if (lineItem['budgetItemId'] == itemId) {
              totalInvoiced += _lineItemTotal(lineItem);
            }
          }
        }
      }

      return totalInvoiced;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('calculateInvoicedAmount: ERROR - $e');
      }
      return 0.0;
    }
  }

  /// Calculate committed cost for a budget item from all purchase orders
  Future<double> calculateCommittedCost(String itemId, String workspaceId) async {
    try {
      // Get the item to find its project
      final item = await getBudgetItem(itemId);
      if (item == null) return 0.0;

      final poSnapshot = await _firestore
          .collection('purchase_orders')
          .where('projectId', isEqualTo: item.projectId)
          .get();

      double totalCommitted = 0.0;

      for (final doc in poSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status != 'cancelled' && status != 'draft') {
          final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            if (lineItem['budgetItemId'] == itemId) {
              totalCommitted += ((lineItem['unitPrice'] as num?)?.toDouble() ?? 0.0) * ((lineItem['quantity'] as num?)?.toDouble() ?? 0.0);
            }
          }
        }
      }
      return totalCommitted;
    } catch (e) {
      return 0.0;
    }
  }

  /// Calculate budget summary for entire project
  /// Calculate budget summary for entire project
  Future<BudgetSummary> calculateBudgetSummary(String projectId, String workspaceId) async {
    try {
      if (kDebugMode) {
        debugPrint('calculateBudgetSummary: Starting optimized calculation for projectId=$projectId');
      }
      
      // 1. Fetch everything in parallel using direct get() calls instead of streams
      final results = await Future.wait([
        _firestore.collection('budget_items')
            .where('projectId', isEqualTo: projectId)
            .where('workspaceId', isEqualTo: workspaceId)
            .get(),
        _firestore.collection('invoices')
            .where('projectId', isEqualTo: projectId)
            .where('workspaceId', isEqualTo: workspaceId)
            .get(),
        _firestore.collection('purchase_orders')
            .where('projectId', isEqualTo: projectId)
            .where('workspaceId', isEqualTo: workspaceId)
            .get(),
        _firestore.collection('cost_items')
            .where('projectId', isEqualTo: projectId)
            .where('workspaceId', isEqualTo: workspaceId)
            .get(),
      ]);

      final budgetSnapshot = results[0];
      final invoicesSnapshot = results[1];
      final poSnapshot = results[2];
      final costsSnapshot = results[3];

      final allItems = budgetSnapshot.docs.map((doc) => BudgetItem.fromJson(doc.data(), doc.id)).toList();

      if (kDebugMode) {
        debugPrint('calculateBudgetSummary: Fetched ${allItems.length} items, ${invoicesSnapshot.docs.length} invoices, ${poSnapshot.docs.length} POs, ${costsSnapshot.docs.length} costs');
      }

      // ... process rest in memory safely ...
      // 2. Process Budget Items (Totals from packages)
      double totalApprovedPrice = 0.0;
      double totalProjectedCost = 0.0;
      final topLevelItems = allItems.where((item) => item.parentId == null).toList();
      for (final item in topLevelItems) {
        totalApprovedPrice += item.approvedPrice;
        totalProjectedCost += item.projectedCost;
      }

      // 3. Process Invoices (Total Invoiced)
      double totalInvoiced = 0.0;
      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'paid' || status == 'sent') {
          final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            totalInvoiced += _lineItemTotal(lineItem);
          }
        }
      }

      // 4. Process Purchase Orders (Total Committed)
      double totalCommittedCost = 0.0;
      for (final doc in poSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status != 'cancelled' && status != 'draft') {
          final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            totalCommittedCost += ((lineItem['unitPrice'] as num?)?.toDouble() ?? 0.0) * ((lineItem['quantity'] as num?)?.toDouble() ?? 0.0);
          }
        }
      }

      // 5. Process Cost Items (Total Actual Cost)
      double totalActualCost = 0.0;
      for (final doc in costsSnapshot.docs) {
        final data = doc.data();
        totalActualCost += ((data['quantity'] as num?)?.toDouble() ?? 0.0) * ((data['unitPrice'] as num?)?.toDouble() ?? 0.0);
      }

      final overallProfit = totalApprovedPrice - totalProjectedCost;
      final overallMargin = totalApprovedPrice > 0 ? (overallProfit / totalApprovedPrice) * 100 : 0.0;

      // 6. Project Completion
      final leafItems = allItems.where((item) => item.hierarchyLevel == 2).toList();
      final completedItems = leafItems.where((item) => item.isComplete).length;

      return BudgetSummary(
        totalApprovedPrice: totalApprovedPrice,
        totalProjectedCost: totalProjectedCost,
        totalCommittedCost: totalCommittedCost,
        totalActualCost: totalActualCost,
        totalInvoiced: totalInvoiced,
        overallProfit: overallProfit,
        overallMargin: overallMargin,
        totalItems: leafItems.length,
        completedItems: completedItems,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('calculateBudgetSummary: ERROR - $e');
      }
      rethrow;
    }
  }

  // Progress Tracking

  /// Mark item as complete
  Future<void> markItemComplete(String itemId, {double? finalCost}) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) {
        throw Exception('Budget item not found');
      }

      // If finalCost not provided, calculate current actual cost
      final cost = finalCost ?? await calculateActualCost(itemId);

      await _firestore.collection('budget_items').doc(itemId).update({
        'isComplete': true,
        'completedDate': Timestamp.now(),
        'finalCost': cost,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Error marking item complete: $e');
    }
  }

  /// Mark item as incomplete
  Future<void> markItemIncomplete(String itemId) async {
    try {
      await _firestore.collection('budget_items').doc(itemId).update({
        'isComplete': false,
        'completedDate': null,
        'finalCost': 0.0,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Error marking item incomplete: $e');
    }
  }

  /// Get progress text for an item (e.g., "3/5" for parents, "Complete" for leaves)
  Future<String> getProgressText(String itemId) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) return '';

      final children = await getChildItems(itemId, workspaceId: item.workspaceId).first;

      if (children.isEmpty) {
        // Leaf item
        return item.isComplete ? 'Complete' : 'Incomplete';
      }

      // Parent: count completed children
      final completeCount = children.where((c) => c.isComplete).length;
      return '$completeCount/${children.length}';
    } catch (e) {
      return '';
    }
  }

  /// Get next available sort order for items within a parent
  Future<int> getNextSortOrder(String? parentId, String projectId) async {
    try {
      // Get all items for project and filter by parentId in code
      // This avoids needing a composite index on projectId + parentId
      final snapshot = await _firestore
          .collection('budget_items')
          .where('projectId', isEqualTo: projectId)
          .get();

      if (snapshot.docs.isEmpty) return 0;

      // Filter by parentId and find max sortOrder
      int maxSort = -1;
      for (final doc in snapshot.docs) {
        final item = BudgetItem.fromJson(doc.data(), doc.id);
        // Match parentId (null for root items)
        if (item.parentId == parentId) {
          if (item.sortOrder > maxSort) {
            maxSort = item.sortOrder;
          }
        }
      }

      return maxSort + 1;
    } catch (e) {
      debugPrint('getNextSortOrder: ERROR $e');
      return 0;
    }
  }

  /// Clear cost cache (useful when CostItems change)
  void clearCostCache() {
    _costCache.clear();
  }

  // Invoice Integration

  /// Get invoiceable budget items (items that can be added to invoices)
  /// Returns only leaf items (no children) that have approved prices
  Future<List<BudgetItem>> getInvoiceableItems(String projectId, String workspaceId) async {
    try {
      final allItems = await getBudgetItems(projectId, workspaceId: workspaceId).first;

      final invoiceableItems = <BudgetItem>[];

      for (final item in allItems) {
        // Only include leaf items (no children)
        final hasChildren = allItems.any((i) => i.parentId == item.id);

        if (!hasChildren && item.approvedPrice > 0) {
          invoiceableItems.add(item);
        }
      }

      return invoiceableItems;
    } catch (e) {
      throw Exception('Error getting invoiceable items: $e');
    }
  }

  /// Get remaining amount that can be invoiced for a budget item
  Future<double> getRemainingToInvoice(String budgetItemId) async {
    try {
      final item = await getBudgetItem(budgetItemId);
      if (item == null) return 0.0;

      final invoiced = await calculateInvoicedAmount(budgetItemId, item.workspaceId);
      final remaining = item.approvedPrice - invoiced;

      return remaining > 0 ? remaining : 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // Catalog Import

  /// Import catalog items as budget items
  /// Creates new budget items from the provided catalog items under the specified parent
  Future<void> importCatalogItemsToBudget({
    required List<CatalogItem> catalogItems,
    required String? parentId,
    required String projectId,
    required String workspaceId,
  }) async {
    try {
      if (catalogItems.isEmpty) return;

      // Determine hierarchy level based on parent
      int hierarchyLevel = 0;
      if (parentId != null) {
        final parent = await getBudgetItem(parentId);
        if (parent == null) {
          throw Exception('Parent budget item not found');
        }
        hierarchyLevel = parent.hierarchyLevel + 1;
        if (hierarchyLevel > 2) {
          throw Exception('Cannot add items below level 2 (Item level)');
        }
      }

      // Get starting sort order
      int sortOrder = await getNextSortOrder(parentId, projectId);
      final now = DateTime.now();

      // Create budget items in batch
      final batch = _firestore.batch();

      for (final catalogItem in catalogItems) {
        final docRef = _firestore.collection('budget_items').doc();
        final budgetItem = BudgetItem(
          id: docRef.id,
          workspaceId: workspaceId,
          projectId: projectId,
          parentId: parentId,
          hierarchyLevel: hierarchyLevel,
          sortOrder: sortOrder++,
          name: catalogItem.name,
          description: catalogItem.description,
          unit: catalogItem.unit,
          unitCost: catalogItem.unitCost,
          unitPrice: catalogItem.unitPrice,
          markup: catalogItem.markup,
          isTaxable: catalogItem.isTaxable,
          categoryId: null, // User can assign categories later
          approvedPrice: catalogItem.unitPrice,
          projectedCost: catalogItem.unitCost,
          itemType: hierarchyLevel < 2 ? BudgetItemType.group : BudgetItemType.item,
          createdAt: now,
          updatedAt: now,
        );

        batch.set(docRef, budgetItem.toJson());
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Error importing catalog items: $e');
    }
  }

  // Document Status Tracking

  /// Get document status for a single budget item
  /// Queries agreements, invoices, generated documents, and bid requests that reference this item
  Future<BudgetItemDocumentStatus> getDocumentStatusForBudgetItem(
    String budgetItemId,
    String workspaceId,
  ) async {
    try {
      double quotedAmount = 0.0;      // Pending proposals (draft/sent)
      double approvedAmount = 0.0;    // Signed proposals/agreements
      double invoicedAmount = 0.0;
      double paidAmount = 0.0;
      int bidRequestCount = 0;
      bool hasPendingBid = false;

      // Query generated_documents that reference this budget item
      final generatedDocsSnapshot = await _firestore
          .collection('generated_documents')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      for (final doc in generatedDocsSnapshot.docs) {
        final data = doc.data();
        final budgetItemIds = (data['budgetItemIds'] as List?)?.cast<String>() ?? [];
        
        if (budgetItemIds.contains(budgetItemId)) {
          final status = data['status'] as String?;
          final docType = data['documentType'] as String?;
          final amounts = (data['budgetItemAmounts'] as Map<String, dynamic>?) ?? {};
          final itemAmount = (amounts[budgetItemId] as num?)?.toDouble() ?? 0.0;
          
          // Skip invoices - they're handled separately
          if (docType == 'invoice' || docType == 'progressInvoice') continue;
          
          // Proposals/agreements: signed = approved, draft/sent/viewed = quoted
          if (status == 'signed') {
            approvedAmount += itemAmount;
          } else if (status == 'draft' || status == 'sent' || status == 'viewed') {
            quotedAmount += itemAmount;
          }
        }
      }

      // Query invoices that reference this budget item
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        
        for (final lineItem in lineItems) {
          if (lineItem['budgetItemId'] == budgetItemId) {
            final status = data['status'] as String?;
            final amount = _lineItemTotal(lineItem);

            if (status == 'paid') {
              paidAmount += amount;
              invoicedAmount += amount;
            } else if (status == 'sent') {
              invoicedAmount += amount;
            }
          }
        }
      }

      // Query bid requests that reference this budget item
      final bidRequestsSnapshot = await _firestore
          .collection('bid_requests')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      for (final doc in bidRequestsSnapshot.docs) {
        final data = doc.data();
        final budgetItemIds = (data['budgetItemIds'] as List?)?.cast<String>() ?? [];
        
        if (budgetItemIds.contains(budgetItemId)) {
          bidRequestCount++;
          final status = data['status'] as String?;
          if (status == 'draft' || status == 'sent' || status == 'pending') {
            hasPendingBid = true;
          }
        }
      }

      return BudgetItemDocumentStatus(
        budgetItemId: budgetItemId,
        quotedAmount: quotedAmount,
        approvedAmount: approvedAmount,
        pendingQuoteAmount: quotedAmount, // Legacy compatibility
        invoicedAmount: invoicedAmount,
        paidAmount: paidAmount,
        bidRequestCount: bidRequestCount,
        hasPendingBid: hasPendingBid,
      );
    } catch (e) {
      // Return empty status on error
      return BudgetItemDocumentStatus(budgetItemId: budgetItemId);
    }
  }

  /// Get document status for all budget items in a project
  /// Returns a map of budgetItemId -> BudgetItemDocumentStatus
  Future<Map<String, BudgetItemDocumentStatus>> getDocumentStatusForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, BudgetItemDocumentStatus>{};
      
      // Initialize with empty status for all budget items
      final itemsSnapshot = await _firestore.collection('budget_items')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();
      
      final allItems = itemsSnapshot.docs.map((doc) => BudgetItem.fromJson(doc.data(), doc.id)).toList();

      for (final item in allItems) {
        result[item.id] = BudgetItemDocumentStatus(budgetItemId: item.id);
      }


      // Query all invoices for this project
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final lineItems = (data['lineItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final status = data['status'] as String?;
        
        for (final lineItem in lineItems) {
          final itemId = lineItem['budgetItemId'] as String?;
          if (itemId == null || !result.containsKey(itemId)) continue;
          
          final amount = _lineItemTotal(lineItem);
          final current = result[itemId]!;

          if (status == 'paid') {
            result[itemId] = BudgetItemDocumentStatus(
              budgetItemId: itemId,
              quotedAmount: current.quotedAmount,
              pendingQuoteAmount: current.pendingQuoteAmount,
              invoicedAmount: current.invoicedAmount + amount,
              paidAmount: current.paidAmount + amount,
              bidRequestCount: current.bidRequestCount,
              hasPendingBid: current.hasPendingBid,
            );
          } else if (status == 'sent') {
            result[itemId] = BudgetItemDocumentStatus(
              budgetItemId: itemId,
              quotedAmount: current.quotedAmount,
              pendingQuoteAmount: current.pendingQuoteAmount,
              invoicedAmount: current.invoicedAmount + amount,
              paidAmount: current.paidAmount,
              bidRequestCount: current.bidRequestCount,
              hasPendingBid: current.hasPendingBid,
            );
          }
        }
      }

      // Query all bid requests for this project
      final bidRequestsSnapshot = await _firestore
          .collection('bid_requests')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      for (final doc in bidRequestsSnapshot.docs) {
        final data = doc.data();
        final budgetItemIds = (data['budgetItemIds'] as List?)?.cast<String>() ?? [];
        final status = data['status'] as String?;
        final isPending = status == 'draft' || status == 'sent' || status == 'pending';
        
        for (final itemId in budgetItemIds) {
          if (!result.containsKey(itemId)) continue;
          
          final current = result[itemId]!;
          result[itemId] = BudgetItemDocumentStatus(
            budgetItemId: itemId,
            quotedAmount: current.quotedAmount,
            pendingQuoteAmount: current.pendingQuoteAmount,
            invoicedAmount: current.invoicedAmount,
            paidAmount: current.paidAmount,
            bidRequestCount: current.bidRequestCount + 1,
            hasPendingBid: current.hasPendingBid || isPending,
          );
        }
      }

      // Roll up statuses to group items (from level 2 down to 0)
      for (int level = 2; level > 0; level--) {
        final parentItems = allItems.where((i) => i.hierarchyLevel == level - 1).toList();
        for (final parent in parentItems) {
          final children = allItems.where((i) => i.parentId == parent.id).toList();
          if (children.isEmpty) continue;

          double quoted = 0, pending = 0, invoiced = 0, paid = 0;
          int bids = 0;
          bool hasPending = false;

          for (final child in children) {
            final childStatus = result[child.id]!;
            quoted += childStatus.quotedAmount;
            pending += childStatus.pendingQuoteAmount;
            invoiced += childStatus.invoicedAmount;
            paid += childStatus.paidAmount;
            bids += childStatus.bidRequestCount;
            hasPending = hasPending || childStatus.hasPendingBid;
          }

          result[parent.id] = BudgetItemDocumentStatus(
            budgetItemId: parent.id,
            quotedAmount: quoted,
            pendingQuoteAmount: pending,
            invoicedAmount: invoiced,
            paidAmount: paid,
            bidRequestCount: bids,
            hasPendingBid: hasPending,
          );
        }
      }

      return result;
    } catch (e, stackTrace) {
      // Log error for debugging - don't fail silently
      if (kDebugMode) {
        debugPrint('getDocumentStatusForProject: ERROR - $e');
        debugPrint('Stack trace: $stackTrace');
      }
      // Return empty map but log that data may be incomplete
      return {};
    }
  }

  /// Get actual costs for all budget items in a project
  /// Returns a map of budgetItemId -> actualCost
  Future<Map<String, double>> getActualCostsForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, double>{};
      final itemsSnapshot = await _firestore.collection('budget_items')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();
      final allItems = itemsSnapshot.docs.map((doc) => BudgetItem.fromJson(doc.data(), doc.id)).toList();
      
      // Get all cost items for the project once
      final costSnapshot = await _firestore.collection('cost_items')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();

      // Group costs by category
      final categoryCosts = <String, double>{};
      for (final doc in costSnapshot.docs) {
        final data = doc.data();
        final categoryId = data['categoryId'] as String?;
        if (categoryId != null) {
          final cost = ((data['quantity'] as num?)?.toDouble() ?? 0.0) * ((data['unitPrice'] as num?)?.toDouble() ?? 0.0);
          categoryCosts[categoryId] = (categoryCosts[categoryId] ?? 0.0) + cost;
        }
      }

      // Calculate for each item
      for (final item in allItems) {
        result[item.id] = _calculateItemActualCostSync(item, allItems, categoryCosts);
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('getActualCostsForProject: ERROR - $e');
      }
      return {};
    }
  }

  /// Synchronous version of actual cost calculation for batch processing
  double _calculateItemActualCostSync(
    BudgetItem item,
    List<BudgetItem> allItems,
    Map<String, double> categoryCosts,
  ) {
    double actualCost = 0.0;

    // Add costs from category matching
    if (item.categoryId != null) {
      actualCost += categoryCosts[item.categoryId!] ?? 0.0;
    }

    // Add costs from children (recursive but using pre-loaded list)
    final children = allItems.where((i) => i.parentId == item.id).toList();
    for (final child in children) {
      actualCost += _calculateItemActualCostSync(child, allItems, categoryCosts);
    }

    return actualCost;
  }

  /// Get progress texts for all budget items in a project
  Future<Map<String, String>> getProgressTextsForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, String>{};
      final itemsSnapshot = await _firestore.collection('budget_items')
          .where('projectId', isEqualTo: projectId)
          .where('workspaceId', isEqualTo: workspaceId)
          .get();
      final allItems = itemsSnapshot.docs.map((doc) => BudgetItem.fromJson(doc.data(), doc.id)).toList();

      for (final item in allItems) {
        final children = allItems.where((i) => i.parentId == item.id).toList();

        if (children.isEmpty) {
          result[item.id] = item.isComplete ? 'Complete' : 'Incomplete';
        } else {
          final completeCount = children.where((c) => c.isComplete).length;
          result[item.id] = '$completeCount/${children.length}';
        }
      }

      return result;
    } catch (e) {
      return {};
    }
  }

  // Batch Operations

  /// Delete multiple budget items by IDs (with recursive deletion of children)
  Future<void> deleteBudgetItems(List<String> itemIds) async {
    try {
      // Collect all unique parents that will need recalculation
      final Set<String> parentsToRecalculate = {};

      for (final itemId in itemIds) {
        final item = await getBudgetItem(itemId);
        if (item == null) continue;

        if (item.parentId != null) {
          parentsToRecalculate.add(item.parentId!);
        }

        // Delete recursively (this handles children)
        await deleteBudgetItem(itemId, recursive: true);
      }

      // Recalculate parent totals (filter out any parents that were deleted)
      for (final parentId in parentsToRecalculate) {
        final parent = await getBudgetItem(parentId);
        if (parent != null) {
          await _recalculateParentTotals(parentId);
        }
      }
    } catch (e) {
      throw Exception('Error deleting budget items: $e');
    }
  }

  /// Update multiple budget items with the same field changes
  Future<void> updateBudgetItems(List<BudgetItem> items) async {
    try {
      if (items.isEmpty) return;

      final batch = _firestore.batch();
      final Set<String> parentsToRecalculate = {};

      for (final item in items) {
        final docRef = _firestore.collection('budget_items').doc(item.id);
        batch.update(docRef, item.toJson());

        if (item.parentId != null) {
          parentsToRecalculate.add(item.parentId!);
        }

        // Invalidate cost cache
        _costCache.remove(item.id);
      }

      await batch.commit();

      // Recalculate parent totals
      for (final parentId in parentsToRecalculate) {
        await _recalculateParentTotals(parentId);
      }
    } catch (e) {
      throw Exception('Error updating budget items: $e');
    }
  }
}

/// Helper class for caching actual cost calculations
class _CachedCost {
  final double cost;
  final DateTime timestamp;

  _CachedCost(this.cost, this.timestamp);

  bool get isExpired {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    return diff.inSeconds > 5; // 5 second TTL
  }
}
