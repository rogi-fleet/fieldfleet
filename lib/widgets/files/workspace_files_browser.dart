import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/customer.dart';
import '../../models/file_attachment.dart';
import '../../models/file_tag.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../models/vendor_subdivision.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../common/saved_views_menu.dart';
import '../common/view_toolbar.dart';
import '../common/view_icon_button.dart';
import 'file_grid_view.dart';
import 'file_list_view.dart';
import 'file_tags_quick_editor.dart';
import 'file_viewer.dart';
import 'files_filter.dart';
import 'files_scope.dart';

/// Flat cross-project file browser used by the global Files screen when the
/// selected scope spans more than one project (All Files / By Customer /
/// By Tag). Streams every workspace file and applies scope + search +
/// filter client-side — Supabase streams can't join, so customer, vendor and
/// tag filters resolve against the [projects] / [vendorSubdivisions] /
/// [workspaceTags] maps passed in by the parent.
class WorkspaceFilesBrowser extends StatefulWidget {
  final String workspaceId;
  final FilesScope scope;
  final String scopeTitle;

  /// Every project in the workspace — used to map `project_id` → project name
  /// for the list column and to resolve `byCustomer` / vendor filters via
  /// `clientId` / `vendorSubdivisionId`.
  final List<Project> projects;

  /// All workspace customers — used to resolve customer names for search.
  final List<Customer> customers;

  /// All workspace vendors — used for filter selection and to resolve vendor
  /// names for search (via project → subdivision → vendor).
  final List<Vendor> vendors;

  /// Every active subdivision in the workspace — maps subdivisionId → vendorId
  /// so vendor filters can match files whose project is under that vendor.
  final List<VendorSubdivision> vendorSubdivisions;

  /// All workspace tags — used to resolve the tag name for `byTag` filters.
  final List<FileTag> workspaceTags;

  /// Current toolbar search query. Empty string means no search active.
  final String searchQuery;

  /// Current advanced filter selections.
  final FilesFilter filter;

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<FilesFilter> onFilterChanged;

  /// Called when the user picks a project in the upload flow so the parent
  /// can switch scope to `ByProjectScope(projectId)` — where the actual
  /// upload UI lives. Hidden when not provided.
  final ValueChanged<String>? onNavigateToProject;

  /// Mobile-only entry point to the scope picker, shown inline in the scope
  /// banner. Null on desktop, where the sidebar is always visible.
  final VoidCallback? onChangeScope;

  /// Saved views state forwarded from the parent screen so the toolbar can
  /// surface a bookmark menu. The parent owns persistence; this widget only
  /// renders and dispatches.
  final List<SavedViewEntry> savedViews;
  final String? activeSavedViewId;
  final bool canSaveCurrentView;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<String> onDeleteSavedView;
  final VoidCallback onSaveCurrentView;

  const WorkspaceFilesBrowser({
    super.key,
    required this.workspaceId,
    required this.scope,
    required this.scopeTitle,
    required this.projects,
    required this.customers,
    required this.vendors,
    required this.vendorSubdivisions,
    required this.workspaceTags,
    required this.searchQuery,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.canSaveCurrentView,
    required this.onApplySavedView,
    required this.onDeleteSavedView,
    required this.onSaveCurrentView,
    this.onNavigateToProject,
    this.onChangeScope,
  });

  @override
  State<WorkspaceFilesBrowser> createState() => _WorkspaceFilesBrowserState();
}

class _WorkspaceFilesBrowserState extends State<WorkspaceFilesBrowser> {
  final _storageService = ServiceLocator.storageService;

  Stream<List<FileAttachment>>? _stream;

  /// Latest file list from the stream — kept so the filter sheet can show
  /// per-option counts without re-subscribing.
  List<FileAttachment> _latestFiles = const [];

  /// userId → display name, used by FileListView for the "Uploaded By" column.
  Map<String, String> _userNames = const {};

  /// Shared with [ProjectFilesScreen] so users get a consistent grid/list
  /// preference across both Files surfaces.
  static const String _viewModePrefKey = 'filesView.mode';

