import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_attachment.dart';
import '../../models/file_folder.dart';
import '../../models/file_tag.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import 'files_filter.dart';

/// Sortable list view of [FileAttachment]s.
///
/// Columns: Name / Type / Folder / Tags / Uploaded By / Uploaded At.
/// [showJobColumn] toggles a Job column for cross-project scopes. Row tap
/// calls [onOpen] so the caller wires up the detail panel.
class FileListView extends StatefulWidget {
  final List<FileAttachment> files;
  final List<FileFolder> folders;
  final void Function(FileAttachment file) onOpen;
  final bool showJobColumn;

  /// Map of projectId → display name, used to render the Job column.
  final Map<String, String> projectNames;

  /// Map of userId → display name, used to render Uploaded By nicely.
  final Map<String, String> userNames;

  /// Ids currently selected for bulk operations. Non-null enables the
  /// checkbox column and "select all" header checkbox.
  final Set<String>? selectedIds;

  /// Called when the user toggles a row's selection via checkbox.
  final ValueChanged<String>? onToggleSelect;

  /// Called when the user toggles the select-all header checkbox.
  /// Receives `true` to select every currently-displayed row, `false`
  /// to clear the entire selection.
  final ValueChanged<bool>? onToggleAll;

  /// When provided, the Tags cell shows a small inline edit button that
  /// invokes this callback. The parent typically wires it up to
  /// [showQuickTagEditor].
  final void Function(FileAttachment file)? onEditTags;

  const FileListView({
    super.key,
    required this.files,
    required this.folders,
    required this.onOpen,
    this.showJobColumn = false,
    this.projectNames = const {},
    this.userNames = const {},
    this.selectedIds,
    this.onToggleSelect,
    this.onToggleAll,
    this.onEditTags,
  });

  @override
  State<FileListView> createState() => _FileListViewState();
}

enum _SortBy { name, type, folder, job, uploadedAt, uploadedBy }

class _FileListViewState extends State<FileListView> {
  _SortBy _sortBy = _SortBy.uploadedAt;
  bool _ascending = false;

  void _toggleSort(_SortBy col) {
    setState(() {
      if (_sortBy == col) {
        _ascending = !_ascending;
      } else {
        _sortBy = col;
        _ascending = col == _SortBy.name || col == _SortBy.folder;
      }
    });
  }

  int _columnIndex({
    required bool showType,
    required bool showFolder,
    required bool showJob,
    required bool showTags,
    required bool showUploader,
  }) {
    // Offsets depend on which optional columns are visible — any leading
    // checkbox, Type, Folder, Job, Tags, Uploaded By columns shift later
    // columns right. If the column the user is currently sorting by was
    // hidden (responsive collapse), fall back to Name (the primary column).
    var idx = widget.selectedIds != null ? 1 : 0;
    switch (_sortBy) {
      case _SortBy.name:
        return idx;
      case _SortBy.type:
        if (!showType) return idx;
        return idx + 1;
      case _SortBy.folder:
        if (!showFolder) return idx;
        idx += 1;
        if (showType) idx += 1;
        return idx;
      case _SortBy.job:
        if (!showJob) return idx;
        idx += 1;
        if (showType) idx += 1;
        if (showFolder) idx += 1;
        return idx;
      case _SortBy.uploadedBy:
        if (!showUploader) return idx;
        idx += 1;
        if (showType) idx += 1;
        if (showFolder) idx += 1;
        if (showJob) idx += 1;
        if (showTags) idx += 1;
        return idx;
      case _SortBy.uploadedAt:
        idx += 1;
        if (showType) idx += 1;
        if (showFolder) idx += 1;
        if (showJob) idx += 1;
        if (showTags) idx += 1;
        if (showUploader) idx += 1;
        return idx;
    }
  }

