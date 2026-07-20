import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/file_folder.dart';
import '../../models/field_form_template.dart';
import '../../models/field_form_submission.dart';
import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/forms/form_renderer.dart';
import '../../widgets/forms/signature_dialog.dart';
import '../../theme/theme.dart';

class FieldFormFillScreen extends StatefulWidget {
  const FieldFormFillScreen({
    super.key,
    required this.templateId,
    this.taskId,
    this.projectId,
    /// Pre-existing draft submission to resume — null means start fresh.
    this.submissionId,
  });

  final String templateId;
  final String? taskId;
  final String? projectId;
  final String? submissionId;

  @override
  State<FieldFormFillScreen> createState() => _FieldFormFillScreenState();
}

class _FieldFormFillScreenState extends State<FieldFormFillScreen> {
  FieldFormTemplate? _template;
  FieldFormSubmission? _submission;
  Project? _project;
  bool _isLoading = true;
  bool _isSaving = false;

  /// Submission-level photo/file attachment ids. Separate from form field
  /// data — these live on the submission row, not inside its JSONB data blob.
  List<String> _attachedIds = [];
  List<FileAttachment> _attachedFiles = [];
  bool _attachmentUploading = false;
  double _attachmentProgress = 0;

  /// Teammates to notify when this submission is submitted.
  List<String> _notifyUserIds = [];
  List<AppUser> _workspaceUsers = [];
  bool _usersLoaded = false;

  static const int _maxAttachmentBytes = 25 * 1024 * 1024;

