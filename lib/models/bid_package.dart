/// Parent of one or more per-vendor Request-for-Bid generated_documents
/// that all quote the same scope. Drives the multi-vendor comparison /
/// award flow.
enum BidPackageStatus {
  draft,
  sent,
  awarded,
  expired,
  cancelled;

  String get displayName {
    switch (this) {
      case BidPackageStatus.draft:
        return 'Draft';
      case BidPackageStatus.sent:
        return 'Sent';
      case BidPackageStatus.awarded:
        return 'Awarded';
      case BidPackageStatus.expired:
        return 'Expired';
      case BidPackageStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get dbValue => name;

  static BidPackageStatus fromDbValue(String? value) {
    if (value == null) return BidPackageStatus.draft;
    return BidPackageStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BidPackageStatus.draft,
    );
  }
}

class BidPackage {
  final String id;
  final String workspaceId;
  final String? projectId;
  final String name;
  final String? scopeDescription;
  final DateTime? dueDate;
  final BidPackageStatus status;
  final String? awardedDocumentId;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  BidPackage({
    required this.id,
    required this.workspaceId,
    this.projectId,
    required this.name,
    this.scopeDescription,
    this.dueDate,
    required this.status,
    this.awardedDocumentId,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BidPackage.fromRow(Map<String, dynamic> row) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return BidPackage(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      projectId: row['project_id'] as String?,
      name: row['name'] as String,
      scopeDescription: row['scope_description'] as String?,
      dueDate: parseDate(row['due_date']),
      status: BidPackageStatus.fromDbValue(row['status'] as String?),
      awardedDocumentId: row['awarded_document_id'] as String?,
      createdBy: row['created_by'] as String?,
      createdAt: parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  bool get isTerminal =>
      status == BidPackageStatus.awarded ||
      status == BidPackageStatus.expired ||
      status == BidPackageStatus.cancelled;
}
