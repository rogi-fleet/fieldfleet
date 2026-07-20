import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/file_attachment.dart';
import '../../models/file_tag.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../theme/theme.dart';
import '../common/searchable_filter_chips.dart';

enum FileTypeFilter {
  pdf,
  image,
  video,
  document,
  other;

  /// Single source of truth for mapping a MIME string to a coarse type
  /// category. Used by the filter, list-view Type column, grid-view badge,
  /// and any leading-icon decoration.
  static FileTypeFilter fromMime(String mime) {
    if (mime == 'application/pdf') return FileTypeFilter.pdf;
    if (mime.startsWith('image/')) return FileTypeFilter.image;
    if (mime.startsWith('video/')) return FileTypeFilter.video;
    if (mime.contains('document') ||
        mime.contains('word') ||
        mime.contains('excel') ||
        mime.contains('spreadsheet') ||
        mime.contains('text') ||
        mime.contains('presentation')) {
      return FileTypeFilter.document;
    }
    return FileTypeFilter.other;
  }
}

extension FileTypeFilterLabel on FileTypeFilter {
  String get label => switch (this) {
        FileTypeFilter.pdf => 'PDF',
        FileTypeFilter.image => 'Image',
        FileTypeFilter.video => 'Video',
        FileTypeFilter.document => 'Document',
        FileTypeFilter.other => 'Other',
      };

  IconData get icon => switch (this) {
        FileTypeFilter.pdf => Icons.picture_as_pdf_outlined,
        FileTypeFilter.image => Icons.image_outlined,
        FileTypeFilter.video => Icons.movie_outlined,
        FileTypeFilter.document => Icons.description_outlined,
        FileTypeFilter.other => Icons.insert_drive_file_outlined,
      };

  Color get color => switch (this) {
        FileTypeFilter.pdf => AppColors.error,
        FileTypeFilter.image => AppColors.success,
        FileTypeFilter.video => AppColors.secondary,
        FileTypeFilter.document => AppColors.info,
        FileTypeFilter.other => AppColors.textTertiary,
      };

  bool matches(FileAttachment f) =>
      FileTypeFilter.fromMime(f.mimeType) == this;
}

enum DateRangeFilter { today, thisWeek, thisMonth, last90Days }

extension DateRangeFilterLabel on DateRangeFilter {
  String get label => switch (this) {
        DateRangeFilter.today => 'Today',
        DateRangeFilter.thisWeek => 'This week',
        DateRangeFilter.thisMonth => 'This month',
        DateRangeFilter.last90Days => 'Last 90 days',
      };

  bool matches(DateTime uploaded) {
    final now = DateTime.now();
    final start = switch (this) {
      DateRangeFilter.today => DateTime(now.year, now.month, now.day),
      DateRangeFilter.thisWeek =>
        DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      DateRangeFilter.thisMonth => DateTime(now.year, now.month),
      DateRangeFilter.last90Days => now.subtract(const Duration(days: 90)),
    };
    return !uploaded.isBefore(start);
  }
}

class FilesFilter {
  final String? customerId;
  final String? vendorId;
  final String? projectId;
  final String? tagId;
  final FileTypeFilter? fileType;
  final DateRangeFilter? dateRange;

  const FilesFilter({
    this.customerId,
    this.vendorId,
    this.projectId,
    this.tagId,
    this.fileType,
    this.dateRange,
  });

  static const empty = FilesFilter();

  bool get isEmpty =>
      customerId == null &&
      vendorId == null &&
      projectId == null &&
      tagId == null &&
      fileType == null &&
      dateRange == null;

  int get activeCount =>
      (customerId != null ? 1 : 0) +
      (vendorId != null ? 1 : 0) +
      (projectId != null ? 1 : 0) +
      (tagId != null ? 1 : 0) +
      (fileType != null ? 1 : 0) +
      (dateRange != null ? 1 : 0);

  FilesFilter copyWith({
    String? Function()? customerId,
    String? Function()? vendorId,
    String? Function()? projectId,
    String? Function()? tagId,
    FileTypeFilter? Function()? fileType,
    DateRangeFilter? Function()? dateRange,
  }) {
    return FilesFilter(
      customerId: customerId != null ? customerId() : this.customerId,
      vendorId: vendorId != null ? vendorId() : this.vendorId,
      projectId: projectId != null ? projectId() : this.projectId,
      tagId: tagId != null ? tagId() : this.tagId,
      fileType: fileType != null ? fileType() : this.fileType,
      dateRange: dateRange != null ? dateRange() : this.dateRange,
    );
  }
}

/// Open the files filter bottom sheet and return the new filter if the user
/// tapped Apply. Returns null if dismissed.
///
/// When [counts] is supplied, each chip is suffixed with the number of files
/// matching that option — helps users pick meaningful filters without
/// blindly applying one that yields zero results. Keys are customer/vendor/
/// project/tag ids.
Future<FilesFilter?> showFilesFilterSheet({
  required BuildContext context,
  required FilesFilter current,
  required List<Customer> customers,
  required List<Vendor> vendors,
  required List<Project> projects,
  required List<FileTag> tags,
  Map<String, int>? counts,
}) {
  return showModalBottomSheet<FilesFilter>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return _FilesFilterSheet(
        initial: current,
        customers: customers,
        vendors: vendors,
        projects: projects,
        tags: tags,
        counts: counts ?? const {},
      );
    },
  );
}

class _FilesFilterSheet extends StatefulWidget {
  final FilesFilter initial;
  final List<Customer> customers;
  final List<Vendor> vendors;
  final List<Project> projects;
  final List<FileTag> tags;
  final Map<String, int> counts;

