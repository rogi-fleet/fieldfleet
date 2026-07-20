/// A consumable / restockable inventory item (anti-microbial, plastic
/// sheeting, drywall, fasteners, PPE, etc.) Tailored to insurance restoration
/// and general contractor workflows.
class InventoryItem {
  final String id;
  final String workspaceId;
  final String? sku;
  final String name;
  final String? description;
  final String category;        // see [InventoryItemCategory]
  final String unitOfMeasure;   // each, box, gallon, sqft, ...
  final String? defaultSupplierId;
  final double unitCost;        // what we pay
  final double? unitSalePrice;  // what we charge a job (markup baked in)
  final double onHandQty;       // maintained by trigger
  final double reorderPoint;
  final String? storageLocation;
  final List<String> photoUrls;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryItem({
    required this.id,
    required this.workspaceId,
    this.sku,
    required this.name,
    this.description,
    this.category = 'other',
    this.unitOfMeasure = 'each',
    this.defaultSupplierId,
    this.unitCost = 0,
    this.unitSalePrice,
    this.onHandQty = 0,
    this.reorderPoint = 0,
    this.storageLocation,
    this.photoUrls = const [],
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBelowReorderPoint => onHandQty <= reorderPoint;

  factory InventoryItem.fromRow(Map<String, dynamic> r) => InventoryItem(
        id: r['id'],
        workspaceId: r['workspace_id'],
        sku: r['sku'],
        name: r['name'] ?? '',
        description: r['description'],
        category: r['category'] ?? 'other',
        unitOfMeasure: r['unit_of_measure'] ?? 'each',
        defaultSupplierId: r['default_supplier_id'],
        unitCost: (r['unit_cost'] as num?)?.toDouble() ?? 0,
        unitSalePrice: (r['unit_sale_price'] as num?)?.toDouble(),
        onHandQty: (r['on_hand_qty'] as num?)?.toDouble() ?? 0,
        reorderPoint: (r['reorder_point'] as num?)?.toDouble() ?? 0,
        storageLocation: r['storage_location'],
        photoUrls:
            (r['photo_urls'] as List<dynamic>?)?.cast<String>() ?? const [],
        isActive: r['is_active'] ?? true,
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'])
            : DateTime.now(),
        updatedAt: r['updated_at'] != null
            ? DateTime.parse(r['updated_at'])
            : DateTime.now(),
      );

  /// Excludes [onHandQty] which is owned by the DB trigger.
  Map<String, dynamic> toDb() => {
        'workspace_id': workspaceId,
        'sku': sku,
        'name': name,
        'description': description,
        'category': category,
        'unit_of_measure': unitOfMeasure,
        'default_supplier_id': defaultSupplierId,
        'unit_cost': unitCost,
        'unit_sale_price': unitSalePrice,
        'reorder_point': reorderPoint,
        'storage_location': storageLocation,
        'photo_urls': photoUrls,
        'is_active': isActive,
      };

  InventoryItem copyWith({
    String? sku,
    String? name,
    String? description,
    String? category,
    String? unitOfMeasure,
    String? defaultSupplierId,
    double? unitCost,
    double? unitSalePrice,
    double? reorderPoint,
    String? storageLocation,
    List<String>? photoUrls,
    bool? isActive,
  }) =>
      InventoryItem(
        id: id,
        workspaceId: workspaceId,
        sku: sku ?? this.sku,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
        defaultSupplierId: defaultSupplierId ?? this.defaultSupplierId,
        unitCost: unitCost ?? this.unitCost,
        unitSalePrice: unitSalePrice ?? this.unitSalePrice,
        onHandQty: onHandQty,
        reorderPoint: reorderPoint ?? this.reorderPoint,
        storageLocation: storageLocation ?? this.storageLocation,
        photoUrls: photoUrls ?? this.photoUrls,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// Pre-defined categories tailored to restoration / GC work. Stored as text
/// so users can extend at any time via free entry.
class InventoryItemCategory {
  static const all = <String, String>{
    'antimicrobial': 'Antimicrobial / Biocide',
    'ppe': 'PPE & Safety',
    'plastic_sheeting': 'Plastic Sheeting & Containment',
    'drywall': 'Drywall & Joint Compound',
    'lumber': 'Lumber & Framing',
    'fasteners': 'Fasteners & Hardware',
    'cleaning': 'Cleaning Supplies',
    'paint': 'Paint & Finishes',
    'flooring': 'Flooring Materials',
    'electrical': 'Electrical Supplies',
    'plumbing': 'Plumbing Supplies',
    'tools_consumable': 'Consumable Tools (blades, bits)',
    'water_damage': 'Water Damage Supplies',
    'mold_remediation': 'Mold Remediation',
    'fire_smoke': 'Fire & Smoke Restoration',
    'other': 'Other',
  };

  static String displayNameFor(String key) =>
      all[key] ?? key.replaceAll('_', ' ');
}
