/// Subcontract domain models.
///
/// A [Subcontract] is a contract issued to a vendor for scoped work on a
/// project. Carries lifecycle (draft → sent → signed → active → completed),
/// items linked to budget, multi-party signatures, and an audit history.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum SubcontractStatus {
  draft,
  sent,
  signed,
  active,
  completed,
  terminated,
  cancelled;

  String get wireValue => switch (this) {
        SubcontractStatus.draft      => 'draft',
        SubcontractStatus.sent       => 'sent',
        SubcontractStatus.signed     => 'signed',
        SubcontractStatus.active     => 'active',
        SubcontractStatus.completed  => 'completed',
        SubcontractStatus.terminated => 'terminated',
        SubcontractStatus.cancelled  => 'cancelled',
      };

  String get label => switch (this) {
        SubcontractStatus.draft      => 'Draft',
        SubcontractStatus.sent       => 'Sent',
        SubcontractStatus.signed     => 'Signed',
        SubcontractStatus.active     => 'Active',
        SubcontractStatus.completed  => 'Completed',
        SubcontractStatus.terminated => 'Terminated',
        SubcontractStatus.cancelled  => 'Cancelled',
      };

  Color get color => switch (this) {
        SubcontractStatus.draft      => AppColors.textSecondary,
        SubcontractStatus.sent       => AppColors.info,
        SubcontractStatus.signed     => AppColors.activityAccent,
        SubcontractStatus.active     => AppColors.warning,
        SubcontractStatus.completed  => AppColors.success,
        SubcontractStatus.terminated => AppColors.error,
        SubcontractStatus.cancelled  => AppColors.textTertiary,
      };

  static SubcontractStatus fromWire(String? raw) {
    switch (raw) {
      case 'sent':       return SubcontractStatus.sent;
      case 'signed':     return SubcontractStatus.signed;
      case 'active':     return SubcontractStatus.active;
      case 'completed':  return SubcontractStatus.completed;
      case 'terminated': return SubcontractStatus.terminated;
      case 'cancelled':  return SubcontractStatus.cancelled;
      default:           return SubcontractStatus.draft;
    }
  }
}

class SubcontractItem {
  final String id;
  final String subcontractId;
  final String workspaceId;
  final String description;
  final double quantity;
  final String? unit;
  final double unitCost;
  final String? budgetItemId;
  final int sortOrder;

  const SubcontractItem({
    required this.id,
    required this.subcontractId,
    required this.workspaceId,
    required this.description,
    this.quantity = 1,
    this.unit,
    this.unitCost = 0,
    this.budgetItemId,
    this.sortOrder = 0,
  });

  double get total => quantity * unitCost;

