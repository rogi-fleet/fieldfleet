import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../models/form_template.dart';
import '../../services/service_locator.dart';
import '../../widgets/forms/form_renderer.dart';
import '../../theme/theme.dart';

class PublicFormScreen extends StatefulWidget {
  final String slug;

  const PublicFormScreen({super.key, required this.slug});

  @override
  State<PublicFormScreen> createState() => _PublicFormScreenState();
}

class _PublicFormScreenState extends State<PublicFormScreen> {
  dynamic get _formService => ServiceLocator.formService;
  FormTemplate? _form;
  bool _isLoading = true;
  bool _isSubmitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  Future<void> _loadForm() async {
    try {
      final form = await _formService.getFormBySlug(widget.slug);
      if (mounted) {
        setState(() {
          _form = form;
          _isLoading = false;
          if (form == null) {
            _error = 'Form not found or is no longer public';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = UserFacingError.uiMessage(e, action: 'load form');
        });
      }
    }
  }

  Future<void> _submitForm(Map<String, dynamic> data) async {
    if (_form == null) return;

    try {
      await _formService.submitForm(
        formTemplateId: _form!.id,
        workspaceId: _form!.workspaceId,
        data: data,
        submittedByEmail: data['email'] as String?,
        submittedByName: data['name'] as String?,
      );

      if (mounted) {
        setState(() {
          _isSubmitted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'submitting form'),
            ),
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

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_isSubmitted) {
      return _buildSuccessScreen();
    }

    return _buildFormScreen();
  }

  Widget _buildFormScreen() {
    final form = _form!;

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (form.description != null &&
                        form.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        form.description!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    FormRenderer(
                      fields: form.fields,
                      onSubmit: _submitForm,
                      workspaceId: form.workspaceId,
                      projectId: form.projectId,
                      uploadedBy: form.createdBy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      size: 48,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Thank You!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your response has been submitted successfully.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSubmitted = false;
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Submit Another Response'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
