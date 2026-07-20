enum StockMovementType {
  receive, // stock arriving
  issue,   // stock used on a job
  returned, // stock returned to inventory from a job (named to avoid `return` keyword)
  adjust;  // manual count correction (signed quantity)

  String get dbName {
    switch (this) {
      case StockMovementType.receive:
        return 'receive';
      case StockMovementType.issue:
        return 'issue';
      case StockMovementType.returned:
        return 'return';
      case StockMovementType.adjust:
        return 'adjust';
    }
  }

  String get displayName {
    switch (this) {
      case StockMovementType.receive:
        return 'Received';
      case StockMovementType.issue:
        return 'Issued to Job';
      case StockMovementType.returned:
        return 'Returned';
      case StockMovementType.adjust:
        return 'Adjustment';
    }
  }

  static StockMovementType fromDb(String? s) {
    switch (s) {
      case 'receive':
        return StockMovementType.receive;
      case 'issue':
        return StockMovementType.issue;
      case 'return':
        return StockMovementType.returned;
      case 'adjust':
        return StockMovementType.adjust;
      default:
        return StockMovementType.adjust;
    }
  }
}

class InventoryStockMovement {
  final String id;
  final String workspaceId;
  final String inventoryItemId;
  final StockMovementType movementType;
  final double quantity;        // always positive; sign comes from movementType
  final double? unitCost;       // snapshot at the moment of movement
  final String? projectId;
  final String? purchaseOrderId;
  final String? costItemId;     // financials backlink
  final String? notes;
  final DateTime occurredAt;
  final DateTime createdAt;

  InventoryStockMovement({
    required this.id,
    required this.workspaceId,
    required this.inventoryItemId,
    required this.movementType,
    required this.quantity,
    this.unitCost,
    this.projectId,
    this.purchaseOrderId,
    this.costItemId,
    this.notes,
    required this.occurredAt,
    required this.createdAt,
  });

  /// Signed delta this movement applies to on-hand qty (UI display only;
  /// the DB trigger is the source of truth).
  double get signedDelta {
    switch (movementType) {
      case StockMovementType.receive:
      case StockMovementType.returned:
      case StockMovementType.adjust:
        return quantity;
      case StockMovementType.issue:
        return -quantity;
    }
  }

  factory InventoryStockMovement.fromRow(Map<String, dynamic> r) =>
      InventoryStockMovement(
        id: r['id'],
        workspaceId: r['workspace_id'],
        inventoryItemId: r['inventory_item_id'],
        movementType: StockMovementType.fromDb(r['movement_type']),
        quantity: (r['quantity'] as num).toDouble(),
        unitCost: (r['unit_cost'] as num?)?.toDouble(),
        projectId: r['project_id'],
        purchaseOrderId: r['purchase_order_id'],
        costItemId: r['cost_item_id'],
        notes: r['notes'],
        occurredAt: r['occurred_at'] != null
            ? DateTime.parse(r['occurred_at'])
            : DateTime.now(),
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'])
            : DateTime.now(),
      );

  Map<String, dynamic> toDb() => {
        'workspace_id': workspaceId,
        'inventory_item_id': inventoryItemId,
        'movement_type': movementType.dbName,
        'quantity': quantity,
        'unit_cost': unitCost,
        'project_id': projectId,
        'purchase_order_id': purchaseOrderId,
        'cost_item_id': costItemId,
        'notes': notes,
        'occurred_at': occurredAt.toIso8601String(),
      };
}
