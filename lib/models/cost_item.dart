import 'package:cloud_firestore/cloud_firestore.dart';

enum CostItemType {
  material,
  labor;

  String get displayName {
    switch (this) {
      case CostItemType.material:
        return 'Material';
      case CostItemType.labor:
        return 'Labor';
    }
  }

  static CostItemType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'material':
        return CostItemType.material;
      case 'labor':
        return CostItemType.labor;
      default:
        throw ArgumentError('Invalid cost item type: $type');
    }
  }
}

class CostItem {
  final String id;
  final String projectId;
  final String workspaceId;
  final CostItemType type;
  final String categoryId;
  final String description;
  final double quantity; // units for materials, hours for labor
  final double unitPrice; // price per unit or hourly rate
  final double totalCost; // calculated: quantity × unitPrice
  final DateTime date;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this cost is chargeable to the client (eligible to be pulled
  /// onto an invoice). Internal-use materials are issued with this false.
  final bool billable;

  /// The invoice document that has billed this cost, or null if still
  /// unbilled. Set by the `bill_cost_items_to_document` RPC.
  final String? invoicedDocumentId;

  CostItem({
    required this.id,
    required this.projectId,
    required this.workspaceId,
    required this.type,
    required this.categoryId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.date,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.billable = true,
    this.invoicedDocumentId,
  }) : totalCost = quantity * unitPrice;

  /// True once this cost has been pulled onto an invoice document.
  bool get isInvoiced => invoicedDocumentId != null;

  factory CostItem.fromJson(Map<String, dynamic> json, String id) {
    return CostItem(
      id: id,
      projectId: json['projectId'] as String,
      workspaceId: json['workspaceId'] as String,
      type: CostItemType.fromString(json['type'] as String),
      categoryId: json['categoryId'] as String,
      description: json['description'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      date: (json['date'] as Timestamp).toDate(),
      notes: json['notes'] as String?,
      createdBy: json['createdBy'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      billable: json['billable'] as bool? ?? true,
      invoicedDocumentId: json['invoicedDocumentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectId': projectId,
      'workspaceId': workspaceId,
      'type': type.name,
      'categoryId': categoryId,
      'description': description,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalCost': totalCost,
      'date': Timestamp.fromDate(date),
      'notes': notes,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'billable': billable,
      'invoicedDocumentId': invoicedDocumentId,
    };
  }

  CostItem copyWith({
    String? id,
    String? projectId,
    String? workspaceId,
    CostItemType? type,
    String? categoryId,
    String? description,
    double? quantity,
    double? unitPrice,
    DateTime? date,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? billable,
    String? invoicedDocumentId,
  }) {
    return CostItem(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      workspaceId: workspaceId ?? this.workspaceId,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      billable: billable ?? this.billable,
      invoicedDocumentId: invoicedDocumentId ?? this.invoicedDocumentId,
    );
  }

  bool validate() {
    return description.isNotEmpty &&
        quantity > 0 &&
        unitPrice > 0 &&
        categoryId.isNotEmpty;
  }

  // Formatted display for quantity
  String get formattedQuantity {
    if (type == CostItemType.labor) {
      return '${quantity.toStringAsFixed(1)} hrs';
    }
    return quantity.toStringAsFixed(2);
  }

  // Formatted display for unit price
  String get formattedUnitPrice {
    if (type == CostItemType.labor) {
      return '\$${unitPrice.toStringAsFixed(2)}/hr';
    }
    return '\$${unitPrice.toStringAsFixed(2)}';
  }

  // Formatted display for total cost
  String get formattedTotalCost {
    return '\$${totalCost.toStringAsFixed(2)}';
  }
}
