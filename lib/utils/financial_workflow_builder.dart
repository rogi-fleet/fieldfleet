import 'package:flutter/material.dart';
import '../models/budget_item.dart';
import '../models/document_status.dart';
import '../models/document_type.dart';
import '../models/financial_workflow_state.dart';
import '../models/generated_document.dart';
import '../models/pay_application.dart';
import '../screens/projects/budget_view_screen.dart';
import 'budget_tab_metrics.dart';

/// Computes [FinancialWorkflowState] from pre-fetched documents and budget
/// items. All logic is pure Dart — no service calls.
class FinancialWorkflowBuilder {
  FinancialWorkflowBuilder._();

  static FinancialWorkflowState build({
    required List<GeneratedDocument> documents,
    required List<BudgetItem> budgetItems,
    required HoldbackBreakdown holdbackBreakdown,
    required String Function(double) formatCurrency,
    Map<String, double> actualCosts = const {},
    List<PayApplication> payApplications = const [],
  }) {
    // ── KPI computation ──────────────────────────────────────────────
    final leaves = budgetItems
        .where((i) => i.itemType == BudgetItemType.item)
        .toList();

    // Build a map of change order document ID → status so we can filter
    // change-order budget items the same way the Overview tab does.
    final coStatusMap = <String, DocumentStatus>{
      for (final d in documents
          .where((d) => d.documentType == DocumentType.changeOrder))
        d.id: d.status,
    };

    final approvedEstimate = leaves.fold<double>(0, (s, i) {
      switch (i.sourceType) {
        case BudgetItemSource.changeOrder:
          {
            final status = coStatusMap[i.changeOrderId];
            if (status != DocumentStatus.approved &&
                status != DocumentStatus.signed) {
              return s;
            }
          }
        case BudgetItemSource.upgrade:
          if (i.upgradeStatus != UpgradeStatus.accepted) { return s; }
        case BudgetItemSource.base:
          break;
      }
      return s + i.approvedPrice;
    });

    final invoiceDocs = documents.where((d) =>
        (d.documentType == DocumentType.invoice ||
            d.documentType == DocumentType.progressInvoice) &&
        (d.status == DocumentStatus.sent ||
            d.status == DocumentStatus.viewed ||
            d.status == DocumentStatus.signed ||
            d.status == DocumentStatus.approved));
    final invoicedToDate =
        invoiceDocs.fold<double>(0, (s, d) => s + d.totalAmount);

    final paidDocs = documents.where((d) =>
        (d.documentType == DocumentType.invoice ||
            d.documentType == DocumentType.progressInvoice) &&
        d.paidDate != null);
    final collected =
        paidDocs.fold<double>(0, (s, d) => s + d.totalAmount);

    final outstanding = invoicedToDate - collected;

    // ── Bands ────────────────────────────────────────────────────────
    final bands = <WorkflowBand>[
      _buildEstimatingBand(documents, budgetItems, formatCurrency),
      _buildCostingBand(budgetItems, actualCosts, formatCurrency),
      _buildInvoicingBand(documents, invoicedToDate, collected, outstanding,
          approvedEstimate, formatCurrency, payApplications),
      _buildChangeOrdersBand(documents, formatCurrency),
      _buildUpgradesBand(budgetItems, formatCurrency),
      _buildHoldbackBand(documents, holdbackBreakdown, formatCurrency),
    ];

    return FinancialWorkflowState(
      approvedEstimate: approvedEstimate,
      invoicedToDate: invoicedToDate,
      collected: collected,
      outstanding: outstanding,
      bands: bands,
    );
  }
  // ── Estimating ─────────────────────────────────────────────────────