  List<FileAttachment> _sortedFiles() {
    final folderNameById = {
      for (final f in widget.folders) f.id: f.displayName,
    };
    final sorted = [...widget.files];
    int cmp<T extends Comparable<Object?>>(T? a, T? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    sorted.sort((a, b) {
      int c;
      switch (_sortBy) {
        case _SortBy.name:
          c = a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
          break;
        case _SortBy.type:
          c = FileTypeFilter.fromMime(a.mimeType)
              .index
              .compareTo(FileTypeFilter.fromMime(b.mimeType).index);
          break;
        case _SortBy.folder:
          c = cmp<String>(folderNameById[a.folderId], folderNameById[b.folderId]);
          break;
        case _SortBy.job:
          c = cmp<String>(
            widget.projectNames[a.projectId],
            widget.projectNames[b.projectId],
          );
          break;
        case _SortBy.uploadedBy:
          c = cmp<String>(
            widget.userNames[a.uploadedBy] ?? a.uploadedBy,
            widget.userNames[b.uploadedBy] ?? b.uploadedBy,
          );
          break;
        case _SortBy.uploadedAt:
          c = a.uploadedAt.compareTo(b.uploadedAt);
          break;
      }
      return _ascending ? c : -c;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final projectLabel = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final folderNameById = {
      for (final f in widget.folders) f.id: f.displayName,
    };
    final files = _sortedFiles();
    final width = MediaQuery.sizeOf(context).width;
    // Column visibility budget — low-priority columns fall off first on narrow
    // viewports so the filename (primary) never gets pushed behind a
    // horizontal scroll.
    final showType = width >= 340;
    final showFolder = width >= 560;
    final showJob = widget.showJobColumn && width >= 720;
    final showTags = width >= 680;
    final showUploader = width >= 820;
    final showDate = width >= 380;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              sortColumnIndex: _columnIndex(
                showType: showType,
                showFolder: showFolder,
                showJob: showJob,
                showTags: showTags,
                showUploader: showUploader,
              ),
              sortAscending: _ascending,
              showCheckboxColumn: false,
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 56,
              dividerThickness: 0.5,
              headingTextStyle: TextStyle(
                color: chrome.sectionLabel,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              dataTextStyle: TextStyle(
                color: chrome.scaffoldText,
                fontSize: 13,
              ),
              columns: [
                if (widget.selectedIds != null)
                  DataColumn(
                    label: Checkbox(
                      value: widget.selectedIds!.isNotEmpty &&
                          widget.files.every(
                            (f) => widget.selectedIds!.contains(f.id),
                          ),
                      tristate: true,
                      onChanged: widget.onToggleAll == null
                          ? null
                          : (v) => widget.onToggleAll!(v ?? false),
                    ),
                  ),
                DataColumn(
                  label: const Text('Name'),
                  onSort: (_, __) => _toggleSort(_SortBy.name),
                ),
                if (showType)
                  DataColumn(
                    label: const Text('Type'),
                    onSort: (_, __) => _toggleSort(_SortBy.type),
                  ),
                if (showFolder)
                  DataColumn(
                    label: const Text('Folder'),
                    onSort: (_, __) => _toggleSort(_SortBy.folder),
                  ),
                if (showJob)
                  DataColumn(
                    label: Text(projectLabel),
                    onSort: (_, __) => _toggleSort(_SortBy.job),
                  ),
                if (showTags) const DataColumn(label: Text('Tags')),
                if (showUploader)
                  DataColumn(
                    label: const Text('Uploaded By'),
                    onSort: (_, __) => _toggleSort(_SortBy.uploadedBy),
                  ),
                if (showDate)
                  DataColumn(
                    label: const Text('Uploaded At'),
                    onSort: (_, __) => _toggleSort(_SortBy.uploadedAt),
                  ),
              ],
              rows: files.map((file) {
                final folderName = folderNameById[file.folderId] ?? '—';
                final jobName =
                    widget.projectNames[file.projectId] ?? file.projectId;
                final uploader = widget.userNames[file.uploadedBy] ??
                    (widget.userNames.isEmpty ? file.uploadedBy : 'Unknown');
                final isSelected =
                    widget.selectedIds?.contains(file.id) ?? false;
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (_) => widget.onOpen(file),
                  cells: [
                    if (widget.selectedIds != null)
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: widget.onToggleSelect == null
                              ? null
                              : (_) => widget.onToggleSelect!(file.id),
                        ),
                      ),
                    DataCell(_nameCell(file)),
                    if (showType) DataCell(_typeCell(file)),
                    if (showFolder)
                      DataCell(Text(folderName,
                          style: const TextStyle(fontSize: 13))),
                    if (showJob)
                      DataCell(Text(jobName,
                          style: const TextStyle(fontSize: 13))),
                    if (showTags) DataCell(_tagCell(file)),
                    if (showUploader)
                      DataCell(Text(uploader,
                          style: const TextStyle(fontSize: 13))),
                    if (showDate)
                      DataCell(
                        Text(
                          _formatDate(file.uploadedAt),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _nameCell(FileAttachment file) {
    final type = FileTypeFilter.fromMime(file.mimeType);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(type.icon, size: 18, color: type.color),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            file.title?.isNotEmpty == true ? file.title! : file.fileName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _typeCell(FileAttachment file) {
    return Text(
      FileTypeFilter.fromMime(file.mimeType).label,
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _tagCell(FileAttachment file) {
    final tags = file.resolvedTags;
    final legacyTags = file.displayLegacyTags;
    final hasAny = tags.isNotEmpty || legacyTags.isNotEmpty;
    // Cap visible chips at 2 and surface a "+N" overflow chip so rows don't
    // balloon horizontally on files with many tags.
    const visibleLimit = 2;

    Widget overflowChip(int extra) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            '+$extra',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        );

    final List<Widget> chips;
    if (tags.isNotEmpty) {
      final extra = tags.length - visibleLimit;
      chips = [
        ...tags.take(visibleLimit).map(_tagChip),
        if (extra > 0) overflowChip(extra),
      ];
    } else if (legacyTags.isNotEmpty) {
      // Legacy plain-string fallback for pre-migration rows.
      final extra = legacyTags.length - visibleLimit;
      chips = [
        ...legacyTags.take(visibleLimit).map(
              (t) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  t,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
            ),
        if (extra > 0) overflowChip(extra),
      ];
    } else {
      chips = const [];
    }

    final showEdit = widget.onEditTags != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: hasAny
                ? Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: chips,
                  )
                : Text(
                    showEdit ? 'Add tags' : '—',
                    style: TextStyle(
                      fontSize: 13,
                      color: showEdit ? AppColors.textSecondary : null,
                      fontStyle:
                          showEdit ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
          ),
          if (showEdit) ...[
            const SizedBox(width: 4),
            // GestureDetector with HitTestBehavior.opaque + a stop tap
            // ensures the row-level onSelectChanged (which would open the
            // file) doesn't also fire when the user taps the edit icon.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onEditTags!(file),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  hasAny ? Icons.edit_outlined : Icons.add,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tagChip(FileTag tag) {
    final color = _hexToColor(tag.color);
    final textColor = _readableTagTextColor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        tag.name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  /// Pick a readable foreground for a chip whose background is the tag's hue
  /// at low alpha — darken in light mode, lighten in dark mode so the label
  /// stays on-brand and legible.
  Color _readableTagTextColor(Color tagColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(tagColor);
    return hsl
        .withLightness(isDark ? 0.78 : 0.32)
        .withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0))
        .toColor();
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

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
