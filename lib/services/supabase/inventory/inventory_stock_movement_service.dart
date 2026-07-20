import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/inventory/inventory_stock_movement.dart';

/// Records stock receive/issue/return/adjust movements. Issuing stock to a
/// project also writes a `cost_items` row so the cost rolls up into the
/// project Financials tab — this is what links inventory consumption to
/// the per-job cost ledger.
class SupabaseInventoryStockMovementService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String workspaceId;

  SupabaseInventoryStockMovementService({required this.workspaceId});

  Stream<List<InventoryStockMovement>> watchMovementsForItem(String itemId) {
    return _supabase
        .from('inventory_stock_movements')
        .stream(primaryKey: ['id'])
        .eq('inventory_item_id', itemId)
        .map((rows) {
          final list = rows.map(InventoryStockMovement.fromRow).toList();
          list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          return list;
        });
  }

  Stream<List<InventoryStockMovement>> watchMovementsForProject(
    String projectId,
  ) {
    return _supabase
        .from('inventory_stock_movements')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .map((rows) {
          final list = rows.map(InventoryStockMovement.fromRow).toList();
          list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          return list;
        });
  }

  Future<InventoryStockMovement> record(InventoryStockMovement movement) async {
    final user = _supabase.auth.currentUser;
    final data = movement.toDb();
    data['created_by'] = user?.id;
    final row = await _supabase
        .from('inventory_stock_movements')
        .insert(data)
        .select()
        .single();
    return InventoryStockMovement.fromRow(row);
  }

  /// Issue stock to a job. Inserts the movement, then writes a corresponding
  /// `cost_items` row of type 'material' so the cost shows up under the
  /// project Financials. Returns the resulting movement.
  ///
  /// [unitSalePriceOverride] takes priority over [unitCost] when writing
  /// the cost item so contractors can mark up materials at issue time.
  ///
  /// [billable] marks the resulting cost as chargeable to the client; pass
  /// false for internal-use stock so it never surfaces in the bill-to-client
  /// picker.
  Future<String> issueToJob({
    required String inventoryItemId,
    required String projectId,
    required double quantity,
    required String itemName,
    required double unitCost,
    double? unitSalePriceOverride,
    String? categoryId,
    String? notes,
    DateTime? occurredAt,
    bool billable = true,
  }) async {
    final now = occurredAt ?? DateTime.now();
    final billedUnit = unitSalePriceOverride ?? unitCost;
    final description =
        (notes != null && notes.isNotEmpty) ? '$itemName — $notes' : itemName;

    // Single Postgres function = single transaction — either the cost row
    // and the movement row are both written, or neither is. No more
    // orphaned cost items if the inventory write fails.
    final movementId = await _supabase.rpc('inventory_issue_to_job', params: {
      'p_workspace_id': workspaceId,
      'p_inventory_item': inventoryItemId,
      'p_project_id': projectId,
      'p_quantity': quantity,
      'p_unit_cost': unitCost,
      'p_billed_unit': billedUnit,
      'p_description': description,
      'p_category_id': categoryId,
      'p_notes': notes,
      'p_occurred_at': now.toIso8601String(),
      'p_billable': billable,
    });
    return movementId as String;
  }

  /// Edit an existing job issue. Updates the movement and its linked
  /// `cost_items` row in one transaction via `inventory_update_issue`, so the
  /// issued quantity and the project cost line can never drift apart. The
  /// apply-movement trigger re-balances on-hand stock from the quantity delta.
  ///
  /// [unitSalePriceOverride] is what the client is charged per unit (the cost
  /// line's unit price); it falls back to [unitCost] when null. The server
  /// refuses the edit if the cost has already been billed to an invoice.
  Future<void> updateIssue({
    required String movementId,
    required double quantity,
    required String itemName,
    required double unitCost,
    double? unitSalePriceOverride,
    String? notes,
    bool billable = true,
  }) async {
    final billedUnit = unitSalePriceOverride ?? unitCost;
    final description =
        (notes != null && notes.isNotEmpty) ? '$itemName — $notes' : itemName;
    await _supabase.rpc('inventory_update_issue', params: {
      'p_movement_id': movementId,
      'p_quantity': quantity,
      'p_unit_cost': unitCost,
      'p_billed_unit': billedUnit,
      'p_description': description,
      'p_notes': notes,
      'p_billable': billable,
    });
  }

  /// Reverse a job issue: delete the movement (the apply-movement trigger adds
  /// the quantity back to on-hand stock) and its linked cost line, atomically.
  /// The server refuses if the cost has already been billed to an invoice.
  Future<void> reverseIssue(String movementId) async {
    await _supabase.rpc('inventory_reverse_issue', params: {
      'p_movement_id': movementId,
    });
  }
}