  static WorkflowBand _buildEstimatingBand(
    List<GeneratedDocument> docs,
    List<BudgetItem> budgetItems,
    String Function(double) fmt,
  ) {
    final leaves = budgetItems
        .where((i) => i.itemType == BudgetItemType.item)
        .toList();
    final leafCount = leaves.length;
    final pricedCount = leaves.where((i) => i.approvedPrice > 0).length;

    final createBudgetStatus = leafCount > 0
        ? WorkflowNodeStatus.complete
        : WorkflowNodeStatus.notStarted;
    final pricingStatus = leafCount == 0
        ? WorkflowNodeStatus.notStarted
        : pricedCount >= leafCount
            ? WorkflowNodeStatus.complete
            : pricedCount > 0
                ? WorkflowNodeStatus.active
                : WorkflowNodeStatus.notStarted;

    final estimates =
        docs.where((d) => d.documentType == DocumentType.quotation).toList();
    final workAuths = docs
        .where((d) =>
            d.documentType == DocumentType.workAuthEmergency ||
            d.documentType == DocumentType.workAuthRestoration ||
            d.documentType == DocumentType.workAuthServices)
        .toList();

    final estimateStatus = _bestDocStatus(estimates);
    final estimateNodeStatus =
        estimateStatus == WorkflowNodeStatus.notStarted &&
            pricingStatus == WorkflowNodeStatus.complete
        ? WorkflowNodeStatus.active
        : estimateStatus;
    final workAuthStatus = _bestDocStatus(workAuths);
    final scopeConfirmed =
        estimateStatus == WorkflowNodeStatus.complete &&
            workAuthStatus == WorkflowNodeStatus.complete;

    return WorkflowBand(
      label: 'BUDGET',
      subtitle: 'Budget, scope & pricing',
      icon: Icons.calculate_outlined,
      viewMode: BudgetViewMode.estimating,
      chains: [
        [
          WorkflowNode(
            id: 'create_budget_items',
            label: 'Create\nBudget Items',
            statusText: leafCount > 0
                ? '$leafCount ${leafCount == 1 ? "Item" : "Items"}'
                : null,
            status: createBudgetStatus,
            icon: Icons.playlist_add_outlined,
            count: leafCount > 0 ? leafCount : null,
            transitionLabel: 'READY TO ESTIMATE',
          ),
          WorkflowNode(
            id: 'create_estimate',
            label: 'Create\nEstimate',
            statusText: _docStatusText(estimates, fmt),
            status: estimateNodeStatus,
            icon: Icons.request_quote_outlined,
            documentId: _mostRelevantDocId(estimates),
            transitionLabel: 'CUSTOMER REVIEW',
            blockedReason: estimates.isEmpty && pricedCount == 0
                ? (leafCount == 0
                    ? 'Create budget items first.'
                    : 'Price your budget items before creating an estimate.')
                : null,
          ),
          WorkflowNode(
            id: 'work_authorization',
            label: 'Work\nAuthorization',
            statusText: _docStatusText(workAuths, fmt),
            status: workAuthStatus,
            icon: Icons.assignment_outlined,
            documentId: _mostRelevantDocId(workAuths),
            transitionLabel: 'APPROVE & START',
            blockedReason: workAuths.isEmpty &&
                    estimateStatus != WorkflowNodeStatus.complete
                ? 'Get the estimate approved before authorizing work.'
                : null,
          ),
          WorkflowNode(
            id: 'scope_confirmed',
            label: 'Scope\nConfirmed',
            statusText: scopeConfirmed ? 'Ready to bill' : null,
            status: scopeConfirmed
                ? WorkflowNodeStatus.complete
                : WorkflowNodeStatus.notStarted,
            icon: Icons.check_circle_outline,
            blockedReason: scopeConfirmed
                ? null
                : 'Scope is confirmed once both the estimate and work authorization are approved.',
          ),
        ],
      ],
    );
  }

  // ── Band 2: Costing ────────────────────────────────────────────────

