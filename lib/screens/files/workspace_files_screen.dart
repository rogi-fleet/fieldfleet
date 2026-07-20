import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../models/file_tag.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../models/vendor_subdivision.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/draggable_divider.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/files/file_detail_panel.dart';
import '../../widgets/common/saved_views_menu.dart';
import '../../widgets/files/files_filter.dart';
import '../../widgets/files/files_scope.dart';
import '../../widgets/files/project_files_screen.dart';
import '../../widgets/files/workspace_files_browser.dart';
import '../../widgets/projects/project_picker_tile.dart';

/// Global Files screen — browse uploaded files across projects.
///
/// Sidebar offers four scopes: All Files, By Customer, By Tag, By Project
/// (legacy behavior). Right pane renders the matching view — the existing
/// [ProjectFilesScreen] for `byProject`, a flat [WorkspaceFilesBrowser]
/// for the cross-job scopes.
class WorkspaceFilesScreen extends StatefulWidget {
  final String? initialProjectId;
  final String? initialVirtualFolder;
  final String? initialSelectedDocumentId;

  /// When set (via `?fileId=<uuid>` on the `/files` route), the screen lands
  /// on that file's project scope and auto-opens its detail panel — used by
  /// the Copy Link action to produce a shareable URL that pops open the
  /// exact file when the recipient navigates to it.
  final String? initialFileId;

  /// When set alongside [initialFileId], the detail panel briefly highlights
  /// the referenced comment. Supplied via `?commentId=<uuid>` — the payload
  /// mention notifications ship so recipients land on the exact comment.
  final String? initialCommentId;

  const WorkspaceFilesScreen({
    super.key,
    this.initialProjectId,
    this.initialVirtualFolder,
    this.initialSelectedDocumentId,
    this.initialFileId,
    this.initialCommentId,
  });

  @override
  State<WorkspaceFilesScreen> createState() => _WorkspaceFilesScreenState();
}

class _WorkspaceFilesScreenState extends State<WorkspaceFilesScreen> {
  static const double _dividerWidth = 8.0;
  static const double _sidebarMinWidth = 200.0;
  static const double _sidebarMaxWidth = 400.0;
  double _sidebarWidth = 260.0;

  FilesScope? _scope;

  List<Project> _projects = [];
  List<Customer> _customers = [];
  List<FileTag> _tags = [];
  List<Vendor> _vendors = [];
  List<VendorSubdivision> _subdivisions = [];
  bool _projectsLoaded = false;
  bool _subdivisionsLoaded = false;

  /// Show the loading spinner until both the project list and the vendor
  /// subdivision map have arrived — the filter sheet resolves vendors via
  /// `project.vendorSubdivisionId`, so opening it before subdivisions load
  /// would silently yield zero results on any vendor selection.
  bool get _loading => !_projectsLoaded || !_subdivisionsLoaded;

  StreamSubscription<List<Project>>? _projectsSub;
  StreamSubscription<List<Customer>>? _customersSub;
  StreamSubscription<List<FileTag>>? _tagsSub;
  StreamSubscription<List<Vendor>>? _vendorsSub;
  String? _subscribedWorkspaceId;

  // Toolbar search — applies to the right-pane file list (covers file name,
  // title, description, tags, plus project / customer / vendor names).
  String _searchQuery = '';

  // Toolbar filter state — persists across scope changes.
  FilesFilter _filter = FilesFilter.empty;

  static const String _savedViewsPrefKey = 'saved_files_views';
  List<_FilesSavedView> _savedViews = const [];
  String? _activeSavedViewId;