  // Process-wide cache of the persisted view mode so the toggle doesn't
  // flicker from grid → list while SharedPreferences resolves.
  static bool? _cachedViewMode;

  bool _isListView = _cachedViewMode ?? true;

  @override
  void initState() {
    super.initState();
    _stream = _storageService.streamWorkspaceFiles(widget.workspaceId);
    if (_cachedViewMode == null) _loadViewModePreference();
    _loadUserNames();
  }

  Future<void> _loadUserNames() async {
    final usersMap = await ServiceLocator.userService
        .getWorkspaceUsersMap(widget.workspaceId);
    if (!mounted) return;
    setState(() {
      _userNames = {
        for (final e in usersMap.entries)
          e.key: e.value.displayName ?? e.value.email,
      };
    });
  }

  Future<void> _loadViewModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString(_viewModePrefKey) != 'grid';
    _cachedViewMode = list;
    if (mounted && _isListView != list) {
      setState(() => _isListView = list);
    }
  }

  Future<void> _persistViewMode(bool list) async {
    _cachedViewMode = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModePrefKey, list ? 'list' : 'grid');
  }

  @override
  Widget build(BuildContext context) {
    final projectsById = {for (final p in widget.projects) p.id: p};
    final customersById = {for (final c in widget.customers) c.id: c};
    final subdivisionToVendor = {
      for (final s in widget.vendorSubdivisions) s.id: s.vendorId
    };
    final vendorsById = {for (final v in widget.vendors) v.id: v};
    final projectNames = {
      for (final p in widget.projects) p.id: p.name,
    };

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: StreamBuilder<List<FileAttachment>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(children: [
                  _buildScopeBanner(resultCount: null, totalCount: null),
                  Expanded(child: _errorState(snapshot.error.toString())),
                ]);
              }
              if (!snapshot.hasData) {
                return Column(children: [
                  _buildScopeBanner(resultCount: null, totalCount: null),
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ]);
              }

              final all = snapshot.data!;
              _latestFiles = all;
              final filtered = _applyAll(
                all,
                projectsById: projectsById,
                customersById: customersById,
                subdivisionToVendor: subdivisionToVendor,
                vendorsById: vendorsById,
              );
              return Column(
                children: [
                  _buildScopeBanner(
                    resultCount: filtered.length,
                    totalCount: all.length,
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _emptyState()
                        : _isListView
                            ? FileListView(
                                files: filtered,
                                folders: const [],
                                onOpen: (f) =>
                                    _openFile(filtered, filtered.indexOf(f)),
                                showJobColumn: true,
                                projectNames: projectNames,
                                userNames: _userNames,
                                onEditTags: (f) => showQuickTagEditor(
                                  context: context,
                                  file: f,
                                  workspaceId: widget.workspaceId,
                                ),
                              )
                            : FileGridView(
                                files: filtered,
                                onOpen: (f) =>
                                    _openFile(filtered, filtered.indexOf(f)),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return ViewToolbar(
      searchHint: 'Search files, projects, customers, vendors...',
      searchQuery: widget.searchQuery,
      onSearch: widget.onSearchChanged,
      filterCount: widget.filter.activeCount,
      onFilterTap: _openFilterSheet,
      quickToggles: [
        SavedViewsMenu(
          savedViews: widget.savedViews,
          activeSavedViewId: widget.activeSavedViewId,
          canSaveCurrent: widget.canSaveCurrentView,
          onApplyView: widget.onApplySavedView,
          onDeleteView: widget.onDeleteSavedView,
          onSaveCurrentView: widget.onSaveCurrentView,
        ),
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Grid view',
          isSelected: !_isListView,
          onTap: () {
            if (_isListView) {
              setState(() => _isListView = false);
              _persistViewMode(false);
            }
          },
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'List view',
          isSelected: _isListView,
          onTap: () {
            if (!_isListView) {
              setState(() => _isListView = true);
              _persistViewMode(true);
            }
          },
        ),
        if (widget.onNavigateToProject != null)
          ViewIconButton(
            icon: Icons.upload_file_outlined,
            tooltip:
                'Upload to a ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()}…',
            isSelected: false,
            onTap: _pickProjectForUpload,
          ),
      ],
    );
  }

  /// Files always belong to a project, so cross-scope views can't upload
  /// directly. Instead, prompt the user to pick one — scoped to what's
  /// relevant to the current view (e.g. this customer's projects) — and
  /// delegate scope switch to the parent. Upload then happens in
  /// [ProjectFilesScreen].
  Future<void> _pickProjectForUpload() async {
    final projectTerm = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );
    final projectTermLower = projectTerm.toLowerCase();
    final projectTermPluralLower = context
        .read<WorkspaceProvider>()
        .projectTerminology
        .toLowerCase();
    final scoped = _projectsForCurrentScope();
    if (scoped.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No $projectTermPluralLower available to upload to.'),
        ),
      );
      return;
    }
    final customersById = {for (final c in widget.customers) c.id: c};
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Upload to which $projectTermLower?',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: scoped
                    .map((p) {
                      final customerName = p.clientId != null
                          ? customersById[p.clientId]?.businessDisplayName
                          : null;
                      final subtitle = [
                        if (p.serialNumber?.isNotEmpty == true) p.serialNumber!,
                        if (customerName != null) customerName,
                      ].join(' · ');
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(p.name),
                        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                        onTap: () => Navigator.pop(sheetCtx, p.id),
                      );
                    })
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      widget.onNavigateToProject!(picked);
    }
  }

  List<Project> _projectsForCurrentScope() {
    final scope = widget.scope;
    return switch (scope) {
      AllWorkspaceScope() => widget.projects,
      ByCustomerScope(:final customerId) =>
        widget.projects.where((p) => p.clientId == customerId).toList(),
      ByTagScope() => widget.projects,
      ByProjectScope(:final projectId) =>
        widget.projects.where((p) => p.id == projectId).toList(),
    };
  }

  /// Strip under the toolbar showing the active sidebar scope, the number
  /// of matching results, and an inline "filters applied" hint so users see
  /// why the list may look shorter than they expected.
  Widget _buildScopeBanner({int? resultCount, int? totalCount}) {
    final hasSearch = widget.searchQuery.isNotEmpty;
    final hasFilter = !widget.filter.isEmpty;
    final filtered = hasSearch || hasFilter;
    String? countText;
    if (resultCount != null) {
      if (filtered && totalCount != null && totalCount != resultCount) {
        countText = '$resultCount of $totalCount';
      } else {
        countText = resultCount == 1 ? '1 file' : '$resultCount files';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(_scopeIcon(), size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.scopeTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (filtered) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                hasSearch && hasFilter
                    ? 'search + filters'
                    : (hasFilter ? 'filtered' : 'searching'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (countText != null)
            Text(
              countText,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          if (widget.onChangeScope != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: widget.onChangeScope,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Change',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showFilesFilterSheet(
      context: context,
      current: widget.filter,
      customers: widget.customers,
      vendors: widget.vendors,
      projects: widget.projects,
      tags: widget.workspaceTags,
      counts: _computeFilterCounts(),
    );
    if (result != null) {
      widget.onFilterChanged(result);
    }
  }

  /// Compute per-option file counts across the current unfiltered set so
  /// the filter sheet can surface "(N)" next to each choice. Uses the
  /// scoped files (respect sidebar scope) but ignores the current search /
  /// filter selections — otherwise the counts would collapse to "(1)" as
  /// soon as the user picks one option.
  Map<String, int> _computeFilterCounts() {
    if (_latestFiles.isEmpty) return const {};
    final projectsById = {for (final p in widget.projects) p.id: p};
    final subToVendor = {
      for (final s in widget.vendorSubdivisions) s.id: s.vendorId
    };
    final tagsByName = {
      for (final t in widget.workspaceTags) t.name.toLowerCase(): t.id,
    };
    final scoped = _applyScope(_latestFiles);
    final counts = <String, int>{};
    for (final file in scoped) {
      final project = projectsById[file.projectId];
      counts[file.projectId] = (counts[file.projectId] ?? 0) + 1;
      if (project != null) {
        final customerId = project.clientId;
        if (customerId != null) {
          counts[customerId] = (counts[customerId] ?? 0) + 1;
        }
        final subdivisionId = project.vendorSubdivisionId;
        if (subdivisionId != null) {
          final vendorId = subToVendor[subdivisionId];
          if (vendorId != null) {
            counts[vendorId] = (counts[vendorId] ?? 0) + 1;
          }
        }
      }
      for (final tag in file.resolvedTags) {
        counts[tag.id] = (counts[tag.id] ?? 0) + 1;
      }
      // Legacy TEXT[] tags — map name → id for count attribution.
      for (final name in file.tags) {
        final tagId = tagsByName[name.toLowerCase()];
        if (tagId != null) {
          counts[tagId] = (counts[tagId] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  IconData _scopeIcon() => switch (widget.scope) {
        AllWorkspaceScope() => Icons.folder_open_outlined,
        ByCustomerScope() => Icons.business_outlined,
        ByTagScope() => Icons.label_outline,
        ByProjectScope() => Icons.folder_outlined,
      };

  /// Applies scope filter (from sidebar), advanced filter (from bottom sheet),
  /// and search query in that order.
  List<FileAttachment> _applyAll(
    List<FileAttachment> all, {
    required Map<String, Project> projectsById,
    required Map<String, Customer> customersById,
    required Map<String, String> subdivisionToVendor,
    required Map<String, Vendor> vendorsById,
  }) {
    var result = _applyScope(all);
    result = _applyFilter(
      result,
      projectsById: projectsById,
      subdivisionToVendor: subdivisionToVendor,
    );
    result = _applySearch(
      result,
      projectsById: projectsById,
      customersById: customersById,
      subdivisionToVendor: subdivisionToVendor,
      vendorsById: vendorsById,
    );
    return result;
  }

  List<FileAttachment> _applyScope(List<FileAttachment> all) {
    final scope = widget.scope;
    return switch (scope) {
      AllWorkspaceScope() => all,
      ByCustomerScope(:final customerId) => () {
          final projectIds = widget.projects
              .where((p) => p.clientId == customerId)
              .map((p) => p.id)
              .toSet();
          return all.where((f) => projectIds.contains(f.projectId)).toList();
        }(),
      ByTagScope(:final tagId) => () {
          final tag = widget.workspaceTags.firstWhere(
            (t) => t.id == tagId,
            orElse: () => throw StateError('Tag $tagId not found'),
          );
          final name = tag.name.toLowerCase();
          return all.where((f) {
            // Check resolved tags first (won't be populated by streams, but
            // reserved for future join support), then fall back to the
            // legacy TEXT[] which updateFileMetadata keeps in sync.
            if (f.resolvedTags.any((t) => t.id == tagId)) return true;
            return f.tags.any((t) => t.toLowerCase() == name);
          }).toList();
        }(),
      // byProject is handled by the parent (renders ProjectFilesScreen
      // directly), so this branch is unreachable. Defensive return keeps
      // the exhaustiveness check happy.
      ByProjectScope(:final projectId) =>
        all.where((f) => f.projectId == projectId).toList(),
    };
  }

  List<FileAttachment> _applyFilter(
    List<FileAttachment> files, {
    required Map<String, Project> projectsById,
    required Map<String, String> subdivisionToVendor,
  }) {
    final f = widget.filter;
    if (f.isEmpty) return files;
    return files.where((file) {
      final project = projectsById[file.projectId];

      if (f.customerId != null &&
          project?.clientId != f.customerId) {
        return false;
      }

      if (f.vendorId != null) {
        final subdivisionId = project?.vendorSubdivisionId;
        if (subdivisionId == null) return false;
        if (subdivisionToVendor[subdivisionId] != f.vendorId) return false;
      }

      if (f.projectId != null && file.projectId != f.projectId) {
        return false;
      }

      if (f.tagId != null) {
        final tag = widget.workspaceTags
            .where((t) => t.id == f.tagId)
            .firstOrNull;
        if (tag == null) return false;
        final matchesResolved =
            file.resolvedTags.any((t) => t.id == f.tagId);
        final matchesLegacy = file.tags
            .any((t) => t.toLowerCase() == tag.name.toLowerCase());
        if (!matchesResolved && !matchesLegacy) return false;
      }

      if (f.fileType != null && !f.fileType!.matches(file)) {
        return false;
      }

      if (f.dateRange != null && !f.dateRange!.matches(file.uploadedAt)) {
        return false;
      }

      return true;
    }).toList();
  }

  List<FileAttachment> _applySearch(
    List<FileAttachment> files, {
    required Map<String, Project> projectsById,
    required Map<String, Customer> customersById,
    required Map<String, String> subdivisionToVendor,
    required Map<String, Vendor> vendorsById,
  }) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return files;

    return files.where((file) {
      if (file.fileName.toLowerCase().contains(query)) return true;
      if ((file.title ?? '').toLowerCase().contains(query)) return true;
      if ((file.description ?? '').toLowerCase().contains(query)) return true;
      if (file.effectiveTagNames
          .any((t) => t.toLowerCase().contains(query))) {
        return true;
      }

      final project = projectsById[file.projectId];
      if (project != null) {
        if (project.name.toLowerCase().contains(query)) return true;
        if ((project.serialNumber ?? '').toLowerCase().contains(query)) {
          return true;
        }

        final customerId = project.clientId;
        if (customerId != null) {
          final customer = customersById[customerId];
          if (customer != null &&
              customer.businessDisplayName.toLowerCase().contains(query)) {
            return true;
          }
        }

        final subdivisionId = project.vendorSubdivisionId;
        if (subdivisionId != null) {
          final vendorId = subdivisionToVendor[subdivisionId];
          if (vendorId != null) {
            final vendor = vendorsById[vendorId];
            if (vendor != null &&
                vendor.companyName.toLowerCase().contains(query)) {
              return true;
            }
          }
        }
      }

      return false;
    }).toList();
  }

  Future<void> _openFile(List<FileAttachment> files, int index) async {
    await openFileViewer(
      context: context,
      files: files,
      initialIndex: index,
      workspaceId: widget.workspaceId,
    );
  }

  Widget _emptyState() {
    final hasSearch = widget.searchQuery.isNotEmpty;
    final hasFilter = !widget.filter.isEmpty;
    final hasActiveQuery = hasSearch || hasFilter;

    String title;
    String subtitle;
    if (hasSearch && hasFilter) {
      title = 'No files match your search and filters';
      subtitle = 'Try loosening the filters, clearing the search, '
          'or switching the view.';
    } else if (hasSearch) {
      title = 'No files match your search';
      subtitle = 'Try a different keyword or clear the search '
          'to see everything in this view.';
    } else if (hasFilter) {
      title = 'No files match your filters';
      subtitle = 'Adjust or clear filters to see more files.';
    } else {
      final scope = widget.scope;
      title = switch (scope) {
        AllWorkspaceScope() => 'No files in this workspace yet',
        ByCustomerScope() =>
          'No files for this customer\'s projects yet',
        ByTagScope() => 'No files with this tag yet',
        ByProjectScope() => 'No files in this project yet',
      };
      subtitle = widget.onNavigateToProject != null
          ? 'Pick a project to upload your first file.'
          : 'Files uploaded in projects will show up here.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasActiveQuery
                  ? Icons.search_off
                  : Icons.folder_open_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (hasSearch)
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Clear search'),
                    onPressed: () => widget.onSearchChanged(''),
                  ),
                if (hasFilter)
                  TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('Clear filters'),
                    onPressed: () => widget.onFilterChanged(FilesFilter.empty),
                  ),
                if (!hasActiveQuery && widget.onNavigateToProject != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: Text(
                      'Upload to a ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()}',
                    ),
                    onPressed: _pickProjectForUpload,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Failed to load files: $error',
          style: TextStyle(color: AppColors.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