  static WorkflowBand _buildCostingBand(
    List<BudgetItem> budgetItems,
    Map<String, double> actualCosts,
    String Function(double) fmt,
  ) {
    final leaves = budgetItems
        .where((i) => i.itemType == BudgetItemType.item)
        .toList();

    final totalEstimated =
        leaves.fold<double>(0, (s, i) => s + i.projectedCost);
    final totalCommitted =
        leaves.fold<double>(0, (s, i) => s + i.committedCost);
    final totalActual = leaves.fold<double>(
        0, (s, i) => s + (actualCosts[i.id] ?? 0));
    final variance = totalEstimated - totalActual;
    final overruns =
        leaves.where((i) => (actualCosts[i.id] ?? 0) > i.projectedCost).length;

    final hasPricedEstimate = leaves.any((i) => i.approvedPrice > 0);

    // Committed Budget node
    final committedStatus = totalCommitted <= 0
        ? WorkflowNodeStatus.notStarted
        : WorkflowNodeStatus.active;

    // Track Costs node — allow recording bills/expenses any time. Walk-in
    // purchases, surprise costs, and material runs don't always have a prior
    // PO commitment, so blocking on totalCommitted == 0 was overly strict.
    final trackStatus = totalActual <= 0
        ? WorkflowNodeStatus.notStarted
        : WorkflowNodeStatus.active;
    final committedBlocked = !hasPricedEstimate
        ? 'Price your budget items first before committing costs.'
        : null;

    // Cost Variance node
    final varianceStatus = totalActual <= 0
        ? WorkflowNodeStatus.notStarted
        : overruns > 0
            ? WorkflowNodeStatus.overdue
            : WorkflowNodeStatus.complete;

    return WorkflowBand(
      label: 'BILLS/EXPENSES',
      subtitle: 'Cost tracking',
      icon: Icons.attach_money,
      viewMode: BudgetViewMode.costing,
      chains: [
        [
          WorkflowNode(
            id: 'committed_budget',
            label: 'PO\nCommitments',
            statusText: totalCommitted > 0
                ? '${fmt(totalCommitted)} committed'
                : null,
            status: committedStatus,
            icon: Icons.assignment_outlined,
            amount: totalCommitted > 0 ? totalCommitted : null,
            transitionLabel: 'TRACK SPEND',
            blockedReason: committedBlocked,
          ),
          WorkflowNode(
            id: 'track_costs',
            label: 'Add Bill /\nExpense',
            statusText: totalActual > 0
                ? '${fmt(totalActual)} spent'
                : null,
            status: trackStatus,
            icon: Icons.track_changes,
            amount: totalActual > 0 ? totalActual : null,
            transitionLabel: 'VARIANCE',
          ),
          WorkflowNode(
            id: 'cost_variance',
            label: 'Budget\nVariance',
            statusText: totalActual > 0
                ? overruns > 0
                    ? '$overruns overrun${overruns == 1 ? '' : 's'}'
                    : '${fmt(variance)} under'
                : null,
            status: varianceStatus,
            icon: Icons.trending_down,
            amount: variance != 0 ? variance : null,
            blockedReason: totalActual <= 0
                ? 'Track actual costs before comparing against the estimate.'
                : null,
          ),
        ],
      ],
    );
  }

  // ── Band 3: Invoicing ─────────────────────────────────────────────

