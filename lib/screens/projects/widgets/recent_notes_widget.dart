import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/project.dart';
import '../../../models/project_note.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

/// Compact recent notes widget for the project overview dashboard.
class RecentNotesWidget extends StatefulWidget {
  final Project project;
  final VoidCallback? onViewAll;

  const RecentNotesWidget({
    super.key,
    required this.project,
    this.onViewAll,
  });

  @override
  State<RecentNotesWidget> createState() => _RecentNotesWidgetState();
}

class _RecentNotesWidgetState extends State<RecentNotesWidget> {
  late Future<List<ProjectNote>> _notesFuture;
  late String _notesFutureKey;

  @override
  void initState() {
    super.initState();
    _notesFutureKey = _computeKey(widget.project);
    _notesFuture = _loadNotes(widget.project);
  }

  @override
  void didUpdateWidget(covariant RecentNotesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = _computeKey(widget.project);
    if (newKey != _notesFutureKey) {
      _notesFutureKey = newKey;
      _notesFuture = _loadNotes(widget.project);
    }
  }

  String _computeKey(Project project) =>
      '${project.id}|${project.workspaceId}';

  Future<List<ProjectNote>> _loadNotes(Project project) {
    return ServiceLocator.projectNoteService.getRecentNotes(
      'project',
      project.id,
      workspaceId: project.workspaceId,
      limit: 5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sticky_note_2,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text(
                  'Recent Notes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (widget.onViewAll != null)
                  TextButton(
                    onPressed: widget.onViewAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View all'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            FutureBuilder<List<ProjectNote>>(
              future: _notesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
                    child: Center(
                        child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  );
                }
                final notes = snapshot.data ?? [];
                if (notes.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No notes yet.',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                return Column(
                  children: notes
                      .map((note) => _RecentNoteRow(note: note))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentNoteRow extends StatelessWidget {
  final ProjectNote note;

  const _RecentNoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final tagColor = _tagColor(note.tag);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.tag != null)
            Container(
              margin: const EdgeInsets.only(top: 3, right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                note.tag!,
                style: TextStyle(
                  fontSize: 10,
                  color: tagColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(top: 5, right: 8),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${note.authorName} · ${DateFormat('MMM d, h:mm a').format(note.createdAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _tagColor(String? tag) {
    switch (tag) {
      case 'issue':
        return AppColors.error;
      case 'resolution':
        return AppColors.success;
      case 'instruction':
        return AppColors.warning;
      case 'update':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }
}