  dynamic get _service => ServiceLocator.fieldFormService;
  dynamic get _projectService => ServiceLocator.projectService;
  dynamic get _storageService => ServiceLocator.storageService;
  dynamic get _userService => ServiceLocator.userService;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final template = await _service.getTemplate(widget.templateId);
      FieldFormSubmission? submission;
      if (widget.submissionId != null) {
        submission = await _service.getSubmission(widget.submissionId!);
      }
      Project? project;
      if (widget.projectId != null) {
        try {
          project = await _projectService.getProject(widget.projectId!);
        } catch (_) {
          // Prefill is best-effort — swallow project fetch failures.
        }
      }
      if (mounted) {
        setState(() {
          _template = template;
          _submission = submission;
          _project = project;
          _attachedIds = List<String>.from(submission?.attachedPhotoIds ?? const []);
          _notifyUserIds = List<String>.from(submission?.notifiedUserIds ?? const []);
          _isLoading = false;
        });
        if (_attachedIds.isNotEmpty) {
          _loadAttachmentMetadata();
        }
        _loadWorkspaceUsers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading form: $e')));
      }
    }
  }

  /// Mapping from template field `id` to a resolver that pulls a value from
  /// the current project context. Drafts always win over prefill.
  static final Map<String, dynamic Function(Project)> _jobPrefillMap = {
    'site_address': (p) => p.address,
  };

  Map<String, dynamic> _buildInitialData(FieldFormTemplate template) {
    final data = <String, dynamic>{};
    final project = _project;
    if (project != null) {
      final ids = template.fields.map((f) => f.id).toSet();
      for (final entry in _jobPrefillMap.entries) {
        if (!ids.contains(entry.key)) continue;
        final value = entry.value(project);
        if (value == null) continue;
        if (value is String && value.isEmpty) continue;
        data[entry.key] = value;
      }
    }
    final submissionData = _submission?.data;
    if (submissionData != null) {
      data.addAll(submissionData);
    }
    return data;
  }

  Future<void> _loadWorkspaceUsers() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) return;
    try {
      final map = await _userService.getWorkspaceUsersMap(workspaceId);
      final list = (map as Map).values.cast<AppUser>().toList()
        ..sort((a, b) =>
            (a.displayName ?? a.email).compareTo(b.displayName ?? b.email));
      if (!mounted) return;
      setState(() {
        _workspaceUsers = list;
        _usersLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _usersLoaded = true);
    }
  }

  Future<void> _openNotifyPicker() async {
    if (!_usersLoaded) return;
    final selected = Set<String>.from(_notifyUserIds);
    final currentUserId = context.read<AuthProvider>().appUser?.id;
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final candidates = _workspaceUsers
              .where((u) => u.id != currentUserId)
              .toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notify on submit',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: candidates.isEmpty
                        ? const Text('No other teammates found.',
                            style: TextStyle(color: AppColors.textSecondary))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final u in candidates)
                                CheckboxListTile(
                                  value: selected.contains(u.id),
                                  title: Text(u.displayName ?? u.email),
                                  subtitle: (u.displayName != null &&
                                          u.email.isNotEmpty)
                                      ? Text(u.email,
                                          style: const TextStyle(fontSize: 11))
                                      : null,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged: (v) {
                                    setSheetState(() {
                                      if (v == true) {
                                        selected.add(u.id);
                                      } else {
                                        selected.remove(u.id);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null && mounted) {
      setState(() => _notifyUserIds = result.toList());
    }
  }

  Future<void> _loadAttachmentMetadata() async {
    final ids = List<String>.from(_attachedIds);
    final loaded = <FileAttachment>[];
    for (final id in ids) {
      try {
        final file = await _storageService.getFileWithTags(id);
        if (file != null) loaded.add(file as FileAttachment);
      } catch (_) {
        // Skip files that can't be resolved (deleted, permission issue).
      }
    }
    if (!mounted) return;
    setState(() => _attachedFiles = loaded);
  }

  Future<void> _pickAndUploadAttachment({required bool photoOnly}) async {
    final auth = context.read<AuthProvider>();
    final workspaceId = auth.appUser?.currentWorkspaceId;
    final userId = auth.appUser?.id;
    if (workspaceId == null || userId == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: photoOnly ? FileType.image : FileType.any,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      if (file.size > _maxAttachmentBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'File is too large (${(file.size / 1024 / 1024).toStringAsFixed(1)} MB). Max 25 MB.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      setState(() {
        _attachmentUploading = true;
        _attachmentProgress = 0;
      });

      FileAttachment attachment;
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) throw Exception('Selected file has no bytes');
        attachment = await _storageService.uploadFileBytes(
          bytes: bytes,
          fileName: file.name,
          workspaceId: workspaceId,
          projectId: widget.projectId ?? '_forms',
          uploadedBy: userId,
          tags: const ['form-submission-attachment'],
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _attachmentProgress = p);
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
          workspaceId: workspaceId,
          projectId: widget.projectId ?? '_forms',
          uploadedBy: userId,
          tags: const ['form-submission-attachment'],
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _attachmentProgress = p);
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _attachedIds = [..._attachedIds, attachment.id];
        _attachedFiles = [..._attachedFiles, attachment];
        _attachmentUploading = false;
        _attachmentProgress = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attachmentUploading = false;
        _attachmentProgress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to upload: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  void _removeAttachment(String id) {
    setState(() {
      _attachedIds = _attachedIds.where((x) => x != id).toList();
      _attachedFiles =
          _attachedFiles.where((f) => f.id != id).toList();
    });
  }

  Future<void> _submit(Map<String, dynamic> data) async {
    final template = _template;
    if (template == null) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id;
    final workspaceId = auth.appUser?.currentWorkspaceId;
    final userName = auth.appUser?.displayName ?? '';
    if (userId == null || workspaceId == null) return;

    setState(() => _isSaving = true);
    try {
      // Create or update draft
      String submissionId;
      if (_submission != null) {
        await _service.saveProgress(
            submissionId: _submission!.id,
            data: data,
            attachedPhotoIds: _attachedIds,
            notifiedUserIds: _notifyUserIds);
        submissionId = _submission!.id;
      } else {
        final created = await _service.createSubmission(
          workspaceId: workspaceId,
          templateId: template.id,
          templateName: template.name,
          projectId: widget.projectId,
          taskId: widget.taskId,
          filledById: userId,
          filledByName: userName,
          data: data,
          attachedPhotoIds: _attachedIds,
          notifiedUserIds: _notifyUserIds,
        );
        submissionId = created.id;
      }

      // If technician signature is required, capture it before submitting
      if (template.requiresTechSignature && mounted) {
        final signed = await SignatureDialog.show(
          context,
          title: 'Sign as Technician',
          disclaimer:
              'By signing you confirm the information in this form is accurate.',
          initialName: userName,
          initialEmail: auth.appUser?.email ?? '',
          onSign: (name, email, bytes) async {
            await _service.signAsTechnician(
              submissionId: submissionId,
              workspaceId: workspaceId,
              signatureBytes: bytes,
              name: name,
              email: email,
            );
          },
        );
        if (!signed) {
          // User cancelled signing — stay on the screen
          setState(() => _isSaving = false);
          return;
        }
      }

      // Submit the form
      await _service.submitForm(submissionId);

      // If this is linked to a task, link the submission
      if (widget.taskId != null) {
        await _service.linkSubmissionToTaskForm(
          taskId: widget.taskId!,
          templateId: template.id,
          submissionId: submissionId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Form submitted successfully')),
        );
        if (widget.projectId != null) {
          context.go(
            Uri(
              path: '/files',
              queryParameters: {
                'projectId': widget.projectId!,
                'folder': VirtualFolderType.forms,
              },
            ).toString(),
          );
        } else {
          context.pushReplacement('/field-forms/submissions/$submissionId');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error submitting: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Collects current form data without validation and saves as a draft.
  Future<void> _saveDraft() async {
    final template = _template;
    if (template == null) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id;
    final workspaceId = auth.appUser?.currentWorkspaceId;
    final userName = auth.appUser?.displayName ?? '';
    if (userId == null || workspaceId == null) return;

    setState(() => _isSaving = true);
    try {
      if (_submission != null) {
        await _service.saveProgress(
          submissionId: _submission!.id,
          data: _collectFormData(),
          attachedPhotoIds: _attachedIds,
          notifiedUserIds: _notifyUserIds,
        );
      } else {
        final created = await _service.createSubmission(
          workspaceId: workspaceId,
          templateId: template.id,
          templateName: template.name,
          projectId: widget.projectId,
          taskId: widget.taskId,
          filledById: userId,
          filledByName: userName,
          data: _collectFormData(),
          attachedPhotoIds: _attachedIds,
          notifiedUserIds: _notifyUserIds,
        );
        _submission = created;

        // Link draft to task so the tile shows it exists
        if (widget.taskId != null) {
          await _service.linkSubmissionToTaskForm(
            taskId: widget.taskId!,
            templateId: template.id,
            submissionId: created.id,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Reads the current state of the FormRenderer by triggering a collect
  /// through the global key. Returns what is currently filled in.
  Map<String, dynamic> _collectFormData() {
    // The FormRenderer stores its data internally; to collect it without
    // submitting we access the renderer state via the key.
    final rendererState = _rendererKey.currentState;
    if (rendererState != null) {
      return rendererState.collectData();
    }
    return _submission?.data ?? {};
  }

  final _rendererKey = GlobalKey<FormRendererState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_template?.name ?? 'Fill Form'),
        actions: [
          if (_template != null)
            TextButton(
              onPressed: _isSaving ? null : _saveDraft,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Draft'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _template == null
              ? const Center(child: Text('Form template not found'))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final template = _template!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContextBanner(context, template),
          const SizedBox(height: 16),
          _buildAttachmentsSection(context),
          const SizedBox(height: 12),
          _buildNotifySection(context),
          const SizedBox(height: 16),
          FormRenderer(
            key: _rendererKey,
            fields: template.fields,
            initialData: _buildInitialData(template),
            onSubmit: _isSaving ? null : _submit,
            submitLabel: template.requiresTechSignature
                ? 'Submit & Sign'
                : 'Submit Form',
            workspaceId: context
                .read<AuthProvider>()
                .appUser
                ?.currentWorkspaceId,
            projectId: widget.projectId,
            uploadedBy:
                context.read<AuthProvider>().appUser?.id,
          ),
        ],
      ),
    );
  }

  Widget _buildContextBanner(
      BuildContext context, FieldFormTemplate template) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(_categoryIcon(template.category),
              color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.category.displayName,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                if (template.description != null)
                  Text(template.description!,
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (template.requiresAnySignature)
            const Tooltip(
              message: 'Signature required',
              child: Icon(Icons.draw_outlined,
                  size: 16, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    final canUpload = user != null && user.currentWorkspaceId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Attachments (${_attachedIds.length})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: (!canUpload || _attachmentUploading)
                    ? null
                    : () => _pickAndUploadAttachment(photoOnly: true),
                icon: const Icon(Icons.photo_camera, size: 16),
                label: const Text('Add Photo'),
              ),
              OutlinedButton.icon(
                onPressed: (!canUpload || _attachmentUploading)
                    ? null
                    : () => _pickAndUploadAttachment(photoOnly: false),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Add File'),
              ),
            ],
          ),
          if (_attachmentUploading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _attachmentProgress),
          ],
          if (_attachedFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final f in _attachedFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      f.mimeType.startsWith('image/')
                          ? Icons.image
                          : Icons.insert_drive_file,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f.fileName,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAttachment(f.id),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ),
          ] else if (_attachedIds.isNotEmpty) ...[
            // Ids exist but metadata hasn't resolved yet (still loading).
            const SizedBox(height: 10),
            const Text('Loading attachments…',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (!canUpload)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Attachments require a workspace context.',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotifySection(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().appUser?.id;
    final usersById = {for (final u in _workspaceUsers) u.id: u};
    final selected = _notifyUserIds
        .where((id) => id != currentUserId && usersById.containsKey(id))
        .toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_none,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Notify on submit',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _usersLoaded ? _openNotifyPicker : null,
                child: Text(selected.isEmpty ? 'Choose' : 'Edit'),
              ),
            ],
          ),
          if (selected.isEmpty)
            const Text(
              'No teammates selected. They will be notified in-app once you submit.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in selected)
                  Chip(
                    label: Text(
                        usersById[id]!.displayName ?? usersById[id]!.email,
                        style: const TextStyle(fontSize: 12)),
                    onDeleted: () {
                      setState(() {
                        _notifyUserIds =
                            _notifyUserIds.where((x) => x != id).toList();
                      });
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _categoryIcon(FieldFormCategory cat) {
    switch (cat) {
      case FieldFormCategory.inspection:
        return Icons.search;
      case FieldFormCategory.completion:
        return Icons.check_circle_outline;
      case FieldFormCategory.safety:
        return Icons.shield_outlined;
      case FieldFormCategory.assessment:
        return Icons.assignment_outlined;
      case FieldFormCategory.custom:
        return Icons.description_outlined;
    }
  }
}
