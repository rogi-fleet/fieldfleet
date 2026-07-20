import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../utils/project_terminology.dart';
import '../../theme/theme.dart';
import '../forms/stacked_field.dart';

/// Shows a dialog to save a project as a reusable template.
///
/// The user can choose a name, description, and optionally include
/// tasks and budget items.
Future<bool> showSaveProjectAsTemplateDialog(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _SaveAsTemplateDialog(projectId: projectId, workspaceId: workspaceId),
  );
  return result ?? false;
}

class _SaveAsTemplateDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;

  const _SaveAsTemplateDialog({
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<_SaveAsTemplateDialog> createState() => _SaveAsTemplateDialogState();
}

class _SaveAsTemplateDialogState extends State<_SaveAsTemplateDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _includeTasks = true;
  bool _includeBudget = true;
  bool _isSaving = false;

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
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await ServiceLocator.projectTemplateService.createTemplateFromProject(
        projectId: widget.projectId,
        workspaceId: widget.workspaceId,
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        createdBy: userId,
        includeTasks: _includeTasks,
        includeBudgetItems: _includeBudget,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving template'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.bookmark_add,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Save as Template'),
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
              'Save this project\'s settings as a reusable template for future projects.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            StackedField(
              label: 'Template Name',
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g., Standard Residential Renovation',
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
                  hintText:
                      'e.g., Template for standard home renovations with typical markups',
                ),
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'What to include',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildCheckbox(
              label: '$singular settings',
              subtitle: 'Pricing, markups, job type, budget',
              value: true,
              enabled: false,
              onChanged: null,
              icon: Icons.settings,
            ),
            _buildCheckbox(
              label: 'Tasks',
              subtitle: 'Task list with hierarchy and descriptions',
              value: _includeTasks,
              enabled: true,
              onChanged: (v) => setState(() => _includeTasks = v ?? true),
              icon: Icons.task_alt,
            ),
            _buildCheckbox(
              label: 'Budget items',
              subtitle: 'Budget structure with prices',
              value: _includeBudget,
              enabled: true,
              onChanged: (v) => setState(() => _includeBudget = v ?? true),
              icon: Icons.attach_money,
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

  Widget _buildCheckbox({
    required String label,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool?>? onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: enabled ? onChanged : null),
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: enabled ? null : AppColors.textSecondary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
