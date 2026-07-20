import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/file_folder.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// Widget for displaying and managing the folder tree structure.
class FolderTreeWidget extends StatefulWidget {
  final List<FileFolder> folders;
  final String? selectedFolderId;
  final Function(FileFolder?) onFolderSelected;
  final Function(String name, String? parentId)? onCreateFolder;
  final Function(String folderId)? onDeleteFolder;
  final Function(String folderId, String newName)? onRenameFolder;

  /// Up to N image URLs per folder id, shown as a tiny thumbnail strip on
  /// the right side of the folder row so users can tell folders apart at
  /// a glance. Populated by the parent (see ProjectFilesScreen) from the
  /// all-project files stream; absence just hides the strip.
  final Map<String, List<String>> thumbnailsByFolder;

  /// Total image count per folder id — feeds the "+N" overflow badge next
  /// to the thumbnail strip.
  final Map<String, int> imageCountByFolder;

  const FolderTreeWidget({
    super.key,
    required this.folders,
    this.selectedFolderId,
    required this.onFolderSelected,
    this.onCreateFolder,
    this.onDeleteFolder,
    this.onRenameFolder,
    this.thumbnailsByFolder = const {},
    this.imageCountByFolder = const {},
  });

  @override
  State<FolderTreeWidget> createState() => _FolderTreeWidgetState();
}

class _FolderTreeWidgetState extends State<FolderTreeWidget> {
  final Set<String> _expandedFolders = {};
  bool _initialExpansionDone = false;

  @override
  void initState() {
    super.initState();
    _expandContentFolder();
  }

  @override
  void didUpdateWidget(covariant FolderTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Expand Content folder when folders first load
    if (!_initialExpansionDone && widget.folders.isNotEmpty) {
      _expandContentFolder();
    }
  }

  void _expandContentFolder() {
    for (final folder in widget.folders) {
      if (folder.name == 'Content') {
        _expandedFolders.add(folder.id);
        _initialExpansionDone = true;
        break;
      }
    }
  }

  List<FileFolder> _getRootFolders() {
    return widget.folders.where((f) => f.parentFolderId == null).toList();
  }

  List<FileFolder> _getChildFolders(String parentId) {
    return widget.folders.where((f) => f.parentFolderId == parentId).toList();
  }

  bool _hasChildren(String folderId) {
    return widget.folders.any((f) => f.parentFolderId == folderId);
  }

  void _toggleExpanded(String folderId) {
    setState(() {
      if (_expandedFolders.contains(folderId)) {
        _expandedFolders.remove(folderId);
      } else {
        _expandedFolders.add(folderId);
      }
    });
  }

  IconData _getFolderIcon(FileFolder folder) {
    if (folder.isVirtual) {
      switch (folder.virtualType) {
        case 'tasks':
          return Icons.check_circle_outline;
        case 'messages':
          return Icons.message_outlined;
        case 'forms':
          return Icons.dynamic_form_outlined;
        case 'documents':
          return Icons.description_outlined;
        default:
          return Icons.folder_special;
      }
    }
    return _hasChildren(folder.id) || _expandedFolders.contains(folder.id)
        ? Icons.folder_open
        : Icons.folder;
  }

