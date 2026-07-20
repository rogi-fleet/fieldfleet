import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/pricing_math.dart';
import 'catalog/catalog_kind.dart';

enum CatalogItemType { group, item }

class CatalogItem {
  static const Object _unset = Object();

  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final String? unit;
  final double unitCost;
  final double unitPrice;
  final double markup; // Percentage
  final double margin; // Percentage
  final bool isTaxable;
  final String? costTypeName;
  final String? costCodeName;
  final String? imageUrl;
  final String? category;
  final String? sku;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Hierarchy
  final String? parentId;
  final int hierarchyLevel;
  final CatalogItemType itemType;
  final int sortOrder;

  // Robustness / integration fields (added 20260510)
  final CatalogKind kind;
  final bool isActive;
  final String? internalNotes;
  final String? barcode;
  final List<String> tags;
  final String currency;
  final double? minPrice;
  // Sales-side defaults
  final double defaultTaxRate; // percent (0-100)
  // Purchase-side defaults
  final String? defaultVendorId;
  final String? purchaseUnit;
  final double? purchaseCost;
  final String? purchaseDescription;
  // Inventory linkage
  final bool inventoryTracked;
  final String? inventoryItemId;
  // Usage analytics
  final int usageCount;
  final DateTime? lastUsedAt;

  CatalogItem({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    this.unit,
    required this.unitCost,
    required this.unitPrice,
    required this.markup,
    required this.margin,
    this.isTaxable = true,
    this.costTypeName,
    this.costCodeName,
    this.imageUrl,
    this.category,
    this.sku,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.hierarchyLevel = 0,
    this.itemType = CatalogItemType.item,
    this.sortOrder = 0,
    this.kind = CatalogKind.service,
    this.isActive = true,
    this.internalNotes,
    this.barcode,
    this.tags = const [],
    this.currency = 'USD',
    this.minPrice,
    this.defaultTaxRate = 0,
    this.defaultVendorId,
    this.purchaseUnit,
    this.purchaseCost,
    this.purchaseDescription,
    this.inventoryTracked = false,
    this.inventoryItemId,
    this.usageCount = 0,
    this.lastUsedAt,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json, String id) {
    return CatalogItem(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      unit: json['unit'] as String?,
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      markup: (json['markup'] as num?)?.toDouble() ?? 0.0,
      margin: (json['margin'] as num?)?.toDouble() ?? 0.0,
      isTaxable: json['isTaxable'] as bool? ?? true,
      costTypeName: json['costTypeName'] as String?,
      costCodeName: json['costCodeName'] as String?,
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String?,
      sku: json['sku'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      parentId: json['parentId'] as String?,
      hierarchyLevel: json['hierarchyLevel'] as int? ?? 0,
      itemType: json['itemType'] != null
          ? CatalogItemType.values.firstWhere(
              (e) => e.toString() == 'CatalogItemType.${json['itemType']}',
              orElse: () => CatalogItemType.item,
            )
          : CatalogItemType.item,
      sortOrder: json['sortOrder'] as int? ?? 0,
      kind: CatalogKind.fromWire(json['kind'] as String?),
      isActive: json['isActive'] as bool? ?? true,
      internalNotes: json['internalNotes'] as String?,
      barcode: json['barcode'] as String?,
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      currency: json['currency'] as String? ?? 'USD',
      minPrice: (json['minPrice'] as num?)?.toDouble(),
      defaultTaxRate: (json['defaultTaxRate'] as num?)?.toDouble() ?? 0.0,
      defaultVendorId: json['defaultVendorId'] as String?,
      purchaseUnit: json['purchaseUnit'] as String?,
      purchaseCost: (json['purchaseCost'] as num?)?.toDouble(),
      purchaseDescription: json['purchaseDescription'] as String?,
      inventoryTracked: json['inventoryTracked'] as bool? ?? false,
      inventoryItemId: json['inventoryItemId'] as String?,
      usageCount: json['usageCount'] as int? ?? 0,
      lastUsedAt: json['lastUsedAt'] is Timestamp
          ? (json['lastUsedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'description': description,
      'unit': unit,
      'unitCost': unitCost,
      'unitPrice': unitPrice,
      'markup': markup,
      'margin': margin,
      'isTaxable': isTaxable,
      'costTypeName': costTypeName,
      'costCodeName': costCodeName,
      'imageUrl': imageUrl,
      'category': category,
      'sku': sku,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'parentId': parentId,
      'hierarchyLevel': hierarchyLevel,
      'itemType': itemType.toString().split('.').last,
      'sortOrder': sortOrder,
      'kind': kind.wire,
      'isActive': isActive,
      'internalNotes': internalNotes,
      'barcode': barcode,
      'tags': tags,
      'currency': currency,
      'minPrice': minPrice,
      'defaultTaxRate': defaultTaxRate,
      'defaultVendorId': defaultVendorId,
      'purchaseUnit': purchaseUnit,
      'purchaseCost': purchaseCost,
      'purchaseDescription': purchaseDescription,
      'inventoryTracked': inventoryTracked,
      'inventoryItemId': inventoryItemId,
      'usageCount': usageCount,
      'lastUsedAt': lastUsedAt == null ? null : Timestamp.fromDate(lastUsedAt!),
    };
  }

  CatalogItem copyWith({
    String? id,
    String? workspaceId,
    String? name,
    Object? description = _unset,
    Object? unit = _unset,
    double? unitCost,
    double? unitPrice,
    double? markup,
    double? margin,
    bool? isTaxable,
    Object? costTypeName = _unset,
    Object? costCodeName = _unset,
    Object? imageUrl = _unset,
    Object? category = _unset,
    Object? sku = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? parentId = _unset,
    int? hierarchyLevel,
    CatalogItemType? itemType,
    int? sortOrder,
    CatalogKind? kind,
    bool? isActive,
    Object? internalNotes = _unset,
    Object? barcode = _unset,
    List<String>? tags,
    String? currency,
    Object? minPrice = _unset,
    double? defaultTaxRate,
    Object? defaultVendorId = _unset,
    Object? purchaseUnit = _unset,
    Object? purchaseCost = _unset,
    Object? purchaseDescription = _unset,
    bool? inventoryTracked,
    Object? inventoryItemId = _unset,
    int? usageCount,
    Object? lastUsedAt = _unset,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      unit: identical(unit, _unset) ? this.unit : unit as String?,
      unitCost: unitCost ?? this.unitCost,
      unitPrice: unitPrice ?? this.unitPrice,
      markup: markup ?? this.markup,
      margin: margin ?? this.margin,
      isTaxable: isTaxable ?? this.isTaxable,
      costTypeName: identical(costTypeName, _unset)
          ? this.costTypeName
          : costTypeName as String?,
      costCodeName: identical(costCodeName, _unset)
          ? this.costCodeName
          : costCodeName as String?,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
      category:
          identical(category, _unset) ? this.category : category as String?,
      sku: identical(sku, _unset) ? this.sku : sku as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentId:
          identical(parentId, _unset) ? this.parentId : parentId as String?,
      hierarchyLevel: hierarchyLevel ?? this.hierarchyLevel,
      itemType: itemType ?? this.itemType,
      sortOrder: sortOrder ?? this.sortOrder,
      kind: kind ?? this.kind,
      isActive: isActive ?? this.isActive,
      internalNotes: identical(internalNotes, _unset)
          ? this.internalNotes
          : internalNotes as String?,
      barcode:
          identical(barcode, _unset) ? this.barcode : barcode as String?,
      tags: tags ?? this.tags,
      currency: currency ?? this.currency,
      minPrice:
          identical(minPrice, _unset) ? this.minPrice : minPrice as double?,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      defaultVendorId: identical(defaultVendorId, _unset)
          ? this.defaultVendorId
          : defaultVendorId as String?,
      purchaseUnit: identical(purchaseUnit, _unset)
          ? this.purchaseUnit
          : purchaseUnit as String?,
      purchaseCost: identical(purchaseCost, _unset)
          ? this.purchaseCost
          : purchaseCost as double?,
      purchaseDescription: identical(purchaseDescription, _unset)
          ? this.purchaseDescription
          : purchaseDescription as String?,
      inventoryTracked: inventoryTracked ?? this.inventoryTracked,
      inventoryItemId: identical(inventoryItemId, _unset)
          ? this.inventoryItemId
          : inventoryItemId as String?,
      usageCount: usageCount ?? this.usageCount,
      lastUsedAt: identical(lastUsedAt, _unset)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
    );
  }

  // Pricing relationships live in PricingMath (shared with budget items and
  // inline grid cells); these aliases keep the historical call sites working.
  static double calculateMarkup(double cost, double price) =>
      PricingMath.markup(cost, price);

  static double calculateMargin(double cost, double price) =>
      PricingMath.margin(cost, price);

  static double calculatePriceFromMarkup(double cost, double markupPercent) =>
      PricingMath.priceFromMarkup(cost, markupPercent);

  static double calculatePriceFromMargin(double cost, double marginPercent) =>
      PricingMath.priceFromMargin(cost, marginPercent);

  String get formattedMarkup => '${markup.toStringAsFixed(1)}%';
  String get formattedMargin => '${margin.toStringAsFixed(1)}%';

  bool validate() {
    return name.isNotEmpty &&
        hierarchyLevel >= 0 &&
        hierarchyLevel <= 2 &&
        unitCost >= 0 &&
        unitPrice >= 0 &&
        defaultTaxRate >= 0 &&
        defaultTaxRate <= 100;
  }

  String get hierarchyLevelName {
    return itemType == CatalogItemType.group ? 'Group' : 'Item';
  }
}
