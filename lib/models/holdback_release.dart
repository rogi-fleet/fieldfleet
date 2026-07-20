import 'package:intl/intl.dart';

/// Status of a [HoldbackRelease].
enum HoldbackReleaseStatus {
  draft,
  issued,
  paid;

  String get dbValue => name;

  String get displayLabel {
    switch (this) {
      case HoldbackReleaseStatus.draft:
        return 'Draft';
      case HoldbackReleaseStatus.issued:
        return 'Issued';
      case HoldbackReleaseStatus.paid:
        return 'Paid';
    }
  }

  static HoldbackReleaseStatus fromDb(String? value) {
    switch (value) {
      case 'issued':
        return HoldbackReleaseStatus.issued;
      case 'paid':
        return HoldbackReleaseStatus.paid;
      default:
        return HoldbackReleaseStatus.draft;
    }
  }
}

/// A single line on a holdback release — represents one source of retainage
/// being released. Either [sourceInvoiceId] or [sourceBudgetItemId] is set.
class HoldbackReleaseLine {
  final String? id;
  final String workspaceId;
  final String? sourceInvoiceId;
  final String? sourceBudgetItemId;
  final String description;
  final double amountHeld;
  final double amountReleased;
  final int sortOrder;

  const HoldbackReleaseLine({
    this.id,
    required this.workspaceId,
    this.sourceInvoiceId,
    this.sourceBudgetItemId,
    required this.description,
    required this.amountHeld,
    required this.amountReleased,
    this.sortOrder = 0,
  });

  HoldbackReleaseLine copyWith({
    String? description,
    double? amountReleased,
    int? sortOrder,
  }) {
    return HoldbackReleaseLine(
      id: id,
      workspaceId: workspaceId,
      sourceInvoiceId: sourceInvoiceId,
      sourceBudgetItemId: sourceBudgetItemId,
      description: description ?? this.description,
      amountHeld: amountHeld,
      amountReleased: amountReleased ?? this.amountReleased,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toDb({required String releaseId}) {
    return {
      if (id != null) 'id': id,
      'release_id': releaseId,
      'workspace_id': workspaceId,
      'source_invoice_id': sourceInvoiceId,
      'source_budget_item_id': sourceBudgetItemId,
      'description': description,
      'amount_held': amountHeld,
      'amount_released': amountReleased,
      'sort_order': sortOrder,
    };
  }

  static HoldbackReleaseLine fromDb(Map<String, dynamic> row) {
    double toD(dynamic v) =>
        v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
    return HoldbackReleaseLine(
      id: row['id'] as String?,
      workspaceId: row['workspace_id'] as String,
      sourceInvoiceId: row['source_invoice_id'] as String?,
      sourceBudgetItemId: row['source_budget_item_id'] as String?,
      description: (row['description'] as String?) ?? '',
      amountHeld: toD(row['amount_held']),
      amountReleased: toD(row['amount_released']),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Header for a holdback release event. One release covers multiple held
/// invoices / budget items being released to the customer in a single
/// statement.
class HoldbackRelease {
  final String id;
  final String workspaceId;
  final String projectId;
  final int releaseNumber;
  final DateTime releaseDate;
  final HoldbackReleaseStatus status;
  final double totalAmount;
  final String? notes;
  final String? documentId;
  final DateTime? issuedAt;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final List<HoldbackReleaseLine> lines;

  // Display-only, hydrated by the service when needed.
  final String? projectName;
  final String? customerName;

  const HoldbackRelease({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.releaseNumber,
    required this.releaseDate,
    required this.status,
    required this.totalAmount,
    this.notes,
    this.documentId,
    this.issuedAt,
    this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.lines = const [],
    this.projectName,
    this.customerName,
  });

  HoldbackRelease copyWith({
    int? releaseNumber,
    DateTime? releaseDate,
    HoldbackReleaseStatus? status,
    double? totalAmount,
    String? notes,
    String? documentId,
    DateTime? issuedAt,
    DateTime? paidAt,
    List<HoldbackReleaseLine>? lines,
    String? projectName,
    String? customerName,
  }) {
    return HoldbackRelease(
      id: id,
      workspaceId: workspaceId,
      projectId: projectId,
      releaseNumber: releaseNumber ?? this.releaseNumber,
      releaseDate: releaseDate ?? this.releaseDate,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
      documentId: documentId ?? this.documentId,
      issuedAt: issuedAt ?? this.issuedAt,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      lines: lines ?? this.lines,
      projectName: projectName ?? this.projectName,
      customerName: customerName ?? this.customerName,
    );
  }

  Map<String, dynamic> toDbHeader() {
    final df = DateFormat('yyyy-MM-dd');
    return {
      'workspace_id': workspaceId,
      'project_id': projectId,
      'release_number': releaseNumber,
      'release_date': df.format(releaseDate),
      'status': status.dbValue,
      'total_amount': totalAmount,
      'notes': notes,
      'document_id': documentId,
      'created_by': createdBy,
    };
  }

  static HoldbackRelease fromDb(
    Map<String, dynamic> row, {
    List<HoldbackReleaseLine> lines = const [],
    String? projectName,
    String? customerName,
  }) {
    double toD(dynamic v) =>
        v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
    DateTime toDt(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) return DateTime.parse(v);
      return DateTime.now();
    }
    DateTime? toDtN(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return HoldbackRelease(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String,
      releaseNumber: (row['release_number'] as num).toInt(),
      releaseDate: toDt(row['release_date']),
      status: HoldbackReleaseStatus.fromDb(row['status'] as String?),
      totalAmount: toD(row['total_amount']),
      notes: row['notes'] as String?,
      documentId: row['document_id'] as String?,
      issuedAt: toDtN(row['issued_at']),
      paidAt: toDtN(row['paid_at']),
      createdAt: toDt(row['created_at']),
      updatedAt: toDt(row['updated_at']),
      createdBy: row['created_by'] as String?,
      lines: lines,
      projectName: projectName,
      customerName: customerName,
    );
  }
}

/// One outstanding-retainage row aggregated from `generated_documents`. Used
/// as the candidate-pool when building a new [HoldbackRelease].
class OutstandingRetainage {
  final String invoiceId;
  final String? documentNumber;
  final DateTime createdAt;
  final double invoiceTotal;
  final double retainagePercent;
  final double retainageAmount;
  final String? customerName;

  const OutstandingRetainage({
    required this.invoiceId,
    this.documentNumber,
    required this.createdAt,
    required this.invoiceTotal,
    required this.retainagePercent,
    required this.retainageAmount,
    this.customerName,
  });
}
