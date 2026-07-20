import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/budget_item.dart';
import '../../models/catalog_item.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../utils/budget_rollup.dart';
import '../../utils/user_facing_error.dart';
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
  final double totalLaborCost;

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
    this.totalLaborCost = 0.0,
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
  final double quotedAmount;
  final double approvedAmount;
  final double pendingAmount;
  final double pendingQuoteAmount;
  final double invoicedAmount;
  final double paidAmount;
  final double committedAmount;
  final double billedAmount;
  final int bidRequestCount;
  final bool hasPendingBid;
  final List<String> documentIds;

  BudgetItemDocumentStatus({
    required this.budgetItemId,
    this.quotedAmount = 0.0,
    this.approvedAmount = 0.0,
    this.pendingAmount = 0.0,
    this.pendingQuoteAmount = 0.0,
    this.invoicedAmount = 0.0,
    this.paidAmount = 0.0,
    this.committedAmount = 0.0,
    this.billedAmount = 0.0,
    this.bidRequestCount = 0,
    this.hasPendingBid = false,
    this.documentIds = const [],
  });

  bool get hasDocuments =>
      quotedAmount > 0 ||
      approvedAmount > 0 ||
      pendingAmount > 0 ||
      committedAmount > 0 ||
      pendingQuoteAmount > 0 ||
      invoicedAmount > 0 ||
      billedAmount > 0 ||
      bidRequestCount > 0;

  String get statusKey {
    if (paidAmount > 0) return 'paid';
    if (invoicedAmount > 0) return 'invoiced';
    if (approvedAmount > 0) return 'approved';
    if (quotedAmount > 0) return 'quoted';
    if (pendingAmount > 0) return 'pending';
    if (pendingQuoteAmount > 0) return 'pending_quote';
    if (hasPendingBid) return 'pending_bid';
    return 'none';
  }

  BudgetItemDocumentStatus copyWith({
    double? quotedAmount,
    double? approvedAmount,
    double? pendingAmount,
    double? pendingQuoteAmount,
    double? invoicedAmount,
    double? paidAmount,
    double? committedAmount,
    double? billedAmount,
    int? bidRequestCount,
    bool? hasPendingBid,
    List<String>? documentIds,
  }) {
    return BudgetItemDocumentStatus(
      budgetItemId: budgetItemId,
      quotedAmount: quotedAmount ?? this.quotedAmount,
      approvedAmount: approvedAmount ?? this.approvedAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      pendingQuoteAmount: pendingQuoteAmount ?? this.pendingQuoteAmount,
      invoicedAmount: invoicedAmount ?? this.invoicedAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      committedAmount: committedAmount ?? this.committedAmount,
      billedAmount: billedAmount ?? this.billedAmount,
      bidRequestCount: bidRequestCount ?? this.bidRequestCount,
      hasPendingBid: hasPendingBid ?? this.hasPendingBid,
      documentIds: documentIds ?? this.documentIds,
    );
  }

  BudgetItemDocumentStatus addDocumentId(String docId) {
    if (documentIds.contains(docId)) return this;
    return copyWith(documentIds: [...documentIds, docId]);
  }

  BudgetItemDocumentStatus add({
    double quotedAmount = 0.0,
    double approvedAmount = 0.0,
    double pendingAmount = 0.0,
    double pendingQuoteAmount = 0.0,
    double invoicedAmount = 0.0,
    double paidAmount = 0.0,
    double committedAmount = 0.0,
    double billedAmount = 0.0,
    int bidRequestCount = 0,
    bool hasPendingBid = false,
  }) {
    return copyWith(
      quotedAmount: this.quotedAmount + quotedAmount,
      approvedAmount: this.approvedAmount + approvedAmount,
      pendingAmount: this.pendingAmount + pendingAmount,
      pendingQuoteAmount: this.pendingQuoteAmount + pendingQuoteAmount,
      invoicedAmount: this.invoicedAmount + invoicedAmount,
      paidAmount: this.paidAmount + paidAmount,
      committedAmount: this.committedAmount + committedAmount,
      billedAmount: this.billedAmount + billedAmount,
      bidRequestCount: this.bidRequestCount + bidRequestCount,
      hasPendingBid: this.hasPendingBid || hasPendingBid,
    );
  }
}

