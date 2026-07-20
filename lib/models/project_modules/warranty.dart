import 'wire_parsing.dart';

class ProjectWarranty {
  final String id;
  final String workspaceId;
  final String projectId;
  final String title;
  final String warrantyType;
  final String? providerName;
  final String? providerVendorId;
  final String? beneficiary;
  final String? description;
  final String? terms;
  final double? coverageAmount;
  final String currency;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? referenceNo;
  final String? documentUrl;
  final String status;
  final int claimCount;
  final String? notes;
  final DateTime createdAt;

  ProjectWarranty({
    required this.id, required this.workspaceId, required this.projectId,
    required this.title, this.warrantyType = 'workmanship',
    this.providerName, this.providerVendorId, this.beneficiary,
    this.description, this.terms, this.coverageAmount, this.currency = 'USD',
    this.startsOn, this.endsOn, this.referenceNo, this.documentUrl,
    this.status = 'active', this.claimCount = 0, this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ProjectWarranty.fromRow(Map<String, dynamic> r) => ProjectWarranty(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    projectId: r['project_id'] as String,
    title: r['title'] as String,
    warrantyType: (r['warranty_type'] as String?) ?? 'workmanship',
    providerName: r['provider_name'] as String?,
    providerVendorId: r['provider_vendor_id'] as String?,
    beneficiary: r['beneficiary'] as String?,
    description: r['description'] as String?,
    terms: r['terms'] as String?,
    coverageAmount: r['coverage_amount'] == null ? null : parseNum(r['coverage_amount']),
    currency: (r['currency'] as String?) ?? 'USD',
    startsOn: parseDate(r['starts_on']),
    endsOn: parseDate(r['ends_on']),
    referenceNo: r['reference_no'] as String?,
    documentUrl: r['document_url'] as String?,
    status: (r['status'] as String?) ?? 'active',
    claimCount: (r['claim_count'] as int?) ?? 0,
    notes: r['notes'] as String?,
    createdAt: parseDate(r['created_at']) ?? DateTime.now(),
  );

  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'project_id': projectId,
    'title': title,
    'warranty_type': warrantyType,
    'provider_name': providerName,
    'provider_vendor_id': providerVendorId,
    'beneficiary': beneficiary,
    'description': description,
    'terms': terms,
    'coverage_amount': coverageAmount,
    'currency': currency,
    'starts_on': startsOn == null ? null : dateOnly(startsOn!),
    'ends_on': endsOn == null ? null : dateOnly(endsOn!),
    'reference_no': referenceNo,
    'document_url': documentUrl,
    'status': status,
    'notes': notes,
  };

  bool get isExpired =>
    endsOn != null && endsOn!.isBefore(DateTime.now());
  int? get daysRemaining {
    if (endsOn == null) return null;
    return endsOn!.difference(DateTime.now()).inDays;
  }
}

class ProjectWarrantyClaim {
  final String id;
  final String workspaceId;
  final String warrantyId;
  final DateTime claimDate;
  final String description;
  final String? resolution;
  final String status;
  final DateTime? resolvedAt;
  final double? cost;
  ProjectWarrantyClaim({
    required this.id, required this.workspaceId, required this.warrantyId,
    required this.claimDate, required this.description, this.resolution,
    this.status = 'open', this.resolvedAt, this.cost,
  });
  factory ProjectWarrantyClaim.fromRow(Map<String, dynamic> r) => ProjectWarrantyClaim(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    warrantyId: r['warranty_id'] as String,
    claimDate: parseDate(r['claim_date']) ?? DateTime.now(),
    description: r['description'] as String,
    resolution: r['resolution'] as String?,
    status: (r['status'] as String?) ?? 'open',
    resolvedAt: parseDate(r['resolved_at']),
    cost: r['cost'] == null ? null : parseNum(r['cost']),
  );
  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'warranty_id': warrantyId,
    'claim_date': dateOnly(claimDate),
    'description': description,
    'resolution': resolution,
    'status': status,
    'resolved_at': resolvedAt == null ? null : dateOnly(resolvedAt!),
    'cost': cost,
  };
}
