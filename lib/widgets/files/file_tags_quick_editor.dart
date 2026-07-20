import 'package:flutter/material.dart';

import '../../models/file_attachment.dart';
import '../../models/file_tag.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Lightweight popover for editing a file's tags from the list view.
///
/// Shows current tags as removable colored chips and a search field that
/// filters existing workspace tags or offers to create a new one. Persists
/// every change immediately via [SupabaseStorageService.updateFileMetadata]
/// so the upstream stream re-emits and the row's chips update in place.
Future<void> showQuickTagEditor({
  required BuildContext context,
  required FileAttachment file,
  required String workspaceId,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _QuickTagEditorDialog(
      file: file,
      workspaceId: workspaceId,
    ),
  );
}

class _QuickTagEditorDialog extends StatefulWidget {
  final FileAttachment file;
  final String workspaceId;

  const _QuickTagEditorDialog({
    required this.file,
    required this.workspaceId,
  });

  @override
  State<_QuickTagEditorDialog> createState() => _QuickTagEditorDialogState();
}

class _QuickTagEditorDialogState extends State<_QuickTagEditorDialog> {
  late final _storageService = ServiceLocator.storageService;
  late final _tagService = ServiceLocator.fileTagService;

  final TextEditingController _searchController = TextEditingController();

  List<FileTag> _attached = const [];
  List<FileTag> _available = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _attached = List.of(widget.file.resolvedTags);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        _tagService.getTagsForFile(widget.file.id),
        _tagService.getWorkspaceTags(widget.workspaceId),
      ]);
      if (!mounted) return;
      setState(() {
        _attached = results[0];
        _available = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Could not load tags: $e');
    }
  }

  Future<void> _persist(List<FileTag> next) async {
    final previous = _attached;
    setState(() {
      _attached = [...next]..sort((a, b) => a.name.compareTo(b.name));
      _busy = true;
    });
    try {
      await _storageService.updateFileMetadata(
        fileId: widget.file.id,
        tagIds: _attached.map((t) => t.id).toList(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _attached = previous;
        _busy = false;
      });
      _showError('Could not save tags: $e');
    }
  }

  Future<void> _removeTag(FileTag tag) async {
    await _persist(_attached.where((t) => t.id != tag.id).toList());
  }

  Future<void> _attachExisting(FileTag tag) async {
    if (_attached.any((t) => t.id == tag.id)) return;
    await _persist([..._attached, tag]);
    _searchController.clear();
    setState(() {});
  }

  Future<void> _createAndAttach(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final tag = await _tagService.ensureTag(
        workspaceId: widget.workspaceId,
        name: name,
      );
      if (!mounted) return;
      if (!_available.any((t) => t.id == tag.id)) {
        _available = [..._available, tag]
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      if (_attached.any((t) => t.id == tag.id)) {
        setState(() => _busy = false);
        return;
      }
      await _persist([..._attached, tag]);
      _searchController.clear();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError('Could not create tag: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final attachedIds = _attached.map((t) => t.id).toSet();
    final suggestions = _available
        .where((t) => !attachedIds.contains(t.id))
        .where((t) => query.isEmpty
            ? true
            : t.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final exactMatch = _available.any(
      (t) => t.name.toLowerCase() == query.toLowerCase(),
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit tags',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text(
                widget.file.title?.isNotEmpty == true
                    ? widget.file.title!
                    : widget.file.fileName,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                if (_attached.isEmpty)
                  Text(
                    'No tags yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _attached
                        .map((t) => _RemovableTagChip(
                              tag: t,
                              onRemove: _busy ? null : () => _removeTag(t),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search or create…',
                    prefixIcon: Icon(Icons.label_outline, size: 18),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    final value = v.trim();
                    if (value.isEmpty) return;
                    final hit = _available.firstWhere(
                      (t) => t.name.toLowerCase() == value.toLowerCase(),
                      orElse: () => FileTag(
                        id: '',
                        workspaceId: widget.workspaceId,
                        name: '',
                        color: '#64748B',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                    if (hit.id.isNotEmpty) {
                      _attachExisting(hit);
                    } else {
                      _createAndAttach(value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (query.isNotEmpty && !exactMatch)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.add, size: 18),
                          title: Text('Create "$query"'),
                          onTap: _busy ? null : () => _createAndAttach(query),
                        ),
                      ...suggestions.map(
                        (t) => ListTile(
                          dense: true,
                          leading: _ColorSwatch(color: _hexToColor(t.color)),
                          title: Text(t.name),
                          onTap: _busy ? null : () => _attachExisting(t),
                        ),
                      ),
                      if (suggestions.isEmpty && query.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Text(
                            'No more workspace tags to add. Type to create a new one.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RemovableTagChip extends StatelessWidget {
  final FileTag tag;
  final VoidCallback? onRemove;

  const _RemovableTagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(tag.color);
    final textColor = _readableTextColor(context, color);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 14,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  const _ColorSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
      ),
    );
  }
}

Color _hexToColor(String hex) {
  var value = hex.replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length == 3) {
    value = value.split('').map((c) => '$c$c').join();
    value = 'FF$value';
  }
  return Color(int.parse(value, radix: 16));
}

/// Pick a readable foreground color for a chip whose background is the tag's
/// hue at low alpha. We darken the tag color in light mode and lighten it in
/// dark mode so the label stays on-brand and legible.
Color _readableTextColor(BuildContext context, Color tagColor) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final hsl = HSLColor.fromColor(tagColor);
  return hsl
      .withLightness(isDark ? 0.78 : 0.32)
      .withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0))
      .toColor();
}
