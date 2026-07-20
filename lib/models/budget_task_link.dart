class BudgetTaskLink {
  final String taskId;
  final String budgetItemId;
  final double allocationPercentage;
  final String workspaceId;
  final DateTime createdAt;

  BudgetTaskLink({
    required this.taskId,
    required this.budgetItemId,
    this.allocationPercentage = 100.0,
    required this.workspaceId,
    required this.createdAt,
  });

  factory BudgetTaskLink.fromJson(Map<String, dynamic> json) {
    return BudgetTaskLink(
      taskId: json['task_id'] as String,
      budgetItemId: json['budget_item_id'] as String,
      allocationPercentage:
          (json['allocation_percentage'] as num?)?.toDouble() ?? 100.0,
      workspaceId: json['workspace_id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'budget_item_id': budgetItemId,
      'allocation_percentage': allocationPercentage,
      'workspace_id': workspaceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  BudgetTaskLink copyWith({
    String? taskId,
    String? budgetItemId,
    double? allocationPercentage,
    String? workspaceId,
    DateTime? createdAt,
  }) {
    return BudgetTaskLink(
      taskId: taskId ?? this.taskId,
      budgetItemId: budgetItemId ?? this.budgetItemId,
      allocationPercentage: allocationPercentage ?? this.allocationPercentage,
      workspaceId: workspaceId ?? this.workspaceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