  static WorkflowBand _buildInvoicingBand(
    List<GeneratedDocument> docs,
    double invoicedToDate,
    double collected,
    double outstanding,
    double approvedEstimate,
    String Function(double) fmt,
    List<PayApplication> payApps,
  ) {
    final progressInvoices = docs
        .where((d) => d.documentType == DocumentType.progressInvoice)
        .toList();
    final invoices =
        docs.where((d) => d.documentType == DocumentType.invoice).toList();
    final deposits =
        docs.where((d) => d.documentType == DocumentType.deposit).toList();
    final allInvoiceDocs = [...progressInvoices, ...invoices];
    final now = DateTime.now();

    // Collect Deposit node
    final depositStatus = _bestDocStatus(deposits);

    // Progress Invoice node
    final piStatus = _bestDocStatus(progressInvoices);

    // Send Invoice node — overdue check
    final overdueInvoices = allInvoiceDocs.where((d) =>
        d.dueDate != null &&
        d.dueDate!.isBefore(now) &&
        d.paidDate == null &&
        d.status != DocumentStatus.draft);
    final sendStatus = overdueInvoices.isNotEmpty
        ? WorkflowNodeStatus.overdue
        : _bestDocStatus(invoices);
    final overdueDoc =
        overdueInvoices.isNotEmpty ? overdueInvoices.first : null;

    // Receive Payment
    final paidCount =
        allInvoiceDocs.where((d) => d.paidDate != null).length;
    final receiveStatus = paidCount == 0
        ? WorkflowNodeStatus.notStarted
        : (collected >= invoicedToDate && invoicedToDate > 0)
            ? WorkflowNodeStatus.complete
            : WorkflowNodeStatus.active;

    // Outstanding Balance
    final outstandingStatus = invoicedToDate == 0
        ? WorkflowNodeStatus.notStarted
        : outstanding <= 0
            ? WorkflowNodeStatus.complete
            : WorkflowNodeStatus.active;

    // Final Invoice — complete if any invoice is fully paid, active if sent
    final paidInvoices =
        allInvoiceDocs.where((d) => d.paidDate != null).toList();
    final allPaid = allInvoiceDocs.isNotEmpty &&
        allInvoiceDocs.every((d) => d.paidDate != null);
    final finalStatus = allInvoiceDocs.isEmpty
        ? WorkflowNodeStatus.notStarted
        : allPaid
            ? WorkflowNodeStatus.complete
            : paidInvoices.isNotEmpty
                ? WorkflowNodeStatus.active
                : WorkflowNodeStatus.notStarted;

    return WorkflowBand(
      label: 'INVOICES',
      subtitle: 'Invoices & receipts',
      icon: Icons.receipt_long_outlined,
      viewMode: BudgetViewMode.invoicing,
      chains: [
        [
          WorkflowNode(
            id: 'collect_deposit',
            label: 'Collect\nDeposit',
            statusText: _docStatusText(deposits, fmt),
            status: depositStatus,
            icon: Icons.savings_outlined,
            documentId: _mostRelevantDocId(deposits),
            count: deposits.length > 1 ? deposits.length : null,
            transitionLabel: 'SEND INVOICE',
            blockedReason: deposits.isEmpty && approvedEstimate <= 0
                ? 'Price your budget items before requesting a deposit.'
                : null,
          ),
          WorkflowNode(
            id: 'send_invoice',
            label: 'Send\nInvoice',
            statusText: overdueDoc != null
                ? '${overdueDoc.documentNumber ?? "Invoice"} Overdue'
                : _docStatusText(invoices, fmt),
            status: sendStatus,
            icon: Icons.send_outlined,
            documentId:
                overdueDoc?.id ?? _mostRelevantDocId(invoices),
            transitionLabel: 'PROGRESS BILLING',
            blockedReason: invoices.isEmpty && approvedEstimate <= 0
                ? 'Price your budget items before issuing an invoice.'
                : null,
          ),
          WorkflowNode(
            id: 'progress_invoice',
            label: 'Send Progress\nInvoice',
            statusText: _docStatusText(progressInvoices, fmt),
            status: piStatus,
            icon: Icons.receipt_outlined,
            documentId: _mostRelevantDocId(progressInvoices),
            count: progressInvoices.length > 1 ? progressInvoices.length : null,
            transitionLabel: 'PAYMENT DUE',
            blockedReason: progressInvoices.isEmpty && approvedEstimate <= 0
                ? 'Price your budget items before billing a progress invoice.'
                : null,
          ),
          WorkflowNode(
            id: 'receive_payment',
            label: 'Receive\nPayment',
            statusText: collected > 0 ? '${fmt(collected)} Posted' : null,
            status: receiveStatus,
            icon: Icons.payments_outlined,
            amount: collected > 0 ? collected : null,
            transitionLabel: 'OUTSTANDING',
            blockedReason: allInvoiceDocs.isEmpty
                ? 'Send an invoice first before recording payment.'
                : null,
          ),
          WorkflowNode(
            id: 'outstanding_balance',
            label: 'Outstanding\nBalance',
            statusText: outstanding > 0 ? '${fmt(outstanding)} Owing' : null,
            status: outstandingStatus,
            icon: Icons.account_balance_wallet_outlined,
            amount: outstanding > 0 ? outstanding : null,
            transitionLabel: 'FINAL PAYMENT',
            blockedReason: allInvoiceDocs.isEmpty
                ? 'Send an invoice first — there is no balance yet.'
                : null,
          ),
          _buildAiaPayAppNode(payApps, approvedEstimate, fmt),
          WorkflowNode(
            id: 'final_invoice',
            label: 'Final\nInvoice',
            statusText: allPaid
                ? 'All paid'
                : allInvoiceDocs.isEmpty
                    ? 'Not started'
                    : null,
            status: finalStatus,
            icon: Icons.task_outlined,
            blockedReason: allInvoiceDocs.isEmpty
                ? 'Send an invoice before closing out with a final invoice.'
                : null,
          ),
        ],
      ],
    );
  }

