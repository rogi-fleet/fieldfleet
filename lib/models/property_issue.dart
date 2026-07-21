/// A maintenance/support issue reported against a single property, either by
/// a unit holder through the client portal or by staff internally. Shared
/// between the portal Issues tab and the staff-side Issues tab.
class PropertyIssue {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? reporterName;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const PropertyIssue({
    required this.id,
    required this.title,
    this.description,
    this.status = 'open',
    this.priority = 'normal',
    this.reporterName,
    required this.createdAt,
    this.resolvedAt,
  });

  factory PropertyIssue.fromRow(Map<String, dynamic> row) {
    return PropertyIssue(
      id: row['id'] as String,
      title: (row['title'] ?? '') as String,
      description: row['description'] as String?,
      status: (row['status'] as String?) ?? 'open',
      priority: (row['priority'] as String?) ?? 'normal',
      reporterName: row['reporter_name'] as String?,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      resolvedAt: row['resolved_at'] != null
          ? DateTime.tryParse(row['resolved_at'].toString())?.toLocal()
          : null,
    );
  }

  bool get isResolved => status == 'resolved' || status == 'closed';
}
