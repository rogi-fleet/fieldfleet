/// AIA G703 continuation-sheet line item.
class PayAppLine {
  final String id;
  final String payApplicationId;
  final String workspaceId;

  /// Source budget item this line was pulled from (null for ad-hoc lines).
  /// Used as the join key when rolling values over from the prior pay app.
  final String? budgetItemId;

  final String? itemNo;
  final String description;
  final double scheduledValue;

  /// Work completed in all prior pay apps (rolled over from previous app).
  final double workCompletedPrevious;

  /// Work completed in THIS period.
  final double workCompletedThisPeriod;

  /// Materials presently stored (not yet incorporated).
  final double materialsStored;

  /// Optional per-line retainage override. When null, retainage is computed
  /// from the header's [retainagePctCompleted] / [retainagePctStored].
  final double? retainageOverride;

  final int sortOrder;

  const PayAppLine({
    required this.id,
    required this.payApplicationId,
    required this.workspaceId,
    this.budgetItemId,
    this.itemNo,
    this.description = '',
    this.scheduledValue = 0,
    this.workCompletedPrevious = 0,
    this.workCompletedThisPeriod = 0,
    this.materialsStored = 0,
    this.retainageOverride,
    this.sortOrder = 0,
  });

  // ── Derived columns ─────────────────────────────────────────────────
  double get totalCompletedAndStored =>
      workCompletedPrevious + workCompletedThisPeriod + materialsStored;

  double get percentComplete {
    if (scheduledValue <= 0) return 0;
    return (totalCompletedAndStored / scheduledValue) * 100.0;
  }

  double get balanceToFinish => scheduledValue - totalCompletedAndStored;

  PayAppLine copyWith({
    String? itemNo,
    String? description,
    double? scheduledValue,
    double? workCompletedPrevious,
    double? workCompletedThisPeriod,
    double? materialsStored,
    Object? retainageOverride = _unset,
    int? sortOrder,
    String? budgetItemId,
  }) {
    return PayAppLine(
      id: id,
      payApplicationId: payApplicationId,
      workspaceId: workspaceId,
      budgetItemId: budgetItemId ?? this.budgetItemId,
      itemNo: itemNo ?? this.itemNo,
      description: description ?? this.description,
      scheduledValue: scheduledValue ?? this.scheduledValue,
      workCompletedPrevious:
          workCompletedPrevious ?? this.workCompletedPrevious,
      workCompletedThisPeriod:
          workCompletedThisPeriod ?? this.workCompletedThisPeriod,
      materialsStored: materialsStored ?? this.materialsStored,
      retainageOverride: identical(retainageOverride, _unset)
          ? this.retainageOverride
          : retainageOverride as double?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toDb() => {
        'pay_application_id': payApplicationId,
        'workspace_id': workspaceId,
        'budget_item_id': budgetItemId,
        'item_no': itemNo,
        'description': description,
        'scheduled_value': scheduledValue,
        'work_completed_previous': workCompletedPrevious,
        'work_completed_this_period': workCompletedThisPeriod,
        'materials_stored': materialsStored,
        'retainage_amount': retainageOverride,
        'sort_order': sortOrder,
      };

  static PayAppLine fromDb(Map<String, dynamic> row) {
    double toDouble(dynamic v) =>
        v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
    return PayAppLine(
      id: row['id'] as String,
      payApplicationId: row['pay_application_id'] as String,
      workspaceId: row['workspace_id'] as String,
      budgetItemId: row['budget_item_id'] as String?,
      itemNo: row['item_no'] as String?,
      description: (row['description'] as String?) ?? '',
      scheduledValue: toDouble(row['scheduled_value']),
      workCompletedPrevious: toDouble(row['work_completed_previous']),
      workCompletedThisPeriod: toDouble(row['work_completed_this_period']),
      materialsStored: toDouble(row['materials_stored']),
      retainageOverride: row['retainage_amount'] == null
          ? null
          : toDouble(row['retainage_amount']),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static const Object _unset = Object();
}
