import 'package:flutter/material.dart';

import '../../models/file_event.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Audit timeline for a single file. Reads live from `file_events`, which
/// every mutation-producing service already writes to (upload, metadata
/// edits, comments, markup). Filter chips let readers narrow the stream
/// by category.
class FileActivityFeed extends StatefulWidget {
  final String fileAttachmentId;
  final String workspaceId;

  const FileActivityFeed({
    super.key,
    required this.fileAttachmentId,
    required this.workspaceId,
  });

  @override
  State<FileActivityFeed> createState() => _FileActivityFeedState();
}

class _FileActivityFeedState extends State<FileActivityFeed> {
  final _eventService = ServiceLocator.fileEventService;
  final _userService = ServiceLocator.userService;

  FileEventCategory? _filter; // null = show all

  Map<String, AppUser> _userCache = const {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final map = await _userService.getWorkspaceUsersMap(widget.workspaceId);
    if (!mounted) return;
    setState(() => _userCache = Map<String, AppUser>.from(map));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FileEvent>>(
      stream: _eventService.streamForFile(widget.fileAttachmentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorBox('Could not load activity: ${snapshot.error}');
        }
        final events = snapshot.data ?? const <FileEvent>[];
        final filtered = _filter == null
            ? events
            : events.where((e) => e.action.category == _filter).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Activity',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                if (events.isNotEmpty)
                  Text(
                    '${events.length}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('All', null),
                _chip('Edits', FileEventCategory.uploadsAndEdits),
                _chip('Comments', FileEventCategory.comments),
                _chip('Markup', FileEventCategory.markup),
                _chip('Sharing', FileEventCategory.sharing),
              ],
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  events.isEmpty
                      ? 'No activity recorded yet.'
                      : 'No events in this category.',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ...filtered.map(_buildRow),
          ],
        );
      },
    );
  }

  Widget _chip(String label, FileEventCategory? category) {
    final selected = _filter == category;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = selected ? null : category),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildRow(FileEvent event) {
    final actor = event.actorId == null ? null : _userCache[event.actorId];
    final actorName = actor?.displayName ?? actor?.email ?? 'Someone';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 10),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _iconColor(event.action).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconFor(event.action),
              size: 14,
              color: _iconColor(event.action),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: actorName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(text: _titleFor(event)),
                    ],
                  ),
                ),
                Text(
                  _formatTime(event.createdAt),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(FileEventAction action) {
    switch (action) {
      case FileEventAction.uploaded:
        return Icons.upload;
      case FileEventAction.renamed:
        return Icons.edit;
      case FileEventAction.described:
        return Icons.short_text;
      case FileEventAction.moved:
        return Icons.drive_file_move;
      case FileEventAction.taggedAdded:
        return Icons.label;
      case FileEventAction.taggedRemoved:
        return Icons.label_off;
      case FileEventAction.deleted:
        return Icons.delete;
      case FileEventAction.commented:
        return Icons.comment;
      case FileEventAction.markedUp:
        return Icons.brush;
      case FileEventAction.revertedMarkup:
        return Icons.restart_alt;
      case FileEventAction.shared:
        return Icons.share;
      case FileEventAction.downloaded:
        return Icons.download;
      case FileEventAction.unknown:
        return Icons.circle;
    }
  }

  Color _iconColor(FileEventAction action) {
    switch (action.category) {
      case FileEventCategory.uploadsAndEdits:
        return AppColors.primary;
      case FileEventCategory.comments:
        return AppColors.secondary;
      case FileEventCategory.markup:
        return AppColors.warning;
      case FileEventCategory.sharing:
        return AppColors.success;
    }
  }

  String _titleFor(FileEvent event) {
    final p = event.payload;
    switch (event.action) {
      case FileEventAction.uploaded:
        return 'uploaded this file';
      case FileEventAction.renamed:
        final to = p['to'];
        return to == null ? 'renamed this file' : 'renamed this file to "$to"';
      case FileEventAction.described:
        return 'updated the description';
      case FileEventAction.moved:
        return 'moved this file to a different folder';
      case FileEventAction.taggedAdded:
        return 'added a tag';
      case FileEventAction.taggedRemoved:
        return 'removed a tag';
      case FileEventAction.deleted:
        return 'deleted this file';
      case FileEventAction.commented:
        final excerpt = p['excerpt'];
        return excerpt == null ? 'commented' : 'commented: "$excerpt"';
      case FileEventAction.markedUp:
        final count = p['shape_count'];
        return count == null
            ? 'added markup'
            : 'added markup ($count shape${count == 1 ? '' : 's'})';
      case FileEventAction.revertedMarkup:
        return 'reverted markup to the original';
      case FileEventAction.shared:
        return 'shared this file';
      case FileEventAction.downloaded:
        return 'downloaded this file';
      case FileEventAction.unknown:
        return 'took an action';
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(msg, style: TextStyle(color: AppColors.error, fontSize: 12)),
    );
  }
}
