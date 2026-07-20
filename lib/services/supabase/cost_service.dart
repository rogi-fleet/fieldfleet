import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/cost_item.dart';

/// Supabase implementation of CostService
class SupabaseCostService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Create a new cost item
  Future<String> createCostItem(CostItem costItem) async {
    try {
      final now = DateTime.now();
      final data = _toDbFormat(costItem);
      data['created_at'] = now.toIso8601String();
      data['updated_at'] = now.toIso8601String();

      final response = await _supabase
          .from('cost_items')
          .insert(data)
          .select('id')
          .single();

      return response['id'];
    } catch (e) {
      throw Exception('Error creating cost item: $e');
    }
  }

  /// Get all cost items for a project
  Stream<List<CostItem>> getCostItems(String projectId, {String? workspaceId}) {
    try {
      return _supabase
          .from('cost_items')
          .stream(primaryKey: ['id'])
          .eq('project_id', projectId)
          .map((data) {
            var items = data.map((row) => _toCostItem(row)).toList();
            if (workspaceId != null) {
              items = items.where((item) => item.workspaceId == workspaceId).toList();
            }
            return items;
          });
    } catch (e) {
      throw Exception('Error fetching cost items: $e');
    }
  }

  /// Get cost items by type
  Stream<List<CostItem>> getCostItemsByType(
    String projectId,
    CostItemType type, {
    String? workspaceId,
  }) {
    try {
      return _supabase
          .from('cost_items')
          .stream(primaryKey: ['id'])
          .eq('project_id', projectId)
          .map((data) {
            var items = data
                .where((row) => row['type'] == type.name)
                .map((row) => _toCostItem(row))
                .toList();
            if (workspaceId != null) {
              items = items.where((item) => item.workspaceId == workspaceId).toList();
            }
            return items;
          });
    } catch (e) {
      throw Exception('Error fetching cost items by type: $e');
    }
  }

  /// Get cost items by category
  Stream<List<CostItem>> getCostItemsByCategory(
    String projectId,
    String categoryId, {
    String? workspaceId,
  }) {
    try {
      return _supabase
          .from('cost_items')
          .stream(primaryKey: ['id'])
          .eq('project_id', projectId)
          .map((data) {
            var items = data
                .where((row) => row['category_id'] == categoryId)
                .map((row) => _toCostItem(row))
                .toList();
            if (workspaceId != null) {
              items = items.where((item) => item.workspaceId == workspaceId).toList();
            }
            return items;
          });
    } catch (e) {
      throw Exception('Error fetching cost items by category: $e');
    }
  }

  /// Update a cost item
  Future<void> updateCostItem(CostItem costItem) async {
    try {
      final data = _toDbFormat(costItem);
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('cost_items')
          .update(data)
          .eq('id', costItem.id);
    } catch (e) {
      throw Exception('Error updating cost item: $e');
    }
  }

  /// Delete a cost item
  Future<void> deleteCostItem(String costItemId) async {
    try {
      await _supabase.from('cost_items').delete().eq('id', costItemId);
    } catch (e) {
      throw Exception('Error deleting cost item: $e');
    }
  }

  /// Calculate cost totals for a project
  Future<Map<String, double>> calculateCostTotals(
    String projectId, {
    String? workspaceId,
  }) async {
    try {
      var query = _supabase
          .from('cost_items')
          .select()
          .eq('project_id', projectId);

      if (workspaceId != null) {
        query = query.eq('workspace_id', workspaceId);
      }

      final response = await query;
      final items = response.map((row) => _toCostItem(row)).toList();

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

  /// Calculate total costs with markup
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

  /// List a project's billable costs that have not yet been pulled onto an
  /// invoice — the candidate list for the "Bill to client" picker.
  Future<List<CostItem>> getUnbilledBillableCosts(
    String projectId, {
    required String workspaceId,
    CostItemType? type,
  }) async {
    try {
      var query = _supabase
          .from('cost_items')
          .select()
          .eq('project_id', projectId)
          .eq('workspace_id', workspaceId)
          .eq('billable', true)
          .isFilter('invoiced_document_id', null);
      if (type != null) {
        query = query.eq('type', type.name);
      }
      final response = await query.order('date');
      return (response as List)
          .cast<Map<String, dynamic>>()
          .map(_toCostItem)
          .toList();
    } catch (e) {
      throw Exception('Error fetching unbilled costs: $e');
    }
  }

  /// Atomically append the given costs to an invoice document as line items
  /// and mark them invoiced. Returns the number of costs actually billed
  /// (costs already invoiced or non-billable are skipped server-side).
  Future<int> billCostsToDocument({
    required String documentId,
    required List<String> costItemIds,
  }) async {
    if (costItemIds.isEmpty) return 0;
    try {
      final result = await _supabase.rpc(
        'bill_cost_items_to_document',
        params: {
          'p_document_id': documentId,
          'p_cost_item_ids': costItemIds,
        },
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      throw Exception('Error billing costs to invoice: $e');
    }
  }

  /// Toggle whether a cost is chargeable to the client.
  Future<void> setBillable(String costItemId, bool billable) async {
    try {
      await _supabase
          .from('cost_items')
          .update({
            'billable': billable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', costItemId);
    } catch (e) {
      throw Exception('Error updating cost billable flag: $e');
    }
  }

  /// Get a single cost item
  Future<CostItem?> getCostItem(String costItemId) async {
    try {
      final response = await _supabase
          .from('cost_items')
          .select()
          .eq('id', costItemId)
          .maybeSingle();

      if (response == null) return null;
      return _toCostItem(response);
    } catch (e) {
      throw Exception('Error fetching cost item: $e');
    }
  }

  /// Convert database row to CostItem
  CostItem _toCostItem(Map<String, dynamic> row) {
    return CostItem(
      id: row['id'],
      workspaceId: row['workspace_id'],
      projectId: row['project_id'],
      categoryId: row['category_id'] ?? '',
      type: CostItemType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => CostItemType.material,
      ),
      description: row['description'] ?? '',
      quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      notes: row['notes'],
      date: row['date'] != null ? DateTime.parse(row['date']) : DateTime.now(),
      createdBy: row['created_by'] ?? '',
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'])
          : DateTime.now(),
      billable: row['billable'] as bool? ?? true,
      invoicedDocumentId: row['invoiced_document_id'] as String?,
    );
  }

  /// Convert CostItem to database format
  Map<String, dynamic> _toDbFormat(CostItem item) {
    return {
      'workspace_id': item.workspaceId,
      'project_id': item.projectId,
      'category_id': item.categoryId,
      'type': item.type.name,
      'description': item.description,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'notes': item.notes,
      'date': item.date.toIso8601String(),
      'created_by': item.createdBy,
      'billable': item.billable,
    };
  }
}
