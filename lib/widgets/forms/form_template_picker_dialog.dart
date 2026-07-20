import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/form_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

/// Dialog for picking a workspace form template when attaching a form to a
/// project. Shows workspace-level templates (no projectId) and a blank option.
///
/// Returns a [FormTemplatPickerResult] describing what the user chose, or null
/// if cancelled.
class FormTemplatePickerDialog extends StatefulWidget {
  final String workspaceId;
  final String projectId;

  const FormTemplatePickerDialog({
    super.key,
    required this.workspaceId,
    required this.projectId,
  });

  /// Convenience: show the dialog and return the result.
  static Future<FormTemplatePickerResult?> show(
    BuildContext context, {
    required String workspaceId,
    required String projectId,
  }) {
    return showDialog<FormTemplatePickerResult>(
      context: context,
      builder: (_) => FormTemplatePickerDialog(
        workspaceId: workspaceId,
        projectId: projectId,
      ),
    );
  }

  @override
  State<FormTemplatePickerDialog> createState() =>
      _FormTemplatePickerDialogState();
}

class _FormTemplatePickerDialogState extends State<FormTemplatePickerDialog> {
  List<FormTemplate>? _templates;
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _duplicatingId;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await ServiceLocator.formService
          .getWorkspaceTemplateForms(widget.workspaceId);
      if (mounted) {
        setState(() {
          _templates = templates;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load templates');
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectTemplate(FormTemplate template) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id ?? '';

    setState(() => _duplicatingId = template.id);
    try {
      final created = await ServiceLocator.formService.duplicateFormTemplate(
        formId: template.id,
        createdBy: userId,
        projectId: widget.projectId,
        name: template.name,
      );
      if (mounted) {
        Navigator.of(context).pop(
          FormTemplatePickerResult.fromTemplate(created),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _duplicatingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'add form')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _templates == null
        ? null
        : _search.isEmpty
            ? _templates!
            : _templates!
                .where(
                  (t) =>
                      t.name.toLowerCase().contains(_search) ||
                      (t.description?.toLowerCase().contains(_search) ?? false),
                )
                .toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Form',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Blank form option
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  FormTemplatePickerResult.blank(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Start with blank form'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: 14,
                  ),
                ),
              ),
            ),

            if (_templates == null || _templates!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'From workspace template',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search templates...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) =>
                      setState(() => _search = v.toLowerCase().trim()),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Template list
            Expanded(
              child: _buildBody(filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<FormTemplate>? filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: AppColors.error)),
      );
    }
    if (filtered == null || filtered.isEmpty) {
      if (_templates != null && _templates!.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Text(
            'No workspace templates yet. Start with a blank form.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Text(
          'No templates match your search.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final template = filtered[i];
        final isDuplicating = _duplicatingId == template.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: isDuplicating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.dynamic_form, color: AppColors.textTertiary),
            ),
            title: Text(template.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (template.description != null &&
                    template.description!.isNotEmpty)
                  Text(
                    template.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Text(
                  '${template.fieldCount} fields',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            enabled: _duplicatingId == null,
            onTap: () => _selectTemplate(template),
          ),
        );
      },
    );
  }
}

/// The result returned by [FormTemplatePickerDialog].
class FormTemplatePickerResult {
  /// If true, the user wants a blank form (navigate to form builder).
  final bool isBlank;

  /// The newly-created project-scoped copy of the selected template, if not blank.
  final FormTemplate? createdForm;

  FormTemplatePickerResult.blank()
      : isBlank = true,
        createdForm = null;

  FormTemplatePickerResult.fromTemplate(FormTemplate form)
      : isBlank = false,
        createdForm = form;
}
