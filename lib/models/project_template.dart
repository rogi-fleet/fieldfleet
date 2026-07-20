/// Model for project templates — reusable project configurations.
class ProjectTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final ProjectTemplateSettings settings;
  final List<ProjectTemplateTask> tasks;
  final List<ProjectTemplateBudgetItem> budgetItems;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.settings,
    this.tasks = const [],
    this.budgetItems = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalItemCount => tasks.length + budgetItems.length;
}

/// Snapshot of project-level settings stored in a template.
class ProjectTemplateSettings {
  final String? jobType;
  final String? priceType;
  final double? materialMarkupPercent;
  final double? laborMarkupPercent;
  final double? estimatedBudget;
  final double? contractAmount;
  final String? costPlusType;
  final double? costPlusValue;
  final String? description;

  ProjectTemplateSettings({
    this.jobType,
    this.priceType,
    this.materialMarkupPercent,
    this.laborMarkupPercent,
    this.estimatedBudget,
    this.contractAmount,
    this.costPlusType,
    this.costPlusValue,
    this.description,
  });

  factory ProjectTemplateSettings.fromJson(Map<String, dynamic> json) {
    return ProjectTemplateSettings(
      jobType: json['job_type'] as String?,
      priceType: json['price_type'] as String?,
      materialMarkupPercent: (json['material_markup_percent'] as num?)?.toDouble(),
      laborMarkupPercent: (json['labor_markup_percent'] as num?)?.toDouble(),
      estimatedBudget: (json['estimated_budget'] as num?)?.toDouble(),
      contractAmount: (json['contract_amount'] as num?)?.toDouble(),
      costPlusType: json['cost_plus_type'] as String?,
      costPlusValue: (json['cost_plus_value'] as num?)?.toDouble(),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_type': jobType,
      'price_type': priceType,
      'material_markup_percent': materialMarkupPercent,
      'labor_markup_percent': laborMarkupPercent,
      'estimated_budget': estimatedBudget,
      'contract_amount': contractAmount,
      'cost_plus_type': costPlusType,
      'cost_plus_value': costPlusValue,
      'description': description,
    };
  }
}

/// Snapshot of a task for inclusion in a project template.
class ProjectTemplateTask {
  final String tempId;
  final String? parentTempId;
  final String title;
  final String? description;
  final int sortOrder;
  final String? groupName;
  final String? groupColor;

  ProjectTemplateTask({
    required this.tempId,
    this.parentTempId,
    required this.title,
    this.description,
    required this.sortOrder,
    this.groupName,
    this.groupColor,
  });

  factory ProjectTemplateTask.fromJson(Map<String, dynamic> json) {
    return ProjectTemplateTask(
      tempId: json['temp_id'] as String? ?? '',
      parentTempId: json['parent_temp_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      groupName: json['group_name'] as String?,
      groupColor: json['group_color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temp_id': tempId,
      'parent_temp_id': parentTempId,
      'title': title,
      'description': description,
      'sort_order': sortOrder,
      'group_name': groupName,
      'group_color': groupColor,
    };
  }
}

/// Snapshot of a budget item for inclusion in a project template.
class ProjectTemplateBudgetItem {
  final String tempId;
  final String? parentTempId;
  final int hierarchyLevel;
  final int sortOrder;
  final String name;
  final String? description;
  final String? categoryId;
  final double approvedPrice;
  final double projectedCost;

  ProjectTemplateBudgetItem({
    required this.tempId,
    this.parentTempId,
    required this.hierarchyLevel,
    required this.sortOrder,
    required this.name,
    this.description,
    this.categoryId,
    required this.approvedPrice,
    required this.projectedCost,
  });

  factory ProjectTemplateBudgetItem.fromJson(Map<String, dynamic> json) {
    return ProjectTemplateBudgetItem(
      tempId: json['temp_id'] as String? ?? '',
      parentTempId: json['parent_temp_id'] as String?,
      hierarchyLevel: (json['hierarchy_level'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      categoryId: json['category_id'] as String?,
      approvedPrice: (json['approved_price'] as num?)?.toDouble() ?? 0.0,
      projectedCost: (json['projected_cost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temp_id': tempId,
      'parent_temp_id': parentTempId,
      'hierarchy_level': hierarchyLevel,
      'sort_order': sortOrder,
      'name': name,
      'description': description,
      'category_id': categoryId,
      'approved_price': approvedPrice,
      'projected_cost': projectedCost,
    };
  }
}
