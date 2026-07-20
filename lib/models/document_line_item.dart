enum DocumentLineItemType { group, item }

/// A line item for documents that can be linked to budget items or standalone.
/// Supports hierarchical display (groups containing items) and visibility controls.
class DocumentLineItem {
  final String id;
  final String? budgetItemId; // Link to budget item (null = doc-only item)

  /// Link to the project cost item this line was billed from (null unless the
  /// line was pulled onto the invoice via the cost → invoice bridge).
  final String? costItemId;
  final DocumentLineItemType type;
  final String? parentId; // For hierarchy (groups contain items)
  final int sortOrder;

  // Content (can override budget item values)
  final String name;
  final String? description;
  final double quantity;
  final String? unit;
  final double unitPrice;

  // Display options
  final bool isVisible; // Eye icon toggle - whether to show in document

  /// Whether this line is subject to sales tax. Tax is charged only on the sum
  /// of taxable lines (`Σ taxable line.total × rate`), so a non-taxable line
  /// (e.g. exempt labor) is excluded from the tax base while still counting
  /// toward the subtotal/total. Defaults to taxable. [M002]
  final bool isTaxable;

  /// Links this line to a stockable inventory item. Non-null only on purchase
  /// order documents whose line was placed against tracked inventory; receiving
  /// such a line records a stock movement that increments on-hand quantity.
  final String? inventoryItemId;

  /// Quantity received so far against [quantity] on a purchase order line.
  /// Only meaningful when [inventoryItemId] is set. Drives the PO's derived
  /// fulfillment state (none / partial / received).
  final double quantityReceived;

  /// Vendor-submitted bid price for this line, populated on
  /// request-for-bid documents after the vendor responds. Null on all other
  /// document types and on RFBs awaiting a vendor response.
  final double? vendorBidPrice;

  /// Optional per-line note the vendor may attach to their bid (e.g.
  /// "excludes permits"). Only meaningful alongside [vendorBidPrice].
  final String? vendorBidNote;

  /// Fields the user has explicitly overridden from the linked budget item.
  /// The resync process skips any field listed here so user adjustments are preserved.
  /// Field names mirror the Dart property names: 'name', 'description',
  /// 'quantity', 'unit', 'unitPrice'.
  final Set<String> customizedFields;

  DocumentLineItem({
    required this.id,
    this.budgetItemId,
    this.costItemId,
    required this.type,
    this.parentId,
    required this.sortOrder,
    required this.name,
    this.description,
    this.quantity = 1.0,
    this.unit,
    this.unitPrice = 0.0,
    this.isVisible = true,
    this.isTaxable = true,
    this.inventoryItemId,
    this.quantityReceived = 0.0,
    this.vendorBidPrice,
    this.vendorBidNote,
    Set<String>? customizedFields,
  }) : customizedFields = customizedFields ?? const {};

  /// Quantity still outstanding on a received PO line (never negative).
  double get quantityRemaining {
    final remaining = quantity - quantityReceived;
    return remaining < 0 ? 0 : remaining;
  }

  /// Total for this line item (quantity * unitPrice)
  double get total => quantity * unitPrice;

  /// Total of the vendor's bid for this line (quantity * vendorBidPrice).
  /// Returns null when the vendor has not submitted a bid yet.
  double? get vendorBidTotal =>
      vendorBidPrice == null ? null : quantity * vendorBidPrice!;

  /// Formatted total as currency string
  String get formattedTotal => '\$${total.toStringAsFixed(2)}';

  /// Formatted unit price as currency string
  String get formattedUnitPrice => '\$${unitPrice.toStringAsFixed(2)}';

  /// Formatted quantity
  String get formattedQuantity {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity.toStringAsFixed(2);
  }

  /// Formatted received quantity (mirrors [formattedQuantity]).
  String get formattedQuantityReceived {
    if (quantityReceived == quantityReceived.roundToDouble()) {
      return quantityReceived.toInt().toString();
    }
    return quantityReceived.toStringAsFixed(2);
  }

