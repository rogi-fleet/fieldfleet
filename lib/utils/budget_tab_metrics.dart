import '../models/budget_item.dart';
import '../models/document_status.dart';
import '../models/document_type.dart';
import '../models/generated_document.dart';
import '../models/template_category.dart';
import '../screens/projects/budget_view_screen.dart';
import '../services/supabase/budget_service.dart';

/// Top-level summary bar metrics (5 values).
class BudgetSummaryMetrics {
  final double approved;
  final double estimatedCost;
  final double actualCost;
  final double revisedContract;
  final double projectedProfit;
  final double projectedMargin;

  const BudgetSummaryMetrics({
    required this.approved,
    required this.estimatedCost,
    required this.actualCost,
    required this.revisedContract,
    required this.projectedProfit,
    required this.projectedMargin,
  });
}

/// A single KPI entry for the per-tab KPI row.
class TabKpi {
  final String label;
  final String value;

  /// Optional subtitle shown below the value.
  final String? subtitle;

  /// Semantic color hint: 'primary', 'success', 'warning', 'error', 'muted'.
  final String color;

  const TabKpi({
    required this.label,
    required this.value,
    this.subtitle,
    this.color = 'primary',
  });
}

/// A single line in the revenue or cost breakdown.
class BreakdownLine {
  final String label;
  final double amount;

  /// Semantic color: 'success', 'warning', 'error', 'muted', or null (default).
  final String? color;

  /// Whether this line is a separator/total row.
  final bool isTotal;

  /// Whether this is a footnote line (smaller text).
  final bool isFootnote;

  const BreakdownLine({
    required this.label,
    required this.amount,
    this.color,
    this.isTotal = false,
    this.isFootnote = false,
  });
}

/// All data needed to render the profit P&L view.
class ProfitBreakdown {
  final List<BreakdownLine> revenueLines;
  final List<BreakdownLine> costLines;

  /// Estimated margin (from projectedCost on base items only).
  final double estimatedMargin;

  /// Actual margin based on real costs.
  final double actualMargin;

  /// Projected margin based on projected costs (matches summary bar).
  final double projectedMargin;

  /// How much upgrades shifted the margin.
  final double upgradeMarginContribution;

  /// How much cost overruns shifted the margin (negative = bad).
  final double overrunMarginImpact;

  const ProfitBreakdown({
    required this.revenueLines,
    required this.costLines,
    required this.estimatedMargin,
    required this.actualMargin,
    required this.projectedMargin,
    required this.upgradeMarginContribution,
    required this.overrunMarginImpact,
  });
}

/// A single item row in the holdback schedule.
class HoldbackScheduleEntry {
  final String name;
  final double approved;
  final double holdbackPercent;
  final double holdbackAmount;
  final bool released;
  final double collectible;

  const HoldbackScheduleEntry({
    required this.name,
    required this.approved,
    required this.holdbackPercent,
    required this.holdbackAmount,
    required this.released,
    required this.collectible,
  });
}

/// All data needed to render the holdback breakdown view.
class HoldbackBreakdown {
  final double totalInvoiced;
  final double holdbackWithheld;
  final double netCash;
  final double holdbackRate;
  final double releasedAmount;
  final int releasedCount;
  final int totalHoldbackItems;
  final List<HoldbackScheduleEntry> schedule;

  const HoldbackBreakdown({
    required this.totalInvoiced,
    required this.holdbackWithheld,
    required this.netCash,
    required this.holdbackRate,
    required this.releasedAmount,
    required this.releasedCount,
    required this.totalHoldbackItems,
    required this.schedule,
  });

  double get holdbackProgress =>
      totalInvoiced > 0 ? holdbackWithheld / totalInvoiced : 0.0;
}

/// Pure-Dart utility that computes budget KPIs from existing data.
///
/// All inputs are already available in [_BudgetViewScreenState]; this class
/// only does arithmetic — no Flutter, no service calls.
class BudgetTabMetrics {
  BudgetTabMetrics._();

  // ── Top-level summary bar ────────────────────────────────────────────

