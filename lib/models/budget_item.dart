import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum BudgetItemType { group, item }

/// Source of a budget item - determines which view mode shows it
enum BudgetItemSource { base, changeOrder, upgrade }

/// Status for upgrade items (only valid when sourceType = upgrade)
enum UpgradeStatus { offered, accepted, declined }

/// Cost type classification for budget items.
enum BudgetCostType {
  labor,
  material,
  other,
  subcontractor;

  String get displayLabel {
    switch (this) {
      case BudgetCostType.labor:
        return 'Labor';
      case BudgetCostType.material:
        return 'Material';
      case BudgetCostType.other:
        return 'Other';
      case BudgetCostType.subcontractor:
        return 'Sub';
    }
  }

  Color get color {
    switch (this) {
      case BudgetCostType.labor:
        return const Color(0xFF4A90A4);
      case BudgetCostType.material:
        return const Color(0xFFE8973A);
      case BudgetCostType.other:
        return const Color(0xFF9E9E9E);
      case BudgetCostType.subcontractor:
        return const Color(0xFF7B61FF);
    }
  }

  static BudgetCostType? fromString(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'labor':
        return BudgetCostType.labor;
      case 'material':
        return BudgetCostType.material;
      case 'other':
        return BudgetCostType.other;
      case 'subcontractor':
        return BudgetCostType.subcontractor;
      default:
        return null;
    }
  }
}

class BudgetItem {
  static const Object _unset = Object();

  final String id;
  final String workspaceId;
  final String projectId;

  // Hierarchy
  final String? parentId; // null for top-level items
  final int
  hierarchyLevel; // Nesting level in the hierarchy (0 = root, 1 = nested once, etc.)
  final BudgetItemType itemType; // group (containers) vs item (leaf nodes)
  final int sortOrder; // for ordering within parent

  // Basic Info
  final String name;
  final String? description;
  final String? categoryId; // links to CostCategory for filtering actual costs

  // Cost Tracking
  final double quantity;
  final String? unit;
  final double unitCost; // Estimated cost per unit
  final double unitPrice; // Estimated price per unit
  final double markup; // Markup percentage (overrides project default)
  final bool isTaxable; // Whether item is taxable
  final double approvedPrice; // What client approved/contracted for (total)
  final DateTime?
  approvedAt; // When this item was contracted (via a linked approved document). null = not yet approved.
  final double?
  approvedQuantity; // Snapshot of quantity at approval time, for variance display
  final double?
  approvedUnitPrice; // Snapshot of unit price at approval time, for variance display
  final double projectedCost; // Estimated cost to complete (total)
  final double committedCost; // Total from Purchase Orders
  final double finalCost; // Actual cost when item is complete (0 if incomplete)

  // Progress
  final bool isComplete;
  final DateTime? completedDate;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  // Source tracking (for Change Orders/Upgrades view modes)
  final BudgetItemSource sourceType;
  final String? changeOrderId;
  final UpgradeStatus? upgradeStatus;

  // Cost type classification
  final BudgetCostType? costType;

  // Holdback / Retention tracking
  final double? holdbackPercent;
  final bool holdbackReleased;
  final DateTime? holdbackReleasedDate;

  // Selections / Allowances: true when this line is the budgeted allowance for
  // a client Selection. Set by the selection-approval RPC; lets the budget UI
  // flag the line as an allowance.
  final bool isAllowance;

  BudgetItem({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    this.parentId,
    required this.hierarchyLevel,
    required this.sortOrder,
    required this.name,
    this.description,
    this.categoryId,
    this.quantity = 1.0,
    this.unit,
    this.unitCost = 0.0,
    this.unitPrice = 0.0,
    this.markup = 0.0,
    this.isTaxable = true,
    required this.approvedPrice,
    this.approvedAt,
    this.approvedQuantity,
    this.approvedUnitPrice,
    required this.projectedCost,
    this.committedCost = 0.0,
    this.finalCost = 0.0,
    this.isComplete = false,
    this.completedDate,
    required this.itemType,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.sourceType = BudgetItemSource.base,
    this.changeOrderId,
    this.upgradeStatus,
    this.costType,
    this.holdbackPercent,
    this.holdbackReleased = false,
    this.holdbackReleasedDate,
    this.isAllowance = false,
  });

