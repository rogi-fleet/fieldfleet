import 'package:flutter/material.dart';
import '../models/document_type.dart';
import '../models/document_status.dart';
import '../models/generated_document.dart';
import '../models/template_category.dart';
import '../theme/theme.dart';

IconData getDocumentTypeIcon(DocumentType type) {
  switch (type) {
    case DocumentType.invoice:
    case DocumentType.progressInvoice:
      return Icons.receipt_long;
    case DocumentType.workOrder:
    case DocumentType.workOrderEmergency:
    case DocumentType.workOrderMaintenance:
      return Icons.assignment;
    case DocumentType.quotation:
      return Icons.request_quote;
    case DocumentType.expense:
      return Icons.money_off;
    case DocumentType.bill:
      return Icons.receipt;
    case DocumentType.purchaseOrder:
      return Icons.shopping_cart;
    case DocumentType.custom:
      return Icons.description;
    default:
      return type.category.icon;
  }
}

Color getDocumentTypeColor(DocumentType type) {
  switch (type) {
    case DocumentType.invoice:
    case DocumentType.progressInvoice:
      return AppColors.info;
    case DocumentType.workOrder:
    case DocumentType.workOrderEmergency:
    case DocumentType.workOrderMaintenance:
      return AppColors.warning;
    case DocumentType.quotation:
      return AppColors.messageAccent;
    case DocumentType.expense:
      return AppColors.error;
    case DocumentType.bill:
      return Colors.brown;
    case DocumentType.purchaseOrder:
      return AppColors.financialAccent;
    case DocumentType.custom:
      return AppColors.textTertiary;
    default:
      return type.category.color;
  }
}

/// A status counts as "billed out" when it indicates the document has been
/// committed to the counterparty — i.e. it represents real money owed in
/// either direction. Drives A/R, A/P, and MTD income/expense so the
/// Dashboard overdue list. Mirrors the convention used by
/// `SupabaseBudgetService.calculateInvoicedAmount` so that the project budget
/// rollups and the Financials view agree on what
/// counts as money on the books.
/// Whether a document is "billed out" — delivered/approved such that it posts
/// to the general ledger and therefore counts as outstanding A/R (invoices) or
/// A/P (bills) and recognized income/expense on the Financials view.
///
/// This MUST match the statuses that trigger `_autoPostToGl` in
/// DocumentService (sent / approved / signed; `viewed` is a post-send read
/// receipt) so the dashboard reconciles with the GL — the dashboard's own
/// "needs posting to GL" reconciliation uses exactly this set.
///
/// Previously this also returned true for `pending` (awaiting internal
/// approval) and `changesRequested` — neither of which ever posts to the GL —
/// which double-counted not-yet-billed invoices in A/R (e.g. a $13k pending
/// invoice showed in "A/R Outstanding" while GL A/R was $0) and broke
/// dashboard↔ledger reconciliation. `applied`/`responded` are non-billing
/// workflow states (e.g. a deposit applied to an invoice is no longer
/// outstanding), so they're excluded too.
bool isStatusBilled(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.sent:
    case DocumentStatus.viewed:
    case DocumentStatus.signed:
    case DocumentStatus.approved:
      return true;
    case DocumentStatus.applied:
    case DocumentStatus.pending:
    case DocumentStatus.responded:
    case DocumentStatus.changesRequested:
    case DocumentStatus.denied:
    case DocumentStatus.withdrawn:
    case DocumentStatus.notSelected:
    case DocumentStatus.draft:
      return false;
  }
}

/// A document is "open / outstanding" when it's been billed out and the
/// `paid_date` is still unset.
bool isDocumentOpen(GeneratedDocument d) =>
    d.paidDate == null && isStatusBilled(d.status);

Color getDocumentStatusColor(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.draft:
      return AppColors.textTertiary;
    case DocumentStatus.sent:
      return AppColors.info;
    case DocumentStatus.viewed:
      return AppColors.warning;
    case DocumentStatus.signed:
      return AppColors.success;
    case DocumentStatus.denied:
      return AppColors.error;
    case DocumentStatus.changesRequested:
      return AppColors.warning;
    case DocumentStatus.pending:
      return AppColors.warning;
    case DocumentStatus.approved:
      return AppColors.financialAccent;
    case DocumentStatus.responded:
      return AppColors.info;
    case DocumentStatus.applied:
      return AppColors.success;
    case DocumentStatus.notSelected:
    case DocumentStatus.withdrawn:
      return AppColors.textTertiary;
  }
}
