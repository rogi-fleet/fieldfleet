/// A single entry in a file's audit trail.
///
/// Rows land in `file_events` via the `record_file_event` RPC; clients only
/// read (RLS + SECURITY DEFINER keeps history honest). The action names
/// here mirror the enum accepted by the RPC.
class FileEvent {
  final String id;
  final String workspaceId;

  /// Null when the referenced file has been deleted. File_events are
  /// preserved with ON DELETE SET NULL so workspace-level audits retain
  /// a record of deletions even after the file is gone.
  final String? fileAttachmentId;

  final String? actorId;
  final FileEventAction action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const FileEvent({
    required this.id,
    required this.workspaceId,
    required this.fileAttachmentId,
    this.actorId,
    required this.action,
    required this.payload,
    required this.createdAt,
  });

  factory FileEvent.fromSupabase(Map<String, dynamic> json) {
    final raw = json['payload'];
    return FileEvent(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      fileAttachmentId: json['file_attachment_id'] as String?,
      actorId: json['actor_id'] as String?,
      action: FileEventAction.fromWire(json['action'] as String),
      payload: raw is Map<String, dynamic>
          ? raw
          : (raw is Map ? Map<String, dynamic>.from(raw) : const {}),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Which file event this row represents. Values match the string enum in
/// `record_file_event`. `unknown` is a forward-compat fallback so new
/// action names added server-side don't break older clients.
enum FileEventAction {
  uploaded,
  renamed,
  described,
  moved,
  taggedAdded,
  taggedRemoved,
  deleted,
  commented,
  markedUp,
  revertedMarkup,
  shared,
  downloaded,
  unknown;

  String get wire {
    switch (this) {
      case FileEventAction.uploaded:
        return 'uploaded';
      case FileEventAction.renamed:
        return 'renamed';
      case FileEventAction.described:
        return 'described';
      case FileEventAction.moved:
        return 'moved';
      case FileEventAction.taggedAdded:
        return 'tagged_added';
      case FileEventAction.taggedRemoved:
        return 'tagged_removed';
      case FileEventAction.deleted:
        return 'deleted';
      case FileEventAction.commented:
        return 'commented';
      case FileEventAction.markedUp:
        return 'marked_up';
      case FileEventAction.revertedMarkup:
        return 'reverted_markup';
      case FileEventAction.shared:
        return 'shared';
      case FileEventAction.downloaded:
        return 'downloaded';
      case FileEventAction.unknown:
        return 'unknown';
    }
  }

  static FileEventAction fromWire(String s) {
    switch (s) {
      case 'uploaded':
        return FileEventAction.uploaded;
      case 'renamed':
        return FileEventAction.renamed;
      case 'described':
        return FileEventAction.described;
      case 'moved':
        return FileEventAction.moved;
      case 'tagged_added':
        return FileEventAction.taggedAdded;
      case 'tagged_removed':
        return FileEventAction.taggedRemoved;
      case 'deleted':
        return FileEventAction.deleted;
      case 'commented':
        return FileEventAction.commented;
      case 'marked_up':
        return FileEventAction.markedUp;
      case 'reverted_markup':
        return FileEventAction.revertedMarkup;
      case 'shared':
        return FileEventAction.shared;
      case 'downloaded':
        return FileEventAction.downloaded;
      default:
        return FileEventAction.unknown;
    }
  }

  /// Grouping for the filter chips in [FileActivityFeed].
  FileEventCategory get category {
    switch (this) {
      case FileEventAction.uploaded:
      case FileEventAction.renamed:
      case FileEventAction.described:
      case FileEventAction.moved:
      case FileEventAction.taggedAdded:
      case FileEventAction.taggedRemoved:
      case FileEventAction.deleted:
        return FileEventCategory.uploadsAndEdits;
      case FileEventAction.commented:
        return FileEventCategory.comments;
      case FileEventAction.markedUp:
      case FileEventAction.revertedMarkup:
        return FileEventCategory.markup;
      case FileEventAction.shared:
      case FileEventAction.downloaded:
        return FileEventCategory.sharing;
      case FileEventAction.unknown:
        return FileEventCategory.uploadsAndEdits;
    }
  }
}

enum FileEventCategory { uploadsAndEdits, comments, markup, sharing }
