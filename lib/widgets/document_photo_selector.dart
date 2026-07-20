import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:taskfleet_ops/services/supabase/storage_service.dart';
import 'package:taskfleet_ops/theme/theme.dart';
import 'package:taskfleet_ops/providers/workspace_provider.dart';
import 'package:taskfleet_ops/utils/project_terminology.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/file_attachment.dart';
import '../services/service_locator.dart';

/// A widget for selecting project files to attach to documents.
/// Displays a grid of project artifacts with multi-select checkmarks
/// and allows uploading new files directly.
class DocumentPhotoSelector extends StatefulWidget {
  final String workspaceId;
  final String projectId;
  final String uploadedBy;
  final List<String> initialSelectedIds;
  final Function(List<String> selectedIds, List<FileAttachment> selectedFiles)
  onSelectionChanged;

  const DocumentPhotoSelector({
    super.key,
    required this.workspaceId,
    required this.projectId,
    required this.uploadedBy,
    this.initialSelectedIds = const [],
    required this.onSelectionChanged,
  });

  @override
  State<DocumentPhotoSelector> createState() => _DocumentPhotoSelectorState();
}

class _DocumentPhotoSelectorState extends State<DocumentPhotoSelector> {
  final _storageService = ServiceLocator.storageService;
  final _imagePicker = ImagePicker();
  Set<String> _selectedIds = {};
  List<FileAttachment> _allFiles = [];
  bool _isLoading = true;
  late Stream<List<FileAttachment>> _filesStream;

  // Upload state
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadError;
  int _totalUploads = 0;
  int _completedUploads = 0;

