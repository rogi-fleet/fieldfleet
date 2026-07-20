import 'pay_app_line.dart';

enum PayApplicationStatus {
  draft,
  submitted,
  certified,
  paid;

  String get displayLabel {
    switch (this) {
      case PayApplicationStatus.draft:
        return 'Draft';
      case PayApplicationStatus.submitted:
        return 'Submitted';
      case PayApplicationStatus.certified:
        return 'Certified';
      case PayApplicationStatus.paid:
        return 'Paid';
    }
  }

  static PayApplicationStatus fromString(String? value) {
    switch (value) {
      case 'submitted':
        return PayApplicationStatus.submitted;
      case 'certified':
        return PayApplicationStatus.certified;
      case 'paid':
        return PayApplicationStatus.paid;
      default:
        return PayApplicationStatus.draft;
    }
  }

  String get dbValue => name;
}

/// AIA G702 — Application and Certificate for Payment.
/// Header-level record. G703 line items live in [PayAppLine].
class PayApplication {
  final String id;
  final String workspaceId;
  final String projectId;

  final int applicationNumber;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final DateTime? dateIssued;
  final DateTime? contractDate;
  final String? contractFor;

  final String? contractorName;
  final String? contractorAddress;
  final String? ownerName;
  final String? ownerAddress;
  final String? architectName;
  final String? architectProjectNo;

  final double originalContractSum;
  final double netChangeByChangeOrders;

  /// Retainage percentage applied to completed work (typically 10%).
  final double retainagePctCompleted;

  /// Retainage percentage applied to stored materials.
  final double retainagePctStored;

  /// G702 line 7: cumulative "Less Previous Certificates for Payment".
  /// Persisted on the header (NOT derived from lines) because once a prior
  /// application is rolled over, its retainage breakdown is lost. Set during
  /// rollover to: (prior.previousCertificatesTotal + prior.currentPaymentDue).
  final double previousCertificatesTotal;

  /// Snapshot of [currentPaymentDue] persisted on save so list views don't
  /// have to load every application's lines.
  final double? currentPaymentDueSnapshot;
  final double? totalCompletedStoredSnapshot;
  final double? totalRetainageSnapshot;

  final PayApplicationStatus status;
  final double? certifiedAmount;
  final String? certifiedBy;
  final DateTime? certifiedAt;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Lines are loaded separately by the service but bundled here for convenience.
  final List<PayAppLine> lines;

  const PayApplication({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.applicationNumber,
    this.periodFrom,
    this.periodTo,
    this.dateIssued,
    this.contractDate,
    this.contractFor,
    this.contractorName,
    this.contractorAddress,
    this.ownerName,
    this.ownerAddress,
    this.architectName,
    this.architectProjectNo,
    this.originalContractSum = 0,
    this.netChangeByChangeOrders = 0,
    this.retainagePctCompleted = 10,
    this.retainagePctStored = 10,
    this.previousCertificatesTotal = 0,
    this.currentPaymentDueSnapshot,
    this.totalCompletedStoredSnapshot,
    this.totalRetainageSnapshot,
    this.status = PayApplicationStatus.draft,
    this.certifiedAmount,
    this.certifiedBy,
    this.certifiedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.lines = const [],
  });

  // ── Derived G702 totals ─────────────────────────────────────────────
  double get contractSumToDate =>
      originalContractSum + netChangeByChangeOrders;

  double get totalCompletedAndStored =>
      lines.fold(0.0, (s, l) => s + l.totalCompletedAndStored);

  double get totalRetainage {
    return lines.fold(0.0, (s, l) {
      if (l.retainageOverride != null) return s + l.retainageOverride!;
      final completedRet =
          (l.workCompletedPrevious + l.workCompletedThisPeriod) *
              (retainagePctCompleted / 100.0);
      final storedRet = l.materialsStored * (retainagePctStored / 100.0);
      return s + completedRet + storedRet;
    });
  }

  double get totalEarnedLessRetainage =>
      totalCompletedAndStored - totalRetainage;

  /// G702 line 7 — cumulative prior certified amounts. Uses the header-level
  /// rollover total, NOT line data (which doesn't carry retainage history).
  double get lessPreviousCertificates => previousCertificatesTotal;

  double get currentPaymentDue =>
      totalEarnedLessRetainage - lessPreviousCertificates;

  double get balanceToFinish =>
      contractSumToDate - totalEarnedLessRetainage;