  static BudgetSummaryMetrics summaryMetrics(
    BudgetSummary summary,
    List<BudgetItem> allItems,
  ) {
    // "Approved" = original base items only (the original estimate/contract).
    // "Revised contract" = base + approved COs + accepted upgrades
    //   (= totalApprovedPrice from the aggregate query).
    final leaves =
        allItems.where((i) => i.itemType == BudgetItemType.item).toList();
    final baseApproved = _sum(
      leaves.where((i) => i.sourceType == BudgetItemSource.base),
      (i) => i.approvedPrice,
    );
    final revised = summary.totalApprovedPrice;
    final profit = revised - summary.totalProjectedCost;
    final margin = revised > 0 ? (profit / revised) * 100 : 0.0;

    return BudgetSummaryMetrics(
      approved: baseApproved,
      estimatedCost: summary.totalProjectedCost,
      actualCost: summary.totalActualCost,
      revisedContract: revised,
      projectedProfit: profit,
      projectedMargin: margin,
    );
  }

  // ── Per-tab KPI rows ─────────────────────────────────────────────────

  static List<TabKpi> kpisForMode({
    required BudgetViewMode mode,
    required List<BudgetItem> allItems,
    required Map<String, double> actualCosts,
    required Map<String, double> invoicedAmounts,
    required String Function(double) formatCurrency,
    Map<String, String> changeOrderStatuses = const {},
  }) {
    // Only leaf items to avoid double-counting groups.
    final leaves =
        allItems.where((i) => i.itemType == BudgetItemType.item).toList();

    switch (mode) {
      case BudgetViewMode.workflow:
        return const []; // Workflow uses its own KPI strip
      case BudgetViewMode.estimating:
        return _estimating(leaves, changeOrderStatuses, formatCurrency);
      case BudgetViewMode.costing:
        return _costing(leaves, actualCosts, formatCurrency);
      case BudgetViewMode.invoicing:
        return _invoicing(leaves, invoicedAmounts, formatCurrency);
      case BudgetViewMode.changeOrders:
        return _changeOrders(leaves, changeOrderStatuses, formatCurrency);
      case BudgetViewMode.upgrades:
        return _upgrades(leaves, formatCurrency);
      case BudgetViewMode.holdback:
        return _holdback(leaves, invoicedAmounts, formatCurrency);
      case BudgetViewMode.profit:
        return _profit(leaves, actualCosts, formatCurrency);
      case BudgetViewMode.purchaseOrders:
      case BudgetViewMode.selections:
        return const [];
    }
  }

  // ── Private builders ─────────────────────────────────────────────────

  static List<TabKpi> _estimating(
    List<BudgetItem> leaves,
    Map<String, String> coStatuses,
    String Function(double) fmt,
  ) {
    // Composition of the revised contract the summary bar shows as one number:
    // base + approved COs + accepted upgrades. Using the same approved/accepted
    // basis keeps these three summing to "Revised contract" above.
    const approvedStatuses = {'Approved', 'Signed', 'Completed'};
    final base = _sum(
      leaves.where((i) => i.sourceType == BudgetItemSource.base),
      (i) => i.approvedPrice,
    );
    final coAdditions = _sum(
      leaves.where((i) =>
          i.sourceType == BudgetItemSource.changeOrder &&
          i.changeOrderId != null &&
          approvedStatuses.contains(coStatuses[i.changeOrderId])),
      (i) => i.approvedPrice,
    );
    final upgradeAdditions = _sum(
      leaves.where((i) =>
          i.sourceType == BudgetItemSource.upgrade &&
          i.upgradeStatus == UpgradeStatus.accepted),
      (i) => i.approvedPrice,
    );

    return [
      TabKpi(
        label: 'Base estimate',
        value: fmt(base),
        color: 'primary',
      ),
      TabKpi(
        label: 'Change orders',
        value: coAdditions > 0 ? '+${fmt(coAdditions)}' : fmt(coAdditions),
        subtitle: 'approved',
        color: coAdditions > 0 ? 'success' : 'muted',
      ),
      TabKpi(
        label: 'Upgrades',
        value: upgradeAdditions > 0
            ? '+${fmt(upgradeAdditions)}'
            : fmt(upgradeAdditions),
        subtitle: 'accepted',
        color: upgradeAdditions > 0 ? 'success' : 'muted',
      ),
    ];
  }