  factory BudgetItem.fromJson(Map<String, dynamic> json, String id) {
    return BudgetItem(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      parentId: json['parentId'] as String?,
      hierarchyLevel: json['hierarchyLevel'] as int,
      sortOrder: json['sortOrder'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      categoryId: json['categoryId'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String?,
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      markup: (json['markup'] as num?)?.toDouble() ?? 0.0,
      isTaxable: json['isTaxable'] as bool? ?? true,
      approvedPrice: (json['approvedPrice'] as num).toDouble(),
      approvedAt: json['approvedAt'] != null
          ? (json['approvedAt'] is Timestamp
                ? (json['approvedAt'] as Timestamp).toDate()
                : DateTime.parse(json['approvedAt'] as String))
          : (json['approved_at'] != null
                ? DateTime.parse(json['approved_at'] as String)
                : null),
      approvedQuantity:
          (json['approvedQuantity'] ?? json['approved_quantity'] as num?)
              ?.toDouble(),
      approvedUnitPrice:
          (json['approvedUnitPrice'] ?? json['approved_unit_price'] as num?)
              ?.toDouble(),
      projectedCost: (json['projectedCost'] as num).toDouble(),
      committedCost: (json['committedCost'] as num?)?.toDouble() ?? 0.0,
      finalCost: json['finalCost'] != null
          ? (json['finalCost'] as num).toDouble()
          : 0.0,
      isComplete: json['isComplete'] as bool? ?? false,
      completedDate: json['completedDate'] != null
          ? (json['completedDate'] as Timestamp).toDate()
          : null,
      itemType: json['itemType'] != null
          ? BudgetItemType.values.firstWhere(
              (e) => e.toString() == 'BudgetItemType.${json['itemType']}',
              orElse: () => json['hierarchyLevel'] < 2
                  ? BudgetItemType.group
                  : BudgetItemType.item,
            )
          : (json['hierarchyLevel'] < 2
                ? BudgetItemType.group
                : BudgetItemType.item),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      notes: json['notes'] as String?,
      sourceType: json['sourceType'] != null || json['source_type'] != null
          ? BudgetItemSource.values.firstWhere(
              (e) =>
                  e.toString() ==
                  'BudgetItemSource.${_snakeToCamel(json['sourceType'] ?? json['source_type'] ?? 'base')}',
              orElse: () => BudgetItemSource.base,
            )
          : BudgetItemSource.base,
      changeOrderId:
          json['changeOrderId'] ?? json['change_order_id'] as String?,
      upgradeStatus:
          json['upgradeStatus'] != null || json['upgrade_status'] != null
          ? UpgradeStatus.values.firstWhere(
              (e) =>
                  e.toString() ==
                  'UpgradeStatus.${_snakeToCamel(json['upgradeStatus'] ?? json['upgrade_status'])}',
              orElse: () => UpgradeStatus.offered,
            )
          : null,
      costType: BudgetCostType.fromString(
        json['costType'] as String? ?? json['cost_type'] as String?,
      ),
      holdbackPercent:
          (json['holdbackPercent'] ?? json['holdback_percent'] as num?)
              ?.toDouble(),
      holdbackReleased:
          json['holdbackReleased'] ??
          json['holdback_released'] as bool? ??
          false,
      holdbackReleasedDate: json['holdbackReleasedDate'] != null
          ? (json['holdbackReleasedDate'] as Timestamp).toDate()
          : json['holdback_released_date'] != null
          ? DateTime.parse(json['holdback_released_date'] as String)
          : null,
      isAllowance:
          (json['isAllowance'] ?? json['is_allowance']) as bool? ?? false,
    );
  }

  /// Convert snake_case to camelCase for enum parsing
  static String _snakeToCamel(String input) {
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

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'parentId': parentId,
      'hierarchyLevel': hierarchyLevel,
      'sortOrder': sortOrder,
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'quantity': quantity,
      'unit': unit,
      'unitCost': unitCost,
      'unitPrice': unitPrice,
      'markup': markup,
      'isTaxable': isTaxable,
      'approvedPrice': approvedPrice,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'approvedQuantity': approvedQuantity,
      'approvedUnitPrice': approvedUnitPrice,
      'projectedCost': projectedCost,
      'committedCost': committedCost,
      'finalCost': finalCost,
      'isComplete': isComplete,
      'completedDate': completedDate != null
          ? Timestamp.fromDate(completedDate!)
          : null,
      'itemType': itemType.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'notes': notes,
      'sourceType': sourceType.toString().split('.').last,
      'changeOrderId': changeOrderId,
      'upgradeStatus': upgradeStatus?.toString().split('.').last,
      'costType': costType?.name,
      'holdbackPercent': holdbackPercent,
      'holdbackReleased': holdbackReleased,
      'holdbackReleasedDate': holdbackReleasedDate != null
          ? Timestamp.fromDate(holdbackReleasedDate!)
          : null,
      'isAllowance': isAllowance,
    };
  }

  BudgetItem copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    Object? parentId = _unset,
    int? hierarchyLevel,
    int? sortOrder,
    String? name,
    Object? description = _unset,
    Object? categoryId = _unset,
    double? quantity,
    Object? unit = _unset,
    double? unitCost,
    double? unitPrice,
    double? markup,
    bool? isTaxable,
    double? approvedPrice,
    Object? approvedAt = _unset,
    Object? approvedQuantity = _unset,
    Object? approvedUnitPrice = _unset,
    double? projectedCost,
    double? committedCost,
    double? finalCost,
    bool? isComplete,
    Object? completedDate = _unset,
    BudgetItemType? itemType,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? notes = _unset,
    BudgetItemSource? sourceType,
    Object? changeOrderId = _unset,
    Object? upgradeStatus = _unset,
    Object? costType = _unset,
    Object? holdbackPercent = _unset,
    bool? holdbackReleased,
    Object? holdbackReleasedDate = _unset,
    bool? isAllowance,
  }) {
    return BudgetItem(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      parentId: identical(parentId, _unset)
          ? this.parentId
          : parentId as String?,
      hierarchyLevel: hierarchyLevel ?? this.hierarchyLevel,
      sortOrder: sortOrder ?? this.sortOrder,
      name: name ?? this.name,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      quantity: quantity ?? this.quantity,
      unit: identical(unit, _unset) ? this.unit : unit as String?,
      unitCost: unitCost ?? this.unitCost,
      unitPrice: unitPrice ?? this.unitPrice,
      markup: markup ?? this.markup,
      isTaxable: isTaxable ?? this.isTaxable,
      approvedPrice: approvedPrice ?? this.approvedPrice,
      approvedAt: identical(approvedAt, _unset)
          ? this.approvedAt
          : approvedAt as DateTime?,
      approvedQuantity: identical(approvedQuantity, _unset)
          ? this.approvedQuantity
          : approvedQuantity as double?,
      approvedUnitPrice: identical(approvedUnitPrice, _unset)
          ? this.approvedUnitPrice
          : approvedUnitPrice as double?,
      projectedCost: projectedCost ?? this.projectedCost,
      committedCost: committedCost ?? this.committedCost,
      finalCost: finalCost ?? this.finalCost,
      isComplete: isComplete ?? this.isComplete,
      completedDate: identical(completedDate, _unset)
          ? this.completedDate
          : completedDate as DateTime?,
      itemType: itemType ?? this.itemType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      sourceType: sourceType ?? this.sourceType,
      changeOrderId: identical(changeOrderId, _unset)
          ? this.changeOrderId
          : changeOrderId as String?,
      upgradeStatus: identical(upgradeStatus, _unset)
          ? this.upgradeStatus
          : upgradeStatus as UpgradeStatus?,
      costType: identical(costType, _unset)
          ? this.costType
          : costType as BudgetCostType?,
      holdbackPercent: identical(holdbackPercent, _unset)
          ? this.holdbackPercent
          : holdbackPercent as double?,
      holdbackReleased: holdbackReleased ?? this.holdbackReleased,
      holdbackReleasedDate: identical(holdbackReleasedDate, _unset)
          ? this.holdbackReleasedDate
          : holdbackReleasedDate as DateTime?,
      isAllowance: isAllowance ?? this.isAllowance,
    );
  }

  bool validate() {
    return name.isNotEmpty &&
        hierarchyLevel >= 0 &&
        hierarchyLevel <= 2 &&
        approvedPrice >= 0 &&
        projectedCost >= 0;
  }

  // Computed Properties

  /// Whether this item has been contracted via an approved document.
  /// When true, approvedPrice/approvedQuantity/approvedUnitPrice are frozen.
  bool get isApproved => approvedAt != null;

  /// Current extended price (live quantity * unit price). Differs from
  /// approvedPrice once the item is approved and then edited.
  double get currentExtendedPrice => quantity * unitPrice;

  /// Delta between current extended price and approved price.
  /// 0 when not yet approved or when values match the snapshot.
  double get approvedPriceVariance =>
      isApproved ? currentExtendedPrice - approvedPrice : 0.0;

  /// Calculate projected profit (approved price - projected cost)
  double get projectedProfit => approvedPrice - projectedCost;

  /// Calculate projected margin as percentage
  double get projectedMargin {
    if (approvedPrice == 0) return 0.0;
    return (projectedProfit / approvedPrice) * 100;
  }

  /// Calculate actual profit based on actual cost
  double actualProfit(double actualCost) => approvedPrice - actualCost;

  /// Calculate actual margin based on actual cost
  double actualMargin(double actualCost) {
    if (approvedPrice == 0) return 0.0;
    return (actualProfit(actualCost) / approvedPrice) * 100;
  }

  /// Calculate profit variance (actual vs projected)
  double projectedProfitVariance(double actualCost) {
    final actProfit = actualProfit(actualCost);
    return actProfit - projectedProfit;
  }

  // Holdback / Retention Computed Properties

  /// Amount held back (not yet collectible) based on holdback percentage
  double get holdbackAmount => (holdbackPercent ?? 0) / 100 * approvedPrice;

  /// Amount actually collectible (approved minus holdback, unless released)
  double get collectibleAmount =>
      holdbackReleased ? approvedPrice : approvedPrice - holdbackAmount;

  /// Whether this item has any holdback configured
  bool get hasHoldback => (holdbackPercent ?? 0) > 0;

  /// Formatted holdback amount
  String get formattedHoldbackAmount =>
      '\$${holdbackAmount.toStringAsFixed(2)}';

  /// Formatted collectible amount
  String get formattedCollectibleAmount =>
      '\$${collectibleAmount.toStringAsFixed(2)}';

  /// Get formatted approved price
  String get formattedApprovedPrice => '\$${approvedPrice.toStringAsFixed(2)}';

  /// Get formatted projected cost
  String get formattedProjectedCost => '\$${projectedCost.toStringAsFixed(2)}';

  /// Get formatted unit cost
  String get formattedUnitCost => '\$${unitCost.toStringAsFixed(2)}';

  /// Get formatted unit price
  String get formattedUnitPrice => '\$${unitPrice.toStringAsFixed(2)}';

  /// Get formatted committed cost
  String get formattedCommittedCost => '\$${committedCost.toStringAsFixed(2)}';

  /// Get formatted final cost
  String get formattedFinalCost => '\$${finalCost.toStringAsFixed(2)}';

  /// Get formatted projected profit
  String get formattedProjectedProfit {
    final profit = projectedProfit;
    return '${profit >= 0 ? '' : '-'}\$${profit.abs().toStringAsFixed(2)}';
  }

  /// Get formatted actual profit
  String formattedActualProfit(double actualCost) {
    final profit = actualProfit(actualCost);
    return '${profit >= 0 ? '' : '-'}\$${profit.abs().toStringAsFixed(2)}';
  }

  /// Get formatted projected margin
  String get formattedProjectedMargin =>
      '${projectedMargin.toStringAsFixed(1)}%';

  /// Get formatted actual margin
  String formattedActualMargin(double actualCost) =>
      '${actualMargin(actualCost).toStringAsFixed(1)}%';

  /// Get formatted markup
  String get formattedMarkup => '${markup.toStringAsFixed(1)}%';

  /// Get extended price (quantity * unit price)
  double get extendedPrice => quantity * unitPrice;

  /// Get formatted extended price
  String get formattedExtendedPrice => '\$${extendedPrice.toStringAsFixed(2)}';

  /// Get item type name (Group or Item based on itemType)
  String get hierarchyLevelName {
    return itemType == BudgetItemType.group ? 'Group' : 'Item';
  }
}
