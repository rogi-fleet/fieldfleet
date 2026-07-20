import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/supabase_config.dart';
import '../../models/file_attachment.dart';
import '../../models/file_folder.dart';
import '../../models/file_tag.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'file_activity_feed.dart';
import 'file_comment_thread.dart';

/// Inline panel for inspecting & editing a single [FileAttachment].
///
/// Shown via [showFileDetailPanel] as a dialog (large on desktop, full-screen
/// on mobile). Writes flow through [SupabaseStorageService.updateFileMetadata]
/// with 500 ms debouncing for the free-text fields.
class FileDetailPanel extends StatefulWidget {
  final FileAttachment file;
  final String workspaceId;
  final String projectId;

  /// Optional: if the caller already has the list of real folders loaded
  /// (e.g. from the file browser), hand them in to skip a stream subscription.
  final List<FileFolder>? folders;

  /// Whether the caller wants the "Delete" action. Hidden when the viewer
  /// is read-only (e.g. client portal scopes).
  final bool canDelete;

  /// Optional hook invoked after successful deletion so the parent can
  /// dismiss itself, refresh lists, etc.
  final VoidCallback? onDeleted;

  /// Optional image-edit hook. When provided and the file is an image, the
  /// overflow menu gains an "Edit image" action that invokes this callback.
  /// The parent screen owns the editor route because that import lives on
  /// the screen side (keeps the panel decoupled from editor internals).
  final ValueChanged<FileAttachment>? onEditImage;

  /// When set, the comment thread briefly highlights the referenced
  /// comment on first render. Used by the `/files?fileId=&commentId=`
  /// deep-link flow from mention notifications.
  final String? highlightCommentId;

  /// Render just the meta column (no surrounding Dialog chrome) so callers
  /// can place this inline as a side panel — used by [FileViewer] on
  /// desktop to keep the panel always-visible next to the picture.
  final bool embedded;

  const FileDetailPanel({
    super.key,
    required this.file,
    required this.workspaceId,
    required this.projectId,
    this.folders,
    this.canDelete = true,
    this.onDeleted,
    this.onEditImage,
    this.highlightCommentId,
    this.embedded = false,
  });

  @override
  State<FileDetailPanel> createState() => _FileDetailPanelState();
}

class _FileDetailPanelState extends State<FileDetailPanel> {
  late final _storageService = ServiceLocator.storageService;
  late final _folderService = ServiceLocator.folderService;
  late final _tagService = ServiceLocator.fileTagService;

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  Timer? _titleDebounce;
  Timer? _descriptionDebounce;

  late FileAttachment _file;
  List<FileTag> _tags = const [];
  List<FileTag> _availableTags = const [];
  List<FileFolder> _folders = const [];

  bool _savingTitle = false;
  bool _savingDescription = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _tags = List.of(widget.file.resolvedTags);
    _titleController = TextEditingController(text: widget.file.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.file.description ?? '');
    _titleController.addListener(_onTitleChanged);
    _descriptionController.addListener(_onDescriptionChanged);

    if (widget.folders != null) {
      _folders = widget.folders!;
    } else {
      _loadFolders();
    }

    _loadWorkspaceTags();
    _refreshTagsFromServer();
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _descriptionDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _descriptionController.removeListener(_onDescriptionChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final stream =
        _folderService.getProjectFolders(widget.workspaceId, widget.projectId);
    final first = await stream.first;
    if (!mounted) return;
    setState(() => _folders = List<FileFolder>.from(first));
  }

  Future<void> _loadWorkspaceTags() async {
    final tags = await _tagService.getWorkspaceTags(widget.workspaceId);
    if (!mounted) return;
    setState(() => _availableTags = tags);
  }

  Future<void> _refreshTagsFromServer() async {
    final serverTags = await _tagService.getTagsForFile(_file.id);
    if (!mounted) return;
    setState(() => _tags = serverTags);
  }

  // --- Title / description debounced saves ----------------------------------

