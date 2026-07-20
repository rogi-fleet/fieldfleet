/// One comment in a file's discussion thread.
///
/// Mirrors the [TaskComment] shape. One level of nesting via
/// [parentCommentId] — replies attach to a top-level comment, replies of
/// replies are flattened up to the same parent.
class FileComment {
  final String id;
  final String workspaceId;
  final String fileAttachmentId;
  final String? parentCommentId;
  final String authorId;
  final String body;
  final List<String> mentionedUserIds;
  final List<String> attachmentIds;
  final DateTime? editedAt;
  final DateTime createdAt;

  const FileComment({
    required this.id,
    required this.workspaceId,
    required this.fileAttachmentId,
    this.parentCommentId,
    required this.authorId,
    required this.body,
    this.mentionedUserIds = const [],
    this.attachmentIds = const [],
    this.editedAt,
    required this.createdAt,
  });

  bool get isReply => parentCommentId != null;
  bool get wasEdited => editedAt != null;

  factory FileComment.fromSupabase(Map<String, dynamic> json) {
    return FileComment(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      fileAttachmentId: json['file_attachment_id'] as String,
      parentCommentId: json['parent_comment_id'] as String?,
      authorId: json['author_id'] as String,
      body: json['body'] as String? ?? '',
      mentionedUserIds:
          (json['mentioned_user_ids'] as List?)?.cast<String>() ??
              const <String>[],
      attachmentIds:
          (json['attachment_ids'] as List?)?.cast<String>() ??
              const <String>[],
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.parse(json['edited_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
