class BudgetItemLaborSummary {
  final String budgetItemId;
  final double estimatedHours;
  final double trackedHours;
  final double laborCost;
  final int taskCount;

  BudgetItemLaborSummary({
    required this.budgetItemId,
    this.estimatedHours = 0.0,
    this.trackedHours = 0.0,
    this.laborCost = 0.0,
    this.taskCount = 0,
  });

  double get hoursVariance => trackedHours - estimatedHours;

  double get hoursUtilization =>
      estimatedHours > 0 ? (trackedHours / estimatedHours) * 100 : 0.0;

  bool get isOverBudget => estimatedHours > 0 && trackedHours > estimatedHours;

  factory BudgetItemLaborSummary.fromJson(Map<String, dynamic> json) {
    return BudgetItemLaborSummary(
      budgetItemId: json['budget_item_id'] as String,
      estimatedHours: (json['estimated_hours'] as num?)?.toDouble() ?? 0.0,
      trackedHours: (json['tracked_hours'] as num?)?.toDouble() ?? 0.0,
      laborCost: (json['labor_cost'] as num?)?.toDouble() ?? 0.0,
      taskCount: (json['task_count'] as num?)?.toInt() ?? 0,
    );
  }

  BudgetItemLaborSummary operator +(BudgetItemLaborSummary other) {
    return BudgetItemLaborSummary(
      budgetItemId: budgetItemId,
      estimatedHours: estimatedHours + other.estimatedHours,
      trackedHours: trackedHours + other.trackedHours,
      laborCost: laborCost + other.laborCost,
      taskCount: taskCount + other.taskCount,
    );
  }
}
