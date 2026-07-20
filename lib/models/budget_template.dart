import 'budget_item.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class BudgetTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final List<BudgetTemplateItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  BudgetTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory BudgetTemplate.fromJson(Map<String, dynamic> json, String id) {
    final itemsList =
        (json['items'] as List?)
            ?.map(
              (item) =>
                  BudgetTemplateItem.fromJson(item as Map<String, dynamic>),
            )
            .toList() ??
        [];

    return BudgetTemplate(
      id: id,
      workspaceId: json['workspaceId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      items: itemsList,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      createdBy: json['createdBy'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'description': description,
      'items': items.map((item) => item.toJson()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }
}

/// Lightweight representation of a budget item for templates
class BudgetTemplateItem {
  final String tempId; // Temporary ID for template (not Firestore ID)
  final String? parentTempId; // Reference to parent's tempId
  final int hierarchyLevel;
  final int sortOrder;
  final BudgetItemType itemType;
  final String name;
  final String? description;
  final String? categoryId;
  final double approvedPrice;
  final double projectedCost;

  BudgetTemplateItem({
    required this.tempId,
    this.parentTempId,
    required this.hierarchyLevel,
    required this.sortOrder,
    required this.itemType,
    required this.name,
    this.description,
    this.categoryId,
    required this.approvedPrice,
    required this.projectedCost,
  });

  factory BudgetTemplateItem.fromJson(Map<String, dynamic> json) {
    return BudgetTemplateItem(
      tempId: json['tempId'] as String,
      parentTempId: json['parentTempId'] as String?,
      hierarchyLevel: (json['hierarchyLevel'] as num).toInt(),
      sortOrder: (json['sortOrder'] as num).toInt(),
      itemType: json['itemType'] != null
          ? BudgetItemType.values.firstWhere(
              (value) => value.name == json['itemType'],
              orElse: () => (json['hierarchyLevel'] as num).toInt() < 2
                  ? BudgetItemType.group
                  : BudgetItemType.item,
            )
          : (json['hierarchyLevel'] as num).toInt() < 2
          ? BudgetItemType.group
          : BudgetItemType.item,
      name: json['name'] as String,
      description: json['description'] as String?,
      categoryId: json['categoryId'] as String?,
      approvedPrice: (json['approvedPrice'] as num?)?.toDouble() ?? 0.0,
      projectedCost: (json['projectedCost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tempId': tempId,
      'parentTempId': parentTempId,
      'hierarchyLevel': hierarchyLevel,
      'sortOrder': sortOrder,
      'itemType': itemType.name,
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'approvedPrice': approvedPrice,
      'projectedCost': projectedCost,
    };
  }
}
