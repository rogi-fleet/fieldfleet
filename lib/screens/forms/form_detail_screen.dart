import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/form_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/forms/form_preview.dart';
import '../../theme/theme.dart';

class FormDetailScreen extends StatefulWidget {
  final String formId;

  const FormDetailScreen({super.key, required this.formId});

  @override
  State<FormDetailScreen> createState() => _FormDetailScreenState();
}

class _FormDetailScreenState extends State<FormDetailScreen> {
  dynamic get _formService => ServiceLocator.formService;
  FormTemplate? _form;
  bool _isLoading = true;
  int _submissionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  void _exportJson(BuildContext context) {
    final form = _form;
    if (form == null) return;
    final json = _formService.exportFormAsJson(form);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Form JSON'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadForm() async {
    try {
      final form = await _formService.getFormTemplate(widget.formId);
      final count = await _formService.getSubmissionCount(widget.formId);
      if (mounted) {
        setState(() {
          _form = form;
          _submissionCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'loading form')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_form == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Form Not Found')),
        body: const Center(child: Text('Form not found')),
      );
    }

    final form = _form!;
    final canManageForms = context.watch<AuthProvider>().canCreateProjects;

    return Scaffold(
      appBar: AppBar(
        title: Text(form.name),
        actions: [
          if (canManageForms)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Form',
              onPressed: () => context.go('/forms/${form.id}/edit'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Form Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: form.isPublic
                              ? AppColors.success.withAlpha(51)
                              : AppColors.textTertiary.withAlpha(51),
                          child: Icon(
                            Icons.dynamic_form,
                            color: form.isPublic
                                ? AppColors.success
                                : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                form.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (form.description != null &&
                                  form.description!.isNotEmpty)
                                Text(
                                  form.description!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      children: [
                        _buildStat('Fields', form.fieldCount.toString()),
                        const SizedBox(width: 32),
                        _buildStat(
                          'Required',
                          form.requiredFieldCount.toString(),
                        ),
                        const SizedBox(width: 32),
                        _buildStat('Submissions', _submissionCount.toString()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Public Link Section
            if (form.isPublic) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.public, color: AppColors.success),
                          const SizedBox(width: 8),
                          Text(
                            'Public Link',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                '${Uri.base.origin}/f/${form.publicSlug}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy Link',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        '${Uri.base.origin}/f/${form.publicSlug}',
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link copied to clipboard'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => context.go('/forms/${form.id}/submissions'),
                  icon: const Icon(Icons.list_alt),
                  label: Text('View Submissions ($_submissionCount)'),
                ),
                if (canManageForms)
                  OutlinedButton.icon(
                    onPressed: () => context.go('/forms/${form.id}/edit'),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Form'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _exportJson(context),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export JSON'),
                ),
                if (canManageForms)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final slug = await _formService.togglePublic(
                        form.id,
                        !form.isPublic,
                      );
                      await _loadForm();
                      if (context.mounted && slug != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              form.isPublic
                                  ? 'Form is now private'
                                  : 'Form is now public',
                            ),
                          ),
                        );
                      }
                    },
                    icon: Icon(form.isPublic ? Icons.lock : Icons.public),
                    label: Text(form.isPublic ? 'Make Private' : 'Make Public'),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Form Preview
            Text(
              'Form Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: FormPreview(fields: form.fields, readOnly: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