  /// Live status for the AIA Pay App node, derived from the project's
  /// payment-application headers.
  ///
  ///   * none                  → notStarted
  ///   * any draft / submitted → active
  ///   * all paid              → complete
  ///   * any certified         → active (waiting on payment)
  ///   * any submitted past 30 days → overdue
  static WorkflowNode _buildAiaPayAppNode(
    List<PayApplication> payApps,
    double approvedEstimate,
    String Function(double) fmt,
  ) {
    WorkflowNodeStatus status;
    String statusText;
    String? docId;
    final now = DateTime.now();

    if (payApps.isEmpty) {
      status = WorkflowNodeStatus.notStarted;
      statusText = 'G702 / G703';
    } else {
      final allPaid =
          payApps.every((a) => a.status == PayApplicationStatus.paid);
      final anyCertified =
          payApps.any((a) => a.status == PayApplicationStatus.certified);
      final overdueSubmitted = payApps.firstWhere(
        (a) =>
            a.status == PayApplicationStatus.submitted &&
            a.dateIssued != null &&
            now.difference(a.dateIssued!).inDays > 30,
        orElse: () => payApps.first,
      );
      final hasOverdue = payApps.any((a) =>
          a.status == PayApplicationStatus.submitted &&
          a.dateIssued != null &&
          now.difference(a.dateIssued!).inDays > 30);

      // Most recent app sets the doc focus.
      final mostRecent = payApps.reduce(
          (a, b) => a.applicationNumber > b.applicationNumber ? a : b);
      docId = mostRecent.id.isEmpty ? null : mostRecent.id;

      if (allPaid) {
        status = WorkflowNodeStatus.complete;
        statusText = '${payApps.length} paid';
      } else if (hasOverdue) {
        status = WorkflowNodeStatus.overdue;
        statusText = '#${overdueSubmitted.applicationNumber} awaiting cert.';
      } else if (anyCertified) {
        status = WorkflowNodeStatus.active;
        final cert = payApps.firstWhere(
            (a) => a.status == PayApplicationStatus.certified,
            orElse: () => mostRecent);
        statusText =
            '#${cert.applicationNumber} certified · ${fmt(cert.certifiedAmount ?? cert.currentPaymentDueSnapshot ?? 0)}';
      } else {
        status = WorkflowNodeStatus.active;
        statusText =
            '#${mostRecent.applicationNumber} ${mostRecent.status.displayLabel.toLowerCase()}';
      }
    }

    return WorkflowNode(
      id: 'aia_pay_app',
      label: 'AIA Pay\nApplication',
      statusText: statusText,
      status: status,
      icon: Icons.description_outlined,
      documentId: docId,
      count: payApps.length > 1 ? payApps.length : null,
      transitionLabel: 'CLOSE OUT',
      blockedReason: payApps.isEmpty && approvedEstimate <= 0
          ? 'Price your budget items before creating a pay application.'
          : null,
    );
  }

