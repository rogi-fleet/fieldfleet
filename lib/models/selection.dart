/// Selections & Allowances domain models.
///
/// A [Selection] is a single decision the client must make on a job
/// (e.g. "Kitchen faucet"). It carries an *allowance* (budgeted amount) and,
/// once approved, a *selected amount* that feeds the budget rollup.
/// Each selection offers one or more [SelectionOption]s to choose from.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum SelectionStatus {
  pending,
  awaitingClient,
  approved,
  declined,
  cancelled;

  String get wireValue => switch (this) {
        SelectionStatus.pending         => 'pending',
        SelectionStatus.awaitingClient  => 'awaiting_client',
        SelectionStatus.approved        => 'approved',
        SelectionStatus.declined        => 'declined',
        SelectionStatus.cancelled       => 'cancelled',
      };

  String get label => switch (this) {
        SelectionStatus.pending         => 'Pending',
        SelectionStatus.awaitingClient  => 'Awaiting Client',
        SelectionStatus.approved        => 'Approved',
        SelectionStatus.declined        => 'Declined',
        SelectionStatus.cancelled       => 'Cancelled',
      };

  Color get color => switch (this) {
        SelectionStatus.pending         => AppColors.textSecondary,
        SelectionStatus.awaitingClient  => AppColors.warning,
        SelectionStatus.approved        => AppColors.success,
        SelectionStatus.declined        => AppColors.error,
        SelectionStatus.cancelled       => AppColors.textTertiary,
      };

  static SelectionStatus fromWire(String? raw) {
    switch (raw) {
      case 'awaiting_client': return SelectionStatus.awaitingClient;
      case 'approved':        return SelectionStatus.approved;
      case 'declined':        return SelectionStatus.declined;
      case 'cancelled':       return SelectionStatus.cancelled;
      default:                return SelectionStatus.pending;
    }
  }
}

class SelectionOption {
  final String id;
  final String selectionId;
  final String workspaceId;
  final String name;
  final String? description;
  final String? vendor;
  final String? sku;
  final double unitCost;
  final double quantity;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? externalUrl;
  final int sortOrder;
  final bool isClientSuggested;

  const SelectionOption({
    required this.id,
    required this.selectionId,
    required this.workspaceId,
    required this.name,
    this.description,
    this.vendor,
    this.sku,
    this.unitCost = 0,
    this.quantity = 1,
    this.imageUrl,
    this.imageUrls = const [],
    this.externalUrl,
    this.sortOrder = 0,
    this.isClientSuggested = false,
  });

  double get totalCost => unitCost * (quantity == 0 ? 1 : quantity);

  /// All photos, preferring the multi-image list and falling back to the
  /// single primary [imageUrl] for legacy rows.
  List<String> get photos => imageUrls.isNotEmpty
      ? imageUrls
      : (imageUrl != null && imageUrl!.isNotEmpty ? [imageUrl!] : const []);

  /// The image to show as the card thumbnail.
  String? get primaryImage => photos.isNotEmpty ? photos.first : null;

  factory SelectionOption.fromRow(Map<String, dynamic> row) {
    final rawImages = row['image_urls'];
    final images = rawImages is List
        ? rawImages.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return SelectionOption(
      id:           row['id'] as String,
      selectionId:  (row['selection_id'] ?? '') as String,
      workspaceId:  (row['workspace_id'] ?? '') as String,
      name:         (row['name'] ?? '') as String,
      description:  row['description'] as String?,
      vendor:       row['vendor']      as String?,
      sku:          row['sku']         as String?,
      unitCost:     (row['unit_cost'] as num?)?.toDouble() ?? 0,
      quantity:     (row['quantity']  as num?)?.toDouble() ?? 1,
      imageUrl:     row['image_url']   as String?,
      imageUrls:    images,
      externalUrl:  row['external_url'] as String?,
      sortOrder:    (row['sort_order'] as num?)?.toInt() ?? 0,
      isClientSuggested: (row['is_client_suggested'] as bool?) ?? false,
    );
  }
}

class Selection {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String? description;
  final String? category;
  final String? location;
  final SelectionStatus status;
  final double allowanceAmount;
  final double selectedAmount;
  final String? budgetItemId;
  final String? selectedOptionId;
  final bool excludeFromBudget;
  final bool showAmountDifferences;
  final bool allowMultipleSelections;
  final String? referenceUrl;
  final List<String> attachmentUrls;
  final DateTime? dueDate;
  final String? clientNotes;
  final String? internalNotes;
  final DateTime? approvedAt;
  final String? approvedByName;
  final String? approvedSignatureUrl;
  final DateTime? declinedAt;
  final String? declinedByName;
  final String? declineReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SelectionOption> options;

