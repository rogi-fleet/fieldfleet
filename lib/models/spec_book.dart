enum SpecBookStatus { draft, issued, signed, superseded }

extension SpecBookStatusX on SpecBookStatus {
  String get dbValue => name;
  String get label {
    switch (this) {
      case SpecBookStatus.draft:
        return 'Draft';
      case SpecBookStatus.issued:
        return 'Issued';
      case SpecBookStatus.signed:
        return 'Signed';
      case SpecBookStatus.superseded:
        return 'Superseded';
    }
  }

  bool get isLocked =>
      this == SpecBookStatus.signed || this == SpecBookStatus.superseded;

  static SpecBookStatus parse(String? v) {
    return SpecBookStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => SpecBookStatus.draft,
    );
  }
}

class SpecBook {
  final String id;
  final String workspaceId;
  final String projectId;
  final String title;
  final String? description;
  final int version;
  final SpecBookStatus status;
  final String? previousBookId;
  final DateTime? issuedAt;
  final DateTime? signedAt;
  final DateTime? supersededAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SpecBook({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.title,
    this.description,
    required this.version,
    required this.status,
    this.previousBookId,
    this.issuedAt,
    this.signedAt,
    this.supersededAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SpecBook.fromMap(Map<String, dynamic> m) => SpecBook(
        id: m['id'] as String,
        workspaceId: m['workspace_id'] as String,
        projectId: m['project_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        version: (m['version'] as num).toInt(),
        status: SpecBookStatusX.parse(m['status'] as String?),
        previousBookId: m['previous_book_id'] as String?,
        issuedAt: _ts(m['issued_at']),
        signedAt: _ts(m['signed_at']),
        supersededAt: _ts(m['superseded_at']),
        createdBy: m['created_by'] as String?,
        createdAt: _ts(m['created_at']) ?? DateTime.now(),
        updatedAt: _ts(m['updated_at']) ?? DateTime.now(),
      );

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);
}
