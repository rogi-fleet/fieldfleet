import 'dart:io';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/plan_discipline.dart';
import '../../models/construction_plan.dart';
import '../../models/property.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/filename_parser.dart';
import '../../utils/project_terminology.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class PlanUploadScreen extends StatefulWidget {
  final String projectId;
  /// Optional pre-selected structure (when entering from a property's
  /// "Add Plan" action). User can still change it.
  final String? initialPropertyId;

  const PlanUploadScreen({
    super.key,
    required this.projectId,
    this.initialPropertyId,
  });

  @override
  State<PlanUploadScreen> createState() => _PlanUploadScreenState();
}

class _PlanUploadScreenState extends State<PlanUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _planService = ServiceLocator.planService;

  File? _selectedFile;
  String? _fileName;
  int? _fileSize;

  final _nameController = TextEditingController();
  final _sheetNumberController = TextEditingController();
  final _versionController = TextEditingController();
  final _notesController = TextEditingController();

  PlanDiscipline _selectedDiscipline = PlanDiscipline.architectural;
  DateTime? _drawingDate;
  bool _isCurrentVersion = true;
  bool _isUploading = false;
  String? _selectedPropertyId;

  bool _nameSuggested = false;
  bool _sheetNumberSuggested = false;
  bool _versionSuggested = false;

  @override
  void initState() {
    super.initState();
    _selectedPropertyId = widget.initialPropertyId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sheetNumberController.dispose();
    _versionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = await file.length();

        // Check file size (50MB limit)
        if (fileSize > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File size must be less than 50MB'),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }

        // Parse filename for suggestions
        final metadata = FilenameParser.parse(fileName);

        setState(() {
          _selectedFile = file;
          _fileName = fileName;
          _fileSize = fileSize;

          // Set suggestions
          if (_nameController.text.isEmpty) {
            _nameController.text = metadata.name;
            _nameSuggested = true;
          }

          if (metadata.sheetNumber != null &&
              _sheetNumberController.text.isEmpty) {
            _sheetNumberController.text = metadata.sheetNumber!;
            _sheetNumberSuggested = true;
          }

          if (metadata.version != null && _versionController.text.isEmpty) {
            _versionController.text = metadata.version!;
            _versionSuggested = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'picking file')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _selectDrawingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _drawingDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _drawingDate = picked;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  Future<void> _uploadPlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a PDF file'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      final userId = authProvider.appUser?.id;

      if (workspaceId == null || userId == null) {
        throw Exception('User not authenticated');
      }

      await _planService.uploadPlan(
        pdfFile: _selectedFile!,
        projectId: widget.projectId,
        workspaceId: workspaceId,
        propertyId: _selectedPropertyId,
        name: _nameController.text.trim(),
        discipline: _selectedDiscipline,
        sheetNumber: _sheetNumberController.text.trim().isEmpty
            ? null
            : _sheetNumberController.text.trim(),
        version: _versionController.text.trim().isEmpty
            ? null
            : _versionController.text.trim(),
        drawingDate: _drawingDate,
        isCurrentVersion: _isCurrentVersion,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        uploadedBy: userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan uploaded successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'uploading plan'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Plan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // File Selection
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDF File',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (_selectedFile == null)
                        OutlinedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Select PDF File'),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.picture_as_pdf,
                                  color: AppColors.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _fileName!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        _formatFileSize(_fileSize!),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setState(() {
                                      _selectedFile = null;
                                      _fileName = null;
                                      _fileSize = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Change File'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Plan Metadata
              if (_selectedFile != null) ...[
                StackedField(
                  label: 'Plan Name *',
                  child: TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.title),
                      helperText: _nameSuggested
                          ? 'Suggested from filename'
                          : 'e.g., First Floor Plan',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a plan name';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      setState(() => _nameSuggested = false);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                StackedField(
                  label: 'Discipline *',
                  child: DropdownButtonFormField<PlanDiscipline>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _selectedDiscipline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: PlanDiscipline.values.map((discipline) {
                      return DropdownMenuItem(
                        value: discipline,
                        child: Row(
                          children: [
                            Icon(
                              discipline.icon,
                              size: 20,
                              color: discipline.color,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(discipline.displayName),
                                Text(
                                  discipline.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedDiscipline = value);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                StackedField(
                  label: 'Structure',
                  child: StreamBuilder<List<Property>>(
                    stream: ServiceLocator.propertyService.getProperties(
                      widget.projectId,
                    ),
                    builder: (context, snapshot) {
                      final properties = snapshot.data ?? const <Property>[];
                      final projectTerm = singularProjectTerminology(
                        context.watch<WorkspaceProvider>().projectTerminology,
                      );
                      final projectTermLower = projectTerm.toLowerCase();
                      // Drop a stale selection if the property no longer
                      // exists in this project.
                      if (_selectedPropertyId != null &&
                          snapshot.hasData &&
                          !properties.any(
                            (p) => p.id == _selectedPropertyId,
                          )) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _selectedPropertyId = null);
                          }
                        });
                      }
                      return DropdownButtonFormField<String?>(
                        borderRadius: AppRadius.cardRadius,
                        initialValue: _selectedPropertyId,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.apartment),
                          helperText: properties.isEmpty
                              ? 'No structures yet — plan will be $projectTermLower-wide'
                              : 'Optional. Leave empty for a $projectTermLower-wide drawing.',
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('$projectTerm-wide (no structure)'),
                          ),
                          ...properties.map(
                            (p) => DropdownMenuItem<String?>(
                              value: p.id,
                              child: Text(p.displayLabel),
                            ),
                          ),
                        ],
                        onChanged: properties.isEmpty
                            ? null
                            : (value) =>
                                  setState(() => _selectedPropertyId = value),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                StackedField(
                  label: 'Sheet Number',
                  child: TextFormField(
                    controller: _sheetNumberController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers),
                      helperText: _sheetNumberSuggested
                          ? 'Suggested from filename'
                          : 'e.g., A-1, E-2.1, S-10',
                    ),
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        if (!ConstructionPlan.validateSheetNumber(
                          value.trim(),
                        )) {
                          return 'Invalid format. Use: A-1, E-2.1, etc.';
                        }
                      }
                      return null;
                    },
                    onChanged: (_) {
                      setState(() => _sheetNumberSuggested = false);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                StackedField(
                  label: 'Version',
                  child: TextFormField(
                    controller: _versionController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.timeline),
                      helperText: _versionSuggested
                          ? 'Suggested from filename'
                          : 'e.g., Rev A, Rev 1, Final',
                    ),
                    onChanged: (_) {
                      setState(() => _versionSuggested = false);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                OutlinedButton.icon(
                  onPressed: _selectDrawingDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _drawingDate == null
                        ? 'Set Drawing Date (optional)'
                        : 'Drawing Date: ${_drawingDate!.month}/${_drawingDate!.day}/${_drawingDate!.year}',
                  ),
                ),
                if (_drawingDate != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _drawingDate = null);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear Date'),
                  ),
                ],
                const SizedBox(height: 16),

                StackedField(
                  label: 'Notes',
                  child: TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      helperText: 'Optional internal notes',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    maxLength: 500,
                  ),
                ),
                const SizedBox(height: 16),

                if (_sheetNumberController.text.trim().isNotEmpty)
                  CheckboxListTile(
                    value: _isCurrentVersion,
                    onChanged: (value) {
                      setState(() => _isCurrentVersion = value ?? true);
                    },
                    title: const Text('Mark as Current Version'),
                    subtitle: const Text(
                      'This will be the active version for this sheet number',
                    ),
                  ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isUploading ? null : _uploadPlan,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Upload Plan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
