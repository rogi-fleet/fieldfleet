import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/area.dart';
import '../../models/form_field_definition.dart';
import '../../models/form_field_type.dart';
import '../../models/file_attachment.dart';
import '../../models/user.dart';
import '../../models/workspace.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/project_terminology.dart';

class FormRenderer extends StatefulWidget {
  final List<FormFieldDefinition> fields;
  final Function(Map<String, dynamic>)? onSubmit;
  final String? workspaceId;
  final String? projectId;
  final String? uploadedBy;
  /// Pre-populate fields with existing data (e.g. resuming a draft).
  final Map<String, dynamic>? initialData;
  /// Label shown on the submit button. Defaults to "Submit".
  final String? submitLabel;

  const FormRenderer({
    super.key,
    required this.fields,
    required this.onSubmit,
    this.workspaceId,
    this.projectId,
    this.uploadedBy,
    this.initialData,
    this.submitLabel,
  });

  @override
  State<FormRenderer> createState() => FormRendererState();
}

class FormRendererState extends State<FormRenderer> {
  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, double> _fileUploadProgress = {};
  final Set<String> _uploadingFieldIds = {};
  final dynamic _storageService = ServiceLocator.storageService;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialData ?? {};
    for (final field in widget.fields) {
      final existing = seed[field.id];
      if (_usesTextController(field.type)) {
        _controllers[field.id] = TextEditingController(
          text: existing?.toString() ?? field.defaultValue ?? '',
        );
      }
      if (existing != null) {
        _formData[field.id] = existing;
      } else if (field.type == FormFieldType.checkbox) {
        _formData[field.id] = false;
      } else if (field.type == FormFieldType.multiSelect) {
        _formData[field.id] = <String>[];
      } else if (field.type == FormFieldType.select &&
          field.defaultValue != null &&
          field.defaultValue!.isNotEmpty) {
        _formData[field.id] = field.defaultValue;
      } else if (field.type == FormFieldType.table) {
        _formData[field.id] = <Map<String, dynamic>>[];
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submitForm() async {
    if (_uploadingFieldIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for file uploads to finish'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final data = _collectVisibleData();
    await widget.onSubmit?.call(data);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  /// Returns the current form data without running validation.
  /// Used by external callers (e.g. "Save Draft") to read the state.
  Map<String, dynamic> collectData() => _collectVisibleData();

  /// Sync controller text into _formData and return only the data for fields
  /// that are currently visible (conditional fields whose dependencies aren't
  /// met are excluded so stale values don't get persisted).
  Map<String, dynamic> _collectVisibleData() {
    for (final field in widget.fields) {
      if (_controllers.containsKey(field.id)) {
        _formData[field.id] = _controllers[field.id]!.text;
      }
    }
    final result = <String, dynamic>{};
    for (final field in widget.fields) {
      if (!_isFieldVisible(field)) continue;
      if (_formData.containsKey(field.id)) {
        result[field.id] = _formData[field.id];
      }
    }
    return result;
  }

  /// Evaluates a field's [FormFieldDefinition.visibleWhen] rules against the
  /// current form state. Returns true when there are no rules or all rules
  /// match (each referenced field's stringified value is in its allowed list).
  bool _isFieldVisible(FormFieldDefinition field) {
    final rules = field.visibleWhen;
    if (rules == null || rules.isEmpty) return true;
    for (final entry in rules.entries) {
      final raw = _formData[entry.key];
      final value = raw?.toString() ?? '';
      if (!entry.value.contains(value)) return false;
    }
    return true;
  }

  bool _usesTextController(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
      case FormFieldType.email:
      case FormFieldType.phone:
      case FormFieldType.textarea:
      case FormFieldType.number:
      case FormFieldType.date:
      case FormFieldType.datetime:
      case FormFieldType.address:
        return true;
      case FormFieldType.time:
        return true;
      case FormFieldType.select:
      case FormFieldType.multiSelect:
      case FormFieldType.checkbox:
      case FormFieldType.file:
      case FormFieldType.photo:
      case FormFieldType.inspectionItem:
      case FormFieldType.rating:
      case FormFieldType.section:
      case FormFieldType.table:
        return false;
    }
  }

  bool get _canUploadFiles =>
      (widget.workspaceId?.isNotEmpty ?? false) &&
      (widget.uploadedBy?.isNotEmpty ?? false);

  Future<void> _pickAndUploadFile(FormFieldDefinition field) async {
    if (!_canUploadFiles) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File uploads are unavailable for this form'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      if (file.size > _maxFileSizeBytes) {
        final sizeMB = (file.size / (1024 * 1024)).toStringAsFixed(1);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File is too large ($sizeMB MB). Maximum allowed size is 25 MB.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadingFieldIds.add(field.id);
        _fileUploadProgress[field.id] = 0.0;
      });

      FileAttachment attachment;
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw Exception('Selected file has no bytes');
        }
        attachment = await _storageService.uploadFileBytes(
          bytes: bytes,
          fileName: file.name,
          workspaceId: widget.workspaceId!,
          projectId: widget.projectId ?? '_forms',
          uploadedBy: widget.uploadedBy!,
          tags: const ['form-upload'],
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _fileUploadProgress[field.id] = progress;
            });
          },
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          throw Exception('Selected file has no path');
        }
        attachment = await _storageService.uploadFile(
          file: File(path),
          fileName: file.name,
          workspaceId: widget.workspaceId!,
          projectId: widget.projectId ?? '_forms',
          uploadedBy: widget.uploadedBy!,
          tags: const ['form-upload'],
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _fileUploadProgress[field.id] = progress;
            });
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _formData[field.id] = {
          'attachmentId': attachment.id,
          'fileName': attachment.fileName,
          'fileUrl': attachment.fileUrl,
          'fileSize': attachment.fileSize,
          'mimeType': attachment.mimeType,
          'uploadedAt': attachment.uploadedAt.toIso8601String(),
        };
        _uploadingFieldIds.remove(field.id);
        _fileUploadProgress.remove(field.id);
      });
      _formKey.currentState?.validate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingFieldIds.remove(field.id);
        _fileUploadProgress.remove(field.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload file: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reserve space below the submit button on mobile so the floating
    // bottom nav bar (~70px + safe area + platform pad) doesn't cover it.
    final isMobile = AppBreakpoints.isMobileContext(context);
    final platformBottomPad = Theme.of(context).platform == TargetPlatform.iOS
        ? 16.0
        : 8.0;
    final bottomReserve = isMobile
        ? MediaQuery.paddingOf(context).bottom + platformBottomPad + 70 + 12
        : 0.0;

    return FormFillContext(
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      submissionDate: DateTime.now(),
      child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.fields
              .where(_isFieldVisible)
              .map((field) => _buildField(field)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (widget.onSubmit == null || _isSubmitting)
                ? null
                : _submitForm,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel ?? 'Submit'),
          ),
          SizedBox(height: bottomReserve),
        ],
      ),
    ),
    );
  }

  /// Appends a unit suffix to the field label based on workspace unit_system
  /// when [FormFieldDefinition.unit] is set. Falls back to the raw label.
  String _labelFor(FormFieldDefinition field) {
    if (field.unit == null) return field.label;
    final isMetric =
        context.watch<WorkspaceProvider>().unitSystem == UnitSystem.metric;
    if (field.unit == 'temperature') {
      return '${field.label} ${isMetric ? '(°C)' : '(°F)'}';
    }
    return field.label;
  }

  Widget _buildField(FormFieldDefinition field) {
    // Section headers render as dividers with no input wrapper.
    if (field.type == FormFieldType.section) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            const SizedBox(height: 8),
            Text(
              field.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            if (field.description != null && field.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                field.description!,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _labelFor(field),
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (field.isRequired)
                const Text(' *', style: TextStyle(color: AppColors.error)),
            ],
          ),
          if (field.description != null && field.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              field.description!,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          _buildFieldInput(field),
        ],
      ),
    );
  }

  Widget _buildFieldInput(FormFieldDefinition field) {
    switch (field.type) {
      case FormFieldType.text:
        return TextFormField(
          controller: _controllers[field.id],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          ),
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.email:
        return TextFormField(
          controller: _controllers[field.id],
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'email@example.com',
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          ),
          validator: (value) {
            if (field.isRequired && (value?.isEmpty ?? true)) {
              return 'This field is required';
            }
            if (value != null &&
                value.isNotEmpty &&
                !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
              return 'Please enter a valid email';
            }
            return null;
          },
        );

      case FormFieldType.phone:
        return TextFormField(
          controller: _controllers[field.id],
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '(555) 123-4567',
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          ),
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.textarea:
        return TextFormField(
          controller: _controllers[field.id],
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter your response...',
            contentPadding: EdgeInsets.all(AppSpacing.md),
          ),
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.number:
        return TextFormField(
          controller: _controllers[field.id],
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter a number',
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          ),
          validator: (value) {
            if (field.isRequired && (value?.isEmpty ?? true)) {
              return 'This field is required';
            }
            if (value != null &&
                value.isNotEmpty &&
                double.tryParse(value) == null) {
              return 'Please enter a valid number';
            }
            return null;
          },
        );

      case FormFieldType.date:
        return TextFormField(
          controller: _controllers[field.id],
          readOnly: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Select a date',
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            suffixIcon: Icon(Icons.calendar_today),
          ),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (date != null) {
              _controllers[field.id]!.text =
                  '${date.month}/${date.day}/${date.year}';
            }
          },
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.select:
        return DropdownButtonFormField<String>(
          borderRadius: AppRadius.cardRadius,
          initialValue: _formData[field.id] as String?,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          ),
          hint: const Text('Select an option'),
          items: (field.options ?? [])
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _formData[field.id] = value;
            });
          },
          validator: field.isRequired
              ? (value) => value == null ? 'Please select an option' : null
              : null,
        );

      case FormFieldType.multiSelect:
        final selectedOptions = _formData[field.id] as List<String>? ?? [];
        return FormField<List<String>>(
          initialValue: selectedOptions,
          validator: (_) {
            if (field.isRequired && selectedOptions.isEmpty) {
              return 'Please select at least one option';
            }
            return null;
          },
          builder: (formFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (field.options ?? []).map((option) {
                  final isSelected = selectedOptions.contains(option);
                  return FilterChip(
                    label: Text(option),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedOptions.add(option);
                        } else {
                          selectedOptions.remove(option);
                        }
                        _formData[field.id] = selectedOptions;
                        formFieldState.didChange(selectedOptions);
                      });
                    },
                  );
                }).toList(),
              ),
              if (formFieldState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    formFieldState.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        );

      case FormFieldType.checkbox:
        return Row(
          children: [
            Checkbox(
              value: _formData[field.id] as bool? ?? false,
              onChanged: (value) {
                setState(() {
                  _formData[field.id] = value ?? false;
                });
              },
            ),
            const SizedBox(width: 8),
            const Text('Yes'),
          ],
        );

      case FormFieldType.file:
        final fileData = _formData[field.id] as Map<String, dynamic>?;
        final isUploading = _uploadingFieldIds.contains(field.id);
        final uploadProgress = _fileUploadProgress[field.id] ?? 0.0;

        return FormField<Map<String, dynamic>?>(
          validator: (_) {
            if (!_canUploadFiles && field.isRequired) {
              return 'File uploads are unavailable for this form';
            }
            if (field.isRequired && fileData == null) {
              return 'Please upload a file';
            }
            return null;
          },
          builder: (formFieldState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: (!_canUploadFiles || isUploading)
                      ? null
                      : () => _pickAndUploadFile(field),
                  icon: Icon(
                    fileData == null ? Icons.upload_file : Icons.refresh,
                  ),
                  label: Text(
                    fileData == null ? 'Choose File' : 'Replace File',
                  ),
                ),
                if (!_canUploadFiles)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'File uploads are only available for ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()}-linked forms.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (isUploading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: uploadProgress),
                ],
                if (fileData != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_file,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileData['fileName'] as String? ??
                                    'Uploaded file',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (fileData['mimeType'] != null ||
                                  fileData['fileSize'] != null)
                                Text(
                                  [
                                    if (fileData['mimeType'] != null)
                                      fileData['mimeType'] as String,
                                    if (fileData['fileSize'] != null)
                                      '${((fileData['fileSize'] as num).toDouble() / 1024).toStringAsFixed(1)} KB',
                                  ].join(' • '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!isUploading)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _formData.remove(field.id);
                              });
                              formFieldState.didChange(null);
                              _formKey.currentState?.validate();
                            },
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove file',
                          ),
                      ],
                    ),
                  ),
                ],
                if (field.isRequired)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'File upload required',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (formFieldState.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formFieldState.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          },
        );

      case FormFieldType.address:
        return TextFormField(
          controller: _controllers[field.id],
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter address...',
            contentPadding: EdgeInsets.all(AppSpacing.md),
          ),
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.datetime:
        return TextFormField(
          controller: _controllers[field.id],
          readOnly: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Select date and time',
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            suffixIcon: Icon(Icons.schedule),
          ),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (date == null || !mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (time == null) return;
            final combined = DateTime(
                date.year, date.month, date.day, time.hour, time.minute);
            _controllers[field.id]!.text =
                '${combined.month}/${combined.day}/${combined.year} '
                '${time.format(context)}';
          },
          validator: field.isRequired
              ? (value) =>
                    (value?.isEmpty ?? true) ? 'This field is required' : null
              : null,
        );

      case FormFieldType.inspectionItem:
        final current = _formData[field.id] as String?;
        return FormField<String>(
          initialValue: current,
          validator: field.isRequired
              ? (v) => (v == null || v.isEmpty) ? 'This field is required' : null
              : null,
          builder: (formFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'pass',
                    label: Text('Pass'),
                    icon: Icon(Icons.check_circle_outline),
                  ),
                  ButtonSegment(
                    value: 'fail',
                    label: Text('Fail'),
                    icon: Icon(Icons.cancel_outlined),
                  ),
                  ButtonSegment(
                    value: 'na',
                    label: Text('N/A'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: {if (current != null) current},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) {
                  setState(() {
                    _formData[field.id] = selection.isEmpty ? null : selection.first;
                  });
                  formFieldState.didChange(
                      selection.isEmpty ? null : selection.first);
                },
              ),
              if (formFieldState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    formFieldState.errorText!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        );

      case FormFieldType.rating:
        final currentRating = (_formData[field.id] as num?)?.toInt() ?? 0;
        return FormField<int>(
          initialValue: currentRating,
          validator: field.isRequired
              ? (v) => (v == null || v == 0) ? 'Please select a rating' : null
              : null,
          builder: (formFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() => _formData[field.id] = star);
                      formFieldState.didChange(star);
                    },
                    icon: Icon(
                      star <= currentRating ? Icons.star : Icons.star_border,
                      color: star <= currentRating
                          ? Colors.amber
                          : AppColors.textTertiary,
                    ),
                  );
                }),
              ),
              if (formFieldState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    formFieldState.errorText!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        );

      case FormFieldType.photo:
        // Photo field: same upload mechanic as file, but accepts images only.
        final photoData = _formData[field.id] as Map<String, dynamic>?;
        final isUploading = _uploadingFieldIds.contains(field.id);
        final uploadProgress = _fileUploadProgress[field.id] ?? 0.0;

        return FormField<Map<String, dynamic>?>(
          validator: (_) {
            if (!_canUploadFiles && field.isRequired) {
              return 'Photo uploads are unavailable for this form';
            }
            if (field.isRequired && photoData == null) return 'Please add a photo';
            return null;
          },
          builder: (formFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: (!_canUploadFiles || isUploading)
                    ? null
                    : () => _pickAndUploadFile(field),
                icon: Icon(photoData == null ? Icons.photo_camera : Icons.refresh),
                label: Text(photoData == null ? 'Add Photo' : 'Replace Photo'),
              ),
              if (isUploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: uploadProgress),
              ],
              if (photoData != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.image, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          photoData['fileName'] as String? ?? 'Photo',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (!isUploading)
                        IconButton(
                          onPressed: () {
                            setState(() => _formData.remove(field.id));
                            formFieldState.didChange(null);
                          },
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove photo',
                        ),
                    ],
                  ),
                ),
              ],
              if (formFieldState.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    formFieldState.errorText!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        );

      case FormFieldType.section:
        // Handled in _buildField — should never reach here.
        return const SizedBox.shrink();

      case FormFieldType.time:
        return TextFormField(
          controller: _controllers[field.id],
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'Select time',
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.access_time),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 14),
          ),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              final formatted =
                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
              _controllers[field.id]?.text = formatted;
              _formData[field.id] = formatted;
            }
          },
          validator: (v) {
            if (field.isRequired && (v == null || v.isEmpty)) {
              return '${field.label} is required';
            }
            return null;
          },
        );

      case FormFieldType.table:
        final rawRows = _formData[field.id];
        final typedRows = rawRows is List
            ? rawRows
                .map((e) => e is Map<String, dynamic>
                    ? e
                    : Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];
        return _TableFieldWidget(
          field: field,
          rows: typedRows,
          onChanged: (rows) => setState(() => _formData[field.id] = rows),
        );
    }
  }
}