/// Supabase implementation of BudgetService
class SupabaseBudgetService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseCostService _costService = SupabaseCostService();

  // Cache for actual cost calculations (5 second TTL)
  final Map<String, _CachedCost> _costCache = {};

  /// Extract line item total from JSON, computing from quantity * unitPrice
  /// when the pre-computed totalPrice key is missing.
  static double _lineItemTotal(Map<String, dynamic> lineItem) {
    final stored = (lineItem['totalPrice'] ?? lineItem['total_price']) as num?;
    if (stored != null) return stored.toDouble();
    final qty = (lineItem['quantity'] as num?)?.toDouble() ?? 1.0;
    final price = (lineItem['unitPrice'] ?? lineItem['unit_price']) as num?;
    return qty * (price?.toDouble() ?? 0.0);
  }

  // CRUD Operations

  /// Create a new budget item
  /// Cost Plus (percentage) jobs bill cost + an agreed % fee, so each leaf
  /// budget line's revenue must equal `cost × (1 + fee%)`. Enforce that
  /// invariant on write — set `markup` to the project fee %, then derive
  /// `unit_price` and `approved_price` from cost — so every revenue surface
  /// (all of which read `approved_price`) reports cost+fee without per-surface
  /// logic. [M001] Frozen (already-approved) lines and non-leaf groups are left
  /// untouched; fixed-fee cost-plus jobs are handled via a dedicated fee line,
  /// not per-line markup.
  Future<BudgetItem> _applyCostPlusPricing(BudgetItem item) async {
    if (item.itemType != BudgetItemType.item || item.isApproved) return item;
    final row = await _supabase
        .from('projects')
        .select('price_type, cost_plus_type, cost_plus_value')
        .eq('id', item.projectId)
        .maybeSingle();
    if (row == null ||
        row['price_type'] != 'cost_plus' ||
        row['cost_plus_type'] != 'percentage') {
      return item;
    }
    final fee = (row['cost_plus_value'] as num?)?.toDouble();
    if (fee == null) return item;
    final unitPrice = item.unitCost * (1 + fee / 100);
    return item.copyWith(
      markup: fee,
      unitPrice: unitPrice,
      approvedPrice: item.quantity * unitPrice,
    );
  }

  Future<String> createBudgetItem(BudgetItem rawItem) async {
    try {
      final item = await _applyCostPlusPricing(rawItem);
      if (!item.validate()) {
        throw Exception('Invalid budget item data');
      }

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

      final now = DateTime.now();
      final data = _toDbFormat(item);
      data['created_at'] = now.toIso8601String();
      data['updated_at'] = now.toIso8601String();

      final response = await _supabase
          .from('budget_items')
          .insert(data)
          .select('id')
          .single();

      // If added to a parent, update parent totals
      if (item.parentId != null) {
        await _recalculateParentTotals(item.parentId!);
      }

      return response['id'];
    } catch (e) {
      throw _wrapBudgetItemWriteError(e, action: 'creating');
    }
  }

  /// Get all budget items for a project
  Stream<List<BudgetItem>> getBudgetItems(
    String projectId, {
    String? workspaceId,
  }) {
    try {
      if (kDebugMode) {
        debugPrint(
          'getBudgetItems: Starting query for projectId=$projectId, workspaceId=$workspaceId',
        );
      }

      return _supabase
          .from('budget_items')
          .stream(primaryKey: ['id'])
          .eq('project_id', projectId)
          .order('hierarchy_level')
          .order('sort_order')
          .map((data) {
            if (kDebugMode) {
              debugPrint(
                'getBudgetItems: Snapshot received with ${data.length} items',
              );
            }
            var items = data.map((row) => _toBudgetItem(row)).toList();
            if (workspaceId != null) {
              items = items
                  .where((item) => item.workspaceId == workspaceId)
                  .toList();
            }
            return items;
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
      final response = await _supabase
          .from('budget_items')
          .select()
          .eq('id', itemId)
          .maybeSingle();

      if (response == null) return null;
      return _toBudgetItem(response);
    } catch (e) {
      throw Exception('Error fetching budget item: $e');
    }
  }

  /// Get child items for a parent
  Stream<List<BudgetItem>> getChildItems(
    String parentId, {
    String? workspaceId,
  }) {
    try {
      return _supabase
          .from('budget_items')
          .stream(primaryKey: ['id'])
          .eq('parent_id', parentId)
          .order('sort_order')
          .map((data) {
            var items = data.map((row) => _toBudgetItem(row)).toList();
            if (workspaceId != null) {
              items = items
                  .where((item) => item.workspaceId == workspaceId)
                  .toList();
            }
            return items;
          });
    } catch (e) {
      throw Exception('Error fetching child items: $e');
    }
  }

  /// Update an existing budget item
  Future<void> updateBudgetItem(BudgetItem rawItem) async {
    try {
      final item = await _applyCostPlusPricing(rawItem);
      if (!item.validate()) {
        throw Exception('Invalid budget item data');
      }

      final data = _toDbFormat(item);
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('budget_items').update(data).eq('id', item.id);

      if (item.parentId != null) {
        await _recalculateParentTotals(item.parentId!);
      }

      _costCache.remove(item.id);
    } catch (e) {
      throw _wrapBudgetItemWriteError(e, action: 'updating');
    }
  }

  /// Update specific fields of a budget item (for inline editing)
  Future<void> updateBudgetItemField(
    String itemId,
    Map<String, dynamic> fields,
  ) async {
    try {
      // Convert camelCase to snake_case
      final snakeFields = <String, dynamic>{};
      fields.forEach((key, value) {
        snakeFields[_camelToSnake(key)] = value;
      });
      snakeFields['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('budget_items').update(snakeFields).eq('id', itemId);

      if (fields.containsKey('approvedPrice') ||
          fields.containsKey('projectedCost') ||
          fields.containsKey('committedCost')) {
        final item = await getBudgetItem(itemId);
        if (item?.parentId != null) {
          await _recalculateParentTotals(item!.parentId!);
        }
      }

      _costCache.remove(itemId);
    } catch (e) {
      throw _wrapBudgetItemWriteError(e, action: 'updating');
    }
  }

  /// Returns linked documents for the given budget item IDs.
  /// Each entry maps an item ID to a list of {id, template_name} maps.
  Future<Map<String, List<Map<String, String>>>>
  getLinkedDocumentsForBudgetItems(List<String> budgetItemIds) async {
    if (budgetItemIds.isEmpty) return {};
    final links = await _supabase
        .from('budget_document_links')
        .select('budget_item_id, generated_document_id')
        .inFilter('budget_item_id', budgetItemIds);
    final docIds = links
        .map((r) => r['generated_document_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (docIds.isEmpty) return {};
    final docs = await _supabase
        .from('generated_documents')
        .select('id, template_name')
        .inFilter('id', docIds);
    final docMap = <String, Map<String, String>>{};
    for (final d in docs) {
      docMap[d['id'] as String] = {
        'id': d['id'] as String,
        'template_name': (d['template_name'] as String?) ?? 'Document',
      };
    }
    final result = <String, List<Map<String, String>>>{};
    for (final link in links) {
      final itemId = link['budget_item_id'] as String?;
      final docId = link['generated_document_id'] as String?;
      if (itemId == null || docId == null) continue;
      final doc = docMap[docId];
      if (doc == null) continue;
      result.putIfAbsent(itemId, () => []).add(doc);
    }
    return result;
  }

  /// Delete a budget item (with optional recursive deletion of children)
  Future<void> deleteBudgetItem(String itemId, {bool recursive = true}) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'deleteBudgetItem: Starting delete for itemId=$itemId, recursive=$recursive',
        );
      }

      final itemToDelete = await getBudgetItem(itemId);
      if (itemToDelete == null) {
        if (kDebugMode) {
          debugPrint('deleteBudgetItem: Item not found, nothing to delete');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          'deleteBudgetItem: Found item "${itemToDelete.name}" with workspaceId=${itemToDelete.workspaceId}',
        );
      }
      final parentId = itemToDelete.parentId;

      if (recursive) {
        final childrenSnapshot = await _supabase
            .from('budget_items')
            .select('id')
            .eq('parent_id', itemId)
            .eq('workspace_id', itemToDelete.workspaceId);

        if (kDebugMode) {
          debugPrint(
            'deleteBudgetItem: Found ${childrenSnapshot.length} children',
          );
        }
        for (final child in childrenSnapshot) {
          await deleteBudgetItem(child['id'], recursive: true);
        }
      }

      await _supabase.from('budget_items').delete().eq('id', itemId);

      if (parentId != null) {
        await _recalculateParentTotals(parentId);
      }

      _costCache.remove(itemId);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('deleteBudgetItem: ERROR - $e');
        debugPrint('deleteBudgetItem: Stack trace - $stackTrace');
      }
      throw Exception('Error deleting budget item: $e');
    }
  }

  /// Recompute `committed_cost` on a leaf budget item by summing every
  /// linked purchase-order line — both `work_order_items` (Materials and
  /// Rentals) and `subcontract_items` — that point at this category, then
  /// bubble the parent totals back up.
  ///
  /// Called from the PO services (work_order_service / subcontract_service)
  /// whenever a line item is added, edited, or removed so the Budget tab
  /// stays in sync with on-the-ground commitments.
  Future<void> recomputeCommittedForBudgetItem(String budgetItemId) async {
    try {
      final wo = await _supabase
          .from('work_order_items')
          .select('quantity, unit_cost')
          .eq('budget_item_id', budgetItemId);
      final sc = await _supabase
          .from('subcontract_items')
          .select('quantity, unit_cost')
          .eq('budget_item_id', budgetItemId);

      var committed = 0.0;
      for (final r in (wo as List)) {
        final q = (r['quantity'] as num?)?.toDouble() ?? 0;
        final c = (r['unit_cost'] as num?)?.toDouble() ?? 0;
        committed += q * c;
      }
      for (final r in (sc as List)) {
        final q = (r['quantity'] as num?)?.toDouble() ?? 0;
        final c = (r['unit_cost'] as num?)?.toDouble() ?? 0;
        committed += q * c;
      }

      final leaf = await _supabase
          .from('budget_items')
          .select('parent_id, workspace_id, item_type')
          .eq('id', budgetItemId)
          .maybeSingle();
      if (leaf == null) return;

      // Guard: groups derive committed_cost from their children's rollup
      // (see _recalculateParentTotals). Writing direct PO totals onto a
      // group would clobber that rollup, so refuse non-leaf targets.
      final itemType = (leaf['item_type'] as String?) ?? 'item';
      if (itemType != 'item') {
        if (kDebugMode) {
          debugPrint(
              'recomputeCommittedForBudgetItem: skipping non-leaf $budgetItemId (item_type=$itemType)');
        }
        return;
      }

      await _supabase
          .from('budget_items')
          .update({
            'committed_cost': committed,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', budgetItemId);

      final parentId = leaf['parent_id'] as String?;
      final workspaceId = leaf['workspace_id'] as String?;
      if (parentId != null) {
        await _recalculateParentTotals(parentId, workspaceId: workspaceId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('recomputeCommittedForBudgetItem: ERROR - $e');
      }
    }
  }

  /// Recalculate totals for a parent group by summing across its children
  Future<void> _recalculateParentTotals(
    String parentId, {
    String? workspaceId,
  }) async {
    try {
      final parentResponse = await _supabase
          .from('budget_items')
          .select()
          .eq('id', parentId)
          .maybeSingle();

      if (parentResponse == null) return;

      final parent = _toBudgetItem(parentResponse);
      final effectiveWorkspaceId = workspaceId ?? parent.workspaceId;

      final childrenSnapshot = await _supabase
          .from('budget_items')
          .select()
          .eq('workspace_id', effectiveWorkspaceId)
          .eq('parent_id', parentId);

      double totalApprovedPrice = 0;
      double totalProjectedCost = 0;
      double totalCommittedCost = 0;

      for (final row in childrenSnapshot) {
        totalApprovedPrice +=
            (row['approved_price'] as num?)?.toDouble() ?? 0.0;
        totalProjectedCost +=
            (row['projected_cost'] as num?)?.toDouble() ?? 0.0;
        totalCommittedCost +=
            (row['committed_cost'] as num?)?.toDouble() ?? 0.0;
      }

      await _supabase
          .from('budget_items')
          .update({
            'approved_price': totalApprovedPrice,
            'projected_cost': totalProjectedCost,
            'committed_cost': totalCommittedCost,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', parentId);

      if (parent.parentId != null) {
        await _recalculateParentTotals(
          parent.parentId!,
          workspaceId: effectiveWorkspaceId,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error recalculating parent totals: $e');
      }
    }
  }

  // Hierarchy Operations

  /// Reorder items within the same parent
  Future<void> reorderItems(
    String? parentId,
    List<String> orderedItemIds,
  ) async {
    try {
      for (int i = 0; i < orderedItemIds.length; i++) {
        await _supabase
            .from('budget_items')
            .update({
              'sort_order': i,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderedItemIds[i]);
      }
    } catch (e) {
      throw Exception('Error reordering items: $e');
    }
  }

  /// Move an item to a different parent
  Future<void> moveItem(
    String itemId,
    String? newParentId,
    int newSortOrder,
  ) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) {
        throw Exception('Budget item not found');
      }

      final oldParentId = item.parentId;

      int newHierarchyLevel = 0;
      if (newParentId != null) {
        final newParent = await getBudgetItem(newParentId);
        if (newParent == null) {
          throw Exception('New parent not found');
        }
        if (newParent.itemType != BudgetItemType.group) {
          throw Exception('Items can only be nested under groups');
        }
        newHierarchyLevel = newParent.hierarchyLevel + 1;
        if (newHierarchyLevel > 2) {
          throw Exception('Maximum hierarchy depth is 3 levels (0-2)');
        }
      }

      final maxSubtreeDepth = await _getMaxSubtreeDepth(item);
      if (newHierarchyLevel + maxSubtreeDepth > 2) {
        throw Exception('Move would exceed maximum hierarchy depth');
      }

      await _supabase
          .from('budget_items')
          .update({
            'parent_id': newParentId,
            'hierarchy_level': newHierarchyLevel,
            'sort_order': newSortOrder,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', itemId);

      await _updateChildrenHierarchyLevel(
        itemId,
        newHierarchyLevel,
        item.workspaceId,
      );

      if (oldParentId != null) {
        await _recalculateParentTotals(
          oldParentId,
          workspaceId: item.workspaceId,
        );
      }

      if (newParentId != null) {
        await _recalculateParentTotals(
          newParentId,
          workspaceId: item.workspaceId,
        );
      }
    } catch (e) {
      throw Exception('Error moving item: $e');
    }
  }

  /// Recursively update hierarchy level for children when parent moves
  Future<void> _updateChildrenHierarchyLevel(
    String parentId,
    int parentLevel,
    String workspaceId,
  ) async {
    final childrenSnapshot = await _supabase
        .from('budget_items')
        .select('id')
        .eq('workspace_id', workspaceId)
        .eq('parent_id', parentId);

    for (final child in childrenSnapshot) {
      await _supabase
          .from('budget_items')
          .update({
            'hierarchy_level': parentLevel + 1,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', child['id']);

      await _updateChildrenHierarchyLevel(
        child['id'],
        parentLevel + 1,
        workspaceId,
      );
    }
  }

  Future<int> _getMaxSubtreeDepth(BudgetItem item) async {
    final snapshot = await _supabase
        .from('budget_items')
        .select('id, parent_id')
        .eq('project_id', item.projectId)
        .eq('workspace_id', item.workspaceId);

    final childrenByParent = <String, List<String>>{};
    for (final row in snapshot) {
      final parentId = row['parent_id'] as String?;
      if (parentId == null) continue;
      childrenByParent
          .putIfAbsent(parentId, () => <String>[])
          .add(row['id'] as String);
    }

    int visit(String itemId) {
      final children = childrenByParent[itemId] ?? const <String>[];
      if (children.isEmpty) return 0;
      var maxDepth = 0;
      for (final childId in children) {
        final depth = 1 + visit(childId);
        if (depth > maxDepth) {
          maxDepth = depth;
        }
      }
      return maxDepth;
    }

    return visit(item.id);
  }

  // Cost Calculations

  /// Calculate actual cost for a budget item
  Future<double> calculateActualCost(String itemId) async {
    final cached = _costCache[itemId];
    if (cached != null && !cached.isExpired) {
      return cached.cost;
    }

    final item = await getBudgetItem(itemId);
    if (item == null) return 0.0;

    double actualCost = 0.0;

    if (item.categoryId != null) {
      final costItems = await _costService
          .getCostItems(item.projectId, workspaceId: item.workspaceId)
          .first;

      actualCost = costItems
          .where((cost) => cost.categoryId == item.categoryId)
          .fold(0.0, (total, cost) => total + cost.totalCost);
    }

    final children = await getChildItems(
      item.id,
      workspaceId: item.workspaceId,
    ).first;
    for (final child in children) {
      actualCost += await calculateActualCost(child.id);
    }

    _costCache[itemId] = _CachedCost(actualCost, DateTime.now());

    return actualCost;
  }

  /// Calculate invoiced amount for a budget item from all invoices
  Future<double> calculateInvoicedAmount(
    String itemId,
    String workspaceId,
  ) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) return 0.0;

      final invoicesSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('project_id', item.projectId)
          .inFilter(
            'document_type',
            DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.customerRevenue,
            ),
          );

      double totalInvoiced = 0.0;
      for (final doc in invoicesSnapshot) {
        final status = doc['status'] as String?;
        if (status == 'paid' || status == 'sent') {
          final lineItems =
              (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            if (lineItem['budgetItemId'] == itemId ||
                lineItem['budget_item_id'] == itemId) {
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

  /// Calculate committed cost for a budget item from purchase orders and
  /// subcontract items.
  ///
  /// Both POs and subcontracts can commit against the same budget item.
  /// They are summed independently — if a subcontract and a PO cover the
  /// same scope, this will currently double-count. Resolve at the
  /// commitment-vehicle policy level (see project docs).
  Future<double> calculateCommittedCost(
    String itemId,
    String workspaceId,
  ) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) return 0.0;

      final poSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('project_id', item.projectId)
          .eq('document_type', DocumentType.purchaseOrder.dbValue);

      double totalCommitted = 0.0;

      for (final doc in poSnapshot) {
        final status = doc['status'] as String?;
        if (status != 'cancelled' && status != 'draft') {
          final lineItems =
              (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            if (lineItem['budgetItemId'] == itemId ||
                lineItem['budget_item_id'] == itemId) {
              totalCommitted +=
                  ((lineItem['unitPrice'] ?? lineItem['unit_price'] as num?)
                          ?.toDouble() ??
                      0.0) *
                  ((lineItem['quantity'] as num?)?.toDouble() ?? 0.0);
            }
          }
        }
      }

      totalCommitted += await _subcontractCommittedForItem(itemId);
      return totalCommitted;
    } catch (e) {
      return 0.0;
    }
  }

  /// Fetch subcontracts for a project for use in the budget summary
  /// commitment rollup. Returns an empty list if the subcontracts table
  /// is missing or the read fails — so older workspaces don't break the
  /// rollup. Keeps the return type as `List<dynamic>` so it composes
  /// cleanly inside `Future.wait`.
  Future<List<dynamic>> _fetchSubcontractsForBudget(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final rows = await _supabase
          .from('subcontracts')
          .select('contract_amount, status')
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);
      return rows as List<dynamic>;
    } catch (_) {
      return const <dynamic>[];
    }
  }

  /// Sum of subcontract item line totals (quantity × unit_cost) linked to
  /// this budget item across non-terminal subcontracts. Tolerates missing
  /// subcontract tables so older workspaces don't break the rollup.
  Future<double> _subcontractCommittedForItem(String itemId) async {
    try {
      final itemRows = await _supabase
          .from('subcontract_items')
          .select('quantity, unit_cost, subcontract_id')
          .eq('budget_item_id', itemId);
      final rows = (itemRows as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return 0.0;
      final scIds = rows
          .map((r) => r['subcontract_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (scIds.isEmpty) return 0.0;
      final scRows = await _supabase
          .from('subcontracts')
          .select('id, status')
          .inFilter('id', scIds)
          .inFilter('status',
              const ['sent', 'signed', 'active', 'completed']);
      final activeIds = (scRows as List)
          .map((r) => (r as Map)['id'] as String)
          .toSet();
      var sum = 0.0;
      for (final r in rows) {
        if (!activeIds.contains(r['subcontract_id'])) continue;
        final q = (r['quantity'] as num?)?.toDouble() ?? 0;
        final c = (r['unit_cost'] as num?)?.toDouble() ?? 0;
        sum += q * c;
      }
      return sum;
    } catch (_) {
      return 0.0;
    }
  }

  /// Calculate budget summary for entire project
  Future<BudgetSummary> calculateBudgetSummary(
    String projectId,
    String workspaceId,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'calculateBudgetSummary: Starting optimized calculation for projectId=$projectId',
        );
      }

      // Fetch everything in parallel (including labor summary).
      // Subcontracts query is tolerant of a missing table (older workspaces
      // may not have the migration) — see the catch-and-default below.
      final results = await Future.wait([
        _supabase
            .from('budget_items')
            .select()
            .eq('project_id', projectId)
            .eq('workspace_id', workspaceId),
        _supabase
            .from('generated_documents')
            .select()
            .eq('project_id', projectId)
            .eq('workspace_id', workspaceId)
            .inFilter(
              'document_type',
              DocumentTypeExtension.dbValuesWithBudgetImpact(
                BudgetImpact.customerRevenue,
              ),
            ),
        _supabase
            .from('generated_documents')
            .select()
            .eq('project_id', projectId)
            .eq('workspace_id', workspaceId)
            .eq('document_type', DocumentType.purchaseOrder.dbValue),
        _supabase
            .from('cost_items')
            .select()
            .eq('project_id', projectId)
            .eq('workspace_id', workspaceId),
        _supabase
            .from('generated_documents')
            .select('id, status')
            .eq('project_id', projectId)
            .eq('workspace_id', workspaceId)
            .eq('document_type', DocumentType.changeOrder.dbValue),
        _fetchSubcontractsForBudget(projectId, workspaceId),
      ]);

      final budgetData = results[0];
      final invoicesData = results[1];
      final poData = results[2];
      final costsData = results[3];
      final subcontractData = results[5];

      // Build change order status map for filtering
      final coStatusData = results[4];
      final coStatuses = <String, String>{};
      for (final row in coStatusData) {
        final id = row['id'] as String?;
        final status = row['status'] as String?;
        if (id != null && status != null) {
          coStatuses[id] = status[0].toUpperCase() + status.substring(1);
        }
      }

      // Fetch labor summary from view
      final budgetItemIds = budgetData
          .map((row) => row['id'] as String)
          .toList();
      double totalLaborCost = 0.0;
      if (budgetItemIds.isNotEmpty) {
        try {
          final laborData = await _supabase
              .from('budget_item_labor_summary')
              .select()
              .inFilter('budget_item_id', budgetItemIds);
          for (final row in laborData) {
            totalLaborCost += (row['labor_cost'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'calculateBudgetSummary: Labor summary fetch failed: $e',
            );
          }
        }
      }

      final allItems = budgetData.map((row) => _toBudgetItem(row)).toList();

      if (kDebugMode) {
        debugPrint(
          'calculateBudgetSummary: Fetched ${allItems.length} items, ${invoicesData.length} invoices, ${poData.length} POs, ${costsData.length} costs',
        );
      }

      // Process Budget Items — only count confirmed items:
      //   base items: always included
      //   change orders: only if CO document is approved/signed/completed
      //   upgrades: only if upgradeStatus is accepted
      // Predicate lives in `BudgetRollup` so the unit tests run against the
      // same math.
      final budgetTotals = BudgetRollup.computeApprovedTotals(
        allItems: allItems,
        coStatusesByDocumentId: coStatuses,
      );
      final totalApprovedPrice = budgetTotals.totalApprovedPrice;
      final totalProjectedCost = budgetTotals.totalProjectedCost;

      // The completion KPIs run on the same leaf-item set the rollup uses
      // — recomputed here (cheap; one pass over allItems) so the helper's
      // internal collection can stay private.
      final parentIds = allItems
          .map((item) => item.parentId)
          .whereType<String>()
          .toSet();
      final leafItems = allItems
          .where((item) =>
              item.itemType == BudgetItemType.item &&
              !parentIds.contains(item.id))
          .toList();

      // Process Invoices
      double totalInvoiced = 0.0;
      double totalCollected = 0.0;
      for (final doc in invoicesData) {
        if (doc['exclude_from_budget'] == true) continue;
        final status = doc['status'] as String?;
        if (status == 'sent' || status == 'signed' || status == 'approved') {
          final lineItems =
              (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          double docTotal = 0.0;
          for (final lineItem in lineItems) {
            docTotal += _lineItemTotal(lineItem);
          }
          totalInvoiced += docTotal;
          // Collected = paid invoices (has paid_date)
          if (doc['paid_date'] != null) {
            totalCollected += docTotal;
          }
        }
      }

      // Process Purchase Orders
      double totalCommittedCost = 0.0;
      for (final doc in poData) {
        if (doc['exclude_from_budget'] == true) continue;
        final status = doc['status'] as String?;
        if (status != 'cancelled' && status != 'draft') {
          final lineItems =
              (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final lineItem in lineItems) {
            totalCommittedCost +=
                ((lineItem['unitPrice'] ?? lineItem['unit_price'] as num?)
                        ?.toDouble() ??
                    0.0) *
                ((lineItem['quantity'] as num?)?.toDouble() ?? 0.0);
          }
        }
      }

      // Process Subcontracts — count contract_amount for non-terminal
      // statuses. May double-count when a subcontract and PO cover the
      // same scope; see commitment-vehicle policy in docs.
      for (final sc in subcontractData) {
        final status = sc['status'] as String?;
        if (status == null ||
            status == 'draft' ||
            status == 'cancelled' ||
            status == 'terminated') {
          continue;
        }
        totalCommittedCost +=
            (sc['contract_amount'] as num?)?.toDouble() ?? 0.0;
      }

      // Process Cost Items
      double totalActualCost = 0.0;
      for (final doc in costsData) {
        totalActualCost +=
            ((doc['quantity'] as num?)?.toDouble() ?? 0.0) *
            ((doc['unit_price'] as num?)?.toDouble() ?? 0.0);
      }

      final overallProfit = totalApprovedPrice - totalProjectedCost;
      final overallMargin = totalApprovedPrice > 0
          ? (overallProfit / totalApprovedPrice) * 100
          : 0.0;

      // Project Completion (reuse leafItems computed above)
      final completedItems = leafItems.where((item) => item.isComplete).length;

      return BudgetSummary(
        totalApprovedPrice: totalApprovedPrice,
        totalProjectedCost: totalProjectedCost,
        totalCommittedCost: totalCommittedCost,
        totalActualCost: totalActualCost + totalLaborCost,
        totalInvoiced: totalInvoiced,
        totalCollected: totalCollected,
        overallProfit: overallProfit,
        overallMargin: overallMargin,
        totalItems: leafItems.length,
        completedItems: completedItems,
        totalLaborCost: totalLaborCost,
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

      final cost = finalCost ?? await calculateActualCost(itemId);

      await _supabase
          .from('budget_items')
          .update({
            'is_complete': true,
            'completed_date': DateTime.now().toIso8601String(),
            'final_cost': cost,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', itemId);
    } catch (e) {
      throw Exception('Error marking item complete: $e');
    }
  }

  /// Mark item as incomplete
  Future<void> markItemIncomplete(String itemId) async {
    try {
      await _supabase
          .from('budget_items')
          .update({
            'is_complete': false,
            'completed_date': null,
            'final_cost': 0.0,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', itemId);
    } catch (e) {
      throw Exception('Error marking item incomplete: $e');
    }
  }

  /// Get progress text for an item
  Future<String> getProgressText(String itemId) async {
    try {
      final item = await getBudgetItem(itemId);
      if (item == null) return '';

      final children = await getChildItems(
        itemId,
        workspaceId: item.workspaceId,
      ).first;

      if (children.isEmpty) {
        return item.isComplete ? 'Complete' : 'Incomplete';
      }

      final completeCount = children.where((c) => c.isComplete).length;
      return '$completeCount/${children.length}';
    } catch (e) {
      return '';
    }
  }

  /// Get next available sort order for items within a parent
  Future<int> getNextSortOrder(String? parentId, String projectId) async {
    try {
      final snapshot = await _supabase
          .from('budget_items')
          .select('sort_order, parent_id')
          .eq('project_id', projectId);

      if (snapshot.isEmpty) return 0;

      int maxSort = -1;
      for (final row in snapshot) {
        if (row['parent_id'] == parentId) {
          final sortOrder = (row['sort_order'] as num?)?.toInt() ?? 0;
          if (sortOrder > maxSort) {
            maxSort = sortOrder;
          }
        }
      }

      return maxSort + 1;
    } catch (e) {
      debugPrint('getNextSortOrder: ERROR $e');
      return 0;
    }
  }

  /// Clear cost cache
  void clearCostCache() {
    _costCache.clear();
  }

  /// Apply a responded Request-for-Bid's line item prices to the linked
  /// budget items' projectedCost and unitCost. The document is transitioned
  /// to 'applied' and each line item's unitPrice is overwritten with the
  /// vendor's bid price so downstream PO derivation carries the vendor's
  /// numbers forward. Audited into budget_item_events.
  Future<void> applyVendorBidToBudget(String documentId) async {
    try {
      await _supabase.rpc(
        'apply_vendor_bid_to_budget',
        params: {'p_document_id': documentId},
      );
      _costCache.clear();
    } catch (e) {
      throw Exception('Failed to apply vendor bid to budget: $e');
    }
  }

  // Invoice Integration

  /// Get invoiceable budget items
  Future<List<BudgetItem>> getInvoiceableItems(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final allItems = await getBudgetItems(
        projectId,
        workspaceId: workspaceId,
      ).first;

      final invoiceableItems = <BudgetItem>[];

      for (final item in allItems) {
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

      final invoiced = await calculateInvoicedAmount(
        budgetItemId,
        item.workspaceId,
      );
      final remaining = item.approvedPrice - invoiced;

      return remaining > 0 ? remaining : 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // Catalog Import

  /// Import catalog items as budget items
  Future<void> importCatalogItemsToBudget({
    required List<CatalogItem> catalogItems,
    required String? parentId,
    required String projectId,
    required String workspaceId,
  }) async {
    try {
      if (catalogItems.isEmpty) return;

      final targetParent = parentId != null
          ? await getBudgetItem(parentId)
          : null;
      if (parentId != null && targetParent == null) {
        throw Exception('Parent budget item not found');
      }
      if (targetParent != null &&
          targetParent.itemType != BudgetItemType.group) {
        throw Exception(
          'Catalog items can only be imported under budget groups',
        );
      }

      final baseHierarchyLevel = targetParent == null
          ? 0
          : targetParent.hierarchyLevel + 1;
      if (baseHierarchyLevel > 2) {
        throw Exception('Cannot add items below level 2 (Item level)');
      }

      final catalogRows = await _supabase
          .from('catalog_items')
          .select()
          .eq('workspace_id', workspaceId)
          .order('sort_order')
          .order('name');
      final allCatalogItems = catalogRows
          .map((row) => _toCatalogImportItem(row))
          .toList(growable: false);

      final catalogItemsById = {
        for (final item in allCatalogItems) item.id: item,
      };
      final childrenByParentId = <String?, List<CatalogItem>>{};
      for (final item in allCatalogItems) {
        childrenByParentId
            .putIfAbsent(item.parentId, () => <CatalogItem>[])
            .add(item);
      }
      for (final children in childrenByParentId.values) {
        children.sort((a, b) {
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          if (sortCompare != 0) return sortCompare;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      }

      final selectedIds = catalogItems.map((item) => item.id).toSet();
      final rootItems = catalogItems
          .where(
            (item) => !_hasSelectedCatalogAncestor(
              item,
              selectedIds: selectedIds,
              itemsById: catalogItemsById,
            ),
          )
          .toList(growable: false);

      final categoryNames = <String>{};
      for (final rootItem in rootItems) {
        _collectCatalogCategoryNames(
          rootItem,
          childrenByParentId: childrenByParentId,
          into: categoryNames,
        );
      }
      final categoryIdsByName = await _ensureCostCategoryIds(
        workspaceId,
        categoryNames,
      );

      var rootSortOrder = await getNextSortOrder(parentId, projectId);
      final insertedGroupIdsByLevel = <int, Set<String>>{};

      // Cost Plus (percentage) jobs price every line at cost + the agreed fee,
      // so imported catalog leaves must carry that markup too (parity with
      // _applyCostPlusPricing on the form path). [M001]
      final pricingRow = await _supabase
          .from('projects')
          .select('price_type, cost_plus_type, cost_plus_value')
          .eq('id', projectId)
          .maybeSingle();
      final costPlusFeePercent = (pricingRow != null &&
              pricingRow['price_type'] == 'cost_plus' &&
              pricingRow['cost_plus_type'] == 'percentage')
          ? (pricingRow['cost_plus_value'] as num?)?.toDouble()
          : null;

      for (final rootItem in rootItems) {
        await _insertCatalogBranchIntoBudget(
          source: rootItem,
          projectId: projectId,
          workspaceId: workspaceId,
          targetParentId: parentId,
          targetHierarchyLevel: baseHierarchyLevel,
          sortOrder: rootSortOrder++,
          childrenByParentId: childrenByParentId,
          categoryIdsByName: categoryIdsByName,
          insertedGroupIdsByLevel: insertedGroupIdsByLevel,
          costPlusFeePercent: costPlusFeePercent,
        );
      }

      final sortedLevels = insertedGroupIdsByLevel.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final level in sortedLevels) {
        for (final groupId in insertedGroupIdsByLevel[level]!) {
          await _recalculateParentTotals(groupId, workspaceId: workspaceId);
        }
      }

      if (parentId != null) {
        await _recalculateParentTotals(parentId, workspaceId: workspaceId);
      }
    } catch (e) {
      throw Exception('Error importing catalog items: $e');
    }
  }

  Future<void> _insertCatalogBranchIntoBudget({
    required CatalogItem source,
    required String projectId,
    required String workspaceId,
    required String? targetParentId,
    required int targetHierarchyLevel,
    required int sortOrder,
    required Map<String?, List<CatalogItem>> childrenByParentId,
    required Map<String, String> categoryIdsByName,
    required Map<int, Set<String>> insertedGroupIdsByLevel,
    double? costPlusFeePercent,
  }) async {
    if (targetHierarchyLevel > 2) {
      throw Exception(
        'Cannot import "${source.name}" because it would exceed the budget item depth limit.',
      );
    }

    final childItems = childrenByParentId[source.id] ?? const <CatalogItem>[];
    if (source.itemType == CatalogItemType.group && targetHierarchyLevel >= 2) {
      throw Exception(
        'Cannot import catalog group "${source.name}" below budget section level.',
      );
    }

    final now = DateTime.now();
    final isGroup = source.itemType == CatalogItemType.group;
    final categoryId = !isGroup && source.category != null
        ? categoryIdsByName[_normalizeLookupKey(source.category!)]
        : null;
    final unitCost = isGroup ? 0.0 : source.unitCost;
    // On a cost-plus % job, derive the leaf's price/markup from cost + fee so
    // every revenue surface (reads approved_price) reports cost+fee. [M001]
    final bool applyCostPlus =
        !isGroup && costPlusFeePercent != null;
    final markup = isGroup
        ? 0.0
        : (applyCostPlus ? costPlusFeePercent : source.markup);
    final unitPrice = isGroup
        ? 0.0
        : (applyCostPlus
            ? source.unitCost * (1 + costPlusFeePercent / 100)
            : source.unitPrice);
    final projectedCost = isGroup ? 0.0 : source.unitCost;
    final approvedPrice = isGroup ? 0.0 : unitPrice;

    final response = await _supabase
        .from('budget_items')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'parent_id': targetParentId,
          'hierarchy_level': targetHierarchyLevel,
          'sort_order': sortOrder,
          'item_type': isGroup
              ? BudgetItemType.group.name
              : BudgetItemType.item.name,
          'name': source.name,
          'description': source.description,
          'category_id': categoryId,
          'quantity': 1.0,
          'unit': source.unit,
          'unit_cost': unitCost,
          'unit_price': unitPrice,
          'markup': markup,
          'is_taxable': source.isTaxable,
          'approved_price': approvedPrice,
          'projected_cost': projectedCost,
          'cost_type': !isGroup
              ? _budgetCostTypeFromCatalog(source.costTypeName)?.name
              : null,
          // Track the source catalog item on leaf rows so future bulk
          // catalog edits can cascade precisely instead of relying on
          // case-insensitive name matching.
          'source_catalog_item_id': isGroup ? null : source.id,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .select('id')
        .single();
    final insertedId = response['id'] as String;

    if (isGroup) {
      insertedGroupIdsByLevel
          .putIfAbsent(targetHierarchyLevel, () => <String>{})
          .add(insertedId);
    }

    for (var index = 0; index < childItems.length; index++) {
      await _insertCatalogBranchIntoBudget(
        source: childItems[index],
        projectId: projectId,
        workspaceId: workspaceId,
        targetParentId: insertedId,
        targetHierarchyLevel: targetHierarchyLevel + 1,
        sortOrder: index,
        childrenByParentId: childrenByParentId,
        categoryIdsByName: categoryIdsByName,
        insertedGroupIdsByLevel: insertedGroupIdsByLevel,
        costPlusFeePercent: costPlusFeePercent,
      );
    }
  }

  void _collectCatalogCategoryNames(
    CatalogItem item, {
    required Map<String?, List<CatalogItem>> childrenByParentId,
    required Set<String> into,
  }) {
    final categoryName = item.category?.trim();
    if (item.itemType == CatalogItemType.item &&
        categoryName != null &&
        categoryName.isNotEmpty) {
      into.add(categoryName);
    }

    for (final child in childrenByParentId[item.id] ?? const <CatalogItem>[]) {
      _collectCatalogCategoryNames(
        child,
        childrenByParentId: childrenByParentId,
        into: into,
      );
    }
  }

  bool _hasSelectedCatalogAncestor(
    CatalogItem item, {
    required Set<String> selectedIds,
    required Map<String, CatalogItem> itemsById,
  }) {
    var parentId = item.parentId;
    while (parentId != null) {
      if (selectedIds.contains(parentId)) return true;
      parentId = itemsById[parentId]?.parentId;
    }
    return false;
  }

  Future<Map<String, String>> _ensureCostCategoryIds(
    String workspaceId,
    Iterable<String> categoryNames,
  ) async {
    final uniqueNames = categoryNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueNames.isEmpty) return const <String, String>{};

    final existingRows = await _supabase
        .from('cost_categories')
        .select('id,name')
        .eq('workspace_id', workspaceId);
    final categoryIdsByKey = <String, String>{
      for (final row in existingRows)
        _normalizeLookupKey(row['name'] as String): row['id'] as String,
    };

    final ensuredIds = <String, String>{};
    final now = DateTime.now().toIso8601String();

    for (final name in uniqueNames) {
      final key = _normalizeLookupKey(name);
      var categoryId = categoryIdsByKey[key];
      if (categoryId == null) {
        final response = await _supabase
            .from('cost_categories')
            .insert({
              'workspace_id': workspaceId,
              'name': name,
              'color': '#9E9E9E',
              'is_default': false,
              'created_at': now,
              'updated_at': now,
            })
            .select('id')
            .single();
        categoryId = response['id'] as String;
        categoryIdsByKey[key] = categoryId;
      }
      ensuredIds[key] = categoryId;
    }

    return ensuredIds;
  }

  BudgetCostType? _budgetCostTypeFromCatalog(String? value) {
    if (value == null) return null;
    final normalized = _normalizeLookupKey(value).replaceAll(' ', '');
    switch (normalized) {
      case 'labor':
        return BudgetCostType.labor;
      case 'material':
      case 'materials':
        return BudgetCostType.material;
      case 'other':
        return BudgetCostType.other;
      case 'sub':
      case 'subcontractor':
      case 'subcontract':
        return BudgetCostType.subcontractor;
      default:
        return null;
    }
  }

  String _normalizeLookupKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  CatalogItem _toCatalogImportItem(Map<String, dynamic> row) {
    final itemType = row['item_type'] as String?;

    return CatalogItem(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      unit: row['unit'] as String?,
      unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      markup: (row['markup'] as num?)?.toDouble() ?? 0.0,
      margin: (row['margin'] as num?)?.toDouble() ?? 0.0,
      isTaxable: row['is_taxable'] as bool? ?? true,
      costTypeName: row['cost_type_name'] as String?,
      costCodeName: row['cost_code_name'] as String?,
      imageUrl: row['image_url'] as String?,
      category: row['category'] as String?,
      sku: row['sku'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
      parentId: row['parent_id'] as String?,
      hierarchyLevel: (row['hierarchy_level'] as num?)?.toInt() ?? 0,
      itemType: itemType == CatalogItemType.group.name
          ? CatalogItemType.group
          : CatalogItemType.item,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  // Document Status Tracking

  /// Get document status for a single budget item
  Future<BudgetItemDocumentStatus> getDocumentStatusForBudgetItem(
    String budgetItemId,
    String workspaceId,
  ) async {
    try {
      double quotedAmount = 0.0;
      double approvedAmount = 0.0;
      double pendingAmount = 0.0;
      double committedAmount = 0.0;
      double invoicedAmount = 0.0;
      double billedAmount = 0.0;
      double paidAmount = 0.0;
      int bidRequestCount = 0;
      bool hasPendingBid = false;

      // Query generated_documents
      final linksSnapshot = await _supabase
          .from('budget_document_links')
          .select('generated_document_id, amount')
          .eq('workspace_id', workspaceId)
          .eq('budget_item_id', budgetItemId);
      final documentIds = linksSnapshot
          .map((row) => row['generated_document_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final linksByDocumentId = <String, double>{};
      for (final row in linksSnapshot) {
        final docId = row['generated_document_id'] as String?;
        if (docId == null) continue;
        linksByDocumentId[docId] = (row['amount'] as num?)?.toDouble() ?? 0.0;
      }

      if (documentIds.isNotEmpty) {
        final generatedDocsSnapshot = await _supabase
            .from('generated_documents')
            .select('id, status, document_type')
            .eq('workspace_id', workspaceId)
            .inFilter('id', documentIds);

        for (final doc in generatedDocsSnapshot) {
          final docId = doc['id'] as String?;
          if (docId == null) continue;
          final status = doc['status'] as String?;
          final docTypeStr = doc['document_type'] as String?;
          final docType = DocumentTypeExtension.fromStoredValue(docTypeStr);
          final itemAmount = linksByDocumentId[docId] ?? 0.0;
          final impact = docType.budgetImpact;

          // Customer-revenue and vendor-cost docs are tallied separately
          // below via line_items, not via the budget_document_links rollup.
          if (impact == BudgetImpact.customerRevenue ||
              impact == BudgetImpact.vendorCost) {
            continue;
          }

          if (status == 'signed' || status == 'approved') {
            if (impact == BudgetImpact.vendorCommitment) {
              committedAmount += itemAmount;
            } else {
              approvedAmount += itemAmount;
            }
          } else if (status == 'pending') {
            pendingAmount += itemAmount;
          } else if (status == 'draft' ||
              status == 'sent' ||
              status == 'viewed') {
            quotedAmount += itemAmount;
          }
        }
      }

      // Query invoices and bills (from generated_documents)
      final invoicesSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .inFilter('document_type', [
            ...DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.customerRevenue,
            ),
            ...DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.vendorCost,
            ),
          ]);

      for (final doc in invoicesSnapshot) {
        if (doc['exclude_from_budget'] == true) continue;
        final lineItems =
            (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final status = doc['status'] as String?;
        final isPaid = doc['paid_date'] != null;
        final docType = DocumentTypeExtension.fromStoredValue(
          doc['document_type'] as String?,
        );
        final impact = docType.budgetImpact;

        for (final lineItem in lineItems) {
          if (lineItem['budgetItemId'] == budgetItemId ||
              lineItem['budget_item_id'] == budgetItemId) {
            final amount = _lineItemTotal(lineItem);

            if (status == 'sent' ||
                status == 'signed' ||
                status == 'approved') {
              if (impact == BudgetImpact.vendorCost) {
                billedAmount += amount;
              } else {
                invoicedAmount += amount;
              }
              if (isPaid) {
                paidAmount += amount;
              }
            }
          }
        }
      }

      // Query bid requests (from generated_documents)
      final bidRequestsSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('document_type', DocumentType.requestForBid.dbValue);

      for (final doc in bidRequestsSnapshot) {
        final budgetItemIds =
            (doc['budget_item_ids'] as List?)?.cast<String>() ?? [];

        if (budgetItemIds.contains(budgetItemId)) {
          bidRequestCount++;
          final status = doc['status'] as String?;
          if (status == 'draft' || status == 'sent') {
            hasPendingBid = true;
          }
        }
      }

      return BudgetItemDocumentStatus(
        budgetItemId: budgetItemId,
        quotedAmount: quotedAmount,
        approvedAmount: approvedAmount,
        pendingAmount: pendingAmount,
        committedAmount: committedAmount,
        pendingQuoteAmount: quotedAmount,
        invoicedAmount: invoicedAmount,
        billedAmount: billedAmount,
        paidAmount: paidAmount,
        bidRequestCount: bidRequestCount,
        hasPendingBid: hasPendingBid,
      );
    } catch (e) {
      return BudgetItemDocumentStatus(budgetItemId: budgetItemId);
    }
  }

  /// Get document status for all budget items in a project
  Future<Map<String, BudgetItemDocumentStatus>> getDocumentStatusForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, BudgetItemDocumentStatus>{};

      final itemsSnapshot = await _supabase
          .from('budget_items')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final allItems = itemsSnapshot.map((row) => _toBudgetItem(row)).toList();

      for (final item in allItems) {
        result[item.id] = BudgetItemDocumentStatus(budgetItemId: item.id);
      }

      // Query generated document links for this project
      final docLinksSnapshot = await _supabase
          .from('budget_document_links')
          .select('budget_item_id, generated_document_id, amount')
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final generatedDocIds = docLinksSnapshot
          .map((row) => row['generated_document_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final generatedDocsById = <String, Map<String, dynamic>>{};
      if (generatedDocIds.isNotEmpty) {
        final generatedDocsSnapshot = await _supabase
            .from('generated_documents')
            .select('id, status, document_type, exclude_from_budget')
            .eq('workspace_id', workspaceId)
            .eq('project_id', projectId)
            .inFilter('id', generatedDocIds);

        for (final doc in generatedDocsSnapshot) {
          final docId = doc['id'] as String?;
          if (docId != null) {
            generatedDocsById[docId] = doc;
          }
        }
      }

      for (final link in docLinksSnapshot) {
        final itemId = link['budget_item_id'] as String?;
        final docId = link['generated_document_id'] as String?;
        if (itemId == null ||
            docId == null ||
            !result.containsKey(itemId) ||
            !generatedDocsById.containsKey(docId)) {
          continue;
        }

        final doc = generatedDocsById[docId]!;
        if (doc['exclude_from_budget'] == true) continue;
        final docType = DocumentTypeExtension.fromStoredValue(
          doc['document_type'] as String?,
        );
        final impact = docType.budgetImpact;
        // Customer-revenue and vendor-cost docs are tallied below via
        // line_items, not via the budget_document_links rollup.
        if (impact == BudgetImpact.customerRevenue ||
            impact == BudgetImpact.vendorCost) {
          continue;
        }

        final status = doc['status'] as String?;
        final amount = (link['amount'] as num?)?.toDouble() ?? 0.0;
        final current = result[itemId]!;
        if (status == 'signed' || status == 'approved') {
          if (impact == BudgetImpact.vendorCommitment) {
            result[itemId] = current
                .add(committedAmount: amount)
                .addDocumentId(docId);
          } else {
            result[itemId] = current
                .add(approvedAmount: amount)
                .addDocumentId(docId);
          }
        } else if (status == 'pending') {
          result[itemId] = current
              .add(pendingAmount: amount)
              .addDocumentId(docId);
        } else if (status == 'draft' ||
            status == 'sent' ||
            status == 'viewed') {
          result[itemId] = current
              .add(quotedAmount: amount)
              .addDocumentId(docId);
        }
      }

      // Query all invoices and bills for this project (from generated_documents)
      final invoicesSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          .inFilter('document_type', [
            ...DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.customerRevenue,
            ),
            ...DocumentTypeExtension.dbValuesWithBudgetImpact(
              BudgetImpact.vendorCost,
            ),
          ]);

      for (final doc in invoicesSnapshot) {
        if (doc['exclude_from_budget'] == true) continue;
        final invoiceDocId = doc['id'] as String?;
        final lineItems =
            (doc['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final status = doc['status'] as String?;
        final isPaid = doc['paid_date'] != null;
        final docType = DocumentTypeExtension.fromStoredValue(
          doc['document_type'] as String?,
        );
        final impact = docType.budgetImpact;

        for (final lineItem in lineItems) {
          final itemId =
              (lineItem['budgetItemId'] ?? lineItem['budget_item_id'])
                  as String?;
          if (itemId == null || !result.containsKey(itemId)) continue;

          final amount = _lineItemTotal(lineItem);
          final current = result[itemId]!;

          if (status == 'sent' || status == 'signed' || status == 'approved') {
            var updated = current;
            if (impact == BudgetImpact.vendorCost) {
              updated = updated.add(
                billedAmount: amount,
                paidAmount: isPaid ? amount : 0.0,
              );
            } else {
              updated = updated.add(
                invoicedAmount: amount,
                paidAmount: isPaid ? amount : 0.0,
              );
            }
            if (invoiceDocId != null) {
              updated = updated.addDocumentId(invoiceDocId);
            }
            result[itemId] = updated;
          }
        }
      }

      // Query all bid requests for this project (from generated_documents)
      final bidRequestsSnapshot = await _supabase
          .from('generated_documents')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          .eq('document_type', DocumentType.requestForBid.dbValue);

      for (final doc in bidRequestsSnapshot) {
        final bidDocId = doc['id'] as String?;
        final budgetItemIds =
            (doc['budget_item_ids'] as List?)?.cast<String>() ?? [];
        final status = doc['status'] as String?;
        final isPending = status == 'draft' || status == 'sent';

        for (final itemId in budgetItemIds) {
          if (!result.containsKey(itemId)) continue;

          var current = result[itemId]!;
          current = current.add(bidRequestCount: 1, hasPendingBid: isPending);
          if (bidDocId != null) {
            current = current.addDocumentId(bidDocId);
          }
          result[itemId] = current;
        }
      }

      // Roll up statuses to group items
      for (int level = 2; level > 0; level--) {
        final parentItems = allItems
            .where((i) => i.hierarchyLevel == level - 1)
            .toList();
        for (final parent in parentItems) {
          final children = allItems
              .where((i) => i.parentId == parent.id)
              .toList();
          if (children.isEmpty) continue;

          double quoted = 0,
              approved = 0,
              committed = 0,
              pendingQuote = 0,
              pendingDoc = 0,
              invoiced = 0,
              billed = 0,
              paid = 0;
          int bids = 0;
          bool hasPending = false;
          final allDocIds = <String>{};

          for (final child in children) {
            final childStatus = result[child.id]!;
            quoted += childStatus.quotedAmount;
            approved += childStatus.approvedAmount;
            committed += childStatus.committedAmount;
            pendingDoc += childStatus.pendingAmount;
            pendingQuote += childStatus.pendingQuoteAmount;
            invoiced += childStatus.invoicedAmount;
            billed += childStatus.billedAmount;
            paid += childStatus.paidAmount;
            bids += childStatus.bidRequestCount;
            hasPending = hasPending || childStatus.hasPendingBid;
            allDocIds.addAll(childStatus.documentIds);
          }

          result[parent.id] = BudgetItemDocumentStatus(
            budgetItemId: parent.id,
            quotedAmount: quoted,
            approvedAmount: approved,
            committedAmount: committed,
            pendingAmount: pendingDoc,
            pendingQuoteAmount: pendingQuote,
            invoicedAmount: invoiced,
            billedAmount: billed,
            paidAmount: paid,
            bidRequestCount: bids,
            hasPendingBid: hasPending,
            documentIds: allDocIds.toList(),
          );
        }
      }

      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('getDocumentStatusForProject: ERROR - $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return {};
    }
  }

  /// Get actual costs for all budget items in a project
  Future<Map<String, double>> getActualCostsForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, double>{};
      final itemsSnapshot = await _supabase
          .from('budget_items')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final allItems = itemsSnapshot.map((row) => _toBudgetItem(row)).toList();

      final costSnapshot = await _supabase
          .from('cost_items')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final categoryCosts = <String, double>{};
      for (final doc in costSnapshot) {
        final categoryId = doc['category_id'] as String?;
        if (categoryId != null) {
          final cost =
              ((doc['quantity'] as num?)?.toDouble() ?? 0.0) *
              ((doc['unit_price'] as num?)?.toDouble() ?? 0.0);
          categoryCosts[categoryId] = (categoryCosts[categoryId] ?? 0.0) + cost;
        }
      }

      final directCostAllocations = _buildDirectCategoryCostAllocations(
        allItems,
        categoryCosts,
      );

      for (final item in allItems) {
        result[item.id] = _calculateItemActualCostSync(
          item,
          allItems,
          directCostAllocations,
        );
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('getActualCostsForProject: ERROR - $e');
      }
      return {};
    }
  }

  double _calculateItemActualCostSync(
    BudgetItem item,
    List<BudgetItem> allItems,
    Map<String, double> directCostAllocations,
  ) {
    double actualCost = directCostAllocations[item.id] ?? 0.0;

    final children = allItems.where((i) => i.parentId == item.id).toList();
    for (final child in children) {
      actualCost += _calculateItemActualCostSync(
        child,
        allItems,
        directCostAllocations,
      );
    }

    return actualCost;
  }

  Map<String, double> _buildDirectCategoryCostAllocations(
    List<BudgetItem> allItems,
    Map<String, double> categoryCosts,
  ) {
    final allocations = <String, double>{};
    final childrenByParent = <String, List<BudgetItem>>{};
    for (final item in allItems) {
      final parentId = item.parentId;
      if (parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => <BudgetItem>[]).add(item);
    }

    final itemsByCategory = <String, List<BudgetItem>>{};
    for (final item in allItems) {
      final categoryId = item.categoryId;
      if (categoryId == null) continue;
      itemsByCategory.putIfAbsent(categoryId, () => <BudgetItem>[]).add(item);
    }

    for (final entry in categoryCosts.entries) {
      final categoryId = entry.key;
      final categoryTotal = entry.value;
      final matchingItems = itemsByCategory[categoryId] ?? const <BudgetItem>[];
      if (matchingItems.isEmpty || categoryTotal == 0) continue;

      final allocationTargets = matchingItems
          .where((item) {
            return !_hasDescendantWithCategory(
              item.id,
              categoryId,
              childrenByParent,
            );
          })
          .toList(growable: false);
      if (allocationTargets.isEmpty) continue;

      final weightedTotal = allocationTargets.fold<double>(
        0.0,
        (sum, item) => sum + _categoryAllocationWeight(item),
      );

      if (weightedTotal > 0) {
        for (final item in allocationTargets) {
          allocations[item.id] =
              (allocations[item.id] ?? 0.0) +
              (categoryTotal * _categoryAllocationWeight(item) / weightedTotal);
        }
        continue;
      }

      final evenShare = categoryTotal / allocationTargets.length;
      for (final item in allocationTargets) {
        allocations[item.id] = (allocations[item.id] ?? 0.0) + evenShare;
      }
    }

    return allocations;
  }

  bool _hasDescendantWithCategory(
    String itemId,
    String categoryId,
    Map<String, List<BudgetItem>> childrenByParent,
  ) {
    final children = childrenByParent[itemId] ?? const <BudgetItem>[];
    for (final child in children) {
      if (child.categoryId == categoryId ||
          _hasDescendantWithCategory(child.id, categoryId, childrenByParent)) {
        return true;
      }
    }
    return false;
  }

  double _categoryAllocationWeight(BudgetItem item) {
    if (item.projectedCost > 0) return item.projectedCost;
    if (item.approvedPrice > 0) return item.approvedPrice;
    if (item.quantity > 0) return item.quantity;
    return 0.0;
  }

  /// Get progress texts for all budget items in a project
  Future<Map<String, String>> getProgressTextsForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, String>{};
      final itemsSnapshot = await _supabase
          .from('budget_items')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId);

      final allItems = itemsSnapshot.map((row) => _toBudgetItem(row)).toList();

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

  Future<Map<String, String>> getChangeOrderStatusesForProject(
    String projectId,
    String workspaceId,
  ) async {
    try {
      final result = <String, String>{};
      final snapshot = await _supabase
          .from('generated_documents')
          .select('id, status')
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          .eq('document_type', DocumentType.changeOrder.dbValue);

      for (final row in snapshot) {
        final id = row['id'] as String?;
        final status = row['status'] as String?;
        if (id == null || status == null) continue;
        // Capitalize first letter for display
        result[id] = status[0].toUpperCase() + status.substring(1);
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('getChangeOrderStatusesForProject: ERROR - $e');
      }
      return {};
    }
  }

  // Batch Operations

  /// Delete multiple budget items by IDs
  Future<void> deleteBudgetItems(List<String> itemIds) async {
    try {
      if (itemIds.isEmpty) return;

      // Bulk fetch all items to delete in a single query
      final itemsSnapshot = await _supabase
          .from('budget_items')
          .select()
          .inFilter('id', itemIds);

      final items = itemsSnapshot.map((row) => _toBudgetItem(row)).toList();

      // Collect parent IDs for recalculation
      final Set<String> parentsToRecalculate = {};
      for (final item in items) {
        if (item.parentId != null) {
          parentsToRecalculate.add(item.parentId!);
        }
      }

      // Delete each item recursively (cascades to children)
      for (final item in items) {
        await deleteBudgetItem(item.id, recursive: true);
      }

      // Recalculate affected parents (only those that still exist)
      // Remove any parents that were themselves deleted
      parentsToRecalculate.removeAll(itemIds);
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

      final Set<String> parentsToRecalculate = {};
      final now = DateTime.now().toIso8601String();

      // Build batch data for upsert
      final batchData = items.map((item) {
        final data = _toDbFormat(item);
        data['id'] = item.id;
        data['updated_at'] = now;
        if (item.parentId != null) {
          parentsToRecalculate.add(item.parentId!);
        }
        _costCache.remove(item.id);
        return data;
      }).toList();

      // Single upsert call instead of N individual updates
      await _supabase.from('budget_items').upsert(batchData);

      for (final parentId in parentsToRecalculate) {
        await _recalculateParentTotals(parentId);
      }
    } catch (e) {
      throw _wrapBudgetItemWriteError(e, action: 'updating');
    }
  }

  // ============================================================================
  // Change Order → Budget Integration
  // ============================================================================

  /// Apply a change order document's line items to the budget.
  ///
  /// Creates a parent group named after the CO (e.g. "CO-001: Title") and
  /// child budget items for each visible line item. All items are tagged with
  /// [BudgetItemSource.changeOrder] and reference the CO document ID.
  ///
  /// Returns the parent group's ID so the caller can navigate to it.
  /// Existing CO budget items are updated in place when possible, missing
  /// items are inserted, and stale items are removed.
  Future<String?> applyChangeOrderToBudget(GeneratedDocument coDocument) async {
    if (coDocument.projectId == null) return null;

    final projectId = coDocument.projectId!;
    final workspaceId = coDocument.workspaceId;
    final changeOrderId = coDocument.id;

    // Collect visible leaf line items (skip groups, skip hidden)
    final leafItems = coDocument.lineItems
        .where((li) => li.isItem && li.isVisible)
        .toList();

    final existingRows = await _supabase
        .from('budget_items')
        .select('id, parent_id, sort_order, source_line_item_id')
        .eq('change_order_id', changeOrderId)
        .order('sort_order');

    if (leafItems.isEmpty) {
      await removeChangeOrderBudgetItems(changeOrderId);
      return null;
    }

    final now = DateTime.now().toIso8601String();
    final parentRow = existingRows.cast<Map<String, dynamic>>().firstWhere(
      (row) => row['parent_id'] == null,
      orElse: () => <String, dynamic>{},
    );
    final existingParentId = parentRow['id'] as String?;

    // Build the CO group label: "CO-001: Title" or just the document number
    final coLabel = coDocument.documentNumber != null
        ? '${coDocument.documentNumber}: ${coDocument.templateName}'
        : coDocument.templateName;

    String parentId;
    if (existingParentId != null) {
      parentId = existingParentId;
      await _supabase
          .from('budget_items')
          .update({'name': coLabel, 'updated_at': now})
          .eq('id', parentId);
    } else {
      final parentSortOrder = await getNextSortOrder(null, projectId);
      final insertedParent = await _supabase
          .from('budget_items')
          .insert({
            'workspace_id': workspaceId,
            'project_id': projectId,
            'parent_id': null,
            'hierarchy_level': 0,
            'sort_order': parentSortOrder,
            'name': coLabel,
            'item_type': 'group',
            'approved_price': 0.0,
            'projected_cost': 0.0,
            'committed_cost': 0.0,
            'final_cost': 0.0,
            'is_complete': false,
            'source_type': 'change_order',
            'change_order_id': changeOrderId,
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();
      parentId = insertedParent['id'] as String;
    }

    final existingChildRows = existingRows
        .cast<Map<String, dynamic>>()
        .where((row) => row['parent_id'] == parentId)
        .toList(growable: false);
    final childrenBySourceLineItemId = <String, Map<String, dynamic>>{};
    final unmatchedLegacyChildren = <Map<String, dynamic>>[];
    for (final row in existingChildRows) {
      final sourceLineItemId = row['source_line_item_id'] as String?;
      if (sourceLineItemId != null && sourceLineItemId.isNotEmpty) {
        childrenBySourceLineItemId[sourceLineItemId] = row;
      } else {
        unmatchedLegacyChildren.add(row);
      }
    }

    // Line items may reference a pre-existing budget item via budgetItemId —
    // typically because the user dropped that item into the CO via the
    // "Select Items" picker. Without this lookup we'd happily create a fresh
    // child here and leave the original budget item orphaned (visible in the
    // Change Orders view AND counted again by anything that walks budget
    // items by source_type), which is the duplicate the AIA G703 sheet was
    // surfacing as two identical lines.
    final adoptionIds = leafItems
        .map((li) => li.budgetItemId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final adoptableById = <String, Map<String, dynamic>>{};
    if (adoptionIds.isNotEmpty) {
      final adoptRows = await _supabase
          .from('budget_items')
          .select('id, parent_id, change_order_id')
          .inFilter('id', adoptionIds);
      for (final row in (adoptRows as List).cast<Map<String, dynamic>>()) {
        final existingCoId = row['change_order_id'] as String?;
        // Only adopt items that aren't already attached to a different CO.
        // Items already linked to this CO are handled by the
        // change_order_id-keyed lookup above.
        if (existingCoId == null || existingCoId == changeOrderId) {
          adoptableById[row['id'] as String] = row;
        }
      }
    }

    final childRowsToInsert = <Map<String, dynamic>>[];
    final adoptedIds = <String>{};
    for (var i = 0; i < leafItems.length; i++) {
      final li = leafItems[i];
      final approvedPrice = li.quantity * li.unitPrice;
      final childUpdateData = {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'parent_id': parentId,
        'hierarchy_level': 1,
        'sort_order': i,
        'name': li.name,
        'description': li.description,
        'item_type': 'item',
        'quantity': li.quantity,
        'unit': li.unit,
        'unit_price': li.unitPrice,
        'approved_price': approvedPrice,
        'approved_at': now,
        'approved_quantity': li.quantity,
        'approved_unit_price': li.unitPrice,
        'projected_cost': approvedPrice,
        'source_type': 'change_order',
        'change_order_id': changeOrderId,
        'source_line_item_id': li.id,
        'updated_at': now,
      };

      // Prefer the change-order-keyed match first (an existing child under
      // this CO's group), then an unmatched legacy child, and finally a
      // pre-existing budget item the line item points at via budgetItemId.
      String? targetId =
          (childrenBySourceLineItemId.remove(li.id))?['id'] as String?;
      if (targetId == null && unmatchedLegacyChildren.isNotEmpty) {
        targetId = unmatchedLegacyChildren.removeAt(0)['id'] as String?;
      }
      if (targetId == null &&
          li.budgetItemId != null &&
          adoptableById.containsKey(li.budgetItemId) &&
          !adoptedIds.contains(li.budgetItemId)) {
        targetId = li.budgetItemId;
        adoptedIds.add(li.budgetItemId!);
      }

      if (targetId != null) {
        await _supabase
            .from('budget_items')
            .update(childUpdateData)
            .eq('id', targetId);
      } else {
        childRowsToInsert.add({
          ...childUpdateData,
          'unit_cost': 0.0,
          'committed_cost': 0.0,
          'final_cost': 0.0,
          'is_complete': false,
          'created_at': now,
        });
      }
    }

    if (childRowsToInsert.isNotEmpty) {
      await _supabase.from('budget_items').insert(childRowsToInsert);
    }

    final staleChildIds = [
      ...childrenBySourceLineItemId.values,
      ...unmatchedLegacyChildren,
    ].map((row) => row['id'] as String).toList(growable: false);
    if (staleChildIds.isNotEmpty) {
      await _supabase
          .from('budget_items')
          .delete()
          .inFilter('id', staleChildIds);
    }

    // Roll up totals into the parent group
    await _recalculateParentTotals(parentId, workspaceId: workspaceId);

    return parentId;
  }

  /// Remove all budget items created from a change order document.
  ///
  /// Used when a previously-approved CO is voided or rejected. Deletes both
  /// the parent group and all children, then recalculates any affected
  /// ancestor totals.
  Future<void> removeChangeOrderBudgetItems(String changeOrderId) async {
    final rows = await _supabase
        .from('budget_items')
        .select('id, parent_id')
        .eq('change_order_id', changeOrderId);

    if (rows.isEmpty) return;

    final itemIds = rows.map((r) => r['id'] as String).toList();
    final parentIds = rows
        .map((r) => r['parent_id'] as String?)
        .whereType<String>()
        .where((pid) => !itemIds.contains(pid))
        .toSet();

    await _supabase.from('budget_items').delete().inFilter('id', itemIds);

    // Recalculate any surviving ancestors
    for (final parentId in parentIds) {
      final parent = await getBudgetItem(parentId);
      if (parent != null) {
        await _recalculateParentTotals(parentId);
      }
    }
  }

  // Helper Methods

  /// Convert database row to BudgetItem directly (avoids Timestamp compatibility issues)
  BudgetItem _toBudgetItem(Map<String, dynamic> row) {
    final hierarchyLevel = (row['hierarchy_level'] as num?)?.toInt() ?? 0;
    final itemTypeStr = row['item_type'] as String?;
    final sourceTypeStr = row['source_type'] as String?;
    final upgradeStatusStr = row['upgrade_status'] as String?;

    return BudgetItem(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String,
      parentId: row['parent_id'] as String?,
      hierarchyLevel: hierarchyLevel,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      name: row['name'] as String,
      description: row['description'] as String?,
      categoryId: row['category_id'] as String?,
      quantity: (row['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: row['unit'] as String?,
      unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      markup: (row['markup'] as num?)?.toDouble() ?? 0.0,
      isTaxable: row['is_taxable'] as bool? ?? true,
      approvedPrice: (row['approved_price'] as num?)?.toDouble() ?? 0.0,
      approvedAt: row['approved_at'] != null
          ? DateTime.parse(row['approved_at'] as String)
          : null,
      approvedQuantity: (row['approved_quantity'] as num?)?.toDouble(),
      approvedUnitPrice: (row['approved_unit_price'] as num?)?.toDouble(),
      projectedCost: (row['projected_cost'] as num?)?.toDouble() ?? 0.0,
      committedCost: (row['committed_cost'] as num?)?.toDouble() ?? 0.0,
      finalCost: (row['final_cost'] as num?)?.toDouble() ?? 0.0,
      isComplete: row['is_complete'] as bool? ?? false,
      completedDate: row['completed_date'] != null
          ? DateTime.parse(row['completed_date'] as String)
          : null,
      itemType: itemTypeStr != null
          ? BudgetItemType.values.firstWhere(
              (e) => e.name == itemTypeStr,
              orElse: () => hierarchyLevel < 2
                  ? BudgetItemType.group
                  : BudgetItemType.item,
            )
          : (hierarchyLevel < 2 ? BudgetItemType.group : BudgetItemType.item),
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
      notes: row['notes'] as String?,
      // New fields for Change Orders/Upgrades/Holdback
      sourceType: sourceTypeStr != null
          ? BudgetItemSource.values.firstWhere(
              (e) => e.name == _snakeToCamel(sourceTypeStr),
              orElse: () => BudgetItemSource.base,
            )
          : BudgetItemSource.base,
      changeOrderId: row['change_order_id'] as String?,
      upgradeStatus: upgradeStatusStr != null
          ? UpgradeStatus.values.firstWhere(
              (e) => e.name == upgradeStatusStr,
              orElse: () => UpgradeStatus.offered,
            )
          : null,
      costType: BudgetCostType.fromString(row['cost_type'] as String?),
      holdbackPercent: (row['holdback_percent'] as num?)?.toDouble(),
      holdbackReleased: row['holdback_released'] as bool? ?? false,
      holdbackReleasedDate: row['holdback_released_date'] != null
          ? DateTime.parse(row['holdback_released_date'] as String)
          : null,
      isAllowance: row['is_allowance'] as bool? ?? false,
    );
  }

  /// Convert snake_case to camelCase for enum parsing
  String _snakeToCamel(String input) {
    final parts = input.split('_');
    if (parts.length == 1) return input;
    return parts[0] +
        parts
            .skip(1)
            .map(
              (p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join();
  }

  /// Convert BudgetItem to database format (snake_case)
  Map<String, dynamic> _toDbFormat(BudgetItem item) {
    return {
      'workspace_id': item.workspaceId,
      'project_id': item.projectId,
      'parent_id': item.parentId,
      'hierarchy_level': item.hierarchyLevel,
      'sort_order': item.sortOrder,
      'name': item.name,
      'description': item.description,
      'category_id': item.categoryId,
      'quantity': item.quantity,
      'approved_price': item.approvedPrice,
      'approved_at': item.approvedAt?.toIso8601String(),
      'approved_quantity': item.approvedQuantity,
      'approved_unit_price': item.approvedUnitPrice,
      'projected_cost': item.projectedCost,
      'committed_cost': item.committedCost,
      'final_cost': item.finalCost,
      'is_complete': item.isComplete,
      'completed_date': item.completedDate?.toIso8601String(),
      'item_type': item.itemType.name,
      'unit': item.unit,
      'unit_cost': item.unitCost,
      'unit_price': item.unitPrice,
      'markup': item.markup,
      'is_taxable': item.isTaxable,
      'notes': item.notes,
      'cost_type': item.costType?.name,
      // New fields for Change Orders/Upgrades/Holdback
      'source_type': _camelToSnake(item.sourceType.name),
      'change_order_id': item.changeOrderId,
      'upgrade_status': item.upgradeStatus?.name,
      'holdback_percent': item.holdbackPercent,
      'holdback_released': item.holdbackReleased,
      'holdback_released_date': item.holdbackReleasedDate?.toIso8601String(),
    };
  }

  /// Convert camelCase to snake_case
  String _camelToSnake(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  Exception _wrapBudgetItemWriteError(Object error, {required String action}) {
    if (error is UserFacingException) {
      return error;
    }

    if (_isBudgetPercentageOverflow(error)) {
      return UserFacingException(
        'One of the budget percentages is too large to save. Lower the markup or holdback percentage and try again.',
        cause: error,
      );
    }

    return Exception('Error $action budget item: $error');
  }

  bool _isBudgetPercentageOverflow(Object error) {
    final text = error is PostgrestException
        ? '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
              .toLowerCase()
        : error.toString().toLowerCase();

    return text.contains('numeric field overflow') &&
        text.contains('precision 5, scale 2');
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
    return diff.inSeconds > 5;
  }
}
