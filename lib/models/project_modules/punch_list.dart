import 'wire_parsing.dart';

class ProjectPunchList {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String? description;
  final String? location;
  final String status;
  final DateTime? dueDate;
  final int openCount;
  final int completedCount;
  final int totalItems;
  final DateTime createdAt;

  ProjectPunchList({
    required this.id, required this.workspaceId, required this.projectId,
    required this.name, this.description, this.location,
    this.status = 'open', this.dueDate,
    this.openCount = 0, this.completedCount = 0, this.totalItems = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ProjectPunchList.fromRow(Map<String, dynamic> r) => ProjectPunchList(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    projectId: r['project_id'] as String,
    name: r['name'] as String,
    description: r['description'] as String?,
    location: r['location'] as String?,
    status: (r['status'] as String?) ?? 'open',
    dueDate: parseDate(r['due_date']),
    openCount: (r['open_count'] as int?) ?? 0,
    completedCount: (r['completed_count'] as int?) ?? 0,
    totalItems: (r['total_items'] as int?) ?? 0,
    createdAt: parseDate(r['created_at']) ?? DateTime.now(),
  );

  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'project_id': projectId,
    'name': name,
    'description': description,
    'location': location,
    'status': status,
    'due_date': dueDate == null ? null : dateOnly(dueDate!),
  };

  double get completionPercent =>
    totalItems == 0 ? 0 : (completedCount / totalItems) * 100;
}

class ProjectPunchListItem {
  final String id;
  final String workspaceId;
  final String punchListId;
  final String title;
  final String? description;
  final String? locationDetail;
  final String? trade;
  final String priority;       // low|medium|high|critical
  final String? assigneeId;
  final String? assigneeName;
  final String? vendorId;
  final String status;         // open|in_progress|ready_review|completed|verified|wont_fix
  final String? photoUrl;
  final String? notes;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final int sortOrder;

  ProjectPunchListItem({
    required this.id, required this.workspaceId, required this.punchListId,
    required this.title, this.description, this.locationDetail, this.trade,
    this.priority = 'medium', this.assigneeId, this.assigneeName, this.vendorId,
    this.status = 'open', this.photoUrl, this.notes, this.dueDate,
    this.completedAt, this.completedBy, this.verifiedAt, this.verifiedBy,
    this.sortOrder = 0,
  });
  factory ProjectPunchListItem.fromRow(Map<String, dynamic> r) => ProjectPunchListItem(
    id: r['id'] as String,
    workspaceId: r['workspace_id'] as String,
    punchListId: r['punch_list_id'] as String,
    title: r['title'] as String,
    description: r['description'] as String?,
    locationDetail: r['location_detail'] as String?,
    trade: r['trade'] as String?,
    priority: (r['priority'] as String?) ?? 'medium',
    assigneeId: r['assignee_id'] as String?,
    assigneeName: r['assignee_name'] as String?,
    vendorId: r['vendor_id'] as String?,
    status: (r['status'] as String?) ?? 'open',
    photoUrl: r['photo_url'] as String?,
    notes: r['notes'] as String?,
    dueDate: parseDate(r['due_date']),
    completedAt: parseDate(r['completed_at']),
    completedBy: r['completed_by'] as String?,
    verifiedAt: parseDate(r['verified_at']),
    verifiedBy: r['verified_by'] as String?,
    sortOrder: (r['sort_order'] as int?) ?? 0,
  );
  Map<String, dynamic> toInsert() => {
    'workspace_id': workspaceId,
    'punch_list_id': punchListId,
    'title': title,
    'description': description,
    'location_detail': locationDetail,
    'trade': trade,
    'priority': priority,
    'assignee_id': assigneeId,
    'assignee_name': assigneeName,
    'vendor_id': vendorId,
    'status': status,
    'photo_url': photoUrl,
    'notes': notes,
    'due_date': dueDate == null ? null : dateOnly(dueDate!),
    'sort_order': sortOrder,
  };
}