/// Propagates submission-time context (workspace, project, submission date) down
/// to table cells that need to query other records — workspace member pickers,
/// project area pickers, and time-entry lookups.
class FormFillContext extends InheritedWidget {
  const FormFillContext({
    super.key,
    required this.workspaceId,
    required this.projectId,
    required this.submissionDate,
    required super.child,
  });

  final String? workspaceId;
  final String? projectId;
  final DateTime submissionDate;

  static FormFillContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormFillContext>();

  @override
  bool updateShouldNotify(FormFillContext old) =>
      old.workspaceId != workspaceId ||
      old.projectId != projectId ||
      old.submissionDate != submissionDate;
}

/// Editable table widget for table-type form fields.
class _TableFieldWidget extends StatefulWidget {
  const _TableFieldWidget({
    required this.field,
    required this.rows,
    required this.onChanged,
  });

  final FormFieldDefinition field;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_TableFieldWidget> createState() => _TableFieldWidgetState();
}

class _TableFieldWidgetState extends State<_TableFieldWidget> {
  final dynamic _userService = ServiceLocator.userService;
  final dynamic _areaService = ServiceLocator.areaService;
  final dynamic _timeEntryService = ServiceLocator.timeEntryService;

  List<AppUser> _members = const [];
  List<Area> _areas = const [];
  bool _membersLoaded = false;
  bool _areasLoaded = false;

