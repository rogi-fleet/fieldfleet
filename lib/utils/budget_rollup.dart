import '../models/budget_item.dart';

/// Output of [BudgetRollup.computeApprovedTotals] — the two figures that
/// drive both the project budget summary and the Financials view's
/// project-level rollups.
class BudgetRollupTotals {
  /// Sum of `approvedPrice` for every leaf budget item that currently
  /// counts toward the customer-facing contract value.
  final double totalApprovedPrice;

  /// Sum of `projectedCost` for the same set of items, used to derive
  /// gross profit and margin.
  final double totalProjectedCost;

  const BudgetRollupTotals({
    required this.totalApprovedPrice,
    required this.totalProjectedCost,
  });

  /// True when neither total has anything to count. Cheap to check from
  /// the UI before deciding whether to render zero-state vs. KPIs.
  bool get isEmpty => totalApprovedPrice == 0 && totalProjectedCost == 0;
}

/// Pure budget-rollup math, extracted from
/// `SupabaseBudgetService.calculateBudgetSummary` so the rules can be
/// exercised in unit tests without a database.
///
/// The same predicate also runs at the project budget view's leaf-row
/// filter and at the Financials view's per-project rollup, so any
/// drift here would cause the two surfaces to disagree about
/// the same contract value.
class BudgetRollup {
  BudgetRollup._();

  /// Statuses on a change-order document that make its scope count
  /// toward the contract value. Anything else (draft, sent, denied,
  /// withdrawn, …) leaves the linked budget items in place but
  /// excludes them from the rollup — so declining a CO doesn't even
  /// require deleting its budget rows for the total to revert, though
  /// the `SupabaseDocumentService` reconciler does delete them
  /// belt-and-suspenders.
  static const approvedCoStatuses = <String>{
    'Approved',
    'Signed',
    'Completed',
  };

  /// Compute approved + projected totals over a flat list of budget
  /// items, given the current status of every change-order document
  /// referenced by any item via `changeOrderId`.
  ///
  /// Rules:
  ///   • Only **leaf** items (no children, `itemType == item`) count.
  ///     Group containers are summed implicitly via their children.
  ///   • Base items always count.
  ///   • Change-order items only count when the linked CO document
  ///     is in `approvedCoStatuses`.
  ///   • Upgrade items only count when `upgradeStatus == accepted`.
  static BudgetRollupTotals computeApprovedTotals({
    required List<BudgetItem> allItems,
    required Map<String, String> coStatusesByDocumentId,
  }) {
    final parentIds = allItems
        .map((item) => item.parentId)
        .whereType<String>()
        .toSet();
    final leafItems = allItems.where(
      (item) =>
          item.itemType == BudgetItemType.item && !parentIds.contains(item.id),
    );

    double totalApprovedPrice = 0;
    double totalProjectedCost = 0;
    for (final item in leafItems) {
      switch (item.sourceType) {
        case BudgetItemSource.base:
          totalApprovedPrice += item.approvedPrice;
          totalProjectedCost += item.projectedCost;
        case BudgetItemSource.changeOrder:
          final coStatus = item.changeOrderId == null
              ? null
              : coStatusesByDocumentId[item.changeOrderId!];
          if (coStatus != null && approvedCoStatuses.contains(coStatus)) {
            totalApprovedPrice += item.approvedPrice;
            totalProjectedCost += item.projectedCost;
          }
        case BudgetItemSource.upgrade:
          if (item.upgradeStatus == UpgradeStatus.accepted) {
            totalApprovedPrice += item.approvedPrice;
            totalProjectedCost += item.projectedCost;
          }
      }
    }
    return BudgetRollupTotals(
      totalApprovedPrice: totalApprovedPrice,
      totalProjectedCost: totalProjectedCost,
    );
  }
}