  static List<TabKpi> _costing(
    List<BudgetItem> leaves,
    Map<String, double> actualCosts,
    String Function(double) fmt,
  ) {
    final estimated = _sum(leaves, (i) => i.projectedCost);
    final actual = _sumMap(leaves, actualCosts);
    final remaining = estimated - actual;
    final consumed = estimated > 0 ? (actual / estimated) * 100 : 0.0;
    final overruns =
        leaves.where((i) => (actualCosts[i.id] ?? 0) > i.projectedCost).length;

    return [
      TabKpi(
        label: 'Budget consumed',
        value: '${consumed.toStringAsFixed(1)}%',
        subtitle: '${fmt(actual)} spent',
        color: consumed > 100
            ? 'error'
            : consumed > 80
                ? 'warning'
                : 'primary',
      ),
      TabKpi(
        label: 'Budget remaining',
        value: fmt(remaining),
        color: remaining >= 0 ? 'success' : 'error',
      ),
      TabKpi(
        label: 'Cost overruns',
        value: '$overruns item${overruns == 1 ? '' : 's'}',
        color: overruns > 0 ? 'error' : 'success',
      ),
    ];
  }

  static List<TabKpi> _invoicing(
    List<BudgetItem> leaves,
    Map<String, double> invoicedAmounts,
    String Function(double) fmt,
  ) {
    final contract = _sum(leaves, (i) => i.approvedPrice);
    final invoiced = _sumMap(leaves, invoicedAmounts);
    final remaining = contract - invoiced;
    final pctBilled = contract > 0 ? (invoiced / contract) * 100 : 0.0;

    return [
      TabKpi(
        label: 'Invoiced to date',
        value: fmt(invoiced),
        color: 'success',
      ),
      TabKpi(
        label: 'Remaining to bill',
        value: fmt(remaining),
        color: remaining > 0 ? 'warning' : 'muted',
      ),
      TabKpi(
        label: 'Billed',
        value: '${pctBilled.toStringAsFixed(1)}%',
        subtitle: 'of contract value',
        color: 'primary',
      ),
    ];
  }

  static List<TabKpi> _changeOrders(
    List<BudgetItem> leaves,
    Map<String, String> coStatuses,
    String Function(double) fmt,
  ) {
    final baseItems =
        leaves.where((i) => i.sourceType == BudgetItemSource.base);
    final coItems =
        leaves.where((i) => i.sourceType == BudgetItemSource.changeOrder);

    // Split COs into approved vs pending using the status map.
    // Status string is capitalized (e.g. "Approved", "Signed", "Draft", "Sent").
    const approvedStatuses = {'Approved', 'Signed', 'Completed'};
    final approvedCOs = coItems.where((i) =>
        i.changeOrderId != null &&
        approvedStatuses.contains(coStatuses[i.changeOrderId]));
    final pendingCOs = coItems.where((i) =>
        i.changeOrderId == null ||
        !approvedStatuses.contains(coStatuses[i.changeOrderId]));

    final original = _sum(baseItems, (i) => i.approvedPrice);
    final approvedAmount = _sum(approvedCOs, (i) => i.approvedPrice);
    final pendingAmount = _sum(pendingCOs, (i) => i.approvedPrice);
    final coImpact = original > 0 ? (approvedAmount / original) * 100 : 0.0;

    return [
      TabKpi(
        label: 'Original contract',
        value: fmt(original),
        color: 'muted',
      ),
      TabKpi(
        label: 'CO additions (approved)',
        value: '+${fmt(approvedAmount)}',
        subtitle: '${approvedCOs.length} approved',
        color: 'success',
      ),
      TabKpi(
        label: 'COs pending approval',
        value: '+${fmt(pendingAmount)}',
        subtitle: '${pendingCOs.length} pending',
        color: pendingAmount > 0 ? 'warning' : 'muted',
      ),
      TabKpi(
        label: 'CO impact',
        value: '+${coImpact.toStringAsFixed(1)}%',
        subtitle: 'of original contract',
        color: 'primary',
      ),
    ];
  }