  Widget _buildThumbnailStrip(FileFolder folder) {
    final thumbs = widget.thumbnailsByFolder[folder.id] ?? const <String>[];
    if (thumbs.isEmpty) return const SizedBox(width: 8);
    final total = widget.imageCountByFolder[folder.id] ?? thumbs.length;
    final overflow = total > thumbs.length ? total - thumbs.length : 0;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < thumbs.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CachedNetworkImage(
                imageUrl: thumbs[i],
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(
                  width: 18,
                  height: 18,
                ),
              ),
            ),
          ],
          if (overflow > 0) ...[
            const SizedBox(width: 3),
            Text(
              '+$overflow',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getFolderColor(FileFolder folder, BuildContext context) {
    if (folder.isVirtual) {
      switch (folder.virtualType) {
        case 'forms':
          return AppColors.financialAccent;
        case 'documents':
          return Colors.indigo;
        default:
          return AppColors.info;
      }
    }
    if (folder.name == 'Content') {
      return AppColors.messageAccent;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Root/All Files option
        _buildFolderTile(context, null, 'All Files', Icons.home, 0),
        const Divider(height: 1),
        // Folder tree
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: _buildFolderTree(context, _getRootFolders(), 0),
          ),
        ),
        // Add folder button
        if (widget.onCreateFolder != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TextButton.icon(
              onPressed: () => _showCreateFolderDialog(context, null),
              icon: const Icon(Icons.create_new_folder, size: 20),
              label: const Text('New Folder'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildFolderTree(
    BuildContext context,
    List<FileFolder> folders,
    int depth,
  ) {
    final widgets = <Widget>[];
    for (final folder in folders) {
      widgets.add(
        _buildFolderTile(
          context,
          folder,
          folder.displayName,
          _getFolderIcon(folder),
          depth,
        ),
      );

      // Add children if expanded
      if (_expandedFolders.contains(folder.id)) {
        final children = _getChildFolders(folder.id);
        widgets.addAll(_buildFolderTree(context, children, depth + 1));
      }
    }
    return widgets;
  }

  Widget _buildFolderTile(
    BuildContext context,
    FileFolder? folder,
    String name,
    IconData icon,
    int depth,
  ) {
    final isSelected =
        folder?.id == widget.selectedFolderId ||
        (folder == null && widget.selectedFolderId == null);
    final hasChildren = folder != null && _hasChildren(folder.id);
    final isExpanded = folder != null && _expandedFolders.contains(folder.id);

    final chrome = ChromeColors.of(context);
    // FolderTreeWidget renders inside a hardcoded white sidebar
    // (project_files_screen + workspace_files_screen), so chrome.scaffoldText
    // would be white-on-white in dark-chrome mode. Use the light-surface
    // text tokens directly for legibility.
    return Material(
      color: isSelected
          ? chrome.selected
          : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onFolderSelected(folder),
        child: Padding(
          padding: EdgeInsets.only(
            left: 8.0 + (depth * 20.0),
            right: 8.0,
            top: 8.0,
            bottom: 8.0,
          ),
          child: Row(
            children: [
              // Expand/collapse button or spacer
              if (hasChildren)
                GestureDetector(
                  onTap: () => _toggleExpanded(folder.id),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                const SizedBox(width: 24),
              // Folder icon
              Icon(
                icon,
                size: 20,
                color: folder != null
                    ? _getFolderColor(folder, context)
                    : AppColors.primary,
              ),
              const SizedBox(width: 8),
              // Folder name
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Thumbnail strip — compact row of up to 3 image tiles
              // from this folder. Hidden for virtual folders and for
              // rows with no image children.
              if (folder != null && !folder.isVirtual)
                _buildThumbnailStrip(folder),
              // Virtual folder indicator
              if (folder?.isVirtual == true)
                Tooltip(
                  message: 'Auto-populated folder',
                  child: Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                )
              // Context menu for non-virtual folders
              else if (folder != null &&
                  !folder.isVirtual &&
                  (widget.onDeleteFolder != null ||
                      widget.onRenameFolder != null ||
                      widget.onCreateFolder != null))
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Folder options',
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    if (widget.onCreateFolder != null)
                      const PopupMenuItem(
                        value: 'subfolder',
                        child: Row(
                          children: [
                            Icon(Icons.create_new_folder, size: 18),
                            SizedBox(width: 8),
                            Text('New Subfolder'),
                          ],
                        ),
                      ),
                    if (widget.onRenameFolder != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Rename'),
                          ],
                        ),
                      ),
                    if (widget.onDeleteFolder != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 18,
                              color: AppColors.errorDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: AppColors.errorDark),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'subfolder':
                        _showCreateFolderDialog(context, folder.id);
                        break;
                      case 'rename':
                        _showRenameFolderDialog(context, folder);
                        break;
                      case 'delete':
                        _showDeleteConfirmDialog(context, folder);
                        break;
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context, String? parentId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(parentId != null ? 'New Subfolder' : 'New Folder'),
        content: StackedField(
          label: 'Folder name',
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                widget.onCreateFolder?.call(value.trim(), parentId);
                Navigator.pop(context);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                widget.onCreateFolder?.call(controller.text.trim(), parentId);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameFolderDialog(BuildContext context, FileFolder folder) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: StackedField(
          label: 'Folder name',
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                widget.onRenameFolder?.call(folder.id, value.trim());
                Navigator.pop(context);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                widget.onRenameFolder?.call(folder.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, FileFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Are you sure you want to delete "${folder.name}"? '
          'Files in this folder will be moved to the root.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              widget.onDeleteFolder?.call(folder.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