  PayApplication copyWith({
    int? applicationNumber,
    DateTime? periodFrom,
    DateTime? periodTo,
    DateTime? dateIssued,
    DateTime? contractDate,
    String? contractFor,
    String? contractorName,
    String? contractorAddress,
    String? ownerName,
    String? ownerAddress,
    String? architectName,
    String? architectProjectNo,
    double? originalContractSum,
    double? netChangeByChangeOrders,
    double? retainagePctCompleted,
    double? retainagePctStored,
    double? previousCertificatesTotal,
    double? currentPaymentDueSnapshot,
    double? totalCompletedStoredSnapshot,
    double? totalRetainageSnapshot,
    PayApplicationStatus? status,
    double? certifiedAmount,
    String? certifiedBy,
    DateTime? certifiedAt,
    String? notes,
    DateTime? updatedAt,
    List<PayAppLine>? lines,
    String? id,
  }) {
    return PayApplication(
      id: id ?? this.id,
      workspaceId: workspaceId,
      projectId: projectId,
      applicationNumber: applicationNumber ?? this.applicationNumber,
      periodFrom: periodFrom ?? this.periodFrom,
      periodTo: periodTo ?? this.periodTo,
      dateIssued: dateIssued ?? this.dateIssued,
      contractDate: contractDate ?? this.contractDate,
      contractFor: contractFor ?? this.contractFor,
      contractorName: contractorName ?? this.contractorName,
      contractorAddress: contractorAddress ?? this.contractorAddress,
      ownerName: ownerName ?? this.ownerName,
      ownerAddress: ownerAddress ?? this.ownerAddress,
      architectName: architectName ?? this.architectName,
      architectProjectNo: architectProjectNo ?? this.architectProjectNo,
      originalContractSum: originalContractSum ?? this.originalContractSum,
      netChangeByChangeOrders:
          netChangeByChangeOrders ?? this.netChangeByChangeOrders,
      retainagePctCompleted:
          retainagePctCompleted ?? this.retainagePctCompleted,
      retainagePctStored: retainagePctStored ?? this.retainagePctStored,
      previousCertificatesTotal:
          previousCertificatesTotal ?? this.previousCertificatesTotal,
      currentPaymentDueSnapshot:
          currentPaymentDueSnapshot ?? this.currentPaymentDueSnapshot,
      totalCompletedStoredSnapshot:
          totalCompletedStoredSnapshot ?? this.totalCompletedStoredSnapshot,
      totalRetainageSnapshot:
          totalRetainageSnapshot ?? this.totalRetainageSnapshot,
      status: status ?? this.status,
      certifiedAmount: certifiedAmount ?? this.certifiedAmount,
      certifiedBy: certifiedBy ?? this.certifiedBy,
      certifiedAt: certifiedAt ?? this.certifiedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lines: lines ?? this.lines,
    );
  }

  Map<String, dynamic> toDb() => {
        'workspace_id': workspaceId,
        'project_id': projectId,
        'application_number': applicationNumber,
        'period_from': periodFrom?.toIso8601String(),
        'period_to': periodTo?.toIso8601String(),
        'date_issued': dateIssued?.toIso8601String(),
        'contract_date': contractDate?.toIso8601String(),
        'contract_for': contractFor,
        'contractor_name': contractorName,
        'contractor_address': contractorAddress,
        'owner_name': ownerName,
        'owner_address': ownerAddress,
        'architect_name': architectName,
        'architect_project_no': architectProjectNo,
        'original_contract_sum': originalContractSum,
        'net_change_by_change_orders': netChangeByChangeOrders,
        'retainage_pct_completed': retainagePctCompleted,
        'retainage_pct_stored': retainagePctStored,
        'previous_certificates_total': previousCertificatesTotal,
        'current_payment_due_snapshot': currentPaymentDueSnapshot,
        'total_completed_stored_snapshot': totalCompletedStoredSnapshot,
        'total_retainage_snapshot': totalRetainageSnapshot,
        'status': status.dbValue,
        'certified_amount': certifiedAmount,
        'certified_by': certifiedBy,
        'certified_at': certifiedAt?.toIso8601String(),
        'notes': notes,
      };

  static PayApplication fromDb(
    Map<String, dynamic> row, {
    List<PayAppLine> lines = const [],
  }) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.parse(v as String);
    double toDouble(dynamic v) =>
        v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);

    return PayApplication(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String,
      applicationNumber: (row['application_number'] as num).toInt(),
      periodFrom: parseDate(row['period_from']),
      periodTo: parseDate(row['period_to']),
      dateIssued: parseDate(row['date_issued']),
      contractDate: parseDate(row['contract_date']),
      contractFor: row['contract_for'] as String?,
      contractorName: row['contractor_name'] as String?,
      contractorAddress: row['contractor_address'] as String?,
      ownerName: row['owner_name'] as String?,
      ownerAddress: row['owner_address'] as String?,
      architectName: row['architect_name'] as String?,
      architectProjectNo: row['architect_project_no'] as String?,
      originalContractSum: toDouble(row['original_contract_sum']),
      netChangeByChangeOrders: toDouble(row['net_change_by_change_orders']),
      retainagePctCompleted: toDouble(row['retainage_pct_completed']),
      retainagePctStored: toDouble(row['retainage_pct_stored']),
      previousCertificatesTotal:
          toDouble(row['previous_certificates_total']),
      currentPaymentDueSnapshot: row['current_payment_due_snapshot'] == null
          ? null
          : toDouble(row['current_payment_due_snapshot']),
      totalCompletedStoredSnapshot:
          row['total_completed_stored_snapshot'] == null
              ? null
              : toDouble(row['total_completed_stored_snapshot']),
      totalRetainageSnapshot: row['total_retainage_snapshot'] == null
          ? null
          : toDouble(row['total_retainage_snapshot']),
      status: PayApplicationStatus.fromString(row['status'] as String?),
      certifiedAmount: row['certified_amount'] == null
          ? null
          : toDouble(row['certified_amount']),
      certifiedBy: row['certified_by'] as String?,
      certifiedAt: parseDate(row['certified_at']),
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lines: lines,
    );
  }
}
