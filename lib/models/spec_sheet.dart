class SpecSheet {
  final String id;
  final String workspaceId;
  final String projectId;
  final String title;
  final String fileAttachmentId;
  final List<String> itemIds;
  final int itemCount;
  final String? createdBy;
  final DateTime createdAt;

  // Joined from file_attachments when available.
  final String? fileName;
  final String? fileUrl;
  final int? fileSize;
  final String? mimeType;

  const SpecSheet({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.title,
    required this.fileAttachmentId,
    required this.itemIds,
    required this.itemCount,
    this.createdBy,
    required this.createdAt,
    this.fileName,
    this.fileUrl,
    this.fileSize,
    this.mimeType,
  });

  factory SpecSheet.fromMap(Map<String, dynamic> m) {
    final file = m['file_attachments'];
    Map<String, dynamic>? fileMap;
    if (file is Map) {
      fileMap = Map<String, dynamic>.from(file);
    } else if (file is List && file.isNotEmpty && file.first is Map) {
      fileMap = Map<String, dynamic>.from(file.first as Map);
    }
    return SpecSheet(
      id: m['id'] as String,
      workspaceId: m['workspace_id'] as String,
      projectId: m['project_id'] as String,
      title: m['title'] as String,
      fileAttachmentId: m['file_attachment_id'] as String,
      itemIds: (m['item_ids'] as List?)?.cast<String>() ?? const [],
      itemCount: (m['item_count'] as num?)?.toInt() ?? 0,
      createdBy: m['created_by'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      fileName: fileMap?['file_name'] as String?,
      fileUrl: fileMap?['file_url'] as String?,
      fileSize: (fileMap?['file_size'] as num?)?.toInt(),
      mimeType: fileMap?['mime_type'] as String?,
    );
  }
}
