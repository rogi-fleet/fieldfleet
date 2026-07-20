/// Work Order domain models.
///
/// A [WorkOrder] is an internal directive to execute scoped work on a project.
/// It has a lifecycle (draft → issued → in_progress → completed) and may carry
/// [WorkOrderItem]s linked to budget items/tasks, [WorkOrderSignature]s for
/// approval, and [WorkOrderHistoryEvent]s as an audit trail.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum WorkOrderStatus {
  draft,
  issued,
  inProgress,
  onHold,
  completed,
  cancelled;

  String get wireValue => switch (this) {
        WorkOrderStatus.draft      => 'draft',
        WorkOrderStatus.issued     => 'issued',
        WorkOrderStatus.inProgress => 'in_progress',
        WorkOrderStatus.onHold     => 'on_hold',
        WorkOrderStatus.completed  => 'completed',
        WorkOrderStatus.cancelled  => 'cancelled',
      };

  String get label => switch (this) {
        WorkOrderStatus.draft      => 'Draft',
        WorkOrderStatus.issued     => 'Issued',
        WorkOrderStatus.inProgress => 'In Progress',
        WorkOrderStatus.onHold     => 'On Hold',
        WorkOrderStatus.completed  => 'Completed',
        WorkOrderStatus.cancelled  => 'Cancelled',
      };

  Color get color => switch (this) {
        WorkOrderStatus.draft      => AppColors.textSecondary,
        WorkOrderStatus.issued     => AppColors.info,
        WorkOrderStatus.inProgress => AppColors.warning,
        WorkOrderStatus.onHold     => AppColors.activityAccent,
        WorkOrderStatus.completed  => AppColors.success,
        WorkOrderStatus.cancelled  => AppColors.textTertiary,
      };

  static WorkOrderStatus fromWire(String? raw) {
    switch (raw) {
      case 'issued':      return WorkOrderStatus.issued;
      case 'in_progress': return WorkOrderStatus.inProgress;
      case 'on_hold':     return WorkOrderStatus.onHold;
      case 'completed':   return WorkOrderStatus.completed;
      case 'cancelled':   return WorkOrderStatus.cancelled;
      default:            return WorkOrderStatus.draft;
    }
  }
}

enum WorkOrderPriority {
  low, normal, high, urgent;

  String get wireValue => switch (this) {
        WorkOrderPriority.low    => 'low',
        WorkOrderPriority.normal => 'normal',
        WorkOrderPriority.high   => 'high',
        WorkOrderPriority.urgent => 'urgent',
      };

  String get label => switch (this) {
        WorkOrderPriority.low    => 'Low',
        WorkOrderPriority.normal => 'Normal',
        WorkOrderPriority.high   => 'High',
        WorkOrderPriority.urgent => 'Urgent',
      };

  Color get color => switch (this) {
        WorkOrderPriority.low    => AppColors.textTertiary,
        WorkOrderPriority.normal => AppColors.textSecondary,
        WorkOrderPriority.high   => AppColors.warning,
        WorkOrderPriority.urgent => AppColors.error,
      };

  static WorkOrderPriority fromWire(String? raw) {
    switch (raw) {
      case 'low':    return WorkOrderPriority.low;
      case 'high':   return WorkOrderPriority.high;
      case 'urgent': return WorkOrderPriority.urgent;
      default:       return WorkOrderPriority.normal;
    }
  }
}

class WorkOrderItem {
  final String id;
  final String workOrderId;
  final String workspaceId;
  final String description;
  final double quantity;
  final String? unit;
  final double unitCost;
  final String? budgetItemId;
  final String? taskId;
  final int sortOrder;

  const WorkOrderItem({
    required this.id,
    required this.workOrderId,
    required this.workspaceId,
    required this.description,
    this.quantity = 1,
    this.unit,
    this.unitCost = 0,
    this.budgetItemId,
    this.taskId,
    this.sortOrder = 0,
  });

  double get total => quantity * unitCost;

