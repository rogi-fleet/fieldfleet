import 'package:cloud_firestore/cloud_firestore.dart';
import 'file_tag.dart';
import 'message_attachment.dart';

class FileAttachment {
  final String id;
  final String workspaceId;
  final String projectId;
  final String? taskId;
  final String? messageId;
  final String? folderId;

  /// Legacy tag names stored in `file_attachments.tags TEXT[]`. Kept for
  /// backwards compatibility while the new [FileTag] join is backfilled; once
  /// the column is dropped in a follow-up migration, this will read empty.
  final List<String> tags;

  /// Tags resolved via the `file_attachment_tags` join. When non-empty this
  /// is the authoritative source; callers that only need names may fall back
  /// to [tags] for pre-migration rows.
  final List<FileTag> resolvedTags;

  final String? title;
  final String? description;
  final String fileName;
  final String fileUrl;
  final int fileSize; // in bytes
  final String mimeType;
  final String uploadedBy;
  final DateTime uploadedAt;
  final String? thumbnailUrl;

  FileAttachment({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    this.taskId,
    this.messageId,
    this.folderId,
    this.tags = const [],
    this.resolvedTags = const [],
    this.title,
    this.description,
    required this.fileName,
    required this.fileUrl,
    required this.fileSize,
    required this.mimeType,
    required this.uploadedBy,
    required this.uploadedAt,
    this.thumbnailUrl,
  });

  // Create from Firestore JSON (legacy — only the deprecated Firebase
  // storage_service.dart still calls this).
  factory FileAttachment.fromJson(Map<String, dynamic> json, String id) {
    return FileAttachment(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      taskId: json['taskId'] as String?,
      messageId: json['messageId'] as String?,
      folderId: json['folderId'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      title: json['title'] as String?,
      description: json['description'] as String?,
      fileName: json['fileName'] as String,
      fileUrl: json['fileUrl'] as String,
      fileSize: json['fileSize'] as int,
      mimeType: json['mimeType'] as String,
      uploadedBy: json['uploadedBy'] as String,
      uploadedAt: (json['uploadedAt'] as Timestamp).toDate(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  // Convert to Firestore JSON (legacy)
  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'taskId': taskId,
      'messageId': messageId,
      'folderId': folderId,
      'tags': tags,
      'title': title,
      'description': description,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'uploadedBy': uploadedBy,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'thumbnailUrl': thumbnailUrl,
    };
  }

  /// Prefer [resolvedTags] names, fall back to legacy [tags] for rows that
  /// haven't been backfilled yet. Useful for any caller that only needs to
  /// render chip labels and doesn't care about color.
  List<String> get effectiveTagNames => resolvedTags.isNotEmpty
      ? resolvedTags.map((t) => t.name).toList()
      : displayLegacyTags;

  /// Subset of legacy [tags] safe to surface in user-facing chip lists. The
  /// `property:<uuid>` family of tags are internal markers attached by
  /// property/area widgets to associate files with a property row — they leak
  /// into the chip column as raw `property:UUID` text without this filter.
  List<String> get displayLegacyTags =>
      tags.where((t) => !_isSystemTag(t)).toList();

  static bool _isSystemTag(String tag) => tag.startsWith('property:');

  // Helper methods for file type detection
  bool get isImage {
    return mimeType.startsWith('image/');
  }

  bool get isPDF {
    return mimeType == 'application/pdf';
  }

  bool get isDocument {
    return mimeType.contains('document') ||
        mimeType.contains('word') ||
        mimeType.contains('excel') ||
        mimeType.contains('spreadsheet') ||
        mimeType.contains('text');
  }

  // Format file size for display
  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  // Get file extension from filename
  String get fileExtension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : 'FILE';
  }

  /// Convert to a [MessageAttachment] for use in the messaging system.
  MessageAttachment toMessageAttachment() {
    return MessageAttachment(
      id: id,
      fileName: fileName,
      fileUrl: fileUrl,
      fileSize: fileSize,
      mimeType: mimeType,
      thumbnailUrl: thumbnailUrl,
    );
  }

  FileAttachment copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? Function()? taskId,
    String? Function()? messageId,
    String? Function()? folderId,
    List<String>? tags,
    List<FileTag>? resolvedTags,
    String? Function()? title,
    String? Function()? description,
    String? fileName,
    String? fileUrl,
    int? fileSize,
    String? mimeType,
    String? uploadedBy,
    DateTime? uploadedAt,
    String? Function()? thumbnailUrl,
  }) {
    return FileAttachment(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      taskId: taskId != null ? taskId() : this.taskId,
      messageId: messageId != null ? messageId() : this.messageId,
      folderId: folderId != null ? folderId() : this.folderId,
      tags: tags ?? this.tags,
      resolvedTags: resolvedTags ?? this.resolvedTags,
      title: title != null ? title() : this.title,
      description: description != null ? description() : this.description,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      thumbnailUrl: thumbnailUrl != null ? thumbnailUrl() : this.thumbnailUrl,
    );
  }
}
