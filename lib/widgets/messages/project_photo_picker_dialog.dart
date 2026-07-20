import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/file_attachment.dart';
import '../../models/message_attachment.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';

/// Shows a dialog to pick photos from a project and returns them as
/// [MessageAttachment]s ready for use in the messaging system.
Future<List<MessageAttachment>?> showProjectPhotoPicker({
  required BuildContext context,
  required String workspaceId,
  required String projectId,
  Set<String> alreadyAttachedIds = const {},
}) {
  return showDialog<List<MessageAttachment>>(
    context: context,
    builder: (context) => _ProjectPhotoPickerDialog(
      workspaceId: workspaceId,
      projectId: projectId,
      alreadyAttachedIds: alreadyAttachedIds,
    ),
  );
}

class _ProjectPhotoPickerDialog extends StatefulWidget {
  final String workspaceId;
  final String projectId;
  final Set<String> alreadyAttachedIds;

  const _ProjectPhotoPickerDialog({
    required this.workspaceId,
    required this.projectId,
    this.alreadyAttachedIds = const {},
  });

  @override
  State<_ProjectPhotoPickerDialog> createState() =>
      _ProjectPhotoPickerDialogState();
}

class _ProjectPhotoPickerDialogState extends State<_ProjectPhotoPickerDialog> {
  final _storageService = ServiceLocator.storageService;
  final Set<String> _selectedIds = {};
  List<FileAttachment> _images = [];
  bool _isLoading = true;
  late Stream<List<FileAttachment>> _filesStream;

  @override
  void initState() {
    super.initState();
    _filesStream = _storageService.getProjectFiles(
      widget.workspaceId,
      widget.projectId,
    );
  }

  void _toggle(FileAttachment file) {
    setState(() {
      if (_selectedIds.contains(file.id)) {
        _selectedIds.remove(file.id);
      } else {
        _selectedIds.add(file.id);
      }
    });
  }

  void _confirm() {
    final selected = _images
        .where((f) => _selectedIds.contains(f.id))
        .map((f) => f.toMessageAttachment())
        .toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.photo_library, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '$singular Photos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Grid
            Expanded(
              child: StreamBuilder<List<FileAttachment>>(
                stream: _filesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final files = snapshot.data ?? [];
                  final images = files.where((f) => f.isImage).toList();

                  if (images.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && (_isLoading || _images.length != images.length)) {
                        setState(() {
                          _images = images;
                          _isLoading = false;
                        });
                      }
                    });
                  } else if (!_isLoading || snapshot.connectionState != ConnectionState.waiting) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _isLoading) {
                        setState(() => _isLoading = false);
                      }
                    });
                  }

                  if (images.isEmpty && !_isLoading) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 48,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No photos in this ${singular.toLowerCase()}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final image = images[index];
                      final isAlreadyAttached =
                          widget.alreadyAttachedIds.contains(image.id);
                      final isSelected = _selectedIds.contains(image.id);

                      return GestureDetector(
                        onTap: isAlreadyAttached
                            ? () {
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text('Already attached'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                              }
                            : () => _toggle(image),
                        child: Opacity(
                          opacity: isAlreadyAttached ? 0.5 : 1.0,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                child: CachedNetworkImage(
                                  imageUrl: image.fileUrl,
                                  fit: BoxFit.cover,
                                  progressIndicatorBuilder: (context, url, progress) =>
                                      Container(
                                        color: colorScheme.surfaceContainerHighest,
                                        child: const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                  errorWidget: (context, url, error) => Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: Icon(Icons.broken_image, color: colorScheme.outline),
                                  ),
                                ),
                              ),
                              if (isSelected || isAlreadyAttached)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(
                                        color: isAlreadyAttached
                                            ? colorScheme.outline
                                            : colorScheme.primary,
                                        width: 3),
                                    color: (isAlreadyAttached
                                            ? colorScheme.outline
                                            : colorScheme.primary)
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isAlreadyAttached
                                        ? colorScheme.outline
                                        : isSelected
                                            ? colorScheme.primary
                                            : Colors.black
                                                .withValues(alpha: 0.5),
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: (isSelected || isAlreadyAttached)
                                      ? const Icon(Icons.check,
                                          size: 14, color: Colors.white)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedIds.length} selected',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedIds.isEmpty ? null : _confirm,
                    child: const Text('Attach'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