  factory DocumentLineItem.fromJson(Map<String, dynamic> json) {
    return DocumentLineItem(
      id: json['id'] as String,
      budgetItemId: json['budgetItemId'] as String?,
      costItemId: json['costItemId'] as String?,
      type: DocumentLineItemType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DocumentLineItemType.item,
      ),
      parentId: json['parentId'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      name: json['name'] as String,
      description: json['description'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String?,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      isVisible: json['isVisible'] as bool? ?? true,
      isTaxable: json['isTaxable'] as bool? ?? true,
      inventoryItemId: json['inventoryItemId'] as String?,
      quantityReceived: (json['quantityReceived'] as num?)?.toDouble() ?? 0.0,
      vendorBidPrice: (json['vendorBidPrice'] as num?)?.toDouble(),
      vendorBidNote: json['vendorBidNote'] as String?,
      customizedFields: Set<String>.from(
        json['customizedFields'] as List? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'budgetItemId': budgetItemId,
      if (costItemId != null) 'costItemId': costItemId,
      'type': type.name,
      'parentId': parentId,
      'sortOrder': sortOrder,
      'name': name,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'totalPrice': total,
      'isVisible': isVisible,
      'isTaxable': isTaxable,
      if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
      if (inventoryItemId != null) 'quantityReceived': quantityReceived,
      if (vendorBidPrice != null) 'vendorBidPrice': vendorBidPrice,
      if (vendorBidNote != null) 'vendorBidNote': vendorBidNote,
      'customizedFields': customizedFields.toList(),
    };
  }

  DocumentLineItem copyWith({
    String? id,
    String? budgetItemId,
    String? costItemId,
    DocumentLineItemType? type,
    String? parentId,
    int? sortOrder,
    String? name,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    bool? isVisible,
    bool? isTaxable,
    String? inventoryItemId,
    double? quantityReceived,
    double? vendorBidPrice,
    String? vendorBidNote,
    Set<String>? customizedFields,
    bool clearVendorBid = false,
  }) {
    return DocumentLineItem(
      id: id ?? this.id,
      budgetItemId: budgetItemId ?? this.budgetItemId,
      costItemId: costItemId ?? this.costItemId,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      name: name ?? this.name,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      isVisible: isVisible ?? this.isVisible,
      isTaxable: isTaxable ?? this.isTaxable,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      quantityReceived: quantityReceived ?? this.quantityReceived,
      vendorBidPrice: clearVendorBid
          ? null
          : (vendorBidPrice ?? this.vendorBidPrice),
      vendorBidNote: clearVendorBid
          ? null
          : (vendorBidNote ?? this.vendorBidNote),
      customizedFields: customizedFields ?? this.customizedFields,
    );
  }

  /// Check if this is a group (can contain other items)
  bool get isGroup => type == DocumentLineItemType.group;

  /// Check if this is a leaf item (cannot contain other items)
  bool get isItem => type == DocumentLineItemType.item;

  /// Check if this is a top-level item (no parent)
  bool get isTopLevel => parentId == null;
}

/// Visibility mode for line items in documents
enum LineItemVisibility {
  all('all', 'All Items', 'Show all line items with full details'),
  topLevel(
    'top_level',
    'Top Level Only',
    'Show only top-level groups with totals',
  ),
  none('none', 'Hide All', 'Hide line items section entirely');

  final String dbValue;
  final String displayName;
  final String description;

  const LineItemVisibility(this.dbValue, this.displayName, this.description);

  static LineItemVisibility fromString(String? value) {
    if (value == null) return LineItemVisibility.all;
    return switch (value) {
      'all' => LineItemVisibility.all,
      'top_level' || 'topLevel' => LineItemVisibility.topLevel,
      'none' => LineItemVisibility.none,
      _ => LineItemVisibility.all,
    };
  }
}