  void _onTitleChanged() {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 500), _persistTitle);
  }

  void _onDescriptionChanged() {
    _descriptionDebounce?.cancel();
    _descriptionDebounce =
        Timer(const Duration(milliseconds: 500), _persistDescription);
  }

  Future<void> _persistTitle() async {
    if (!mounted) return;
    final value = _titleController.text.trim();
    final previousTitle = _file.title;
    if (value == (previousTitle ?? '')) return;
    // Optimistic — flip local state first so breadcrumbs, activity feed, and
    // any side-panel chrome in the dialog update instantly. If the save
    // fails we revert.
    setState(() {
      _file = _file.copyWith(title: () => value.isEmpty ? null : value);
      _savingTitle = true;
    });
    try {
      await _storageService.updateFileMetadata(fileId: _file.id, title: value);
      if (!mounted) return;
      setState(() => _savingTitle = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _file = _file.copyWith(title: () => previousTitle);
        _savingTitle = false;
      });
      _showError('Could not save title: $e');
    }
  }

  Future<void> _persistDescription() async {
    if (!mounted) return;
    final value = _descriptionController.text.trim();
    final previousDescription = _file.description;
    if (value == (previousDescription ?? '')) return;
    setState(() {
      _file = _file.copyWith(
        description: () => value.isEmpty ? null : value,
      );
      _savingDescription = true;
    });
    try {
      await _storageService.updateFileMetadata(
        fileId: _file.id,
        description: value,
      );
      if (!mounted) return;
      setState(() => _savingDescription = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _file = _file.copyWith(description: () => previousDescription);
        _savingDescription = false;
      });
      _showError('Could not save description: $e');
    }
  }

  // --- Folder -----------------------------------------------------------------

  Future<void> _changeFolder(String? folderId) async {
    try {
      await _storageService.updateFileMetadata(
        fileId: _file.id,
        folderId: folderId,
        clearFolder: folderId == null,
      );
      if (!mounted) return;
      setState(() {
        _file = _file.copyWith(folderId: () => folderId);
      });
    } catch (e) {
      _showError('Could not move file: $e');
    }
  }

  // --- Tags -------------------------------------------------------------------

  Future<void> _removeTag(FileTag tag) async {
    final previous = _tags;
    final next = _tags.where((t) => t.id != tag.id).toList();
    setState(() => _tags = next);
    try {
      // Route through updateFileMetadata so the legacy `tags` TEXT[] mirror
      // stays in sync — the grid/list streams don't include the join table.
      await _storageService.updateFileMetadata(
        fileId: _file.id,
        tagIds: next.map((t) => t.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _tags = previous);
      _showError('Could not remove tag: $e');
    }
  }

  Future<void> _addTag(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    try {
      final tag = await _tagService.ensureTag(
        workspaceId: widget.workspaceId,
        name: name,
      );
      if (_tags.any((t) => t.id == tag.id)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${tag.name}" is already attached')),
        );
        return;
      }
      final next = [..._tags, tag]..sort((a, b) => a.name.compareTo(b.name));
      await _storageService.updateFileMetadata(
        fileId: _file.id,
        tagIds: next.map((t) => t.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _tags = next;
        if (!_availableTags.any((t) => t.id == tag.id)) {
          _availableTags = [..._availableTags, tag]
            ..sort((a, b) => a.name.compareTo(b.name));
        }
      });
    } catch (e) {
      _showError('Could not add tag: $e');
    }
  }

  // --- Actions ----------------------------------------------------------------

  Future<void> _downloadOriginal() async {
    final uri = Uri.tryParse(_file.fileUrl);
    if (uri == null) {
      _showError('Invalid file URL');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    // Copy an app-internal deep link that resolves back to this file via the
    // /files route (WorkspaceFilesScreen handles initialFileId by popping
    // the detail panel once the tree mounts). The raw Supabase URL is kept
    // as a secondary action because public bucket URLs never expire.
    final deepLink = '${SupabaseConfig.siteUrl}/files?fileId=${_file.id}';
    await Clipboard.setData(ClipboardData(text: deepLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Future<void> _copyRawUrl() async {
    await Clipboard.setData(ClipboardData(text: _file.fileUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct URL copied to clipboard')),
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(
          'This will permanently remove "${_file.fileName}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _storageService.deleteFile(_file);
      if (!mounted) return;
      widget.onDeleted?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showError('Could not delete file: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  // --- Rendering --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildMetaColumn();
    }

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppBreakpoints.tablet;

    if (isDesktop) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 960,
          height: 640,
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildPreview()),
              const VerticalDivider(width: 1),
              Expanded(flex: 2, child: _buildMetaColumn()),
            ],
          ),
        ),
      );
    }

    return Dialog.fullscreen(
      child: Column(
        children: [
          _buildMobileHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 280, child: _buildPreview()),
                  _buildMetaColumn(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: AppColors.surfaceAlt,
      child: _file.isImage
          ? InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: _file.fileUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 64),
                ),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _iconForFile(_file),
                    size: 96,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _file.fileExtension,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMobileHeader() {
    return Material(
      color: AppColors.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                _file.fileName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildOverflowMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case 'download':
            _downloadOriginal();
            break;
          case 'copy':
            _copyLink();
            break;
          case 'copyUrl':
            _copyRawUrl();
            break;
          case 'delete':
            _delete();
            break;
          case 'open':
            _downloadOriginal();
            break;
          case 'edit':
            widget.onEditImage?.call(_file);
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.open_in_new),
            title: Text('Open original'),
          ),
        ),
        if (widget.onEditImage != null && _file.isImage)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('Edit image'),
            ),
          ),
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Download'),
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Copy link'),
            subtitle: Text('Share within FieldFleet'),
          ),
        ),
        const PopupMenuItem(
          value: 'copyUrl',
          child: ListTile(
            leading: Icon(Icons.public),
            title: Text('Copy direct URL'),
            subtitle: Text('Unexpiring public link'),
          ),
        ),
        if (widget.canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
            ),
          ),
      ],
    );
  }

  Widget _buildMetaColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.embedded &&
              MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _file.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildOverflowMenu(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Title',
              hintText: 'Add a title',
              suffixIcon: _savingTitle
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Add details…',
              alignLabelWithHint: true,
              suffixIcon: _savingDescription
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          _buildFolderPicker(),
          const SizedBox(height: 16),
          _buildTagEditor(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          _metaRow('Uploaded', _formatDate(_file.uploadedAt)),
          _metaRow('Size', _file.formattedSize),
          _metaRow('Type', _file.mimeType),
          _metaRow('File name', _file.fileName),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          FileCommentThread(
            file: _file,
            highlightCommentId: widget.highlightCommentId,
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          FileActivityFeed(
            fileAttachmentId: _file.id,
            workspaceId: _file.workspaceId,
          ),
          if (widget.canDelete) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Delete file'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderPicker() {
    final entries = _buildFolderTreeEntries();

    return DropdownButtonFormField<String?>(
      initialValue: _file.folderId,
      decoration: const InputDecoration(labelText: 'Folder'),
      // Indent nested folders visually in the open dropdown list, but render
      // just the folder name in the closed field (selectedItemBuilder).
      selectedItemBuilder: (_) => [
        const Text('— Unfiled —'),
        ...entries.map(
          (e) => Text(e.folder.displayName, overflow: TextOverflow.ellipsis),
        ),
      ],
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('— Unfiled —'),
        ),
        ...entries.map(
          (e) => DropdownMenuItem<String?>(
            value: e.folder.id,
            child: Padding(
              padding: EdgeInsets.only(left: 12.0 * e.depth),
              child: Text(
                e.folder.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
      onChanged: _changeFolder,
    );
  }

  /// Flatten the (non-virtual) folder list into a depth-ordered walk so the
  /// dropdown can indent children under their parents. Folders whose parent
  /// isn't in the visible set (e.g. permissions quirks) are treated as roots.
  List<_FolderEntry> _buildFolderTreeEntries() {
    final real = _folders.where((f) => !f.isVirtual).toList();
    final byParent = <String?, List<FileFolder>>{};
    final realIds = real.map((f) => f.id).toSet();

    for (final folder in real) {
      final parent = folder.parentFolderId != null &&
              realIds.contains(folder.parentFolderId)
          ? folder.parentFolderId
          : null;
      (byParent[parent] ??= []).add(folder);
    }
    for (final siblings in byParent.values) {
      siblings.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    final out = <_FolderEntry>[];
    void walk(String? parentId, int depth) {
      for (final f in byParent[parentId] ?? const <FileFolder>[]) {
        out.add(_FolderEntry(f, depth));
        walk(f.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  Widget _buildTagEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ..._tags.where((t) => t.name.isNotEmpty).map(
                  (t) => Chip(
                    label: Text(t.name),
                    backgroundColor:
                        _hexToColor(t.color).withValues(alpha: 0.15),
                    side: BorderSide(
                      color: _hexToColor(t.color).withValues(alpha: 0.4),
                    ),
                    onDeleted: () => _removeTag(t),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            _buildAddTagChip(),
          ],
        ),
      ],
    );
  }

  Widget _buildAddTagChip() {
    return ActionChip(
      avatar: const Icon(Icons.add, size: 16),
      label: const Text('Add tag'),
      onPressed: _openAddTagSheet,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _openAddTagSheet() async {
    final attachedIds = _tags.map((t) => t.id).toSet();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddTagSheet(
        availableTags: _availableTags,
        attachedIds: attachedIds,
        hexToColor: _hexToColor,
      ),
    );

    if (chosen != null && chosen.isNotEmpty) {
      await _addTag(chosen);
    }
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(FileAttachment file) {
    if (file.isPDF) return Icons.picture_as_pdf;
    if (file.mimeType.contains('word') || file.mimeType.contains('document')) {
      return Icons.description;
    }
    if (file.mimeType.contains('sheet') || file.mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    return Icons.insert_drive_file;
  }

  Color _hexToColor(String hex) {
    try {
      var value = hex.replaceAll('#', '');
      if (value.length == 6) value = 'FF$value';
      if (value.length == 3) {
        value = value.split('').map((c) => '$c$c').join();
        value = 'FF$value';
      }
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return const Color(0xFF64748B);
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

/// Flat entry representing a folder at a given depth in the folder tree.
/// Used by [_FileDetailPanelState._buildFolderTreeEntries] to render
/// hierarchical indentation in the Folder dropdown.
class _FolderEntry {
  final FileFolder folder;
  final int depth;
  const _FolderEntry(this.folder, this.depth);
}

/// Bottom sheet for picking an existing workspace tag or creating a new one.
///
/// Extracted so its [TextEditingController] has a real lifecycle — the former
/// inline `showModalBottomSheet` + `StatefulBuilder` version leaked a
/// controller per open/close.
class _AddTagSheet extends StatefulWidget {
  final List<FileTag> availableTags;
  final Set<String> attachedIds;
  final Color Function(String hex) hexToColor;

  const _AddTagSheet({
    required this.availableTags,
    required this.attachedIds,
    required this.hexToColor,
  });

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final suggestions = widget.availableTags
        .where((t) => !widget.attachedIds.contains(t.id))
        .where(
          (t) => query.isEmpty
              ? true
              : t.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final exactMatch = suggestions.any(
      (t) => t.name.toLowerCase() == query.toLowerCase(),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search or create tag',
                prefixIcon: Icon(Icons.label_outline),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (query.isNotEmpty && !exactMatch)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add),
                      title: Text('Create "$query"'),
                      onTap: () => Navigator.of(context).pop(query),
                    ),
                  ...suggestions.map(
                    (t) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 8,
                        backgroundColor: widget.hexToColor(t.color),
                      ),
                      title: Text(t.name),
                      onTap: () => Navigator.of(context).pop(t.name),
                    ),
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

/// Convenience wrapper — call this from `onTap` to open the detail panel.
Future<void> showFileDetailPanel({
  required BuildContext context,
  required FileAttachment file,
  required String workspaceId,
  required String projectId,
  List<FileFolder>? folders,
  bool canDelete = true,
  VoidCallback? onDeleted,
  ValueChanged<FileAttachment>? onEditImage,
  String? highlightCommentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FileDetailPanel(
      file: file,
      workspaceId: workspaceId,
      projectId: projectId,
      folders: folders,
      canDelete: canDelete,
      onDeleted: onDeleted,
      onEditImage: onEditImage,
      highlightCommentId: highlightCommentId,
    ),
  );
}
