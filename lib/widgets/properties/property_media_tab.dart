import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../file_upload_widget.dart';
import '../../screens/files/file_markup_editor_screen.dart';

class PropertyMediaTab extends StatelessWidget {
  final Property property;
  final Project project;

  const PropertyMediaTab({
    super.key,
    required this.property,
    required this.project,
  });

  String get _propertyTag => 'property:${property.id}';

  @override
  Widget build(BuildContext context) {
    final storageService = ServiceLocator.storageService;
    final userId = context.read<AuthProvider>().appUser?.id ?? '';

    return StreamBuilder<List<FileAttachment>>(
      stream: storageService.getProjectFiles(
        project.workspaceId,
        project.id,
      ),
      builder: (context, snapshot) {
        final allFiles = snapshot.data ?? [];
        final files = allFiles
            .where((f) => f.tags.contains(_propertyTag))
            .toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${files.length} file${files.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showUploadSheet(context, project, userId),
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('Upload'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (snapshot.connectionState == ConnectionState.waiting &&
                allFiles.isEmpty)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (files.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No files yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload photos or documents for this property.',
                        style: TextStyle(color: AppColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return _FileGridTile(
                      file: file,
                      onTap: () => _showViewer(context, files, index),
                      onDelete: () => _deleteFile(context, file),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _showUploadSheet(
      BuildContext context, Project project, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: FileUploadWidget(
            workspaceId: project.workspaceId,
            projectId: project.id,
            tags: [_propertyTag],
            uploadedBy: userId,
            onUploadComplete: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  void _showViewer(
      BuildContext context, List<FileAttachment> files, int initialIndex) {
    final outerContext = context;
    showDialog(
      context: context,
      builder: (_) => _MediaViewer(
        files: files,
        initialIndex: initialIndex,
        onEdit: (file) => Navigator.of(outerContext).push(
          MaterialPageRoute(builder: (_) => FileMarkupEditorScreen(file: file)),
        ),
      ),
    );
  }

  Future<void> _deleteFile(
      BuildContext context, FileAttachment file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(file.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.storageService.deleteFile(file);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }
}

class _FileGridTile extends StatelessWidget {
  final FileAttachment file;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _FileGridTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file.isImage)
              CachedNetworkImage(
                imageUrl: file.fileUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _filePlaceholder(),
                progressIndicatorBuilder: (_, __, ___) =>
                    const Center(child: CircularProgressIndicator()),
              )
            else
              _filePlaceholder(),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
            if (!file.isImage)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: 2),
                  child: Text(
                    file.fileName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filePlaceholder() {
    return Container(
      color: AppColors.surfaceAlt,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            file.isPDF ? Icons.picture_as_pdf : Icons.insert_drive_file,
            size: 32,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              file.fileExtension.toUpperCase(),
              style: TextStyle(
                  fontSize: 10, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaViewer extends StatefulWidget {
  final List<FileAttachment> files;
  final int initialIndex;
  final void Function(FileAttachment file)? onEdit;

  const _MediaViewer({
    required this.files,
    required this.initialIndex,
    this.onEdit,
  });

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late int _current;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.files[_current];
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(AppSpacing.base),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.files.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final f = widget.files[i];
              return f.isImage
                  ? InteractiveViewer(
                      child: Center(child: CachedNetworkImage(imageUrl: f.fileUrl)),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.insert_drive_file,
                              size: 64, color: Colors.white54),
                          const SizedBox(height: 12),
                          Text(f.fileName,
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    );
            },
          ),
          if (widget.onEdit != null && widget.files[_current].isImage)
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                tooltip: 'Edit image',
                onPressed: () {
                  final file = widget.files[_current];
                  Navigator.pop(context);
                  widget.onEdit!(file);
                },
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Text(
                  file.fileName,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (widget.files.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_current + 1} / ${widget.files.length}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