  const Selection({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.name,
    this.description,
    this.category,
    this.location,
    required this.status,
    this.allowanceAmount = 0,
    this.selectedAmount = 0,
    this.budgetItemId,
    this.selectedOptionId,
    this.excludeFromBudget = false,
    this.showAmountDifferences = true,
    this.allowMultipleSelections = false,
    this.referenceUrl,
    this.attachmentUrls = const [],
    this.dueDate,
    this.clientNotes,
    this.internalNotes,
    this.approvedAt,
    this.approvedByName,
    this.approvedSignatureUrl,
    this.declinedAt,
    this.declinedByName,
    this.declineReason,
    required this.createdAt,
    required this.updatedAt,
    this.options = const [],
  });

  /// Delta vs allowance. Positive = over-budget overage.
  double get variance => selectedAmount - allowanceAmount;

  /// What hits the budget rollup right now: approved → selected, else allowance.
  double get budgetImpact =>
      status == SelectionStatus.approved ? selectedAmount : allowanceAmount;

  factory Selection.fromRow(
    Map<String, dynamic> row, {
    List<SelectionOption> options = const [],
  }) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return Selection(
      id:               row['id'] as String,
      workspaceId:      (row['workspace_id'] ?? '') as String,
      projectId:        (row['project_id']   ?? '') as String,
      name:             (row['name'] ?? '') as String,
      description:      row['description'] as String?,
      category:         row['category']    as String?,
      location:         row['location']    as String?,
      status:           SelectionStatus.fromWire(row['status'] as String?),
      allowanceAmount:  (row['allowance_amount'] as num?)?.toDouble() ?? 0,
      selectedAmount:   (row['selected_amount']  as num?)?.toDouble() ?? 0,
      budgetItemId:     row['budget_item_id']    as String?,
      selectedOptionId: row['selected_option_id'] as String?,
      excludeFromBudget:       (row['exclude_from_budget'] as bool?) ?? false,
      showAmountDifferences:   (row['show_amount_differences'] as bool?) ?? true,
      allowMultipleSelections: (row['allow_multiple_selections'] as bool?) ?? false,
      referenceUrl:     row['reference_url'] as String?,
      attachmentUrls:   (row['attachment_urls'] is List)
          ? (row['attachment_urls'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      dueDate:          parse(row['due_date']),
      clientNotes:      row['client_notes']   as String?,
      internalNotes:    row['internal_notes'] as String?,
      approvedAt:       parse(row['approved_at']),
      approvedByName:   row['approved_by_name'] as String?,
      approvedSignatureUrl: row['approved_signature_url'] as String?,
      declinedAt:       parse(row['declined_at']),
      declinedByName:   row['declined_by_name'] as String?,
      declineReason:    row['decline_reason']   as String?,
      createdAt:        parse(row['created_at']) ?? DateTime.now(),
      updatedAt:        parse(row['updated_at']) ?? DateTime.now(),
      options:          options,
    );
  }
}

/// A single message in a selection's back-and-forth thread (builder ↔ client).
class SelectionComment {
  final String id;
  final String body;
  final String? authorName;
  final bool isFromClient;
  final DateTime createdAt;

  const SelectionComment({
    required this.id,
    required this.body,
    this.authorName,
    this.isFromClient = false,
    required this.createdAt,
  });

  factory SelectionComment.fromRow(Map<String, dynamic> row) {
    return SelectionComment(
      id: row['id'] as String,
      body: (row['body'] ?? '') as String,
      authorName: row['author_name'] as String?,
      isFromClient: (row['is_from_client'] as bool?) ?? false,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// One e-signature on a selection (a selection can collect several).
class SelectionSignature {
  final String id;
  final String? signerName;
  final String? signerEmail;
  final String signatureUrl;
  final DateTime signedAt;

  const SelectionSignature({
    required this.id,
    this.signerName,
    this.signerEmail,
    required this.signatureUrl,
    required this.signedAt,
  });

  factory SelectionSignature.fromRow(Map<String, dynamic> row) {
    return SelectionSignature(
      id: row['id'] as String,
      signerName: row['signer_name'] as String?,
      signerEmail: row['signer_email'] as String?,
      signatureUrl: (row['signature_url'] ?? '') as String,
      signedAt: DateTime.tryParse(row['signed_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// Aggregate budget impact of all selections on a project.
class SelectionSummary {
  final double totalAllowance;       // sum of allowance for all non-cancelled
  final double approvedAllowance;    // allowance baseline of approved-only
  final double totalSelected;        // approved-only selected amount
  final double pendingAllowance;     // awaiting_client or pending
  final int countTotal;
  final int countAwaitingClient;
  final int countApproved;
  final int countDeclined;

  const SelectionSummary({
    required this.totalAllowance,
    required this.approvedAllowance,
    required this.totalSelected,
    required this.pendingAllowance,
    required this.countTotal,
    required this.countAwaitingClient,
    required this.countApproved,
    required this.countDeclined,
  });

  /// Approved overage vs the allowance baseline of the SAME approved items.
  /// Positive = over budget. Pending/declined items don't distort this.
  double get approvedVariance => totalSelected - approvedAllowance;

  static const empty = SelectionSummary(
    totalAllowance: 0, approvedAllowance: 0, totalSelected: 0,
    pendingAllowance: 0,
    countTotal: 0, countAwaitingClient: 0, countApproved: 0, countDeclined: 0,
  );
}