  /// Tracks which row+column timesheet lookups are in-flight so we don't
  /// re-fire on every rebuild. Key: `$rowIdx:$colKey`.
  final Set<String> _timesheetInFlight = {};

  /// Last employee id we pulled a timesheet for, keyed by row index. Used to
  /// decide whether the worker selection changed and a refetch is needed.
  final Map<int, String?> _lastPulledEmployeeId = {};

  String? _loadedWorkspaceId;
  String? _loadedProjectId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctx = FormFillContext.maybeOf(context);
    final cols = widget.field.columns ?? const [];
    final needsMembers = cols.any((c) => c.type == 'employeeRef');
    final needsAreas = cols.any((c) => c.type == 'locationRef');

    final wsId = ctx?.workspaceId;
    final projId = ctx?.projectId;

    if (needsMembers && wsId != null && wsId != _loadedWorkspaceId) {
      _loadedWorkspaceId = wsId;
      _loadMembers(wsId);
    }
    if (needsAreas && projId != null && projId != _loadedProjectId) {
      _loadedProjectId = projId;
      _loadAreas(projId, wsId);
    }
  }

  Future<void> _loadMembers(String workspaceId) async {
    try {
      final usersMap = await _userService.getWorkspaceUsersMap(workspaceId);
      final list = (usersMap as Map).values.cast<AppUser>().toList()
        ..sort((a, b) =>
            (a.displayName ?? a.email).compareTo(b.displayName ?? b.email));
      if (!mounted) return;
      setState(() {
        _members = list;
        _membersLoaded = true;
      });
    } catch (e) {
      AppLogger.warning('Form table: failed to load workspace members',
          metadata: {'error': e.toString()});
      if (mounted) setState(() => _membersLoaded = true);
    }
  }

  Future<void> _loadAreas(String projectId, String? workspaceId) async {
    try {
      // Use the stream's first emission as a one-shot fetch.
      final areas = await _areaService
          .getAreasByProject(projectId, workspaceId: workspaceId)
          .first;
      if (!mounted) return;
      setState(() {
        _areas = (areas as List).cast<Area>();
        _areasLoaded = true;
      });
    } catch (e) {
      AppLogger.warning('Form table: failed to load project areas',
          metadata: {'error': e.toString()});
      if (mounted) setState(() => _areasLoaded = true);
    }
  }

  void _updateRow(int rowIndex, Map<String, dynamic> next) {
    final updated = List<Map<String, dynamic>>.from(widget.rows);
    updated[rowIndex] = next;
    widget.onChanged(updated);
  }

  /// Checks the row's employeeRef companion id, fires time-entry lookup if
  /// changed, and writes the computed value back into the row.
  Future<void> _pullTimesheetIfNeeded(
      int rowIndex, Map<String, dynamic> row, TableColumnDef col) async {
    final computeFrom = col.computeFrom;
    if (computeFrom == null) return;
    final workerId = row['${computeFrom}_id'] as String?;
    final lookupKey = '$rowIndex:${col.key}';
    if (_timesheetInFlight.contains(lookupKey)) return;

    if (workerId == null || workerId.isEmpty) {
      // Worker cleared — clear any stale computed values.
      if (_lastPulledEmployeeId[rowIndex] != null) {
        _lastPulledEmployeeId[rowIndex] = null;
      }
      return;
    }
    if (_lastPulledEmployeeId[rowIndex] == workerId &&
        row.containsKey(col.key) &&
        (row[col.key]?.toString().isNotEmpty ?? false)) {
      return;
    }

    _timesheetInFlight.add(lookupKey);
    try {
      final ctx = FormFillContext.maybeOf(context);
      final date = ctx?.submissionDate ?? DateTime.now();
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      final entries = await _timeEntryService.getTimeEntriesForDateRangeOnce(
        workerId,
        startOfDay,
        endOfDay,
        workspaceId: ctx?.workspaceId,
      );
      if (!mounted) return;
      _lastPulledEmployeeId[rowIndex] = workerId;
      // Apply pulled values for every timesheetPull column in this row that
      // computes from the same employee column — avoids N separate network calls.
      final cols = widget.field.columns ?? const [];
      final computedUpdates = <String, String>{};
      for (final c in cols) {
        if (c.type != 'timesheetPull' || c.computeFrom != computeFrom) continue;
        computedUpdates[c.key] = _formatPull(entries as List, c.pullField);
      }
      final next = Map<String, dynamic>.from(row);
      next.addAll(computedUpdates);
      _updateRow(rowIndex, next);
    } catch (e) {
      AppLogger.warning('Form table: timesheet lookup failed',
          metadata: {'error': e.toString()});
    } finally {
      _timesheetInFlight.remove(lookupKey);
    }
  }

  String _formatPull(List entries, String? pullField) {
    if (entries.isEmpty) return '';
    // Sum totals across entries; take earliest clockIn and latest clockOut.
    dynamic earliestIn;
    dynamic latestOut;
    int breakMinutes = 0;
    int totalMinutes = 0;
    for (final e in entries) {
      final clockIn = e.clockIn as DateTime;
      final clockOut = e.clockOut as DateTime?;
      if (earliestIn == null || clockIn.isBefore(earliestIn)) earliestIn = clockIn;
      if (clockOut != null &&
          (latestOut == null || clockOut.isAfter(latestOut))) {
        latestOut = clockOut;
      }
      breakMinutes += (e.breakDuration as int);
      totalMinutes += (e.totalDuration as int);
    }
    switch (pullField) {
      case 'startTime':
        return earliestIn == null ? '' : _fmtTime(earliestIn as DateTime);
      case 'endTime':
        return latestOut == null ? '' : _fmtTime(latestOut as DateTime);
      case 'breakMinutes':
        return breakMinutes.toString();
      case 'totalHours':
        return (totalMinutes / 60.0).toStringAsFixed(2);
      default:
        return '';
    }
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final columns = widget.field.columns ?? [];
    if (columns.isEmpty) {
      return const Text('No columns defined for this table.',
          style: TextStyle(color: AppColors.textSecondary));
    }

    final rows = widget.rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 44,
            columns: [
              for (final col in columns)
                DataColumn(label: Text(col.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12))),
              const DataColumn(label: SizedBox(width: 32)),
            ],
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  cells: [
                    for (final col in columns)
                      DataCell(_buildCell(context, col, rows[i], i)),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          final updated =
                              List<Map<String, dynamic>>.from(rows);
                          updated.removeAt(i);
                          _lastPulledEmployeeId.remove(i);
                          widget.onChanged(updated);
                        },
                        visualDensity: VisualDensity.compact,
                        color: AppColors.textTertiary,
                        tooltip: 'Remove row',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final newRow = <String, dynamic>{};
            for (final col in columns) {
              newRow[col.key] = '';
            }
            widget.onChanged([...rows, newRow]);
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Row'),
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, TableColumnDef col,
      Map<String, dynamic> row, int rowIndex) {
    final value = row[col.key]?.toString() ?? '';

    if (col.type == 'employeeRef') {
      return _buildEmployeeRefCell(col, row, rowIndex, value);
    }
    if (col.type == 'locationRef') {
      return _buildLocationRefCell(col, row, rowIndex, value);
    }
    if (col.type == 'timesheetPull') {
      // Fire lookup after build completes if the sibling employee id changed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pullTimesheetIfNeeded(rowIndex, row, col);
      });
      return SizedBox(
        width: 80,
        child: Text(value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 12)),
      );
    }

    if (col.type == 'select' && col.options != null) {
      return DropdownButton<String>(
        value: col.options!.contains(value) ? value : null,
        hint: const Text('Select', style: TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
        items: col.options!
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          _updateRow(
              rowIndex, Map<String, dynamic>.from(row)..[col.key] = v);
        },
      );
    }

    return SizedBox(
      width: col.type == 'number' || col.type == 'time' ? 80 : 140,
      child: TextFormField(
        key: ValueKey('cell_${rowIndex}_${col.key}_$value'),
        initialValue: value,
        style: const TextStyle(fontSize: 12),
        keyboardType: col.type == 'number'
            ? TextInputType.number
            : TextInputType.text,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          border: InputBorder.none,
        ),
        onChanged: (v) {
          _updateRow(
              rowIndex, Map<String, dynamic>.from(row)..[col.key] = v);
        },
      ),
    );
  }

  Widget _buildEmployeeRefCell(TableColumnDef col, Map<String, dynamic> row,
      int rowIndex, String value) {
    final idKey = '${col.key}_id';
    final currentId = row[idKey] as String?;
    if (!_membersLoaded) {
      return const SizedBox(
        width: 140,
        child: Text('Loading…',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    if (_members.isEmpty) {
      // Fallback: no members available → plain editable text.
      return _buildPlainTextCell(col, row, rowIndex, value, width: 140);
    }
    return SizedBox(
      width: 160,
      child: DropdownButton<String>(
        value: _members.any((u) => u.id == currentId) ? currentId : null,
        hint: const Text('Select', style: TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
        items: [
          for (final u in _members)
            DropdownMenuItem(
              value: u.id,
              child: Text(u.displayName ?? u.email,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) {
          final user = _members.firstWhere(
            (u) => u.id == id,
            orElse: () => _members.first,
          );
          final next = Map<String, dynamic>.from(row)
            ..[col.key] = user.displayName ?? user.email
            ..[idKey] = user.id;
          // Clear any cached timesheet values tied to the previous employee so
          // they re-pull with the new worker's entries.
          for (final c in widget.field.columns ?? const []) {
            if (c.type == 'timesheetPull' && c.computeFrom == col.key) {
              next[c.key] = '';
            }
          }
          _lastPulledEmployeeId[rowIndex] = null;
          _updateRow(rowIndex, next);
        },
      ),
    );
  }

  Widget _buildLocationRefCell(TableColumnDef col, Map<String, dynamic> row,
      int rowIndex, String value) {
    final idKey = '${col.key}_id';
    final currentId = row[idKey] as String?;
    if (!_areasLoaded) {
      return const SizedBox(
        width: 140,
        child: Text('Loading…',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    if (_areas.isEmpty) {
      return _buildPlainTextCell(col, row, rowIndex, value, width: 140);
    }
    return SizedBox(
      width: 160,
      child: DropdownButton<String>(
        value: _areas.any((a) => a.id == currentId) ? currentId : null,
        hint: const Text('Select', style: TextStyle(fontSize: 12)),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
        items: [
          for (final a in _areas)
            DropdownMenuItem(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) {
          final area = _areas.firstWhere(
            (a) => a.id == id,
            orElse: () => _areas.first,
          );
          _updateRow(
            rowIndex,
            Map<String, dynamic>.from(row)
              ..[col.key] = area.name
              ..[idKey] = area.id,
          );
        },
      ),
    );
  }

  Widget _buildPlainTextCell(TableColumnDef col, Map<String, dynamic> row,
      int rowIndex, String value,
      {double width = 140}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('cell_${rowIndex}_${col.key}_fallback'),
        initialValue: value,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          border: InputBorder.none,
        ),
        onChanged: (v) {
          _updateRow(
              rowIndex, Map<String, dynamic>.from(row)..[col.key] = v);
        },
      ),
    );
  }
}