  const _FilesFilterSheet({
    required this.initial,
    required this.customers,
    required this.vendors,
    required this.projects,
    required this.tags,
    required this.counts,
  });

  @override
  State<_FilesFilterSheet> createState() => _FilesFilterSheetState();
}

class _FilesFilterSheetState extends State<_FilesFilterSheet> {
  late FilesFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  /// Append a "(N)" suffix to an option label when a count is available.
  /// When the count is zero or missing we leave the label alone so an empty
  /// workspace's filter sheet doesn't read "(0)" beside every single row.
  String _withCount(String label, String id) {
    final n = widget.counts[id];
    if (n == null || n == 0) return label;
    return '$label  ($n)';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _draft = FilesFilter.empty),
                    child: const Text('Clear all'),
                  ),
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _draft),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                children: [
                  _section(
                    title: 'Customer',
                    icon: Icons.business_outlined,
                    hasValue: _draft.customerId != null,
                    subtitle: _draft.customerId != null
                        ? widget.customers
                                .where((c) => c.id == _draft.customerId)
                                .firstOrNull
                                ?.businessDisplayName ??
                            'Selected'
                        : 'All',
                    child: SearchableFilterChips(
                      items: widget.customers
                          .map((c) => (
                                id: c.id,
                                label: _withCount(c.businessDisplayName, c.id),
                              ))
                          .toList(),
                      selectedId: _draft.customerId,
                      onAllSelected: () => setState(() =>
                          _draft = _draft.copyWith(customerId: () => null)),
                      onItemSelected: (id) => setState(() =>
                          _draft = _draft.copyWith(customerId: () => id)),
                      searchHint: 'Search customers...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Vendor',
                    icon: Icons.local_shipping_outlined,
                    hasValue: _draft.vendorId != null,
                    subtitle: _draft.vendorId != null
                        ? widget.vendors
                                .where((v) => v.id == _draft.vendorId)
                                .firstOrNull
                                ?.companyName ??
                            'Selected'
                        : 'All',
                    child: SearchableFilterChips(
                      items: widget.vendors
                          .map((v) => (
                                id: v.id,
                                label: _withCount(v.companyName, v.id),
                              ))
                          .toList(),
                      selectedId: _draft.vendorId,
                      onAllSelected: () => setState(() =>
                          _draft = _draft.copyWith(vendorId: () => null)),
                      onItemSelected: (id) => setState(() =>
                          _draft = _draft.copyWith(vendorId: () => id)),
                      searchHint: 'Search vendors...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Project',
                    icon: Icons.folder_outlined,
                    hasValue: _draft.projectId != null,
                    subtitle: _draft.projectId != null
                        ? widget.projects
                                .where((p) => p.id == _draft.projectId)
                                .firstOrNull
                                ?.name ??
                            'Selected'
                        : 'All',
                    child: SearchableFilterChips(
                      items: widget.projects
                          .map((p) => (
                                id: p.id,
                                label: _withCount(p.name, p.id),
                              ))
                          .toList(),
                      selectedId: _draft.projectId,
                      onAllSelected: () => setState(() =>
                          _draft = _draft.copyWith(projectId: () => null)),
                      onItemSelected: (id) => setState(() =>
                          _draft = _draft.copyWith(projectId: () => id)),
                      searchHint: 'Search projects...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Tag',
                    icon: Icons.label_outline,
                    hasValue: _draft.tagId != null,
                    subtitle: _draft.tagId != null
                        ? widget.tags
                                .where((t) => t.id == _draft.tagId)
                                .firstOrNull
                                ?.name ??
                            'Selected'
                        : 'All',
                    child: SearchableFilterChips(
                      items: widget.tags
                          .map((t) => (
                                id: t.id,
                                label: _withCount(t.name, t.id),
                              ))
                          .toList(),
                      selectedId: _draft.tagId,
                      onAllSelected: () => setState(() =>
                          _draft = _draft.copyWith(tagId: () => null)),
                      onItemSelected: (id) => setState(() =>
                          _draft = _draft.copyWith(tagId: () => id)),
                      searchHint: 'Search tags...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'File type',
                    icon: Icons.category_outlined,
                    hasValue: _draft.fileType != null,
                    subtitle: _draft.fileType?.label ?? 'All',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _draft.fileType == null,
                          onSelected: (_) => setState(() =>
                              _draft = _draft.copyWith(fileType: () => null)),
                        ),
                        ...FileTypeFilter.values.map((t) {
                          return ChoiceChip(
                            avatar: Icon(t.icon, size: 16),
                            label: Text(t.label),
                            selected: _draft.fileType == t,
                            onSelected: (_) => setState(() => _draft =
                                _draft.copyWith(fileType: () => t)),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Date uploaded',
                    icon: Icons.event_outlined,
                    hasValue: _draft.dateRange != null,
                    subtitle: _draft.dateRange?.label ?? 'Any time',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Any time'),
                          selected: _draft.dateRange == null,
                          onSelected: (_) => setState(() => _draft =
                              _draft.copyWith(dateRange: () => null)),
                        ),
                        ...DateRangeFilter.values.map((d) {
                          return ChoiceChip(
                            label: Text(d.label),
                            selected: _draft.dateRange == d,
                            onSelected: (_) => setState(() => _draft =
                                _draft.copyWith(dateRange: () => d)),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required bool hasValue,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: hasValue
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: hasValue
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            icon,
            size: 20,
            color: hasValue ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          initiallyExpanded: hasValue,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
