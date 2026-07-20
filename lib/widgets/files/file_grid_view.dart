import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/file_attachment.dart';
import '../../theme/theme.dart';
import 'files_filter.dart';

/// Grid / icon view of [FileAttachment]s — image thumbnails for images, type
/// icon otherwise, with name, size, and up to three tag chips. Used by both
/// the per-project Files screen and the global Files browser.
///
/// Selection is opt-in: pass [selectedIds] + [onToggleSelect] to enable
/// long-press selection and tap-to-extend-selection. Pass [onDelete] to
/// surface a per-card delete overlay.
class FileGridView extends StatelessWidget {
  final List<FileAttachment> files;
  final void Function(FileAttachment file) onOpen;

  /// Ids currently selected for bulk operations. Non-null enables
  /// long-press → select and the selection check overlay.
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggleSelect;

  /// When provided, each card shows a small (×) overlay that invokes this
  /// callback. Workspace-level browsers leave this null because deletes
  /// happen in the per-project screen.
  final ValueChanged<FileAttachment>? onDelete;

  const FileGridView({
    super.key,
    required this.files,
    required this.onOpen,
    this.selectedIds,
    this.onToggleSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) => _FileCard(
        file: files[index],
        selected: selectedIds?.contains(files[index].id) ?? false,
        anySelected: selectedIds?.isNotEmpty ?? false,
        onOpen: () => onOpen(files[index]),
        onToggleSelect: onToggleSelect == null
            ? null
            : () => onToggleSelect!(files[index].id),
        onDelete:
            onDelete == null ? null : () => onDelete!(files[index]),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final FileAttachment file;
  final bool selected;
  final bool anySelected;
  final VoidCallback onOpen;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onDelete;

  const _FileCard({
    required this.file,
    required this.selected,
    required this.anySelected,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final type = FileTypeFilter.fromMime(file.mimeType);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.transparent,
          width: selected ? 2 : 0,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: InkWell(
        onTap: () {
          // Once any selection exists, short-tap continues to build the
          // selection set — otherwise users would have to long-press every
          // single item. Bulk bar has a Clear button to exit select mode.
          if (anySelected && onToggleSelect != null) {
            onToggleSelect!();
          } else {
            onOpen();
          }
        },
        onLongPress: onToggleSelect == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onToggleSelect!();
              },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: AppColors.surfaceAlt,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (file.isImage)
                          CachedNetworkImage(
                            imageUrl: file.fileUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            ),
                          )
                        else
                          Center(
                            child: Icon(
                              type.icon,
                              size: 48,
                              color: type.color,
                            ),
                          ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _typeBadge(),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        file.formattedSize,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      if (file.displayLegacyTags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: file.displayLegacyTags
                              .take(3)
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        if (file.displayLegacyTags.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '+${file.displayLegacyTags.length - 3} more',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
            if (onDelete != null)
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: const Color.fromRGBO(0, 0, 0, 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.r16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.r16),
                    onTap: onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(AppSpacing.xs),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.6),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        file.fileExtension,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
