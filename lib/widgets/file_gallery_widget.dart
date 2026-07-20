import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/file_attachment.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/files/file_markup_editor_screen.dart';

class FileGalleryWidget extends StatelessWidget {
  final String workspaceId;
  final String projectId;
  final String? taskId;

  const FileGalleryWidget({
    super.key,
    required this.workspaceId,
    required this.projectId,
    this.taskId,
  });

  Future<void> _deleteFile(BuildContext context, FileAttachment file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.fileName}"?'),
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

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.storageService.deleteFile(file);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('File deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting file'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _openEditor(BuildContext context, FileAttachment file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileMarkupEditorScreen(file: file),
      ),
    );
  }

  Future<void> _openFile(BuildContext context, FileAttachment file) async {
    if (file.isImage) {
      // Capture outer context for the editor navigation below
      final outerContext = context;
      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          child: Stack(
            children: [
              InteractiveViewer(
                child: CachedNetworkImage(imageUrl: file.fileUrl, fit: BoxFit.contain),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white, size: 24),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _openEditor(outerContext, file);
                  },
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  tooltip: 'Edit image',
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(dialogContext),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Download/open document
      final uri = Uri.parse(file.fileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not open file'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FileAttachment>>(
      stream: taskId != null
          ? ServiceLocator.storageService.getTaskFiles(workspaceId, taskId!)
          : ServiceLocator.storageService.getProjectFiles(
              workspaceId,
              projectId,
            ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load files'),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final files = snapshot.data ?? [];

        if (files.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No files uploaded yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Separate images and documents
        final images = files.where((f) => f.isImage).toList();
        final documents = files.where((f) => !f.isImage).toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Images grid
              if (images.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    'Images (${images.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final file = images[index];
                    return _ImageThumbnail(
                      file: file,
                      onTap: () => _openFile(context, file),
                      onEdit: () => _openEditor(context, file),
                      onDelete: () => _deleteFile(context, file),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Documents list
              if (documents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    'Documents (${documents.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final file = documents[index];
                    return _DocumentListTile(
                      file: file,
                      onTap: () => _openFile(context, file),
                      onDelete: () => _deleteFile(context, file),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final FileAttachment file;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ImageThumbnail({
    required this.file,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CachedNetworkImage(
              imageUrl: file.thumbnailUrl ?? file.fileUrl,
              fit: BoxFit.cover,
              progressIndicatorBuilder: (context, url, progress) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) => Container(
                color: AppColors.cardBorder,
                child: const Icon(Icons.broken_image, size: 32),
              ),
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
              onPressed: onEdit,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                padding: const EdgeInsets.all(AppSpacing.xs),
                minimumSize: const Size(28, 28),
              ),
              tooltip: 'Edit image',
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.white, size: 18),
              onPressed: onDelete,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.error.withValues(alpha: 0.7),
                padding: const EdgeInsets.all(AppSpacing.xs),
                minimumSize: const Size(28, 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentListTile extends StatelessWidget {
  final FileAttachment file;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DocumentListTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
  });

  IconData _getIconForFileType() {
    if (file.isPDF) return Icons.picture_as_pdf;
    if (file.isDocument) return Icons.description;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: ListTile(
        leading: Icon(_getIconForFileType(), size: 32),
        title: Text(file.fileName),
        subtitle: Text('${file.formattedSize} • ${file.fileExtension}'),
        trailing: IconButton(
          icon: Icon(Icons.delete, color: AppColors.error),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}
