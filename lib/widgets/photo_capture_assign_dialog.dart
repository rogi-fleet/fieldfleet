import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../utils/project_terminology.dart';
import '../theme/theme.dart';
import 'project_selector_dialog.dart';

/// Opens the photo-capture-and-assign flow.
///
/// Optionally pass [preSelectedProject] to skip the project picker step when
/// the user is already inside a project context.
Future<void> showPhotoCaptureAssignDialog(
  BuildContext context, {
  Project? preSelectedProject,
  Task? preSelectedTask,
}) async {
  final source = await _pickSource(context);
  if (source == null || !context.mounted) return;

  final images = await _pickImages(source);
  if (images.isEmpty || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PhotoAssignSheet(
      images: images,
      preSelectedProject: preSelectedProject,
      preSelectedTask: preSelectedTask,
    ),
  );
}

Future<ImageSource?> _pickSource(BuildContext context) async {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SourceSheet(),
  );
}

Future<List<XFile>> _pickImages(ImageSource source) async {
  if (source == ImageSource.camera && kIsWeb) return const [];

  final picker = ImagePicker();

  if (source == ImageSource.camera) {
    final image = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    return image == null ? const [] : [image];
  }

  return picker.pickMultiImage(
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
}

class _SourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add photo',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!kIsWeb)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.secondary,
                ),
              ),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.info,
              ),
            ),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PhotoAssignSheet extends StatefulWidget {
  final List<XFile> images;
  final Project? preSelectedProject;
  final Task? preSelectedTask;

  const _PhotoAssignSheet({
    required this.images,
    this.preSelectedProject,
    this.preSelectedTask,
  });

  @override
  State<_PhotoAssignSheet> createState() => _PhotoAssignSheetState();
}

class _PhotoAssignSheetState extends State<_PhotoAssignSheet> {
  late Project? _project = widget.preSelectedProject;
  late Task? _task = widget.preSelectedTask;
  late final Future<List<Uint8List>> _imageBytesFuture;
  List<Task>? _tasks;
  bool _loadingTasks = false;
  bool _uploading = false;
  double _progress = 0;
  int _uploadingIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _imageBytesFuture = Future.wait(
      widget.images.map((image) => image.readAsBytes()),
    );
    if (_project != null) {
      _loadTasks(_project!.id, preserveSelectedTask: true);
    }
  }

  Future<void> _loadTasks(
    String projectId, {
    bool preserveSelectedTask = false,
  }) async {
    final selectedTaskId = preserveSelectedTask ? _task?.id : null;
    setState(() {
      _loadingTasks = true;
      if (!preserveSelectedTask) {
        _task = null;
      }
      _tasks = null;
    });
    try {
      final snap = await ServiceLocator.taskService.getTasks(projectId).first;
      if (mounted) {
        final activeTasks = snap.where((t) => !t.isComplete).toList();
        setState(() {
          _tasks = activeTasks;
          _task = selectedTaskId == null
              ? _task
              : activeTasks.cast<Task?>().firstWhere(
                  (task) => task?.id == selectedTaskId,
                  orElse: () => null,
                );
          _loadingTasks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _pickProject(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final project = await showDialog<Project>(
      context: context,
      builder: (ctx) => ProjectSelectorDialog(
        workspaceId: workspaceId,
        currentProjectId: _project?.id,
      ),
    );
    if (project != null) {
      setState(() => _project = project);
      _loadTasks(project.id);
    }
  }

  Future<void> _save() async {
    if (_project == null) return;
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final userId = authProvider.appUser?.id ?? '';

    setState(() {
      _uploading = true;
      _progress = 0;
      _uploadingIndex = 0;
      _error = null;
    });

    try {
      final imageBytes = await _imageBytesFuture;
      final totalImages = widget.images.length;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (var index = 0; index < totalImages; index++) {
        final image = widget.images[index];
        final bytes = imageBytes[index];
        final fileName = image.name.isNotEmpty
            ? image.name
            : 'photo_${timestamp}_${index + 1}.jpg';

        if (mounted) {
          setState(() {
            _uploadingIndex = index;
          });
        }

        await ServiceLocator.storageService.uploadFileBytes(
          bytes: bytes,
          fileName: fileName,
          workspaceId: workspaceId,
          projectId: _project!.id,
          taskId: _task?.id,
          uploadedBy: userId,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = (index + p) / totalImages;
            });
          },
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = 'Upload failed. Please try again.';
        });
      }
    }
  }

  Widget _buildPreview() {
    return FutureBuilder<List<Uint8List>>(
      future: _imageBytesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final images = snapshot.data!;
        if (images.length == 1) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: Image.memory(
              images.first,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.r12),
              child: Image.memory(
                images.first,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${images.length} photos selected',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.memory(
                      images[index],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final projectTermLower = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text(
                  widget.images.length == 1 ? 'Save photo' : 'Save photos',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _uploading
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _buildPreview(),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Project',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _uploading ? null : () => _pickProject(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _project == null
                            ? AppColors.error.withValues(alpha: 0.6)
                            : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: _project == null
                              ? AppColors.error
                              : AppColors.info,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _project?.name ?? 'Select a ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}…',
                            style: TextStyle(
                              color: _project == null ? Colors.grey : null,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_project != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assign to task (optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _loadingTasks
                      ? const SizedBox(
                          height: 44,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : DropdownButtonFormField<Task?>(
                        borderRadius: AppRadius.cardRadius,
                          initialValue: _task,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: AppSpacing.md,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                          hint: Text('No task — save to $projectTermLower files'),
                          items: [
                            DropdownMenuItem<Task?>(
                              value: null,
                              child:
                                  Text('No task — save to $projectTermLower files'),
                            ),
                            if (_tasks != null)
                              for (final t in _tasks!)
                                DropdownMenuItem<Task?>(
                                  value: t,
                                  child: Text(
                                    t.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          ],
                          onChanged: _uploading
                              ? null
                              : (t) => setState(() => _task = t),
                        ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          if (_uploading)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.images.length == 1
                          ? 'Uploading photo...'
                          : 'Uploading ${_uploadingIndex + 1} of ${widget.images.length}...',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton(
              onPressed: (_project == null || _uploading) ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: _uploading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.images.length == 1
                          ? 'Save photo'
                          : 'Save ${widget.images.length} photos',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