  static List<TabKpi> _upgrades(
    List<BudgetItem> leaves,
    String Function(double) fmt,
  ) {
    final upgrades =
        leaves.where((i) => i.sourceType == BudgetItemSource.upgrade).toList();
    final offered = upgrades.length;
    final accepted =
        upgrades.where((i) => i.upgradeStatus == UpgradeStatus.accepted).length;
    final rate = offered > 0 ? (accepted / offered) * 100 : 0.0;

    final acceptedItems =
        upgrades.where((i) => i.upgradeStatus == UpgradeStatus.accepted);
    final avgMargin =
        acceptedItems.isEmpty
            ? 0.0
            : acceptedItems.map((i) => i.projectedMargin).reduce((a, b) =>
                a + b) /
                acceptedItems.length;

    return [
      TabKpi(label: 'Upgrades offered', value: '$offered', color: 'muted'),
      TabKpi(
        label: 'Upgrades accepted',
        value: '$accepted',
        subtitle:
            accepted > 0
                ? fmt(
                  _sum(acceptedItems, (i) => i.approvedPrice),
                )
                : null,
        color: 'success',
      ),
      TabKpi(
        label: 'Acceptance rate',
        value: '${rate.toStringAsFixed(1)}%',
        color: 'primary',
      ),
      TabKpi(
        label: 'Avg upgrade margin',
        value: '${avgMargin.toStringAsFixed(1)}%',
        color: 'success',
      ),
    ];
  }

  static List<TabKpi> _holdback(
    List<BudgetItem> leaves,
    Map<String, double> invoicedAmounts,
    String Function(double) fmt,
  ) {
    final holdbackItems = leaves.where((i) => i.hasHoldback).toList();
    final invoiced = _sumMap(leaves, invoicedAmounts);
    final withheld = _sum(holdbackItems, (i) => i.holdbackAmount);
    final netCash = invoiced - withheld;

    return [
      TabKpi(
        label: 'Total invoiced',
        value: fmt(invoiced),
        color: 'primary',
      ),
      TabKpi(
        label: 'Holdback withheld',
        value: fmt(withheld),
        color: 'warning',
      ),
      TabKpi(
        label: 'Net cash received',
        value: fmt(netCash),
        color: 'success',
      ),
    ];
  }

  static List<TabKpi> _profit(
    List<BudgetItem> leaves,
    Map<String, double> actualCosts,
    String Function(double) fmt,
  ) {
    final revenue = _sum(leaves, (i) => i.approvedPrice);
    final projected = _sum(leaves, (i) => i.projectedCost);
    final actual = _sumMap(leaves, actualCosts);
    final variance = actual - projected;

    final targetMargin =
        revenue > 0 ? ((revenue - projected) / revenue) * 100 : 0.0;
    final currentMargin =
        revenue > 0 ? ((revenue - actual) / revenue) * 100 : 0.0;

    return [
      TabKpi(
        label: 'Target margin',
        value: '${targetMargin.toStringAsFixed(1)}%',
        subtitle: 'based on estimates',
        color: 'muted',
      ),
      TabKpi(
        label: 'Current margin',
        value: '${currentMargin.toStringAsFixed(1)}%',
        subtitle: 'based on actuals',
        color: currentMargin >= targetMargin
            ? 'success'
            : currentMargin >= 0
                ? 'warning'
                : 'error',
      ),
      TabKpi(
        label: 'Cost variance',
        value: fmt(variance.abs()),
        subtitle: variance > 0
            ? 'over budget'
            : variance < 0
                ? 'under budget'
                : 'on budget',
        color: variance > 0
            ? 'error'
            : variance < 0
                ? 'success'
                : 'muted',
      ),
    ];
  }

  // ── Profit breakdown ──────────────────────────────────────────────────

