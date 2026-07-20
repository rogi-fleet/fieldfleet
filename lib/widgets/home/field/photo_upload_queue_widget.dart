import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Quick photo capture and upload status for job site documentation.
class PhotoUploadQueueWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;

  const PhotoUploadQueueWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
  });

  @override
  State<PhotoUploadQueueWidget> createState() => _PhotoUploadQueueWidgetState();
}

class _PhotoUploadQueueWidgetState extends State<PhotoUploadQueueWidget> {
  final ImagePicker _picker = ImagePicker();
  final List<_PhotoUploadItem> _recentUploads = [];
  bool _isCapturing = false;
  String? _selectedProjectId;

  String? get _selectedProjectName {
    if (_selectedProjectId == null) return null;
    return widget.allProjects
        ?.cast<Project?>()
        .firstWhere((p) => p!.id == _selectedProjectId, orElse: () => null)
        ?.name;
  }

  Future<void> _captureAndUpload(ImageSource source) async {
    if (_isCapturing) return;

    if (_selectedProjectId == null) {
      _showProjectPicker();
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) {
        if (mounted) setState(() => _isCapturing = false);
        return;
      }

      final item = _PhotoUploadItem(
        fileName: image.name,
        status: _UploadStatus.uploading,
      );

      setState(() {
        _recentUploads.insert(0, item);
        _isCapturing = false;
      });

      try {
        await ServiceLocator.storageService.uploadFile(
          file: File(image.path),
          fileName: image.name,
          workspaceId: widget.workspaceId,
          projectId: _selectedProjectId!,
          uploadedBy: widget.userId,
        );
        if (mounted) {
          setState(() => item.status = _UploadStatus.complete);
        }
      } catch (_) {
        if (mounted) {
          setState(() => item.status = _UploadStatus.failed);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _showProjectPicker() {
    final singularTerminology = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );
    final activeProjects = (widget.allProjects ?? <Project>[])
        .where((p) => p.status == ProjectStatus.active)
        .toList();

    if (activeProjects.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Select $singularTerminology',
                    style: Theme.of(ctx).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...activeProjects.map((project) => ListTile(
              title: Text(project.name),
              trailing: _selectedProjectId == project.id
                  ? const Icon(Icons.check, color: Color(0xFF4F46E5))
                  : null,
              onTap: () {
                setState(() => _selectedProjectId = project.id);
                Navigator.of(ctx).pop();
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: AppSpacing.base),

            // Project selector
            InkWell(
              onTap: _showProjectPicker,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.iconGap,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _selectedProjectName ??
                            'Select a ${singularTerminology.toLowerCase()} first',
                        style: TextStyle(
                          fontSize: 13,
                          color: _selectedProjectId != null
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Quick action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isCapturing
                        ? null
                        : () => _captureAndUpload(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Take Photo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _captureAndUpload(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),

            // Recent uploads
            if (_recentUploads.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.iconGap),
              const Text(
                'Recent Uploads',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._recentUploads.take(4).map((item) {
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _iconForStatus(item.status),
                        size: 16,
                        color: _colorForStatus(item.status),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.fileName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _labelForStatus(item.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _colorForStatus(item.status),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.photo_camera,
                        size: 48,
                        color: AppColors.cardBorder,
                      ),
                      const SizedBox(height: AppSpacing.iconGap),
                      const Text(
                        'No photos captured yet',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Capture photos for ${singularTerminology.toLowerCase()} site documentation',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.camera_alt,
            color: Color(0xFF4F46E5),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Photo Upload',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (_recentUploads.isNotEmpty)
          TextButton(
            onPressed: () => context.go('/files'),
            child: const Text('View All'),
          ),
      ],
    );
  }

  IconData _iconForStatus(_UploadStatus status) {
    switch (status) {
      case _UploadStatus.uploading:
        return Icons.cloud_upload;
      case _UploadStatus.complete:
        return Icons.check_circle;
      case _UploadStatus.failed:
        return Icons.error;
    }
  }

  Color _colorForStatus(_UploadStatus status) {
    switch (status) {
      case _UploadStatus.uploading:
        return AppColors.info;
      case _UploadStatus.complete:
        return AppColors.success;
      case _UploadStatus.failed:
        return AppColors.error;
    }
  }

  String _labelForStatus(_UploadStatus status) {
    switch (status) {
      case _UploadStatus.uploading:
        return 'Uploading';
      case _UploadStatus.complete:
        return 'Done';
      case _UploadStatus.failed:
        return 'Failed';
    }
  }
}

enum _UploadStatus { uploading, complete, failed }

class _PhotoUploadItem {
  final String fileName;
  _UploadStatus status;

  _PhotoUploadItem({required this.fileName, required this.status});
}
