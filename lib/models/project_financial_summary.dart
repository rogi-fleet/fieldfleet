/// Financial summary for a project showing all key financial metrics.
///
/// This model aggregates data from budget items, invoices, and cost items
/// to provide a comprehensive view of project financial health.
class ProjectFinancialSummary {
  /// Total approved/contracted amount (from budget or contract)
  final double approvedPrice;

  /// Sum of all paid invoices
  final double collectedSoFar;

  /// Outstanding amount owed by client (approvedPrice - collectedSoFar)
  final double remainingBalance;

  /// Estimated or actual costs to complete the project
  final double costToComplete;

  /// Expected profit (approvedPrice - costToComplete)
  final double projectedProfit;

  /// Profit margin as percentage (projectedProfit / approvedPrice * 100)
  final double projectedMargin;

  /// Number of budget items included in calculation
  final int budgetItemCount;

  /// Number of paid invoices included in calculation
  final int paidInvoiceCount;

  /// Number of cost items included in calculation
  final int costItemCount;

  /// Total purchase costs for assets assigned to project
  final double assetPurchaseCosts;

  /// Total maintenance costs for assets assigned to project
  final double assetMaintenanceCosts;

  /// Total asset costs (purchase + maintenance)
  double get totalAssetCosts => assetPurchaseCosts + assetMaintenanceCosts;

  /// Total amount from pending bid requests
  final double pendingBidsAmount;

  /// Committed costs from confirmed purchase orders
  final double committedCostsFromPOs;

  /// Total unpaid bills from vendors
  final double unpaidBillsAmount;

  /// Total refunds issued to clients
  final double totalRefundsIssued;


  /// When this summary was calculated
  final DateTime calculatedAt;

  const ProjectFinancialSummary({
    required this.approvedPrice,
    required this.collectedSoFar,
    required this.remainingBalance,
    required this.costToComplete,
    required this.projectedProfit,
    required this.projectedMargin,
    required this.budgetItemCount,
    required this.paidInvoiceCount,
    required this.costItemCount,
    this.assetPurchaseCosts = 0.0,
    this.assetMaintenanceCosts = 0.0,
    this.pendingBidsAmount = 0.0,
    this.committedCostsFromPOs = 0.0,
    this.unpaidBillsAmount = 0.0,
    this.totalRefundsIssued = 0.0,
    required this.calculatedAt,
  });

  /// Create a financial summary from calculated values
  factory ProjectFinancialSummary.fromCalculation({
    required double approvedPrice,
    required double collectedSoFar,
    required double costToComplete,
    required int budgetItemCount,
    required int paidInvoiceCount,
    required int costItemCount,
    double assetPurchaseCosts = 0.0,
    double assetMaintenanceCosts = 0.0,
    double pendingBidsAmount = 0.0,
    double committedCostsFromPOs = 0.0,
    double unpaidBillsAmount = 0.0,
    double totalRefundsIssued = 0.0,
  }) {
    final remainingBalance = approvedPrice - collectedSoFar;
    final projectedProfit = approvedPrice - costToComplete;
    final projectedMargin =
        approvedPrice > 0 ? (projectedProfit / approvedPrice) * 100 : 0.0;

    return ProjectFinancialSummary(
      approvedPrice: approvedPrice,
      collectedSoFar: collectedSoFar,
      remainingBalance: remainingBalance,
      costToComplete: costToComplete,
      projectedProfit: projectedProfit,
      projectedMargin: projectedMargin,
      budgetItemCount: budgetItemCount,
      paidInvoiceCount: paidInvoiceCount,
      costItemCount: costItemCount,
      assetPurchaseCosts: assetPurchaseCosts,
      assetMaintenanceCosts: assetMaintenanceCosts,
      pendingBidsAmount: pendingBidsAmount,
      committedCostsFromPOs: committedCostsFromPOs,
      unpaidBillsAmount: unpaidBillsAmount,
      totalRefundsIssued: totalRefundsIssued,
      calculatedAt: DateTime.now(),
    );
  }

  /// Format approved price as currency
  String get formattedApprovedPrice => _formatCurrency(approvedPrice);

  /// Format collected so far as currency
  String get formattedCollectedSoFar => _formatCurrency(collectedSoFar);

  /// Format remaining balance as currency
  String get formattedRemainingBalance => _formatCurrency(remainingBalance);

  /// Format cost to complete as currency
  String get formattedCostToComplete => _formatCurrency(costToComplete);

  /// Format projected profit as currency
  String get formattedProjectedProfit => _formatCurrency(projectedProfit);

  /// Format projected margin as percentage
  String get formattedProjectedMargin => '${projectedMargin.toStringAsFixed(1)}%';

  /// Format asset purchase costs as currency
  String get formattedAssetPurchaseCosts => _formatCurrency(assetPurchaseCosts);

  /// Format asset maintenance costs as currency
  String get formattedAssetMaintenanceCosts => _formatCurrency(assetMaintenanceCosts);

  /// Format total asset costs as currency
  String get formattedTotalAssetCosts => _formatCurrency(totalAssetCosts);

  /// Format pending bids amount as currency
  String get formattedPendingBidsAmount => _formatCurrency(pendingBidsAmount);

  /// Format committed costs from POs as currency
  String get formattedCommittedCostsFromPOs => _formatCurrency(committedCostsFromPOs);

  /// Format unpaid bills amount as currency
  String get formattedUnpaidBillsAmount => _formatCurrency(unpaidBillsAmount);

  /// Format total refunds issued as currency
  String get formattedTotalRefundsIssued => _formatCurrency(totalRefundsIssued);


  /// Check if the project is profitable (positive profit)
  bool get isProfitable => projectedProfit > 0;

  /// Check if margin is healthy (>= 20%)
  bool get hasHealthyMargin => projectedMargin >= 20.0;

  /// Check if margin is low (10-19%)
  bool get hasLowMargin => projectedMargin >= 10.0 && projectedMargin < 20.0;

  /// Check if margin is critical (5-9%)
  bool get hasCriticalMargin => projectedMargin >= 5.0 && projectedMargin < 10.0;

  /// Check if margin is in danger (<5% or negative)
  bool get hasDangerMargin => projectedMargin < 5.0;

  /// Validate that all values are reasonable
  bool validate() {
    // All monetary values should be >= 0 (negative profit is allowed)
    if (approvedPrice < 0 || collectedSoFar < 0 || costToComplete < 0) {
      return false;
    }

    // Counts should be >= 0
    if (budgetItemCount < 0 || paidInvoiceCount < 0 || costItemCount < 0) {
      return false;
    }

    // Calculated values should match
    if ((approvedPrice - collectedSoFar - remainingBalance).abs() > 0.01) {
      return false;
    }

    if ((approvedPrice - costToComplete - projectedProfit).abs() > 0.01) {
      return false;
    }

    return true;
  }

  /// Format a dollar amount with thousand separators
  String _formatCurrency(double amount) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    final parts = absAmount.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    // Add thousand separators
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
    }

    return '${isNegative ? '-' : ''}\$${buffer.toString()}.$decPart';
  }

  @override
  String toString() {
    return 'ProjectFinancialSummary('
        'approvedPrice: $formattedApprovedPrice, '
        'collectedSoFar: $formattedCollectedSoFar, '
        'remainingBalance: $formattedRemainingBalance, '
        'costToComplete: $formattedCostToComplete, '
        'projectedProfit: $formattedProjectedProfit, '
        'projectedMargin: $formattedProjectedMargin, '
        'calculatedAt: $calculatedAt)';
  }
}