  static ProfitBreakdown profitBreakdown({
    required List<BudgetItem> allItems,
    required Map<String, double> actualCosts,
    required Map<String, double> invoicedAmounts,
    required String Function(double) formatCurrency,
    Map<String, String> changeOrderStatuses = const {},
  }) {
    final leaves =
        allItems.where((i) => i.itemType == BudgetItemType.item).toList();

    // ── Revenue breakdown ──────────────────────────────────────────────
    const approvedCoStatuses = {'Approved', 'Signed', 'Completed'};
    final baseLeaves =
        leaves.where((i) => i.sourceType == BudgetItemSource.base);
    final coLeaves =
        leaves.where((i) => i.sourceType == BudgetItemSource.changeOrder);
    final approvedCoLeaves = coLeaves.where((i) =>
        i.changeOrderId != null &&
        approvedCoStatuses.contains(changeOrderStatuses[i.changeOrderId]));
    final pendingCoLeaves = coLeaves.where((i) =>
        i.changeOrderId == null ||
        !approvedCoStatuses.contains(changeOrderStatuses[i.changeOrderId]));
    final upgradeLeaves =
        leaves.where((i) => i.sourceType == BudgetItemSource.upgrade);
    final acceptedUpgrades =
        upgradeLeaves.where((i) => i.upgradeStatus == UpgradeStatus.accepted);

    final baseRevenue = _sum(baseLeaves, (i) => i.approvedPrice);
    final coRevenue = _sum(approvedCoLeaves, (i) => i.approvedPrice);
    final upgradeRevenue = _sum(acceptedUpgrades, (i) => i.approvedPrice);
    final confirmedRevenue = baseRevenue + coRevenue + upgradeRevenue;

    final holdbackTotal = _sum(
      leaves.where((i) => i.hasHoldback),
      (i) => i.holdbackAmount,
    );
    final availableCash = confirmedRevenue - holdbackTotal;

    final revenueLines = <BreakdownLine>[
      BreakdownLine(
        label: 'Original estimate (approved)',
        amount: baseRevenue,
      ),
    ];

    // Add approved CO items
    for (final co in approvedCoLeaves) {
      revenueLines.add(BreakdownLine(
        label: 'CO: ${co.name}',
        amount: co.approvedPrice,
        color: 'success',
      ));
    }

    // Add pending CO items (shown separately, not in confirmed total)
    for (final co in pendingCoLeaves) {
      revenueLines.add(BreakdownLine(
        label: 'CO (pending): ${co.name}',
        amount: co.approvedPrice,
        color: 'warning',
      ));
    }

    // Add accepted upgrades
    for (final upg in acceptedUpgrades) {
      revenueLines.add(BreakdownLine(
        label: 'Upgrade: ${upg.name}',
        amount: upg.approvedPrice,
        color: 'success',
      ));
    }

    revenueLines.addAll([
      BreakdownLine(
        label: 'Confirmed revenue',
        amount: confirmedRevenue,
        isTotal: true,
      ),
      if (holdbackTotal > 0)
        BreakdownLine(
          label: 'Holdback withheld',
          amount: -holdbackTotal,
          color: 'warning',
        ),
      BreakdownLine(
        label: 'Available cash',
        amount: availableCash,
        color: 'success',
        isTotal: true,
      ),
    ]);

    // ── Cost breakdown by type ─────────────────────────────────────────
    double costForType(BudgetCostType? type) {
      final items = leaves.where((i) => i.costType == type);
      return _sumMap(items, actualCosts);
    }

    // Items with no cost type assigned get lumped into "Other"
    final laborCost = costForType(BudgetCostType.labor);
    final materialCost = costForType(BudgetCostType.material);
    final subCost = costForType(BudgetCostType.subcontractor);
    final otherCost = costForType(BudgetCostType.other) + costForType(null);
    final totalActual = laborCost + materialCost + subCost + otherCost;

    // Overrun amount
    final totalProjected = _sum(leaves, (i) => i.projectedCost);
    final overrunAmount =
        totalActual > totalProjected ? totalActual - totalProjected : 0.0;

    final costLines = <BreakdownLine>[
      BreakdownLine(label: 'Labour (actuals)', amount: laborCost),
      BreakdownLine(label: 'Materials (actuals)', amount: materialCost),
      BreakdownLine(label: 'Subcontractors', amount: subCost),
      BreakdownLine(label: 'Other', amount: otherCost),
      BreakdownLine(
        label: 'Total actual cost',
        amount: totalActual,
        color: 'warning',
        isTotal: true,
      ),
      if (overrunAmount > 0)
        BreakdownLine(
          label: 'Cost overrun included',
          amount: overrunAmount,
          color: 'error',
          isFootnote: true,
        ),
    ];

    // ── Margin analysis ────────────────────────────────────────────────
    // Estimated margin = profit / revenue on base items only (the "target")
    final baseCost = _sum(baseLeaves, (i) => i.projectedCost);
    final estimatedMargin =
        baseRevenue > 0 ? ((baseRevenue - baseCost) / baseRevenue) * 100 : 0.0;

    // Actual margin = (confirmed revenue - actual costs) / confirmed revenue
    final actualMargin =
        confirmedRevenue > 0
            ? ((confirmedRevenue - totalActual) / confirmedRevenue) * 100
            : 0.0;

    // Upgrade contribution: margin delta from adding upgrade revenue
    final revenueWithoutUpgrades = baseRevenue + coRevenue;
    final marginWithoutUpgrades =
        revenueWithoutUpgrades > 0
            ? ((revenueWithoutUpgrades - totalActual) / revenueWithoutUpgrades) *
                100
            : 0.0;
    final upgradeContribution = actualMargin - marginWithoutUpgrades;

    // Overrun impact: how much margin dropped due to actual > projected costs
    final marginIfOnBudget =
        confirmedRevenue > 0
            ? ((confirmedRevenue - totalProjected) / confirmedRevenue) * 100
            : 0.0;
    final overrunImpact = actualMargin - marginIfOnBudget;

    return ProfitBreakdown(
      revenueLines: revenueLines,
      costLines: costLines,
      estimatedMargin: estimatedMargin,
      actualMargin: actualMargin,
      projectedMargin: marginIfOnBudget,
      upgradeMarginContribution: upgradeContribution,
      overrunMarginImpact: overrunImpact,
    );
  }

