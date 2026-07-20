import 'package:flutter/material.dart';
import '../../models/task_group_template.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

/// Shows a picker of saved task-group templates and imports the chosen one into
/// [projectId]. When [parentId] is provided the imported tasks attach beneath
/// that group; otherwise they land at the project root.
///
/// Returns true if a template was imported.
Future<bool> showImportTaskTemplateDialog(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
  String? parentId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _ImportTaskTemplateDialog(
      projectId: projectId,
      workspaceId: workspaceId,
      parentId: parentId,
    ),
  );
  return result ?? false;
}

class _ImportTaskTemplateDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String? parentId;

  const _ImportTaskTemplateDialog({
    required this.projectId,
    required this.workspaceId,
    this.parentId,
  });

  @override
  State<_ImportTaskTemplateDialog> createState() =>
      _ImportTaskTemplateDialogState();
}

class _ImportTaskTemplateDialogState extends State<_ImportTaskTemplateDialog> {
  String? _busyTemplateId;

  Future<void> _import(TaskGroupTemplate template) async {
    setState(() => _busyTemplateId = template.id);
    try {
      final count =
          await ServiceLocator.taskGroupTemplateService.applyTemplateToProject(
        templateId: template.id,
        projectId: widget.projectId,
        workspaceId: widget.workspaceId,
        parentId: widget.parentId,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Imported $count task${count == 1 ? '' : 's'} '
              'from "${template.name}"',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busyTemplateId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'importing template'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _delete(TaskGroupTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Delete "${template.name}"? This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ServiceLocator.taskGroupTemplateService
          .deleteTemplate(template.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'deleting template'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.library_add_check,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Import Tasks from Template')),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 380,
        child: StreamBuilder<List<TaskGroupTemplate>>(
          stream: ServiceLocator.taskGroupTemplateService
              .getTemplates(widget.workspaceId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  UserFacingError.uiMessage(snapshot.error,
                      action: 'load templates'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final templates = snapshot.data!;
            if (templates.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      'No task templates yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Save a phase as a template from its ⋮ menu first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              itemCount: templates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final t = templates[index];
                final isBusy = _busyTemplateId == t.id;
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                  leading: const Icon(Icons.folder_special_outlined),
                  title: Text(t.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      '${t.taskCount} task${t.taskCount == 1 ? '' : 's'}',
                      if (t.description != null &&
                          t.description!.trim().isNotEmpty)
                        t.description!.trim(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Delete',
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: AppColors.textTertiary),
                        onPressed:
                            _busyTemplateId != null ? null : () => _delete(t),
                      ),
                      isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton.tonal(
                              onPressed: _busyTemplateId != null
                                  ? null
                                  : () => _import(t),
                              child: const Text('Import'),
                            ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busyTemplateId != null
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
