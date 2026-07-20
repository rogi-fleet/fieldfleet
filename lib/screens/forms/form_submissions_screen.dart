import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import '../../models/form_template.dart';
import '../../models/form_submission.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

class FormSubmissionsScreen extends StatefulWidget {
  final String formId;

  const FormSubmissionsScreen({super.key, required this.formId});

  @override
  State<FormSubmissionsScreen> createState() => _FormSubmissionsScreenState();
}

class _FormSubmissionsScreenState extends State<FormSubmissionsScreen> {
  dynamic get _formService => ServiceLocator.formService;
  FormTemplate? _form;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  Future<void> _loadForm() async {
    try {
      final form = await _formService.getFormTemplate(widget.formId);
      if (mounted) {
        setState(() {
          _form = form;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${form.name} - Submissions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/forms/${form.id}'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export to CSV',
            onPressed: () => _exportToCSV(context),
          ),
        ],
      ),
      body: StreamBuilder<List<FormSubmission>>(
        stream: _formService.getSubmissions(widget.formId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          final submissions = snapshot.data ?? [];

          if (submissions.isEmpty) {
            return _buildEmptyState();
          }

          return _buildSubmissionsList(submissions);
        },
      ),
    );
  }

  Widget _buildSubmissionsList(List<FormSubmission> submissions) {
    return ListView.builder(
      itemCount: submissions.length,
      padding: const EdgeInsets.all(AppSpacing.base),
      itemBuilder: (context, index) {
        final submission = submissions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.info.withAlpha(51),
              child: Text(
                '${index + 1}',
                style: TextStyle(color: AppColors.info),
              ),
            ),
            title: Text(
              submission.submittedByName ??
                  submission.submittedByEmail ??
                  'Anonymous',
            ),
            subtitle: Text(submission.formattedSubmittedAt),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _deleteSubmission(context, submission),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _form!.fields.map((field) {
                    final value = submission.getFieldValue(field.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              field.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              value.isNotEmpty ? value : '-',
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSubmission(
    BuildContext context,
    FormSubmission submission,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Submission'),
        content: const Text('Are you sure you want to delete this submission?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _formService.deleteSubmission(submission.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Submission deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _exportToCSV(BuildContext context) async {
    try {
      // Get all submissions
      final submissions = await _formService
          .getSubmissions(widget.formId)
          .first;
      final csv = _formService.exportSubmissionsToCSV(_form!, submissions);

      // For web, we'd use a different approach
      // For now, show a dialog with the CSV content
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export CSV'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: SingleChildScrollView(
                child: SelectableText(
                  csv,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'exporting')),
          ),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No submissions yet',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your form to start collecting responses',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