  // ── Holdback breakdown ────────────────────────────────────────────────

  static HoldbackBreakdown holdbackBreakdown({
    required List<BudgetItem> allItems,
    required Map<String, double> invoicedAmounts,
    List<GeneratedDocument> invoices = const [],
  }) {
    final leaves =
        allItems.where((i) => i.itemType == BudgetItemType.item).toList();
    final holdbackItems = leaves.where((i) => i.hasHoldback).toList();
    final budgetTotalInvoiced = _sumMap(leaves, invoicedAmounts);
    final budgetHoldback = _sum(holdbackItems, (i) => i.holdbackAmount);
    final totalApproved = _sum(holdbackItems, (i) => i.approvedPrice);

    // Invoice-level retainage: only count customer invoices that are actually
    // issued (exclude drafts and non-invoice document types). This prevents
    // drafts, vendor bills, or work orders that happen to carry a retainage
    // value from inflating the holdback totals.
    final eligibleInvoices = invoices.where((d) {
      if (d.retainageAmount <= 0) return false;
      if (d.documentType.category != TemplateCategory.customerInvoice) {
        return false;
      }
      return d.status != DocumentStatus.draft;
    }).toList();

    final invoiceTotalInvoiced =
        eligibleInvoices.fold<double>(0, (s, d) => s + d.totalAmount);
    final invoiceHoldback =
        eligibleInvoices.fold<double>(0, (s, d) => s + d.retainageAmount);

    // Single source of truth: per-invoice retainage is the project's billing
    // model now. If any eligible invoices carry retainage, drive every total
    // from the invoice side so we never double-count against the legacy
    // budget-item holdback. Budget-item holdback is used only when no
    // invoice-level retainage exists on the project.
    final useInvoicePath = eligibleInvoices.isNotEmpty;

    final totalInvoiced =
        useInvoicePath ? invoiceTotalInvoiced : budgetTotalInvoiced;
    final holdbackWithheld =
        useInvoicePath ? invoiceHoldback : budgetHoldback;
    final netCash = totalInvoiced - holdbackWithheld;

    // Holdback rate display: when every invoice was billed at the same rate
    // (common: workspace-wide retainage policy), surface that rate verbatim.
    // Falling back to invoiceHoldback / invoiceTotalInvoiced ratios against
    // tax-inclusive totals understates the rate the customer agreed to
    // (e.g. a 10% retainage on a 15%-taxable subtotal shows as ~8.7%
    // against the total, leaving the user wondering why "10%" became "9%").
    final double holdbackRate;
    if (useInvoicePath) {
      final percents = eligibleInvoices
          .map((d) => d.retainagePercent)
          .where((p) => p > 0)
          .toSet();
      if (percents.length == 1) {
        holdbackRate = percents.first;
      } else if (percents.isEmpty) {
        holdbackRate = 0.0;
      } else {
        // Mixed rates across invoices — compute a weighted-average against the
        // subtotal each invoice was billed at, not the post-tax total.
        final weighted = eligibleInvoices.fold<double>(0, (s, d) {
          final subtotal = d.totalAmount - _docTaxAmount(d);
          return s + (subtotal * d.retainagePercent);
        });
        final subtotalSum = eligibleInvoices.fold<double>(
            0, (s, d) => s + (d.totalAmount - _docTaxAmount(d)));
        holdbackRate = subtotalSum > 0 ? weighted / subtotalSum : 0.0;
      }
    } else {
      holdbackRate =
          totalApproved > 0 ? (budgetHoldback / totalApproved) * 100 : 0.0;
    }

    // Released tracking — budget items only. Invoice-level retainage release
    // is tracked via HoldbackService.releaseHoldback() and surfaced separately
    // through HoldbackService.getProjectSummary(); we don't duplicate it here.
    final releasedItems = holdbackItems.where((i) => i.holdbackReleased);
    final releasedAmount = _sum(releasedItems, (i) => i.holdbackAmount);

    // Build schedule entries from the active source of truth.
    final schedule = <HoldbackScheduleEntry>[
      if (useInvoicePath)
        ...eligibleInvoices.map(
          (d) => HoldbackScheduleEntry(
            name: d.documentNumber ?? d.templateName,
            approved: d.totalAmount,
            holdbackPercent: d.retainagePercent,
            holdbackAmount: d.retainageAmount,
            released: false,
            collectible: (d.totalAmount - d.retainageAmount)
                .clamp(0.0, double.infinity),
          ),
        )
      else
        ...holdbackItems.map(
          (item) => HoldbackScheduleEntry(
            name: item.name,
            approved: item.approvedPrice,
            holdbackPercent: item.holdbackPercent ?? 0,
            holdbackAmount: item.holdbackAmount,
            released: item.holdbackReleased,
            collectible: item.collectibleAmount,
          ),
        ),
    ];

    return HoldbackBreakdown(
      totalInvoiced: totalInvoiced,
      holdbackWithheld: holdbackWithheld,
      netCash: netCash,
      holdbackRate: holdbackRate,
      releasedAmount: useInvoicePath ? 0 : releasedAmount,
      releasedCount: useInvoicePath ? 0 : releasedItems.length,
      totalHoldbackItems: useInvoicePath
          ? eligibleInvoices.length
          : holdbackItems.length,
      schedule: schedule,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static double _sum(
    Iterable<BudgetItem> items,
    double Function(BudgetItem) selector,
  ) => items.fold(0.0, (s, i) => s + selector(i));

  static double _sumMap(
    Iterable<BudgetItem> items,
    Map<String, double> values,
  ) => items.fold(0.0, (s, i) => s + (values[i.id] ?? 0.0));

  /// Best-effort recovery of the tax portion of a document's totalAmount.
  /// Mirrors the rule the create-document form uses: subtotal = totalAmount
  /// when there's no taxRate, otherwise totalAmount × (rate / (100 + rate)).
  /// taxRate is stored as a percentage (e.g. 15 → 15%), per the catalog
  /// model's documented convention.
  static double _docTaxAmount(GeneratedDocument doc) {
    if (!doc.collectTax || doc.taxRate <= 0) return 0;
    final rate = doc.taxRate / 100.0;
    return doc.totalAmount * (rate / (1 + rate));
  }
}