  // ── Band 4: Change Orders ──────────────────────────────────────────

  static WorkflowBand _buildChangeOrdersBand(
    List<GeneratedDocument> docs,
    String Function(double) fmt,
  ) {
    final changeOrders = docs
        .where((d) => d.documentType == DocumentType.changeOrder)
        .toList();
    final coStatus = _bestDocStatus(changeOrders);
    final pendingCOs = changeOrders.where((d) =>
        d.status == DocumentStatus.draft || d.status == DocumentStatus.sent);
    final pendingCoAmount =
        pendingCOs.fold<double>(0, (s, d) => s + d.totalAmount);

    // Add to Invoice — approved COs not yet invoiced
    final approvedCOs = changeOrders.where((d) =>
        d.status == DocumentStatus.signed ||
        d.status == DocumentStatus.approved);
    final approvedCoAmount =
        approvedCOs.fold<double>(0, (s, d) => s + d.totalAmount);
    final addToInvoiceStatus = approvedCOs.isEmpty
        ? WorkflowNodeStatus.notStarted
        : WorkflowNodeStatus.active;

    return WorkflowBand(
      label: 'CHANGE ORDERS',
      subtitle: 'Scope changes',
      icon: Icons.swap_horiz,
      viewMode: BudgetViewMode.changeOrders,
      chains: [
        [
          WorkflowNode(
            id: 'change_order',
            label: 'Create Change\nOrder',
            statusText: changeOrders.isEmpty
                ? null
                : pendingCOs.isNotEmpty
                    ? '${changeOrders.first.documentNumber ?? "CO"} Pending'
                    : _docStatusText(changeOrders, fmt),
            status: coStatus,
            icon: Icons.swap_horiz,
            documentId: _mostRelevantDocId(changeOrders),
            count: changeOrders.length > 1 ? changeOrders.length : null,
            transitionLabel: 'APPROVED →',
          ),
          WorkflowNode(
            id: 'add_to_invoice',
            label: 'Add to\nInvoice',
            statusText: approvedCoAmount > 0
                ? '+${fmt(approvedCoAmount)} approved'
                : pendingCoAmount > 0
                    ? '+${fmt(pendingCoAmount)} pending'
                    : null,
            status: addToInvoiceStatus,
            icon: Icons.playlist_add,
            amount: approvedCoAmount > 0 ? approvedCoAmount : null,
            blockedReason: approvedCOs.isEmpty
                ? (changeOrders.isEmpty
                    ? 'Create a change order first.'
                    : 'Approve a change order before adding it to an invoice.')
                : null,
          ),
        ],
      ],
    );
  }

  // ── Band 5: Upgrades ──────────────────────────────────────────────

