import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../forms/stacked_field.dart';

/// Shows a dialog to save a task group (a phase and its subtree) as a reusable
/// template that can be imported into any project.
///
/// Returns true if a template was saved.
Future<bool> showSaveTaskGroupAsTemplateDialog(
  BuildContext context, {
  required Task rootTask,
  required String projectId,
  required String workspaceId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _SaveTaskGroupAsTemplateDialog(
      rootTask: rootTask,
      projectId: projectId,
      workspaceId: workspaceId,
    ),
  );
  return result ?? false;
}

class _SaveTaskGroupAsTemplateDialog extends StatefulWidget {
  final Task rootTask;
  final String projectId;
  final String workspaceId;

  const _SaveTaskGroupAsTemplateDialog({
    required this.rootTask,
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<_SaveTaskGroupAsTemplateDialog> createState() =>
      _SaveTaskGroupAsTemplateDialogState();
}

class _SaveTaskGroupAsTemplateDialogState
    extends State<_SaveTaskGroupAsTemplateDialog> {
  late final TextEditingController _nameController;
  final _descriptionController = TextEditingController();
  bool _includeAssignees = true;
  bool _includeChecklists = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rootTask.title);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a template name'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = context.read<AuthProvider>().appUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final template =
          await ServiceLocator.taskGroupTemplateService.createTemplateFromGroup(
        rootTaskId: widget.rootTask.id,
        projectId: widget.projectId,
        workspaceId: widget.workspaceId,
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        createdBy: userId,
        includeAssignees: _includeAssignees,
        includeChecklists: _includeChecklists,
      );

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Saved "$name" (${template.taskCount} '
              'task${template.taskCount == 1 ? '' : 's'})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(UserFacingError.uiMessage(e, action: 'saving template')),
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
          Icon(Icons.bookmark_add,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Save Group as Template')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save "${widget.rootTask.title}" and everything under it as a '
                'reusable template. Import it into any project later.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              StackedField(
                label: 'Template Name',
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Quotation Phase',
                  ),
                  autofocus: true,
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(height: 16),
              StackedField(
                label: 'Description (optional)',
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    hintText: 'What this set of tasks is for',
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeAssignees,
                onChanged: (v) =>
                    setState(() => _includeAssignees = v ?? true),
                title: const Text('Keep assignees'),
                subtitle: Text(
                  'Carry over assigned users',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeChecklists,
                onChanged: (v) =>
                    setState(() => _includeChecklists = v ?? true),
                title: const Text('Keep checklists'),
                subtitle: Text(
                  'Carry over checklist items (reset to unchecked)',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: Text(_isSaving ? 'Saving...' : 'Save Template'),
        ),
      ],
    );
  }
}