  factory SubcontractItem.fromRow(Map<String, dynamic> row) => SubcontractItem(
        id:             row['id'] as String,
        subcontractId:  (row['subcontract_id'] ?? '') as String,
        workspaceId:    (row['workspace_id']   ?? '') as String,
        description:    (row['description']    ?? '') as String,
        quantity:       (row['quantity']  as num?)?.toDouble() ?? 1,
        unit:           row['unit'] as String?,
        unitCost:       (row['unit_cost'] as num?)?.toDouble() ?? 0,
        budgetItemId:   row['budget_item_id'] as String?,
        sortOrder:      (row['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class SubcontractSignature {
  final String id;
  final String subcontractId;
  final String role; // contractor / vendor / client / witness
  final String signerName;
  final String? signerEmail;
  final String signatureUrl;
  final DateTime signedAt;

  const SubcontractSignature({
    required this.id,
    required this.subcontractId,
    required this.role,
    required this.signerName,
    this.signerEmail,
    required this.signatureUrl,
    required this.signedAt,
  });

  factory SubcontractSignature.fromRow(Map<String, dynamic> row) =>
      SubcontractSignature(
        id:             row['id'] as String,
        subcontractId:  (row['subcontract_id'] ?? '') as String,
        role:           (row['role'] ?? 'vendor') as String,
        signerName:     (row['signer_name'] ?? '') as String,
        signerEmail:    row['signer_email'] as String?,
        signatureUrl:   (row['signature_url'] ?? '') as String,
        signedAt:       DateTime.tryParse((row['signed_at'] ?? '').toString())
                            ?.toLocal() ?? DateTime.now(),
      );

  String get roleLabel => switch (role) {
        'contractor' => 'Contractor',
        'vendor'     => 'Vendor',
        'client'     => 'Client',
        'witness'    => 'Witness',
        _ => role,
      };
}

class SubcontractHistoryEvent {
  final String id;
  final String subcontractId;
  final String eventType;
  final String? fromStatus;
  final String? toStatus;
  final String? message;
  final String? actorName;
  final DateTime createdAt;

  const SubcontractHistoryEvent({
    required this.id,
    required this.subcontractId,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.message,
    this.actorName,
    required this.createdAt,
  });

  factory SubcontractHistoryEvent.fromRow(Map<String, dynamic> row) =>
      SubcontractHistoryEvent(
        id:             row['id'] as String,
        subcontractId:  (row['subcontract_id'] ?? '') as String,
        eventType:      (row['event_type'] ?? '') as String,
        fromStatus:     row['from_status'] as String?,
        toStatus:       row['to_status']   as String?,
        message:        row['message']     as String?,
        actorName:      row['actor_name']  as String?,
        createdAt:      DateTime.tryParse((row['created_at'] ?? '').toString())
                            ?.toLocal() ?? DateTime.now(),
      );
}

class Subcontract {
  final String id;
  final String workspaceId;
  final String projectId;
  final String vendorId;
  final String number;
  final String title;
  final String? description;
  final String? scopeOfWork;
  final SubcontractStatus status;
  final double contractAmount;
  final double retainagePercent;
  final double paidToDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? sentAt;
  final DateTime? signedAt;
  final DateTime? completedAt;
  final DateTime? terminatedAt;
  final String? paymentTerms;
  final bool insuranceRequired;
  final bool insuranceVerified;
  final DateTime? insuranceVerifiedAt;
  final String? internalNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SubcontractItem> items;
  final List<SubcontractSignature> signatures;

  const Subcontract({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.vendorId,
    required this.number,
    required this.title,
    this.description,
    this.scopeOfWork,
    required this.status,
    this.contractAmount = 0,
    this.retainagePercent = 0,
    this.paidToDate = 0,
    this.startDate,
    this.endDate,
    this.sentAt,
    this.signedAt,
    this.completedAt,
    this.terminatedAt,
    this.paymentTerms,
    this.insuranceRequired = true,
    this.insuranceVerified = false,
    this.insuranceVerifiedAt,
    this.internalNotes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.signatures = const [],
  });

  double get remaining => contractAmount - paidToDate;

  factory Subcontract.fromRow(
    Map<String, dynamic> row, {
    List<SubcontractItem> items = const [],
    List<SubcontractSignature> signatures = const [],
  }) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return Subcontract(
      id:                  row['id'] as String,
      workspaceId:         (row['workspace_id'] ?? '') as String,
      projectId:           (row['project_id']   ?? '') as String,
      vendorId:            (row['vendor_id']    ?? '') as String,
      number:              (row['number'] ?? '') as String,
      title:               (row['title']  ?? '') as String,
      description:         row['description']    as String?,
      scopeOfWork:         row['scope_of_work']  as String?,
      status:              SubcontractStatus.fromWire(row['status'] as String?),
      contractAmount:      (row['contract_amount']    as num?)?.toDouble() ?? 0,
      retainagePercent:    (row['retainage_percent']  as num?)?.toDouble() ?? 0,
      paidToDate:          (row['paid_to_date']       as num?)?.toDouble() ?? 0,
      startDate:           parse(row['start_date']),
      endDate:             parse(row['end_date']),
      sentAt:              parse(row['sent_at']),
      signedAt:            parse(row['signed_at']),
      completedAt:         parse(row['completed_at']),
      terminatedAt:        parse(row['terminated_at']),
      paymentTerms:        row['payment_terms'] as String?,
      insuranceRequired:   (row['insurance_required'] as bool?) ?? true,
      insuranceVerified:   (row['insurance_verified'] as bool?) ?? false,
      insuranceVerifiedAt: parse(row['insurance_verified_at']),
      internalNotes:       row['internal_notes'] as String?,
      createdAt:           parse(row['created_at']) ?? DateTime.now(),
      updatedAt:           parse(row['updated_at']) ?? DateTime.now(),
      items:               items,
      signatures:          signatures,
    );
  }
}

class SubcontractSummary {
  final int countTotal;
  final int countActive;
  final int countCompleted;
  final double totalCommitted;
  final double totalPaid;
  final double totalRemaining;

  const SubcontractSummary({
    required this.countTotal,
    required this.countActive,
    required this.countCompleted,
    required this.totalCommitted,
    required this.totalPaid,
    required this.totalRemaining,
  });

  static const empty = SubcontractSummary(
    countTotal: 0, countActive: 0, countCompleted: 0,
    totalCommitted: 0, totalPaid: 0, totalRemaining: 0,
  );
}