  static WorkflowBand _buildUpgradesBand(
    List<BudgetItem> budgetItems,
    String Function(double) fmt,
  ) {
    final upgradeItems =
        budgetItems.where((i) => i.sourceType == BudgetItemSource.upgrade).toList();
    final offeredCount =
        upgradeItems.where((i) => i.upgradeStatus == UpgradeStatus.offered).length;
    final acceptedItems =
        upgradeItems.where((i) => i.upgradeStatus == UpgradeStatus.accepted).toList();
    final upgradeStatus = upgradeItems.isEmpty
        ? WorkflowNodeStatus.notStarted
        : offeredCount > 0
            ? WorkflowNodeStatus.active
            : WorkflowNodeStatus.complete;

    final pendingUpgradeAmount =
        acceptedItems.fold<double>(0, (s, i) => s + i.approvedPrice);
    final billSeparatelyStatus = acceptedItems.isEmpty
        ? WorkflowNodeStatus.notStarted
        : WorkflowNodeStatus.active;

    return WorkflowBand(
      label: 'UPGRADES',
      subtitle: 'Customer extras',
      icon: Icons.upgrade,
      viewMode: BudgetViewMode.upgrades,
      chains: [
        [
          WorkflowNode(
            id: 'customer_upgrade',
            label: 'Create Customer\nUpgrade',
            statusText: upgradeItems.isEmpty
                ? null
                : '${upgradeItems.length} ${upgradeItems.length == 1 ? "Upgrade" : "Upgrades"}',
            status: upgradeStatus,
            icon: Icons.upgrade,
            count: upgradeItems.length > 1 ? upgradeItems.length : null,
            transitionLabel: 'APPROVED →',
          ),
          WorkflowNode(
            id: 'bill_separately',
            label: 'Add to\nInvoice',
            statusText: pendingUpgradeAmount > 0
                ? '+${fmt(pendingUpgradeAmount)} pending'
                : null,
            status: billSeparatelyStatus,
            icon: Icons.receipt_long_outlined,
            amount: pendingUpgradeAmount > 0 ? pendingUpgradeAmount : null,
            blockedReason: acceptedItems.isEmpty
                ? (upgradeItems.isEmpty
                    ? 'Offer a customer upgrade first.'
                    : 'Customer must accept an upgrade before you can bill it.')
                : null,
          ),
        ],
      ],
    );
  }

  // ── Band 6: Holdback ──────────────────────────────────────────────