  factory WorkOrderItem.fromRow(Map<String, dynamic> row) => WorkOrderItem(
        id:            row['id'] as String,
        workOrderId:   (row['work_order_id'] ?? '') as String,
        workspaceId:   (row['workspace_id']  ?? '') as String,
        description:   (row['description']   ?? '') as String,
        quantity:      (row['quantity']  as num?)?.toDouble() ?? 1,
        unit:          row['unit'] as String?,
        unitCost:      (row['unit_cost'] as num?)?.toDouble() ?? 0,
        budgetItemId:  row['budget_item_id'] as String?,
        taskId:        row['task_id'] as String?,
        sortOrder:     (row['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class WorkOrderSignature {
  final String id;
  final String workOrderId;
  final String role; // contractor / client / vendor / witness
  final String signerName;
  final String? signerEmail;
  final String signatureUrl;
  final DateTime signedAt;

  const WorkOrderSignature({
    required this.id,
    required this.workOrderId,
    required this.role,
    required this.signerName,
    this.signerEmail,
    required this.signatureUrl,
    required this.signedAt,
  });

  factory WorkOrderSignature.fromRow(Map<String, dynamic> row) =>
      WorkOrderSignature(
        id:           row['id'] as String,
        workOrderId:  (row['work_order_id'] ?? '') as String,
        role:         (row['role'] ?? 'contractor') as String,
        signerName:   (row['signer_name'] ?? '') as String,
        signerEmail:  row['signer_email'] as String?,
        signatureUrl: (row['signature_url'] ?? '') as String,
        signedAt:     DateTime.tryParse((row['signed_at'] ?? '').toString())
                          ?.toLocal() ?? DateTime.now(),
      );

  String get roleLabel => switch (role) {
        'contractor' => 'Contractor',
        'client'     => 'Client',
        'vendor'     => 'Vendor',
        'witness'    => 'Witness',
        _ => role,
      };
}

class WorkOrderHistoryEvent {
  final String id;
  final String workOrderId;
  final String eventType;
  final String? fromStatus;
  final String? toStatus;
  final String? message;
  final String? actorName;
  final DateTime createdAt;

  const WorkOrderHistoryEvent({
    required this.id,
    required this.workOrderId,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.message,
    this.actorName,
    required this.createdAt,
  });

  factory WorkOrderHistoryEvent.fromRow(Map<String, dynamic> row) =>
      WorkOrderHistoryEvent(
        id:          row['id'] as String,
        workOrderId: (row['work_order_id'] ?? '') as String,
        eventType:   (row['event_type'] ?? '') as String,
        fromStatus:  row['from_status'] as String?,
        toStatus:    row['to_status']   as String?,
        message:     row['message']     as String?,
        actorName:   row['actor_name']  as String?,
        createdAt:   DateTime.tryParse((row['created_at'] ?? '').toString())
                         ?.toLocal() ?? DateTime.now(),
      );
}

class WorkOrder {
  final String id;
  final String workspaceId;
  final String projectId;
  final String number;
  final String title;
  final String? description;
  final String? scopeOfWork;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final String? assignedTo;
  final String? vendorId;
  final String? location;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final double? estimatedHours;
  final double? actualHours;
  final double totalAmount;
  /// Sum of payments recorded against this purchase order to date.
  /// Mirrors `subcontracts.paid_to_date` so Materials and Rentals can
  /// report Committed / Paid / Remaining identically to Subcontracts.
  final double paidToDate;
  final String? internalNotes;
  final String? clientNotes;
  /// Discriminator for what this purchase-order-style record represents.
  /// 'materials' = traditional work order for materials/services from a
  /// vendor. 'rental' = rental equipment expense request issued to a
  /// third-party rental house (paid later). Shares the same lifecycle,
  /// line items, signatures and history as work orders.
  final String kind;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkOrderItem> items;
  final List<WorkOrderSignature> signatures;

  const WorkOrder({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.number,
    required this.title,
    this.description,
    this.scopeOfWork,
    required this.status,
    this.priority = WorkOrderPriority.normal,
    this.assignedTo,
    this.vendorId,
    this.location,
    this.scheduledStart,
    this.scheduledEnd,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.estimatedHours,
    this.actualHours,
    this.totalAmount = 0,
    this.paidToDate = 0,
    this.internalNotes,
    this.clientNotes,
    this.kind = 'materials',
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.signatures = const [],
  });

  factory WorkOrder.fromRow(
    Map<String, dynamic> row, {
    List<WorkOrderItem> items = const [],
    List<WorkOrderSignature> signatures = const [],
  }) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return WorkOrder(
      id:             row['id'] as String,
      workspaceId:    (row['workspace_id'] ?? '') as String,
      projectId:      (row['project_id']   ?? '') as String,
      number:         (row['number'] ?? '') as String,
      title:          (row['title']  ?? '') as String,
      description:    row['description']    as String?,
      scopeOfWork:    row['scope_of_work']  as String?,
      status:         WorkOrderStatus.fromWire(row['status'] as String?),
      priority:       WorkOrderPriority.fromWire(row['priority'] as String?),
      assignedTo:     row['assigned_to'] as String?,
      vendorId:       row['vendor_id']   as String?,
      location:       row['location']    as String?,
      scheduledStart: parse(row['scheduled_start']),
      scheduledEnd:   parse(row['scheduled_end']),
      startedAt:      parse(row['started_at']),
      completedAt:    parse(row['completed_at']),
      cancelledAt:    parse(row['cancelled_at']),
      estimatedHours: (row['estimated_hours'] as num?)?.toDouble(),
      actualHours:    (row['actual_hours']    as num?)?.toDouble(),
      totalAmount:    (row['total_amount']    as num?)?.toDouble() ?? 0,
      paidToDate:     (row['paid_to_date']    as num?)?.toDouble() ?? 0,
      internalNotes:  row['internal_notes']  as String?,
      clientNotes:    row['client_notes']    as String?,
      kind:           (row['kind'] as String?) ?? 'materials',
      createdAt:      parse(row['created_at']) ?? DateTime.now(),
      updatedAt:      parse(row['updated_at']) ?? DateTime.now(),
      items:          items,
      signatures:     signatures,
    );
  }
}

/// Aggregate counts/amounts for a project, mirrored on
/// [SubcontractSummary] so the Materials, Rentals and Subcontracts boards
/// can render identical Committed / Paid / Remaining KPI strips.
///
/// - [totalCommitted] sums `total_amount` across every non-cancelled
///   record (active commitment to the budget).
/// - [totalPaid] sums `paid_to_date` across all records.
/// - [totalRemaining] = committed − paid.
class WorkOrderSummary {
  final int countTotal;
  final int countOpen;       // draft + issued + in_progress + on_hold
  final int countCompleted;
  final int countCancelled;
  final double totalCommitted;
  final double totalPaid;
  final double totalRemaining;

  const WorkOrderSummary({
    required this.countTotal,
    required this.countOpen,
    required this.countCompleted,
    required this.countCancelled,
    required this.totalCommitted,
    required this.totalPaid,
    required this.totalRemaining,
  });

  static const empty = WorkOrderSummary(
    countTotal: 0, countOpen: 0, countCompleted: 0, countCancelled: 0,
    totalCommitted: 0, totalPaid: 0, totalRemaining: 0,
  );
}
