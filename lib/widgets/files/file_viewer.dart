import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/file_attachment.dart';
import '../../models/file_markup.dart';
import '../../screens/files/file_markup_editor_screen.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'file_detail_panel.dart';
import 'markup_renderer.dart';

/// Full-screen photo/file viewer with swipe next/prev navigation.
///
/// Opened from grid/list row taps. Keeps the file list in `PageView` so the
/// user can swipe or arrow-key through the whole filtered view, and exposes
/// overlay actions (Details / Download / Copy Link / Edit image / Delete)
/// in a top bar. The detail panel itself is invoked on demand for metadata
/// edits so this viewer stays focused on the content.
class FileViewer extends StatefulWidget {
  final List<FileAttachment> files;
  final int initialIndex;
  final String workspaceId;

  /// When the user chooses "Edit image" on an image file. Caller handles the
  /// route (viewer pops itself first). Omitted if image editing isn't
  /// supported in the current context.
  final ValueChanged<FileAttachment>? onEditImage;

  const FileViewer({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.workspaceId,
    this.onEditImage,
  });

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  late PageController _pageController;
  late int _index;
  late List<FileAttachment> _files;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _files = List.of(widget.files);
    _index = widget.initialIndex.clamp(0, _files.length - 1);
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focus.dispose();
    super.dispose();
  }

  FileAttachment get _current => _files[_index];

  void _goTo(int i) {
    if (i < 0 || i >= _files.length || i == _index) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _download() async {
    final base = Uri.tryParse(_current.fileUrl);
    if (base == null) return;
    // Append `?download=<filename>` so Supabase sets
    // `Content-Disposition: attachment` — without this, browsers display
    // images/PDFs inline in a new tab instead of saving them to disk.
    final downloadUri = base.replace(
      queryParameters: {
        ...base.queryParameters,
        'download': _current.fileName,
      },
    );
    final ok = await launchUrl(
      downloadUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start download')),
      );
    }
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Public, time-limited share link — works for anyone with the URL,
      // no sign-in required. Default 7-day expiry; recipient can view or
      // save the file directly.
      final url = await ServiceLocator.storageService.createShareableLink(
        _current.id,
      );
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Shareable link copied (valid for 7 days)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create share link: $e')),
      );
    }
  }

  Future<void> _openDetails() async {
    await showFileDetailPanel(
      context: context,
      file: _current,
      workspaceId: _current.workspaceId,
      projectId: _current.projectId,
      onEditImage: widget.onEditImage == null
          ? null
          : (f) {
              Navigator.of(context).pop(); // close viewer
              widget.onEditImage!(f);
            },
      onDeleted: () {
        // The file was deleted from the panel; drop it from our list and
        // either advance to the neighbor or pop if empty.
        setState(() {
          _files.removeAt(_index);
          if (_files.isEmpty) {
            Navigator.of(context).pop();
            return;
          }
          if (_index >= _files.length) _index = _files.length - 1;
          _pageController.jumpToPage(_index);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final isDesktop = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;

    final viewerStack = Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: _files.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => _buildPage(_files[i]),
        ),
        _buildTopBar(showInfoButton: !isDesktop),
        _buildCaption(),
        if (_index > 0)
          _buildNavArrow(
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left,
            onTap: () => _goTo(_index - 1),
          ),
        if (_index < _files.length - 1)
          _buildNavArrow(
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right,
            onTap: () => _goTo(_index + 1),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focus,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _goTo(_index + 1);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _goTo(_index - 1);
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
          }
        },
        child: Row(
          children: [
            Expanded(child: viewerStack),
            if (isDesktop)
              SizedBox(
                width: 380,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: FileDetailPanel(
                    key: ValueKey(_current.id),
                    file: _current,
                    workspaceId: _current.workspaceId,
                    projectId: _current.projectId,
                    embedded: true,
                    onEditImage: widget.onEditImage == null
                        ? null
                        : (f) {
                            Navigator.of(context).pop();
                            widget.onEditImage!(f);
                          },
                    onDeleted: () {
                      setState(() {
                        _files.removeAt(_index);
                        if (_files.isEmpty) {
                          Navigator.of(context).pop();
                          return;
                        }
                        if (_index >= _files.length) {
                          _index = _files.length - 1;
                        }
                        _pageController.jumpToPage(_index);
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(FileAttachment file) {
    if (!file.isImage) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForFile(file),
              size: 120,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              file.fileName,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open original'),
            ),
          ],
        ),
      );
    }
    // Images stream their markup layer and overlay it read-only through
    // the shared MarkupImageOverlay so the viewer's aspect-ratio handling
    // matches the editor's and shapes never drift off the image.
    return StreamBuilder<MarkupLayer?>(
      stream: ServiceLocator.fileMarkupService.streamLayer(file.id),
      builder: (context, snapshot) {
        final layer = snapshot.data;
        final shapes = layer?.shapes ?? const <MarkupShape>[];
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: MarkupImageOverlay(
            imageUrl: file.fileUrl,
            shapes: shapes,
            rotation: layer?.rotation ?? 0,
            flipHorizontal: layer?.flipHorizontal ?? false,
            flipVertical: layer?.flipVertical ?? false,
            cropRect: layer?.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1),
            placeholder: const CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  Widget _buildTopBar({bool showInfoButton = true}) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 56 + MediaQuery.of(context).padding.top,
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Text(
              '${_index + 1} of ${_files.length}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const Spacer(),
            if (showInfoButton)
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.info_outline),
                tooltip: 'Details',
                onPressed: _openDetails,
              ),
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.link),
              tooltip: 'Copy link',
              onPressed: _copyLink,
            ),
            IconButton(
              color: Colors.white,
              icon: const Icon(Icons.download),
              tooltip: 'Download',
              onPressed: _download,
            ),
            _buildOverflow(),
          ],
        ),
      ),
    );
  }

  void _openMarkupEditor() {
    final file = _current;
    if (widget.onEditImage != null) {
      Navigator.of(context).pop();
      widget.onEditImage!(file);
    } else {
      // Fallback when the caller didn't provide a hook — push the markup
      // editor directly so Mark up is always reachable on images.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileMarkupEditorScreen(file: file),
        ),
      );
    }
  }

  Widget _buildOverflow() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _openMarkupEditor();
            break;
          case 'delete':
            _confirmDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        if (_current.isImage)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.brush),
              title: Text('Mark up'),
            ),
          ),
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

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(
          'This will permanently remove "${_current.fileName}". This cannot be undone.',
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
    try {
      await ServiceLocator.storageService.deleteFile(_current);
      if (!mounted) return;
      setState(() {
        _files.removeAt(_index);
        if (_files.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        if (_index >= _files.length) _index = _files.length - 1;
        _pageController.jumpToPage(_index);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildCaption() {
    final file = _current;
    final title = (file.title != null && file.title!.isNotEmpty)
        ? file.title!
        : file.fileName;
    final description = file.description;
    if (title.isEmpty && (description == null || description.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavArrow({
    required AlignmentGeometry alignment,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Material(
            color: Colors.black.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(icon, color: Colors.white, size: 32),
              onPressed: onTap,
            ),
          ),
        ),
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
}

/// Convenience launcher — push a full-screen route with [FileViewer].
Future<void> openFileViewer({
  required BuildContext context,
  required List<FileAttachment> files,
  required int initialIndex,
  required String workspaceId,
  ValueChanged<FileAttachment>? onEditImage,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FileViewer(
        files: files,
        initialIndex: initialIndex,
        workspaceId: workspaceId,
        onEditImage: onEditImage,
      ),
    ),
  );
}