  static WorkflowBand _buildHoldbackBand(
    List<GeneratedDocument> docs,
    HoldbackBreakdown holdback,
    String Function(double) fmt,
  ) {
    // Holdback Withheld
    final withheldStatus = holdback.totalHoldbackItems == 0
        ? WorkflowNodeStatus.notStarted
        : WorkflowNodeStatus.active;

    // Release Holdback
    final releaseStatus = holdback.totalHoldbackItems == 0
        ? WorkflowNodeStatus.notStarted
        : holdback.releasedCount >= holdback.totalHoldbackItems
            ? WorkflowNodeStatus.complete
            : WorkflowNodeStatus.active;

    // Credits
    final credits =
        docs.where((d) => d.documentType == DocumentType.credit).toList();
    final creditStatus = _bestDocStatus(credits);

    // Refunds
    final refunds =
        docs.where((d) => d.documentType == DocumentType.refund).toList();
    final refundStatus = _bestDocStatus(refunds);

    return WorkflowBand(
      label: 'HOLDBACK',
      subtitle: 'Retention & adjustments',
      icon: Icons.lock_outline,
      viewMode: BudgetViewMode.holdback,
      chains: [
        // Left chain: Holdback
        [
          WorkflowNode(
            id: 'holdback_withheld',
            label: 'Holdback\nWithheld',
            statusText: holdback.holdbackWithheld > 0
                ? '${fmt(holdback.holdbackWithheld)} Auto-held'
                : null,
            status: withheldStatus,
            icon: Icons.lock_outlined,
            amount: holdback.holdbackWithheld > 0
                ? holdback.holdbackWithheld
                : null,
            transitionLabel: 'SIGN-OFF REQ\'D',
          ),
          WorkflowNode(
            id: 'release_holdback',
            label: 'Release\nHoldback',
            statusText: holdback.totalHoldbackItems == 0
                ? null
                : holdback.releasedCount >= holdback.totalHoldbackItems
                    ? 'All released'
                    : 'Pending sign-off',
            status: releaseStatus,
            icon: Icons.lock_open_outlined,
            blockedReason: holdback.totalHoldbackItems == 0
                ? 'No holdback has been withheld yet.'
                : null,
          ),
        ],
        // Right chain: Credits & Refunds
        [
          WorkflowNode(
            id: 'credit_note',
            label: 'Credit\nNote',
            statusText: credits.isEmpty ? 'None Issued' : _docStatusText(credits, fmt),
            status: creditStatus,
            icon: Icons.remove_circle_outline,
            documentId: _mostRelevantDocId(credits),
            transitionLabel: 'IF APPLICABLE',
          ),
          WorkflowNode(
            id: 'refund_adjustment',
            label: 'Refund /\nAdjustment',
            statusText: refunds.isEmpty ? 'None Issued' : _docStatusText(refunds, fmt),
            status: refundStatus,
            icon: Icons.currency_exchange,
            documentId: _mostRelevantDocId(refunds),
          ),
        ],
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Derive the best visual status from a set of documents of the same type.
  static WorkflowNodeStatus _bestDocStatus(List<GeneratedDocument> docs) {
    if (docs.isEmpty) return WorkflowNodeStatus.notStarted;

    final hasComplete = docs.any((d) =>
        d.status == DocumentStatus.signed ||
        d.status == DocumentStatus.approved ||
        d.paidDate != null);
    final hasActive = docs.any((d) =>
        d.status == DocumentStatus.sent || d.status == DocumentStatus.viewed);
    final hasDraft = docs.any((d) => d.status == DocumentStatus.draft);

    if (hasComplete) return WorkflowNodeStatus.complete;
    if (hasActive) return WorkflowNodeStatus.active;
    if (hasDraft) return WorkflowNodeStatus.draft;
    return WorkflowNodeStatus.notStarted;
  }

  /// Build a human-readable status string for the most relevant document.
  static String? _docStatusText(
    List<GeneratedDocument> docs,
    String Function(double) fmt,
  ) {
    if (docs.isEmpty) return null;
    final doc = _mostRelevantDoc(docs);
    if (doc == null) return null;

    final number = doc.documentNumber;
    final prefix = number ?? '';

    switch (doc.status) {
      case DocumentStatus.signed:
      case DocumentStatus.approved:
        return doc.paidDate != null
            ? '$prefix Paid'.trim()
            : '$prefix ${doc.status == DocumentStatus.signed ? "Signed" : "Approved"}'
                .trim();
      case DocumentStatus.sent:
      case DocumentStatus.viewed:
        return '$prefix ${doc.status == DocumentStatus.sent ? "Sent" : "Viewed"}'
            .trim();
      case DocumentStatus.draft:
        return '$prefix Draft'.trim();
      case DocumentStatus.denied:
        return '$prefix Denied'.trim();
      case DocumentStatus.changesRequested:
        return '$prefix Changes requested'.trim();
      case DocumentStatus.pending:
        return '$prefix Pending'.trim();
      case DocumentStatus.responded:
        return '$prefix Bid received'.trim();
      case DocumentStatus.applied:
        return '$prefix Applied'.trim();
      case DocumentStatus.notSelected:
        return '$prefix Not selected'.trim();
      case DocumentStatus.withdrawn:
        return '$prefix Withdrawn'.trim();
    }
  }

  /// Pick the most relevant document from a set (overdue > unpaid active > latest).
  static GeneratedDocument? _mostRelevantDoc(List<GeneratedDocument> docs) {
    if (docs.isEmpty) return null;
    final now = DateTime.now();

    // Overdue first
    final overdue = docs.where((d) =>
        d.dueDate != null && d.dueDate!.isBefore(now) && d.paidDate == null);
    if (overdue.isNotEmpty) return overdue.first;

    // Active (sent/viewed) unpaid
    final active = docs.where((d) =>
        (d.status == DocumentStatus.sent ||
            d.status == DocumentStatus.viewed) &&
        d.paidDate == null);
    if (active.isNotEmpty) return active.first;

    // Default to most recent
    return docs.first;
  }

  static String? _mostRelevantDocId(List<GeneratedDocument> docs) =>
      _mostRelevantDoc(docs)?.id;
}