  // Track IDs that existed before upload so we can auto-select new ones
  Set<String> _preUploadIds = {};
  bool _pendingAutoSelect = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _initStream();
  }

  @override
  void didUpdateWidget(DocumentPhotoSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _isLoading = true;
      _initStream();
    }
  }

  void _initStream() {
    _filesStream = _storageService.getProjectFiles(
      widget.workspaceId,
      widget.projectId,
    );
  }

  void _toggleSelection(FileAttachment file) {
    setState(() {
      if (_selectedIds.contains(file.id)) {
        _selectedIds.remove(file.id);
      } else {
        _selectedIds.add(file.id);
      }
    });
    _notifyChange();
  }

  void _selectAll() {
    setState(() {
      _selectedIds = _allFiles.map((f) => f.id).toSet();
    });
    _notifyChange();
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
    _notifyChange();
  }

  void _notifyChange() {
    final selectedFiles = _allFiles
        .where((f) => _selectedIds.contains(f.id))
        .toList();
    widget.onSelectionChanged(_selectedIds.toList(), selectedFiles);
  }

  bool _areListsEqual(List<FileAttachment> a, List<FileAttachment> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  // --- Upload methods ---

  Future<void> _pickFromGallery() async {
    try {
      setState(() => _uploadError = null);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        await _uploadFiles(result.files);
      }
    } catch (e) {
      setState(() => _uploadError = 'Error picking image: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    if (kIsWeb) return;

    try {
      setState(() => _uploadError = null);

      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (photo != null) {
        final file = PlatformFile(
          name: photo.name,
          size: await photo.length(),
          path: photo.path,
          bytes: kIsWeb ? await photo.readAsBytes() : null,
        );
        await _uploadFiles([file]);
      }
    } catch (e) {
      setState(() => _uploadError = 'Error taking photo: $e');
    }
  }

  Future<void> _pickFiles() async {
    try {
      setState(() => _uploadError = null);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'heic',
          'heif',
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
        ],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        await _uploadFiles(result.files);
      }
    } catch (e) {
      setState(() => _uploadError = 'Error picking file: $e');
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    if (files.isEmpty) return;

    // Snapshot current IDs so we can auto-select new ones after upload
    _preUploadIds = _allFiles.map((f) => f.id).toSet();
    _pendingAutoSelect = true;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadError = null;
      _totalUploads = files.length;
      _completedUploads = 0;
    });

    final failedUploads = <String>[];

    for (var i = 0; i < files.length; i++) {
      final platformFile = files[i];

      try {
        if (kIsWeb) {
          if (platformFile.bytes == null) {
            throw Exception('File bytes are null');
          }
          await _storageService.uploadFileBytes(
            bytes: platformFile.bytes!,
            fileName: platformFile.name,
            workspaceId: widget.workspaceId,
            projectId: widget.projectId,
            uploadedBy: widget.uploadedBy,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _uploadProgress = (i + progress) / files.length;
              });
            },
          );
        } else {
          if (platformFile.path == null) {
            throw Exception('File path is null');
          }
          await _storageService.uploadFile(
            file: File(platformFile.path!),
            fileName: platformFile.name,
            workspaceId: widget.workspaceId,
            projectId: widget.projectId,
            uploadedBy: widget.uploadedBy,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _uploadProgress = (i + progress) / files.length;
              });
            },
          );
        }
      } on StorageQuotaExceededException catch (e) {
        failedUploads.add(e.toString());
        break;
      } catch (e) {
        failedUploads.add('${platformFile.name}: $e');
      }

      if (!mounted) return;

      setState(() {
        _completedUploads = i + 1;
        _uploadProgress = (i + 1) / files.length;
      });
    }

    if (!mounted) return;

    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
      _totalUploads = 0;
      _completedUploads = 0;
      _uploadError = failedUploads.isEmpty ? null : failedUploads.join('\n');
    });

    if (failedUploads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            files.length == 1
                ? 'File uploaded'
                : '${files.length} files uploaded',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (failedUploads.length < files.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Uploaded ${files.length - failedUploads.length} of ${files.length} files',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Widget _buildUploadButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _UploadActionChip(
          icon: Icons.photo_library,
          label: 'Photo Library',
          onTap: _pickFromGallery,
        ),
        if (!kIsWeb)
          _UploadActionChip(
            icon: Icons.camera_alt,
            label: 'Camera',
            onTap: _pickFromCamera,
          ),
        _UploadActionChip(
          icon: Icons.attach_file,
          label: 'Choose Files',
          onTap: _pickFiles,
        ),
      ],
    );
  }

  Widget _buildUploadProgress() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _totalUploads > 1
                ? 'Uploading ${_completedUploads + 1} of $_totalUploads...'
                : 'Uploading...',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _uploadProgress),
          const SizedBox(height: 4),
          Text(
            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with selection controls
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Icon(Icons.attach_file, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '$singularTerminology Files',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_allFiles.isNotEmpty) ...[
                TextButton(
                  onPressed: _selectAll,
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ),

        // Upload progress
        if (_isUploading) _buildUploadProgress(),

        // Upload error
        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: Text(
              _uploadError!,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),

        // File grid
        StreamBuilder<List<FileAttachment>>(
          stream: _filesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: Text(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load files',
                    ),
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                _isLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final files = snapshot.data ?? [];
            final documentFiles = files
                .where((f) => f.isImage || f.isPDF || f.isDocument)
                .toList();

            // Update state after frame to avoid setState during build
            final hasChanged =
                _allFiles.length != documentFiles.length ||
                _isLoading ||
                !_areListsEqual(_allFiles, documentFiles);

            if (hasChanged) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  // Auto-select newly uploaded files
                  if (_pendingAutoSelect && !_isUploading) {
                    final newIds = documentFiles
                        .map((f) => f.id)
                        .where((id) => !_preUploadIds.contains(id))
                        .toSet();
                    if (newIds.isNotEmpty) {
                      _selectedIds.addAll(newIds);
                      _pendingAutoSelect = false;
                    }
                  }

                  setState(() {
                    _allFiles = documentFiles;
                    _isLoading = false;
                  });

                  // Notify if we auto-selected
                  if (_selectedIds.isNotEmpty) {
                    _notifyChange();
                  }
                }
              });
            }

            if (documentFiles.isEmpty && !_isUploading) {
              return Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.upload_file_outlined,
                        size: 48,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No files in this ${singularTerminology.toLowerCase()}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _buildUploadButtons(),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: documentFiles.length,
                    itemBuilder: (context, index) {
                      final file = documentFiles[index];
                      final isSelected = _selectedIds.contains(file.id);

                      return _PhotoThumbnail(
                        file: file,
                        isSelected: isSelected,
                        onTap: () => _toggleSelection(file),
                      );
                    },
                  ),
                ),
                if (!_isUploading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _buildUploadButtons(),
                  ),
              ],
            );
          },
        ),

        // Footer with selection count
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${_selectedIds.length} file${_selectedIds.length == 1 ? '' : 's'} selected',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact action chip for upload options
class _UploadActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _UploadActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.primary,
      onPressed: onTap,
    );
  }
}

/// Individual file thumbnail with selection state
class _PhotoThumbnail extends StatelessWidget {
  final FileAttachment file;
  final bool isSelected;
  final VoidCallback onTap;

  const _PhotoThumbnail({
    required this.file,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // File preview
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: file.isImage
                ? CachedNetworkImage(
                    imageUrl: file.thumbnailUrl ?? file.fileUrl,
                    fit: BoxFit.cover,
                    progressIndicatorBuilder: (context, url, progress) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image,
                        color: colorScheme.outline,
                      ),
                    ),
                  )
                : Container(
                    color: colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _iconForFile(file),
                          size: 28,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          file.fileExtension,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          file.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Selection overlay
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colorScheme.primary, width: 3),
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),

          // Checkmark
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? colorScheme.primary
                    : Colors.black.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(FileAttachment file) {
    if (file.isPDF) return Icons.picture_as_pdf;
    if (file.mimeType.contains('spreadsheet') ||
        file.mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    if (file.isDocument) return Icons.description;
    return Icons.insert_drive_file;
  }
}
