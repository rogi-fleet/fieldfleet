import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/field_forms/field_form_fill_screen.dart';
import '../../screens/field_forms/field_form_submission_detail_screen.dart';
import '../../models/field_form_submission.dart';
import '../../models/field_form_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Shows the required forms list for a task.
/// Drop this widget into the task detail screen to add form integration.
///
/// Usage:
/// ```dart
/// TaskRequiredFormsWidget(taskId: task.id, projectId: task.projectId)
/// ```
class TaskRequiredFormsWidget extends StatefulWidget {
  const TaskRequiredFormsWidget({
    super.key,
    required this.taskId,
    this.projectId,
    /// If true, the "Add Form" button is hidden (read-only mode).
    this.readOnly = false,
  });

  final String taskId;
  final String? projectId;
  final bool readOnly;

  @override
  State<TaskRequiredFormsWidget> createState() =>
      _TaskRequiredFormsWidgetState();
}

class _TaskRequiredFormsWidgetState extends State<TaskRequiredFormsWidget> {
  dynamic get _service => ServiceLocator.fieldFormService;

  late Stream<List<TaskRequiredForm>> _formsStream;

  @override
  void initState() {
    super.initState();
    _formsStream = _service.getTaskRequiredForms(widget.taskId);
  }

  @override
  void didUpdateWidget(TaskRequiredFormsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _formsStream = _service.getTaskRequiredForms(widget.taskId);
    }
  }

  void _refreshStream() {
    setState(() {
      _formsStream = _service.getTaskRequiredForms(widget.taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TaskRequiredForm>>(
      stream: _formsStream,
      builder: (context, snapshot) {
        final forms = snapshot.data ?? [];
        final hasData = snapshot.hasData;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, forms),
            if (!hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: LinearProgressIndicator(),
              )
            else if (forms.isEmpty)
              _buildEmptyState(context)
            else
              ...forms.map((rf) => _RequiredFormTile(
                    key: ValueKey('${rf.taskId}_${rf.templateId}'),
                    requiredForm: rf,
                    taskId: widget.taskId,
                    projectId: widget.projectId,
                    onRemove: widget.readOnly
                        ? null
                        : () => _removeForm(context, rf),
                    onReturn: _refreshStream,
                  )),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, List<TaskRequiredForm> forms) {
    final completed = forms.where((f) => f.isCompleted).length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Required Forms',
                  style: Theme.of(context).textTheme.titleSmall),
              if (forms.isNotEmpty)
                Text(
                  '$completed of ${forms.length} complete',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        if (!widget.readOnly)
          TextButton.icon(
            onPressed: () => _showAddFormDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Form'),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (widget.readOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('No forms required for this task.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text('No forms required for this task.',
          style: TextStyle(
              fontSize: 13, color: AppColors.textSecondary)),
    );
  }

  Future<void> _showAddFormDialog(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final templates = await _service.getTemplates(workspaceId).first;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _AddFormDialog(
        templates: templates,
        taskId: widget.taskId,
      ),
    );

    if (mounted) _refreshStream();
  }

  Future<void> _removeForm(
      BuildContext context, TaskRequiredForm rf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Required Form'),
        content: const Text(
            'Remove this form requirement? Any existing submission will be kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.removeRequiredFormFromTask(
        taskId: rf.taskId,
        templateId: rf.templateId,
      );
      if (mounted) _refreshStream();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _RequiredFormTile extends StatelessWidget {
  const _RequiredFormTile({
    super.key,
    required this.requiredForm,
    required this.taskId,
    this.projectId,
    this.onRemove,
    this.onReturn,
  });

  final TaskRequiredForm requiredForm;
  final String taskId;
  final String? projectId;
  final VoidCallback? onRemove;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final hasSubmission = requiredForm.submissionId != null;

    return FutureBuilder<FieldFormTemplate?>(
      future: ServiceLocator.fieldFormService
          .getTemplate(requiredForm.templateId),
      builder: (context, snap) {
        final template = snap.data;
        final name = template?.name ?? 'Loading…';

        // If there's a linked submission, check if it's still a draft.
        return FutureBuilder<FieldFormSubmission?>(
          future: hasSubmission
              ? ServiceLocator.fieldFormService
                  .getSubmission(requiredForm.submissionId!)
              : Future.value(null),
          builder: (context, subSnap) {
            final submission = subSnap.data;
            final isDraft = submission?.status == FieldFormStatus.draft;
            final isCompleted = hasSubmission && !isDraft;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.success.withOpacity(0.06)
                    : isDraft
                        ? AppColors.warning.withOpacity(0.06)
                        : AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isCompleted
                      ? AppColors.success.withOpacity(0.3)
                      : isDraft
                          ? AppColors.warning.withOpacity(0.3)
                          : AppColors.cardBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle
                        : isDraft
                            ? Icons.edit_note
                            : Icons.radio_button_unchecked,
                    size: 18,
                    color: isCompleted
                        ? AppColors.success
                        : isDraft
                            ? AppColors.warning
                            : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        if (isDraft)
                          Text('Draft — tap Continue to finish',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.warning))
                        else if (requiredForm.blocksCompletion)
                          Text(
                            'Required to complete task',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.warning),
                          ),
                      ],
                    ),
                  ),
                  if (isDraft)
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => FieldFormFillScreen(
                              templateId: requiredForm.templateId,
                              taskId: taskId,
                              projectId: projectId,
                              submissionId: requiredForm.submissionId,
                            ),
                          ),
                        );
                        onReturn?.call();
                      },
                      child: const Text('Continue'),
                    )
                  else if (isCompleted)
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => FieldFormSubmissionDetailScreen(
                              submissionId: requiredForm.submissionId!,
                            ),
                          ),
                        );
                        onReturn?.call();
                      },
                      child: const Text('View'),
                    )
                  else
                    FilledButton(
                      onPressed: () async {
                        await Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => FieldFormFillScreen(
                              templateId: requiredForm.templateId,
                              taskId: taskId,
                              projectId: projectId,
                            ),
                          ),
                        );
                        onReturn?.call();
                      },
                      child: const Text('Fill'),
                    ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        );
          },
        );
      },
    );
  }
}

class _AddFormDialog extends StatefulWidget {
  const _AddFormDialog({
    required this.templates,
    required this.taskId,
  });

  final List<FieldFormTemplate> templates;
  final String taskId;

  @override
  State<_AddFormDialog> createState() => _AddFormDialogState();
}

class _AddFormDialogState extends State<_AddFormDialog> {
  FieldFormTemplate? _selected;
  bool _blocksCompletion = false;
  bool _saving = false;

  dynamic get _service => ServiceLocator.fieldFormService;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Required Form'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.templates.isEmpty)
              const Text(
                  'No form templates found. Create a template first.')
            else
              DropdownButtonFormField<FieldFormTemplate>(
                hint: const Text('Select a template'),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.templates
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _blocksCompletion,
              onChanged: (v) =>
                  setState(() => _blocksCompletion = v ?? false),
              title: const Text('Block task completion until filled'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed:
              (_selected == null || _saving) ? null : () => _add(context),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final template = _selected;
    if (template == null) return;
    setState(() => _saving = true);
    try {
      await _service.addRequiredFormToTask(
        taskId: widget.taskId,
        templateId: template.id,
        blocksCompletion: _blocksCompletion,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
