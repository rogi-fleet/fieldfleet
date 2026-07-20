import 'wire_parsing.dart';

class ProjectInspection {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String inspectionType;
  final String? location;
  final DateTime? scheduledFor;
  final DateTime? performedAt;
  final String? performedBy;
  final String? inspectorName;
  final String? inspectorCompany;
  final String status;
  final int passCount;
  final int failCount;
  final int totalItems;
  final double? score;
  final String? notes;
  final String? signatureUrl;
  final String? reportUrl;
  final DateTime createdAt;

  ProjectInspection({
    required this.id, required this.workspaceId, required this.projectId,
    required this.name, this.inspectionType = 'quality',
    this.location, this.scheduledFor, this.performedAt,
    this.performedBy, this.inspectorName, this.inspectorCompany,
    this.status = 'scheduled',
    this.passCount = 0, this.failCount = 0, this.totalItems = 0,
    this.score, this.notes, this.signatureUrl, this.reportUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ProjectInspection.fromRow(Map<String, dynamic> r) => ProjectInspection(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    projectId: r['project_id'] as String,
    name: r['name'] as String,
    inspectionType: (r['inspection_type'] as String?) ?? 'quality',
    location: r['location'] as String?,
    scheduledFor: parseDate(r['scheduled_for']),
    performedAt: parseDate(r['performed_at']),
    performedBy: r['performed_by'] as String?,
    inspectorName: r['inspector_name'] as String?,
    inspectorCompany: r['inspector_company'] as String?,
    status: (r['status'] as String?) ?? 'scheduled',
    passCount: (r['pass_count'] as int?) ?? 0,
    failCount: (r['fail_count'] as int?) ?? 0,
    totalItems: (r['total_items'] as int?) ?? 0,
    score: r['score'] == null ? null : parseNum(r['score']),
    notes: r['notes'] as String?,
    signatureUrl: r['signature_url'] as String?,
    reportUrl: r['report_url'] as String?,
    createdAt: parseDate(r['created_at']) ?? DateTime.now(),
  );

  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'project_id': projectId,
    'name': name,
    'inspection_type': inspectionType,
    'location': location,
    'scheduled_for': scheduledFor?.toIso8601String(),
    'performed_at': performedAt?.toIso8601String(),
    'performed_by': performedBy,
    'inspector_name': inspectorName,
    'inspector_company': inspectorCompany,
    'status': status,
    'notes': notes,
    'signature_url': signatureUrl,
    'report_url': reportUrl,
  };
}

class ProjectInspectionItem {
  final String id;
  final String workspaceId;
  final String inspectionId;
  final String? category;
  final String label;
  final String? description;
  final String result;     // pass|fail|na|pending
  final String? notes;
  final String? photoUrl;
  final int sortOrder;
  ProjectInspectionItem({
    required this.id, required this.workspaceId, required this.inspectionId,
    this.category, required this.label, this.description,
    this.result = 'pending', this.notes, this.photoUrl, this.sortOrder = 0,
  });
  factory ProjectInspectionItem.fromRow(Map<String, dynamic> r) => ProjectInspectionItem(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    inspectionId: r['inspection_id'] as String,
    category: r['category'] as String?,
    label: r['label'] as String,
    description: r['description'] as String?,
    result: (r['result'] as String?) ?? 'pending',
    notes: r['notes'] as String?,
    photoUrl: r['photo_url'] as String?,
    sortOrder: (r['sort_order'] as int?) ?? 0,
  );
  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'inspection_id': inspectionId,
    'category': category,
    'label': label,
    'description': description,
    'result': result,
    'notes': notes,
    'photo_url': photoUrl,
    'sort_order': sortOrder,
  };
}