  bool _autoOpenedInitialFile = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialProjectId != null) {
      _scope = FilesScope.byProject(widget.initialProjectId!);
    }
    if (widget.initialFileId != null) {
      _resolveInitialFile(widget.initialFileId!);
    }
    _loadSavedViews();
  }

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService
        .getSavedViews(_savedViewsPrefKey);
    if (!mounted) return;
    setState(() {
      _savedViews = raw.map(_FilesSavedView.fromMap).toList();
    });
  }

  void _applySavedViewById(String viewId) {
    final view = _savedViews.where((v) => v.id == viewId).firstOrNull;
    if (view == null) return;
    setState(() {
      _scope = view.scope;
      _searchQuery = view.searchQuery;
      _filter = view.filter;
      _activeSavedViewId = view.id;
    });
  }

  Future<void> _saveCurrentView() async {
    final scope = _scope;
    if (scope == null) return;
    final name = await promptSavedViewName(
      context,
      hintText: 'e.g. Roof inspection PDFs',
    );
    if (name == null || name.isEmpty) return;
    final view = _FilesSavedView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      scope: scope,
      searchQuery: _searchQuery,
      filter: _filter,
      createdAt: DateTime.now(),
    );
    await ServiceLocator.userPreferencesService.upsertSavedView(
      _savedViewsPrefKey,
      view.toMap(),
    );
    if (!mounted) return;
    setState(() => _activeSavedViewId = view.id);
    await _loadSavedViews();
  }

  Future<void> _deleteSavedView(String viewId) async {
    await ServiceLocator.userPreferencesService.deleteSavedView(
      _savedViewsPrefKey,
      viewId,
    );
    if (!mounted) return;
    if (_activeSavedViewId == viewId) {
      setState(() => _activeSavedViewId = null);
    }
    await _loadSavedViews();
  }

  /// True when the user has set search or filter beyond the bare scope. A
  /// no-op view (e.g. just "All Files") is rarely worth persisting and clutters
  /// the menu.
  bool get _hasNonDefaultState =>
      _searchQuery.trim().isNotEmpty ||
      !_filter.isEmpty ||
      _scope is! AllWorkspaceScope;

  /// For deep-link `/files?fileId=<id>` — fetch the file, jump the scope to
  /// its project, and auto-open the detail panel once the tree is mounted.
  /// Surfaces a snackbar when the link is dead so the user isn't left
  /// wondering why the detail panel never opened.
  Future<void> _resolveInitialFile(String fileId) async {
    if (_autoOpenedInitialFile) return;
    _autoOpenedInitialFile = true;
    try {
      final file = await ServiceLocator.storageService.getFileWithTags(fileId);
      if (!mounted) return;
      if (file == null) {
        _showDeepLinkError('This file is no longer available.');
        return;
      }
      setState(() {
        _scope = FilesScope.byProject(file.projectId);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showFileDetailPanel(
          context: context,
          file: file,
          workspaceId: file.workspaceId,
          projectId: file.projectId,
          highlightCommentId: widget.initialCommentId,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _showDeepLinkError('Could not open the shared file. It may have been '
          'deleted or you may not have access.');
    }
  }

  void _showDeepLinkError(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceFilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != oldWidget.initialProjectId &&
        widget.initialProjectId != null) {
      _scope = FilesScope.byProject(widget.initialProjectId!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on AuthProvider (listen: true) rather than read() so this re-runs
    // when appUser hydrates. On a cold load / refresh of this route appUser is
    // briefly null; with read() the subscription was skipped and never retried,
    // leaving the screen stuck on the loading spinner forever.
    final workspaceId =
        Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId;
    if (workspaceId != null && workspaceId != _subscribedWorkspaceId) {
      _subscribedWorkspaceId = workspaceId;
      _subscribeAll(workspaceId);
    }
  }

  void _subscribeAll(String workspaceId) {
    _projectsSub?.cancel();
    _customersSub?.cancel();
    _tagsSub?.cancel();
    _vendorsSub?.cancel();

    _projectsSub = ServiceLocator.projectService
        .getProjects(workspaceId)
        .listen((projects) {
      if (!mounted) return;
      setState(() {
        _projects = List<Project>.from(projects)
          ..sort((a, b) => a.name.compareTo(b.name));
        _projectsLoaded = true;
        // If no scope yet and projects exist, default to All Files so users
        // land on something useful.
        _scope ??= const FilesScope.allWorkspace();
      });
    }, onError: (_) {
      // Don't leave the screen stuck on the spinner if the projects stream
      // errors — flip the flag so the (empty) Files UI still renders.
      if (!mounted) return;
      setState(() {
        _projectsLoaded = true;
        _scope ??= const FilesScope.allWorkspace();
      });
    });

    _customersSub = ServiceLocator.customerService
        .getCustomers(workspaceId)
        .listen((customers) {
      if (!mounted) return;
      setState(() {
        _customers = List<Customer>.from(customers)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    });

    _tagsSub = ServiceLocator.fileTagService
        .streamWorkspaceTags(workspaceId)
        .listen((tags) {
      if (!mounted) return;
      setState(() => _tags = tags);
    });

    final vendorStream =
        ServiceLocator.vendorService.getVendors(workspaceId) as Stream<List<Vendor>>;
    _vendorsSub = vendorStream.listen((vendors) {
      if (!mounted) return;
      setState(() {
        _vendors = List<Vendor>.from(vendors)
          ..sort((a, b) =>
              a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase()));
      });
    });

    // Subdivisions are used only to map project → vendor for the filter, so a
    // single fetch at scope-load time is fine (no realtime updates needed).
    // Flip _subdivisionsLoaded regardless of success so a transient fetch
    // failure doesn't leave the screen stuck on the spinner.
    ServiceLocator.vendorSubdivisionService
        .getWorkspaceSubdivisions(workspaceId)
        .then((subs) {
      if (!mounted) return;
      setState(() {
        _subdivisions = subs;
        _subdivisionsLoaded = true;
      });
    }).catchError((_) {
      // Flip the flag even on failure so a transient subdivisions fetch error
      // doesn't leave the screen stuck on the spinner (as the comment intends).
      if (!mounted) return;
      setState(() => _subdivisionsLoaded = true);
    });
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _customersSub?.cancel();
    _tagsSub?.cancel();
    _vendorsSub?.cancel();
    super.dispose();
  }

  void _setScope(FilesScope scope) {
    // Scope and advanced filter overlap semantically (e.g. picking "By
    // Customer" in the sidebar is the same axis as the Customer filter
    // chip). Clear filter on scope change so the new view doesn't silently
    // filter to nothing; keep the free-text search — it's less coupled to
    // scope and users often want it to persist.
    final hadFilter = !_filter.isEmpty;
    setState(() {
      _scope = scope;
      _filter = FilesFilter.empty;
      _activeSavedViewId = null;
    });
    if (hadFilter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Filters cleared for the new view'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ColoredBox(
      // Content area uses the light background even in dark-chrome mode; the
      // scope sidebar wraps itself in chrome.background to stay dark.
      color: AppColors.background,
      child: Column(
        children: [
          const ModuleHeader(
            icon: Icons.folder_copy_outlined,
            title: 'Files',
            description:
                'All workspace files, organized by project, customer or tag.',
          ),
          Expanded(
            child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          ),
        ],
      ),
    );
  }

  // ── Desktop layout ───────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _sidebarWidth, child: _buildScopeSidebar()),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) {
            setState(() {
              _sidebarWidth = (_sidebarWidth + d.delta.dx)
                  .clamp(_sidebarMinWidth, _sidebarMaxWidth);
            });
          },
          child: const DraggableDivider(width: _dividerWidth),
        ),
        Expanded(child: _buildContentArea()),
      ],
    );
  }

  Widget _buildScopeSidebar() {
    final chrome = ChromeColors.of(context);
    return ColoredBox(
      color: chrome.background,
      child: Column(
        children: [
          // Header strip that aligns with the ViewToolbar in the content area.
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: chrome.divider)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                _buildAllFilesTile(),
                _buildByCustomerSection(),
                _buildByTagSection(),
                _buildByProjectSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllFilesTile() {
    final selected = _scope is AllWorkspaceScope;
    return _ScopeTile(
      icon: Icons.folder_open_outlined,
      label: 'All Files',
      selected: selected,
      onTap: () => _setScope(const FilesScope.allWorkspace()),
    );
  }

  Widget _buildByCustomerSection() {
    if (_customers.isEmpty) return const SizedBox.shrink();
    return _SidebarSection(
      title: 'By Customer',
      children: _customers.map((c) {
        final selected = _scope is ByCustomerScope &&
            (_scope as ByCustomerScope).customerId == c.id;
        return _ScopeTile(
          icon: Icons.business_outlined,
          label: c.name.isEmpty ? '(unnamed)' : c.name,
          selected: selected,
          onTap: () => _setScope(FilesScope.byCustomer(c.id)),
          indent: 12,
        );
      }).toList(),
    );
  }

  Widget _buildByTagSection() {
    if (_tags.isEmpty) return const SizedBox.shrink();
    return _SidebarSection(
      title: 'By Tag',
      children: _tags.map((t) {
        final selected =
            _scope is ByTagScope && (_scope as ByTagScope).tagId == t.id;
        return _ScopeTile(
          icon: Icons.label_outline,
          iconColor: _tagColor(t.color),
          label: t.name,
          selected: selected,
          onTap: () => _setScope(FilesScope.byTag(t.id)),
          indent: 12,
        );
      }).toList(),
    );
  }

  Widget _buildByProjectSection() {
    final terminology = context.read<WorkspaceProvider>().projectTerminology;
    return _SidebarSection(
      title: 'By ${singularProjectTerminology(terminology)}',
      initiallyExpanded: true,
      children: [
        if (_projects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            child: Text(
              'No $terminology.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          )
        else
          ..._projects.map((project) {
            final isSelected = _scope is ByProjectScope &&
                (_scope as ByProjectScope).projectId == project.id;
            return Container(
              color:
                  isSelected ? AppColors.primary.withValues(alpha: 0.07) : null,
              child: ProjectPickerTile(
                project: project,
                isCurrent: isSelected,
                onTap: () => _setScope(FilesScope.byProject(project.id)),
              ),
            );
          }),
      ],
    );
  }

  Color _tagColor(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
      value = 'FF$value';
    }
    return Color(int.parse(value, radix: 16));
  }

  // ── Mobile layout ────────────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    // Browser scopes (All / Customer / Tag) render their own scope banner
    // with an inline "Change" button, so the chip row would be a duplicate.
    // ByProjectScope renders ProjectFilesScreen, which has no scope chrome
    // of its own — keep the chips there so the user can hop back out.
    final showChips = _scope is ByProjectScope || _scope == null;
    return Column(
      children: [
        if (showChips) _buildMobileScopeChips(),
        Expanded(child: _buildContentArea()),
      ],
    );
  }

  Widget _buildMobileScopeChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showMobileScopePicker,
              child: Row(
                children: [
                  Icon(_scopeIcon(), size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _scopeLabel(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
      ),
    );
  }

  IconData _scopeIcon() {
    final scope = _scope;
    return switch (scope) {
      AllWorkspaceScope() => Icons.folder_open_outlined,
      ByCustomerScope() => Icons.business_outlined,
      ByTagScope() => Icons.label_outline,
      ByProjectScope() => Icons.folder_outlined,
      null => Icons.folder_open_outlined,
    };
  }

  String _scopeLabel() {
    final scope = _scope;
    return switch (scope) {
      AllWorkspaceScope() => 'All Files',
      ByCustomerScope(:final customerId) =>
        _customers.where((c) => c.id == customerId).firstOrNull?.name ??
            '(deleted customer)',
      ByTagScope(:final tagId) =>
        _tags.where((t) => t.id == tagId).firstOrNull?.name ?? '(deleted tag)',
      ByProjectScope(:final projectId) =>
        _projects.where((p) => p.id == projectId).firstOrNull?.name ??
            '(deleted project)',
      null => 'Select a view',
    };
  }

  Future<void> _showMobileScopePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  _buildAllFilesTile(),
                  _buildByCustomerSection(),
                  _buildByTagSection(),
                  _buildByProjectSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared content area ──────────────────────────────────────────────────

  Widget _buildContentArea() {
    final scope = _scope;
    if (scope == null) return _buildSelectScopePrompt();

    return switch (scope) {
      ByProjectScope(:final projectId) => _buildProjectPane(projectId),
      AllWorkspaceScope() => _buildBrowserPane(scope, 'All Files'),
      ByCustomerScope(:final customerId) => () {
          final customer =
              _customers.where((c) => c.id == customerId).firstOrNull;
          if (customer == null) return _buildScopeUnavailablePrompt('customer');
          return _buildBrowserPane(scope, customer.name);
        }(),
      ByTagScope(:final tagId) => () {
          final tag = _tags.where((t) => t.id == tagId).firstOrNull;
          if (tag == null) return _buildScopeUnavailablePrompt('tag');
          return _buildBrowserPane(scope, tag.name);
        }(),
    };
  }

  Widget _buildProjectPane(String projectId) {
    final project = _projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) return _buildProjectUnavailablePrompt();

    return ProjectFilesScreen(
      key: ValueKey(
        '$projectId:${widget.initialVirtualFolder ?? ''}:${widget.initialSelectedDocumentId ?? ''}',
      ),
      projectId: project.id,
      workspaceId: project.workspaceId,
      project: project,
      initialVirtualFolder: widget.initialVirtualFolder,
      initialSelectedDocumentId: widget.initialSelectedDocumentId,
    );
  }

  Widget _buildBrowserPane(FilesScope scope, String scopeTitle) {
    final workspaceId = _subscribedWorkspaceId;
    if (workspaceId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return WorkspaceFilesBrowser(
      key: ValueKey('browser:$scope'),
      workspaceId: workspaceId,
      scope: scope,
      scopeTitle: scopeTitle,
      projects: _projects,
      customers: _customers,
      vendors: _vendors,
      vendorSubdivisions: _subdivisions,
      workspaceTags: _tags,
      searchQuery: _searchQuery,
      filter: _filter,
      onSearchChanged: (q) => setState(() {
        _searchQuery = q;
        _activeSavedViewId = null;
      }),
      onFilterChanged: (f) => setState(() {
        _filter = f;
        _activeSavedViewId = null;
      }),
      onNavigateToProject: (projectId) =>
          _setScope(FilesScope.byProject(projectId)),
      onChangeScope: isDesktop ? null : _showMobileScopePicker,
      savedViews: _savedViews
          .map((v) => SavedViewEntry(id: v.id, name: v.name))
          .toList(growable: false),
      activeSavedViewId: _activeSavedViewId,
      canSaveCurrentView: _hasNonDefaultState,
      onApplySavedView: _applySavedViewById,
      onDeleteSavedView: _deleteSavedView,
      onSaveCurrentView: _saveCurrentView,
    );
  }

  Widget _buildSelectScopePrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a view',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a scope from the sidebar to browse files.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectUnavailablePrompt() {
    return _buildScopeUnavailablePrompt('project');
  }

  Widget _buildScopeUnavailablePrompt(String entity) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              '${_capitalize(entity)} not available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'This $entity may have been deleted or you no longer have access to it.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () =>
                  setState(() => _scope = const FilesScope.allWorkspace()),
              child: const Text('View all files'),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ───────────────────────────────────────────────────────────────────────────
// Sidebar building blocks
// ───────────────────────────────────────────────────────────────────────────

class _SidebarSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _SidebarSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return ExpansionTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: chrome.scaffoldTextSecondary,
        ),
      ),
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      childrenPadding: EdgeInsets.zero,
      dense: true,
      shape: const Border(),
      children: children,
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double indent;

  const _ScopeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconColor,
    this.indent = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final chrome = ChromeColors.of(context);
          return Container(
            color: selected ? AppColors.primary.withValues(alpha: 0.07) : null,
            padding: EdgeInsets.only(
              left: 16 + indent,
              right: 12,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: iconColor ??
                      (selected
                          ? AppColors.primary
                          : chrome.scaffoldTextSecondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.primary : chrome.scaffoldText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Persists everything the user can configure on the Files screen: the sidebar
/// scope (kind + ref id), free-text search, and every advanced filter axis.
/// Stored as JSONB rows under the `saved_files_views` user-prefs key. Scope
/// keys ('all'/'project'/'customer'/'tag') deliberately use a flat string +
/// optional id rather than a sealed-class JSON envelope so the legacy menu
/// stays forward-compatible if more scopes get added.
class _FilesSavedView {
  final String id;
  final String name;
  final FilesScope scope;
  final String searchQuery;
  final FilesFilter filter;
  final DateTime createdAt;

  const _FilesSavedView({
    required this.id,
    required this.name,
    required this.scope,
    required this.searchQuery,
    required this.filter,
    required this.createdAt,
  });

  factory _FilesSavedView.fromMap(Map<String, dynamic> map) {
    final scope = _scopeFromMap(
      map['scope_kind'] as String?,
      map['scope_id'] as String?,
    );
    final fileTypeName = map['file_type'] as String?;
    final dateRangeName = map['date_range'] as String?;
    return _FilesSavedView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      scope: scope,
      searchQuery: map['search_query'] as String? ?? '',
      filter: FilesFilter(
        customerId: map['customer_id'] as String?,
        vendorId: map['vendor_id'] as String?,
        projectId: map['project_id'] as String?,
        tagId: map['tag_id'] as String?,
        fileType: FileTypeFilter.values
            .where((v) => v.name == fileTypeName)
            .firstOrNull,
        dateRange: DateRangeFilter.values
            .where((v) => v.name == dateRangeName)
            .firstOrNull,
      ),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    final (kind, refId) = _scopeToMap(scope);
    return {
      'id': id,
      'name': name,
      'scope_kind': kind,
      'scope_id': refId,
      'search_query': searchQuery,
      'customer_id': filter.customerId,
      'vendor_id': filter.vendorId,
      'project_id': filter.projectId,
      'tag_id': filter.tagId,
      'file_type': filter.fileType?.name,
      'date_range': filter.dateRange?.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static FilesScope _scopeFromMap(String? kind, String? id) {
    return switch (kind) {
      'project' when id != null => FilesScope.byProject(id),
      'customer' when id != null => FilesScope.byCustomer(id),
      'tag' when id != null => FilesScope.byTag(id),
      _ => const FilesScope.allWorkspace(),
    };
  }

  static (String, String?) _scopeToMap(FilesScope scope) {
    return switch (scope) {
      AllWorkspaceScope() => ('all', null),
      ByProjectScope(:final projectId) => ('project', projectId),
      ByCustomerScope(:final customerId) => ('customer', customerId),
      ByTagScope(:final tagId) => ('tag', tagId),
    };
  }
}
