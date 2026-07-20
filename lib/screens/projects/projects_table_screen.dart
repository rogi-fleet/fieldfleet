import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/customer.dart';
import '../../models/job_type.dart';
import '../../models/price_type.dart';
import '../../models/project.dart';
import '../../models/project_financial_summary.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../models/task.dart';
import '../../models/workspace_member.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/project_form_popup.dart';
import '../../widgets/animated_empty_state_cta.dart';
import '../../widgets/common/entity_card_grid.dart';
import '../../widgets/common/entity_create_card.dart';
import '../../widgets/common/module_header.dart';
import 'widgets/view_toggle_button.dart';
import 'widgets/project_card.dart';
import 'widgets/project_card_skeleton.dart';
import 'widgets/project_table_row.dart';
import 'widgets/project_filters.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/projects/kanban_project_board_view.dart';
import '../../widgets/timeline/project_calendar_widget.dart';
import '../../widgets/timeline/project_gantt_view.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../utils/project_customer_name.dart';
import '../../utils/project_terminology.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

import 'widgets/active_alerts_widget.dart';

class ProjectsTableScreen extends StatefulWidget {
  const ProjectsTableScreen({super.key});

  @override
  State<ProjectsTableScreen> createState() => _ProjectsTableScreenState();
}

class _ProjectsTableScreenState extends State<ProjectsTableScreen>
    with SingleTickerProviderStateMixin {
  ProjectViewType _currentView = ProjectViewType.card;
  ProjectViewType? _lastMirroredView;
  bool _isLoading = true;
  String _searchQuery = '';
  ProjectStatus? _selectedStatus;
  String? _selectedCustomerId;
  String? _selectedProjectManagerId;
  String? _selectedSupervisorId;
  String? _selectedSalespersonId;
  JobType? _selectedJobType;
  PriceType? _selectedPriceType;
  ProjectSortOption _selectedSort = ProjectSortOption.recent;
  String? _tableSortColumn;
  bool _tableSortAscending = true;
  final Map<String, double> _columnWidths = {};

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
    _persistView();
  }

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Set<String> _favoriteProjectIds = {};
  Set<String> _selectedProjectIds = {};
  bool _selectionMode = false;
  bool _pmExplicitlySet = false; // true once user has touched the PM filter
  List<_SavedProjectView> _savedViews = [];
  String? _activeSavedViewId;
  List<Project> _allProjects = [];
  StreamSubscription<List<Project>>? _projectsSub;
  String? _subscribedWorkspaceId;
  bool _isProjectsLoading = true;
  Object? _projectsLoadError;
  bool _hasShownProjectsConnectionNotice = false;
  Map<String, ProjectTaskMetrics> _taskMetricsByProject = {};
  bool _isLoadingTaskMetrics = false;
  String? _taskMetricsWorkspaceId;
  final Map<String, Future<ProjectFinancialSummary>> _financialsFutures = {};
  final Map<String, Future<List<Task>>> _tasksFutures = {};
  final Map<String, Future<List<ProjectAlert>>> _alertsFutures = {};
  final Map<String, Future<Customer?>> _customerFutures = {};
  Future<Map<String, AppUser>>? _workspaceUsersFuture;
  String? _workspaceUsersWorkspaceId;

  @override
  void initState() {
    super.initState();
    _hydrateViewPrefs();
    _loadFavorites();
    _loadSavedViews();

    // Pulse animation for the + button to draw attention
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  /// The effective PM id used for filtering:
  /// - if the user has explicitly set a PM filter, use that
  /// - otherwise in field mode, default to the current user
  String? get _effectivePMId {
    if (_pmExplicitlySet) return _selectedProjectManagerId;
    final auth = context.read<AuthProvider>();
    return auth.isFieldMode ? auth.currentUserId : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId != null && workspaceId != _subscribedWorkspaceId) {
      _subscribeToProjects(workspaceId);
    }
  }

  void _subscribeToProjects(String workspaceId) {
    setState(() {
      _subscribedWorkspaceId = workspaceId;
      _isProjectsLoading = true;
      _projectsLoadError = null;
      _hasShownProjectsConnectionNotice = false;
      _allProjects = [];
      _taskMetricsByProject = {};
      _isLoadingTaskMetrics = true;
      _taskMetricsWorkspaceId = workspaceId;
      _financialsFutures.clear();
      _tasksFutures.clear();
      _alertsFutures.clear();
      _customerFutures.clear();
      _workspaceUsersWorkspaceId = workspaceId;
      _workspaceUsersFuture = ServiceLocator.userService.getWorkspaceUsersMap(
        workspaceId,
      );
    });
    _projectsSub?.cancel();
    _projectsSub = ServiceLocator.projectService
        .getProjects(workspaceId)
        .listen(
          (projects) {
            if (!mounted || _subscribedWorkspaceId != workspaceId) return;
            setState(() {
              _allProjects = projects;
              _isProjectsLoading = false;
              _projectsLoadError = null;
              _hasShownProjectsConnectionNotice = false;
            });
          },
          onError: (error) {
            if (!mounted || _subscribedWorkspaceId != workspaceId) return;
            final hasCachedProjects = _allProjects.isNotEmpty;
            setState(() {
              _projectsLoadError = hasCachedProjects ? null : error;
              _isProjectsLoading = false;
            });

            if (hasCachedProjects && !_hasShownProjectsConnectionNotice) {
              _hasShownProjectsConnectionNotice = true;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Connection lost. Showing the last loaded projects until you reconnect.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        );
    _loadTaskMetrics(workspaceId);
  }

  Set<String> get _assignedProjectManagerIds => _allProjects
      .where((p) => p.projectManagerId != null)
      .map((p) => p.projectManagerId!)
      .toSet();

  Set<String> get _assignedSupervisorIds => _allProjects
      .where((p) => p.supervisorId != null)
      .map((p) => p.supervisorId!)
      .toSet();

  int get _activeFilterCount {
    int count = 0;
    if (_selectedStatus != null) count++;
    if (_selectedCustomerId != null) count++;
    if (_effectivePMId != null) count++;
    if (_selectedSupervisorId != null) count++;
    if (_selectedSalespersonId != null) count++;
    if (_selectedJobType != null) count++;
    if (_selectedPriceType != null) count++;
    return count;
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _hydrateViewPrefs() async {
    final svc = ServiceLocator.viewPrefsService;
    await svc.whenHydrated;
    if (!mounted) return;

    final blob = svc.read(_ProjectsListViewPrefs.scopeKey);
    if (blob != null) {
      final prefs = _ProjectsListViewPrefs.fromJson(blob);
      setState(() {
        _searchQuery = prefs.searchQuery;
        _selectedStatus = prefs.status;
        _selectedCustomerId = prefs.customerId;
        _selectedProjectManagerId = prefs.projectManagerId;
        _pmExplicitlySet = prefs.pmExplicitlySet;
        _selectedSalespersonId = prefs.salespersonId;
        _selectedSupervisorId = prefs.supervisorId;
        _selectedJobType = prefs.jobType;
        _selectedPriceType = prefs.priceType;
        _selectedSort = prefs.sort;
        _tableSortColumn = prefs.tableSortColumn;
        _tableSortAscending = prefs.tableSortAscending;
        _currentView = prefs.viewType;
        _columnWidths
          ..clear()
          ..addAll(prefs.columnWidths);
        _activeSavedViewId = prefs.activeSavedViewId;
        _isLoading = false;
      });
    } else {
      // First run: fall back to the legacy view-type SharedPreferences key so
      // returning users keep their previous selection.
      final legacy = await ViewToggleButton.loadPreference();
      if (!mounted) return;
      setState(() {
        _currentView = legacy;
        _isLoading = false;
      });
    }
  }

  /// Snapshot the current screen state into the view-prefs service.
  /// Cheap (one map allocation) and fully debounced inside the service.
  void _persistView() {
    if (!mounted) return;
    final blob = _ProjectsListViewPrefs(
      searchQuery: _searchQuery,
      status: _selectedStatus,
      customerId: _selectedCustomerId,
      projectManagerId: _selectedProjectManagerId,
      pmExplicitlySet: _pmExplicitlySet,
      salespersonId: _selectedSalespersonId,
      supervisorId: _selectedSupervisorId,
      jobType: _selectedJobType,
      priceType: _selectedPriceType,
      sort: _selectedSort,
      tableSortColumn: _tableSortColumn,
      tableSortAscending: _tableSortAscending,
      viewType: _currentView,
      columnWidths: Map.of(_columnWidths),
      activeSavedViewId: _activeSavedViewId,
    ).toJson();
    ServiceLocator.viewPrefsService
        .write(_ProjectsListViewPrefs.scopeKey, blob);

    // Mirror viewType into the legacy SharedPreferences key so other entry
    // points (e.g. embedded_project_list) stay in sync. Skipped when the
    // value hasn't changed to avoid pointless disk writes.
    if (_lastMirroredView != _currentView) {
      _lastMirroredView = _currentView;
      unawaited(_mirrorLegacyViewType(_currentView));
    }
  }

  Future<void> _mirrorLegacyViewType(ProjectViewType vt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('projects_view_type', vt.name);
  }

  Future<void> _loadFavorites() async {
    final ids = await ServiceLocator.userPreferencesService
        .getFavoriteProjectIds();
    if (mounted) {
      setState(() => _favoriteProjectIds = ids.toSet());
    }
  }

  static const String _savedViewsPrefKey = 'saved_project_views';

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService
        .getSavedViews(_savedViewsPrefKey);
    if (!mounted) return;

    setState(() {
      _savedViews = raw.map(_SavedProjectView.fromMap).toList();
    });
  }

  Future<void> _loadTaskMetrics(String workspaceId) async {
    try {
      final metrics =
          await ServiceLocator.taskService.getProjectListMetrics(workspaceId)
              as Map<String, ProjectTaskMetrics>;
      if (!mounted || _taskMetricsWorkspaceId != workspaceId) return;
      setState(() {
        _taskMetricsByProject = metrics;
        _isLoadingTaskMetrics = false;
      });
    } catch (_) {
      if (!mounted || _taskMetricsWorkspaceId != workspaceId) return;
      setState(() {
        _taskMetricsByProject = {};
        _isLoadingTaskMetrics = false;
      });
    }
  }

  Future<ProjectFinancialSummary> _financialsFutureFor(Project project) {
    return _financialsFutures.putIfAbsent(
      project.id,
      () =>
          ServiceLocator.projectService.getProjectFinancials(
                project.id,
                project,
              )
              as Future<ProjectFinancialSummary>,
    );
  }

  Future<List<Task>> _tasksFutureFor(Project project) {
    return _tasksFutures.putIfAbsent(
      project.id,
      () => ServiceLocator.taskService
          .getTasks(project.id, workspaceId: project.workspaceId)
          .first,
    );
  }

  Future<List<ProjectAlert>> _alertsFutureFor(Project project) {
    return _alertsFutures.putIfAbsent(project.id, () async {
      try {
        final financials = await _financialsFutureFor(project);
        return ProjectAlertsEngine.generateAlerts(
          project,
          financialSummary: financials,
        );
      } catch (_) {
        return ProjectAlertsEngine.generateAlerts(project);
      }
    });
  }

  Future<Customer?>? _customerFutureFor(Project project) {
    final customerId = project.clientId;
    if (customerId == null ||
        customerId.isEmpty ||
        !projectCustomerNeedsRefresh(project)) {
      return null;
    }

    return _customerFutures.putIfAbsent(
      customerId,
      () => ServiceLocator.customerService.getCustomer(customerId),
    );
  }

  Future<Map<String, AppUser>>? _workspaceUsersFutureFor(String workspaceId) {
    if (_workspaceUsersFuture == null ||
        _workspaceUsersWorkspaceId != workspaceId) {
      _workspaceUsersWorkspaceId = workspaceId;
      _workspaceUsersFuture = ServiceLocator.userService.getWorkspaceUsersMap(
        workspaceId,
      );
    }
    return _workspaceUsersFuture;
  }

  void _toggleFavorite(String projectId, bool isFavorite) {
    setState(() {
      if (isFavorite) {
        _favoriteProjectIds.add(projectId);
      } else {
        _favoriteProjectIds.remove(projectId);
      }
    });
    ServiceLocator.userPreferencesService.toggleFavoriteProject(projectId);
  }

  @override
  Widget build(BuildContext context) {
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular =
        singularProjectTerminology(projectTerminology).toLowerCase();
    return Scaffold(
      body: Column(
        children: [
          ModuleHeader(
            icon: Icons.folder_outlined,
            title: projectTerminology,
            description:
                'Plan, track and deliver every $singular from estimate to close-out.',
          ),
          _buildHeader(context),
          const Divider(height: 1),
          if (_selectionMode && _selectedProjectIds.isNotEmpty)
            _buildBulkActionBar(context),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final terminology =
        context.watch<WorkspaceProvider>().projectTerminology.toLowerCase();
    return ViewToolbar(
      searchHint: 'Search $terminology...',
      searchQuery: _searchQuery,
      onSearch: (query) {
        setState(() {
          _searchQuery = query;
          _activeSavedViewId = null;
        });
        _persistView();
      },
      centerSlot: _buildProjectViewIcons(),
      quickToggles: [_buildSortToggle()],
      filterCount: _activeFilterCount,
      onFilterTap: _showProjectFilterDialog,
    );
  }

  Widget _buildProjectViewIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _currentView == ProjectViewType.card,
          onTap: () => _setViewType(ProjectViewType.card),
        ),
        ViewIconButton(
          icon: Icons.view_list,
          tooltip: 'Table',
          isSelected: _currentView == ProjectViewType.table,
          onTap: () => _setViewType(ProjectViewType.table),
        ),
        ViewIconButton(
          icon: Icons.calendar_month,
          tooltip: 'Calendar',
          isSelected: _currentView == ProjectViewType.calendar,
          onTap: () => _setViewType(ProjectViewType.calendar),
        ),
        ViewIconButton(
          icon: Icons.view_timeline,
          tooltip: 'Gantt',
          isSelected: _currentView == ProjectViewType.gantt,
          onTap: () => _setViewType(ProjectViewType.gantt),
        ),
        ViewIconButton(
          icon: Icons.view_kanban,
          tooltip: 'Board',
          isSelected: _currentView == ProjectViewType.board,
          onTap: () => _setViewType(ProjectViewType.board),
        ),
      ],
    );
  }

  void _setViewType(ProjectViewType viewType) {
    if (_currentView == viewType) return;
    setState(() => _currentView = viewType);
    _persistView();
  }

  Widget _buildSortToggle() {
    return PopupMenuButton<ProjectSortOption>(
      onSelected: (sort) {
        setState(() {
          _selectedSort = sort;
          _activeSavedViewId = null;
        });
        _persistView();
      },
      tooltip: 'Sort',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 180),
      child: Builder(
        builder: (context) {
          final chrome = ChromeColors.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: chrome.subtleBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort, size: 16, color: chrome.text),
                const SizedBox(width: 6),
                Text(
                  _selectedSort.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: chrome.textActive,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 18, color: chrome.text),
              ],
            ),
          );
        },
      ),
      itemBuilder: (context) => [
        for (final option in ProjectSortOption.values)
          PopupMenuItem<ProjectSortOption>(
            value: option,
            height: 40,
            child: Row(
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: option == _selectedSort
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: option == _selectedSort ? AppColors.primary : null,
                  ),
                ),
                const Spacer(),
                if (option == _selectedSort)
                  const Icon(Icons.check, size: 18, color: AppColors.primary),
              ],
            ),
          ),
      ],
    );
  }

  void _showProjectFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return _ProjectFilterDialog(
          selectedStatus: _selectedStatus,
          selectedCustomerId: _selectedCustomerId,
          selectedProjectManagerId: _effectivePMId,
          selectedSupervisorId: _selectedSupervisorId,
          selectedSalespersonId: _selectedSalespersonId,
          selectedJobType: _selectedJobType,
          selectedPriceType: _selectedPriceType,
          projectManagerIds: _assignedProjectManagerIds,
          supervisorIds: _assignedSupervisorIds,
          savedViews: _savedViews,
          activeSavedViewId: _activeSavedViewId,
          onApply:
              (status, customerId, pmId, supervisorId, salespersonId, jobType,
                  priceType) {
            setState(() {
              _selectedStatus = status;
              _selectedCustomerId = customerId;
              _pmExplicitlySet = true;
              _selectedProjectManagerId = pmId;
              _selectedSupervisorId = supervisorId;
              _selectedSalespersonId = salespersonId;
              _selectedJobType = jobType;
              _selectedPriceType = priceType;
              _activeSavedViewId = null;
            });
            _persistView();
            Navigator.of(ctx).pop();
          },
          onApplySavedView: (viewId) {
            Navigator.of(ctx).pop();
            _applySavedViewById(viewId);
          },
          onSaveView:
              (status, customerId, pmId, supervisorId, salespersonId, jobType,
                  priceType) {
            Navigator.of(ctx).pop();
            _showSaveViewDialog(
              status: status,
              customerId: customerId,
              projectManagerId: pmId,
              supervisorId: supervisorId,
              salespersonId: salespersonId,
              jobType: jobType,
              priceType: priceType,
            );
          },
          onDeleteSavedView: (viewId) {
            _deleteSavedViewById(viewId);
          },
          onResetToDefaults: () {
            Navigator.of(ctx).pop();
            _resetViewToDefaults();
          },
        );
      },
    );
  }

  /// Drop the persisted view-prefs blob and snap the screen back to the
  /// constructor defaults. The legacy `projects_view_type` SharedPreferences
  /// key is cleared too so other entry points (embedded project list) reset.
  void _resetViewToDefaults() {
    ServiceLocator.viewPrefsService.remove(_ProjectsListViewPrefs.scopeKey);
    _lastMirroredView = null;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.remove('projects_view_type')),
    );
    setState(() {
      _searchQuery = '';
      _selectedStatus = null;
      _selectedCustomerId = null;
      _selectedProjectManagerId = null;
      _pmExplicitlySet = false;
      _selectedSupervisorId = null;
      _selectedSalespersonId = null;
      _selectedJobType = null;
      _selectedPriceType = null;
      _selectedSort = ProjectSortOption.recent;
      _tableSortColumn = null;
      _tableSortAscending = true;
      _columnWidths.clear();
      _activeSavedViewId = null;
    });
  }

  void _applySavedViewById(String viewId) {
    _SavedProjectView? view;
    for (final candidate in _savedViews) {
      if (candidate.id == viewId) {
        view = candidate;
        break;
      }
    }
    if (view == null) return;
    final selectedView = view;
    setState(() {
      _searchQuery = selectedView.searchQuery;
      _selectedStatus = selectedView.status;
      _selectedCustomerId = selectedView.customerId;
      _selectedProjectManagerId = selectedView.projectManagerId;
      _pmExplicitlySet =
          true; // saved view always represents an explicit choice
      _selectedSupervisorId = selectedView.supervisorId;
      _selectedSalespersonId = selectedView.salespersonId;
      _selectedJobType = selectedView.jobType;
      _selectedPriceType = selectedView.priceType;
      _selectedSort = selectedView.sortOption;
      _tableSortColumn = selectedView.tableSortColumn;
      _tableSortAscending = selectedView.tableSortAscending;
      _activeSavedViewId = selectedView.id;
    });
    _persistView();
  }

  Future<void> _showSaveViewDialog({
    required ProjectStatus? status,
    required String? customerId,
    required String? projectManagerId,
    required String? supervisorId,
    required String? salespersonId,
    required JobType? jobType,
    required PriceType? priceType,
  }) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save current view'),
          content: StackedField(
            label: 'View name',
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Active - High Budget',
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.of(context).pop(value.trim());
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.of(context).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    final view = _SavedProjectView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      searchQuery: _searchQuery,
      status: status,
      customerId: customerId,
      projectManagerId: projectManagerId,
      supervisorId: supervisorId,
      salespersonId: salespersonId,
      jobType: jobType,
      priceType: priceType,
      sortOption: _selectedSort,
      tableSortColumn: _tableSortColumn,
      tableSortAscending: _tableSortAscending,
      createdAt: DateTime.now(),
    );

    await ServiceLocator.userPreferencesService.upsertSavedView(
      _savedViewsPrefKey,
      view.toMap(),
    );
    if (!mounted) return;

    setState(() {
      _activeSavedViewId = view.id;
    });
    _persistView();
    await _loadSavedViews();
  }

  Future<void> _deleteSavedViewById(String viewId) async {
    await ServiceLocator.userPreferencesService.deleteSavedView(
      _savedViewsPrefKey,
      viewId,
    );
    if (!mounted) return;
    if (_activeSavedViewId == viewId) {
      setState(() => _activeSavedViewId = null);
      _persistView();
    }
    await _loadSavedViews();
  }

  Widget _buildContent(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Center(child: Text('No workspace selected'));
    }

    if (_isProjectsLoading) {
      if (_currentView == ProjectViewType.card) {
        return const ProjectCardSkeletonList();
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading ${context.watch<WorkspaceProvider>().projectTerminology.toLowerCase()}…',
            ),
          ],
        ),
      );
    }

    if (_projectsLoadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            SelectableText(
              UserFacingError.uiMessage(
                _projectsLoadError,
                action: 'load projects',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                final wid = _subscribedWorkspaceId;
                if (wid != null) _subscribeToProjects(wid);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filteredProjects = _filterAndSortProjects(_allProjects);

    // Board view should always render columns for spatial context,
    // even when the filtered list is empty.
    if (filteredProjects.isEmpty && _currentView != ProjectViewType.board) {
      return _buildEmptyState(context);
    }

    switch (_currentView) {
      case ProjectViewType.table:
        return _buildTableView(context, filteredProjects);
      case ProjectViewType.board:
        return _buildBoardView(filteredProjects);
      case ProjectViewType.calendar:
        return _buildCalendarView(filteredProjects);
      case ProjectViewType.card:
        return _buildCardView(filteredProjects);
      case ProjectViewType.gantt:
        return _buildGanttView(filteredProjects);
    }
  }

  List<Project> _filterAndSortProjects(List<Project> projects) {
    var filtered = projects.where((project) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        if (!_matchesProjectSearch(project, _searchQuery)) return false;
      }

      // Status filter
      if (_selectedStatus != null && project.status != _selectedStatus) {
        return false;
      }

      // Customer filter
      if (_selectedCustomerId != null &&
          project.clientId != _selectedCustomerId) {
        return false;
      }

      // Project manager filter
      if (_effectivePMId != null &&
          project.projectManagerId != _effectivePMId) {
        return false;
      }

      // Supervisor filter
      if (_selectedSupervisorId != null &&
          project.supervisorId != _selectedSupervisorId) {
        return false;
      }

      // Sales person filter
      if (_selectedSalespersonId != null &&
          project.salespersonId != _selectedSalespersonId) {
        return false;
      }

      // Job type filter
      if (_selectedJobType != null && project.jobType != _selectedJobType) {
        return false;
      }

      // Price type filter
      if (_selectedPriceType != null &&
          project.priceType != _selectedPriceType) {
        return false;
      }

      return true;
    }).toList();

    // Sort — column sort (table view) takes priority over the dropdown sort
    if (_tableSortColumn != null && _currentView == ProjectViewType.table) {
      final asc = _tableSortAscending;
      filtered.sort((a, b) {
        int cmp;
        switch (_tableSortColumn) {
          case 'id':
            cmp = compareProjectTableIds(a, b);
            break;
          case 'project':
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            break;
          case 'customer':
            cmp = (a.customerName ?? '').toLowerCase().compareTo(
              (b.customerName ?? '').toLowerCase(),
            );
            break;
          case 'status':
            cmp = a.status.displayName.toLowerCase().compareTo(
              b.status.displayName.toLowerCase(),
            );
            break;
          case 'budget':
            cmp = (a.estimatedBudget ?? 0).compareTo(b.estimatedBudget ?? 0);
            break;
          case 'tasks':
            final aMetrics = _taskMetricsByProject[a.id];
            final bMetrics = _taskMetricsByProject[b.id];
            cmp = (aMetrics?.totalCount ?? 0).compareTo(
              bMetrics?.totalCount ?? 0,
            );
            break;
          case 'timeline':
            final aDate = a.startDate ?? a.createdAt;
            final bDate = b.startDate ?? b.createdAt;
            cmp = aDate.compareTo(bDate);
            break;
          case 'progress':
            final aMetrics = _taskMetricsByProject[a.id];
            final bMetrics = _taskMetricsByProject[b.id];
            cmp = (aMetrics?.progressPercent ?? 0).compareTo(
              bMetrics?.progressPercent ?? 0,
            );
            break;
          default:
            cmp = 0;
        }
        return asc ? cmp : -cmp;
      });
    } else {
      switch (_selectedSort) {
        case ProjectSortOption.recent:
          filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
        case ProjectSortOption.nameAsc:
          filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case ProjectSortOption.nameDesc:
          filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
          break;
        case ProjectSortOption.budgetHigh:
          filtered.sort(
            (a, b) =>
                (b.estimatedBudget ?? 0).compareTo(a.estimatedBudget ?? 0),
          );
          break;
        case ProjectSortOption.budgetLow:
          filtered.sort(
            (a, b) =>
                (a.estimatedBudget ?? 0).compareTo(b.estimatedBudget ?? 0),
          );
          break;
      }
    }

    // Favorites only affect the default browse order. When the user explicitly
    // sorts by a column or non-default option, that sort should win outright.
    final shouldPinFavorites =
        _favoriteProjectIds.isNotEmpty &&
        _tableSortColumn == null &&
        _selectedSort == ProjectSortOption.recent;

    // Favorites float to top while preserving sort order within each group.
    // Using a separate .sort() would break the previous ordering because
    // Dart's sort is not guaranteed to be stable.
    if (shouldPinFavorites) {
      final favSet = _favoriteProjectIds;
      final indexed = List.generate(filtered.length, (i) => i);
      indexed.sort((i, j) {
        final aFav = favSet.contains(filtered[i].id) ? 0 : 1;
        final bFav = favSet.contains(filtered[j].id) ? 0 : 1;
        if (aFav != bFav) return aFav.compareTo(bFav);
        return i.compareTo(j); // preserve original order
      });
      filtered = [for (final i in indexed) filtered[i]];
    }

    return filtered;
  }

  bool _matchesProjectSearch(Project project, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final normalizedQuery = _normalizeIdentifier(query);
    final fallbackTableId = project.id.length > 8
        ? project.id.substring(project.id.length - 8)
        : project.id;
    final fallbackCardId = project.id.length > 6
        ? project.id.substring(0, 6)
        : project.id;

    final textMatches =
        project.name.toLowerCase().contains(query) ||
        project.address.toLowerCase().contains(query) ||
        (project.description?.toLowerCase().contains(query) ?? false) ||
        (project.customerName?.toLowerCase().contains(query) ?? false) ||
        (project.primaryContactName?.toLowerCase().contains(query) ?? false) ||
        (project.purchaseOrderNumber?.toLowerCase().contains(query) ?? false) ||
        (project.serialNumber?.toLowerCase().contains(query) ?? false);

    if (textMatches) return true;

    if (normalizedQuery.isEmpty) return false;

    final identifierCandidates = <String>{
      if (project.serialNumber != null) project.serialNumber!,
      if (project.serialNumber != null) '#${project.serialNumber!}',
      fallbackTableId,
      fallbackCardId,
      '#$fallbackCardId',
    };

    for (final candidate in identifierCandidates) {
      if (_normalizeIdentifier(candidate).contains(normalizedQuery)) {
        return true;
      }
    }

    return false;
  }

  String _normalizeIdentifier(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<TableColumnSchema> _tableColumns(String projectLabel) => [
    const TableColumnSchema(
      id: 'id',
      label: '#',
      defaultWidth: kProjectTableColId,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'project',
      label: projectLabel,
      defaultWidth: kProjectTableColProject,
      minWidth: 120,
      maxWidth: 500,
    ),
    const TableColumnSchema(
      id: 'customer',
      label: 'Customer',
      defaultWidth: kProjectTableColCustomer,
      minWidth: 100,
      maxWidth: 400,
    ),
    const TableColumnSchema(
      id: 'status',
      label: 'Status',
      defaultWidth: kProjectTableColStatus,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'budget',
      label: 'Budget',
      defaultWidth: kProjectTableColBudget,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'margin',
      label: 'Margin',
      defaultWidth: kProjectTableColMargin,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'profit',
      label: 'Profit',
      defaultWidth: kProjectTableColProfit,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'tasks',
      label: 'Tasks',
      defaultWidth: kProjectTableColTasks,
      minWidth: 80,
      maxWidth: 200,
    ),
    const TableColumnSchema(
      id: 'timeline',
      label: 'Dates',
      defaultWidth: kProjectTableColTimeline,
      minWidth: 100,
      maxWidth: 300,
    ),
    const TableColumnSchema(
      id: 'progress',
      label: 'Progress',
      defaultWidth: kProjectTableColProgress,
      minWidth: 80,
      maxWidth: 250,
    ),
  ];

  void _onColumnSortTap(String columnId) {
    setState(() {
      if (_tableSortColumn == columnId) {
        if (_tableSortAscending) {
          _tableSortAscending = false;
        } else {
          // Third tap clears column sort
          _tableSortColumn = null;
          _tableSortAscending = true;
        }
      } else {
        _tableSortColumn = columnId;
        _tableSortAscending = true;
      }
      _activeSavedViewId = null;
    });
    _persistView();
  }

  Widget _buildBoardView(List<Project> filteredProjects) {
    return KanbanProjectBoardView(
      projects: filteredProjects,
      taskMetricsByProject: _taskMetricsByProject,
      onProjectStatusChanged: (project, newStatus) async {
        if (project.status == newStatus) return;

        // Confirm before moving to a terminal status.
        if (newStatus.isClosed) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Move to ${newStatus.displayName}?'),
              content: Text(
                'Are you sure you want to mark "${project.name}" '
                'as ${newStatus.displayName}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }

        try {
          await ServiceLocator.projectService.updateProject(
            projectId: project.id,
            status: newStatus,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'update project status'),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildTableView(BuildContext context, List<Project> projects) {
    final allSelected =
        projects.isNotEmpty &&
        projects.every((p) => _selectedProjectIds.contains(p.id));

    final headerStyle = TableViewStyles.headerLabelStyle(context);

    // Build resizable/sortable header cells via shared builder
    final columns = _tableColumns(_getSingularTerminology(context));
    final headerCells = buildTableHeaderCells(
      context: context,
      columns: columns,
      widths: {
        for (final c in columns) c.id: _columnWidths[c.id] ?? c.defaultWidth,
      },
      onColumnResize: _handleColumnResize,
      textStyle: headerStyle,
      onSortTap: (column) => _onColumnSortTap(column.id),
      sortedColumnId: _tableSortColumn,
      sortAscending: _tableSortAscending,
    );

    // Interleave column cells with gap spacers
    final headerChildren = <Widget>[
      if (_selectionMode) ...[
        SizedBox(
          width: 40,
          child: Checkbox(
            value: allSelected,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedProjectIds = projects.map((p) => p.id).toSet();
                } else {
                  _selectedProjectIds.clear();
                }
              });
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    ];
    for (int i = 0; i < headerCells.length; i++) {
      if (i > 0) headerChildren.add(const SizedBox(width: kProjectTableColGap));
      headerChildren.add(headerCells[i]);
    }

    return TableLayoutShell(
      minTableWidth: 1450,
      header: TableHeaderRow(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        children: headerChildren,
      ),
      body: ListView.builder(
        itemCount: projects.length + 1, // +1 for "Add project" row
        itemBuilder: (context, index) {
          if (index == projects.length) return _buildAddProjectRow(context);
          final project = projects[index];
          return ProjectTableRow(
            project: project,
            columnWidths: _columnWidths,
            taskMetrics: _isLoadingTaskMetrics
                ? null
                : (_taskMetricsByProject[project.id] ??
                      ProjectTaskMetrics.empty(project.id)),
            financialsFuture: _financialsFutureFor(project),
            customerFuture: _customerFutureFor(project),
            isFavorite: _favoriteProjectIds.contains(project.id),
            onFavoriteToggled: (isFav) => _toggleFavorite(project.id, isFav),
            isSelected: _selectedProjectIds.contains(project.id),
            selectionMode: _selectionMode,
            onSelectionChanged: (selected) =>
                _toggleSelection(project.id, selected),
            onLongPress: () => _enterSelectionMode(project.id),
          );
        },
      ),
    );
  }

  Widget _buildAddProjectRow(BuildContext context) {
    if (!context.read<AuthProvider>().canCreateProjects) {
      return const SizedBox.shrink();
    }
    return InkWell(
      onTap: () =>
          showProjectFormPopup(context, initialCustomerId: _selectedCustomerId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: TableViewStyles.rowDivider(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Text(
              'New ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)}',
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView(List<Project> projects) {
    return ProjectCalendarWidget(
      projects: projects,
      taskMetricsByProject: _taskMetricsByProject,
      onProjectTap: (project) => context.go('/projects/${project.id}'),
      onDateTap: (date) {
        // No-op for now; day tap doesn't navigate
      },
      onAddProjectForDate: context.read<AuthProvider>().canCreateProjects
          ? (date) => showProjectFormPopup(
              context,
              initialCustomerId: _selectedCustomerId,
              initialStartDate: date,
            )
          : null,
    );
  }

  Widget _buildGanttView(List<Project> projects) {
    return ProjectGanttView(
      projects: projects,
      taskMetricsByProject: _taskMetricsByProject,
      onProjectTap: (project) => context.go('/projects/${project.id}'),
    );
  }

  Widget _buildCardView(List<Project> projects) {
    final canCreateProjects = context.read<AuthProvider>().canCreateProjects;

    return EntityCardGrid(
      mobileColumns: 1,
      itemCount: projects.length,
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.paddingOf(context).bottom + 90,
      ),
      itemBuilder: (context, index, _) => ProjectCard(
        project: projects[index],
        forceCompactLayout: true,
        taskMetrics: _isLoadingTaskMetrics
            ? null
            : (_taskMetricsByProject[projects[index].id] ??
                  ProjectTaskMetrics.empty(projects[index].id)),
        customerFuture: _customerFutureFor(projects[index]),
        financialsFuture: _financialsFutureFor(projects[index]),
        tasksFuture: _tasksFutureFor(projects[index]),
        alertsFuture: _alertsFutureFor(projects[index]),
        workspaceUsersFuture: _workspaceUsersFutureFor(
          projects[index].workspaceId,
        ),
        isFavorite: _favoriteProjectIds.contains(projects[index].id),
        onFavoriteToggled: (isFav) =>
            _toggleFavorite(projects[index].id, isFav),
        isSelected: _selectedProjectIds.contains(projects[index].id),
        selectionMode: _selectionMode,
        onSelectionChanged: (selected) =>
            _toggleSelection(projects[index].id, selected),
        onLongPress: () => _enterSelectionMode(projects[index].id),
      ),
      trailingBuilder: canCreateProjects
          ? (context, cardWidth) => EntityCreateCard(
              title: 'Create New ${_getSingularTerminology(context)}',
              subtitle: kIsWeb
                  ? 'Click to start a new ${_getSingularTerminology(context)}'
                  : 'Tap to start a new ${_getSingularTerminology(context)}',
              minHeight: _getCreateCardHeight(cardWidth),
              onTap: () => showProjectFormPopup(
                context,
                initialCustomerId: _selectedCustomerId,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final bool hasFilters =
        _searchQuery.isNotEmpty ||
        _selectedStatus != null ||
        _selectedCustomerId != null ||
        _effectivePMId != null ||
        _selectedSupervisorId != null ||
        _selectedSalespersonId != null ||
        _selectedJobType != null ||
        _selectedPriceType != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon container
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: hasFilters ? 1.0 : _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: hasFilters
                        ? null
                        : LinearGradient(
                            colors: [
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1),
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: hasFilters ? AppColors.surfaceAlt : null,
                    shape: BoxShape.circle,
                    boxShadow: hasFilters
                        ? null
                        : [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                  ),
                  child: Icon(
                    hasFilters ? Icons.search_off : Icons.folder_open_outlined,
                    size: 40,
                    color: hasFilters
                        ? AppColors.textTertiary
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          Text(
            hasFilters
                ? 'No ${context.watch<WorkspaceProvider>().projectTerminology.toLowerCase()} found'
                : 'No ${context.watch<WorkspaceProvider>().projectTerminology.toLowerCase()} yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilters
                ? 'Try adjusting your filters or search query'
                : 'Create your first ${_getSingularTerminology(context)} to get started',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          if (hasFilters) ...[
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _selectedStatus = null;
                  _selectedCustomerId = null;
                  _selectedProjectManagerId = null;
                  _pmExplicitlySet = false;
                  _selectedSupervisorId = null;
                  _selectedSalespersonId = null;
                  _selectedJobType = null;
                  _selectedPriceType = null;
                  _selectedSort = ProjectSortOption.recent;
                  _tableSortColumn = null;
                  _tableSortAscending = true;
                  _activeSavedViewId = null;
                });
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ] else ...[
            AnimatedEmptyStateCta(
              animation: _pulseAnimation,
              label: 'Create Your First ${_getSingularTerminology(context)}',
              onTap: () {
                showProjectFormPopup(
                  context,
                  initialCustomerId: _selectedCustomerId,
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              kIsWeb
                  ? 'Click "Create Your First ${_getSingularTerminology(context)}" to begin'
                  : 'Tap "Create Your First ${_getSingularTerminology(context)}" to begin',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleSelection(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedProjectIds.add(id);
      } else {
        _selectedProjectIds.remove(id);
      }
    });
  }

  void _enterSelectionMode(String projectId) {
    setState(() {
      _selectionMode = true;
      _selectedProjectIds = {projectId};
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedProjectIds.clear();
    });
  }

  Future<void> _executeBulkAction(
    Future<void> Function() action,
    String successMsg,
  ) async {
    try {
      await action();
      if (mounted) {
        _exitSelectionMode();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildBulkActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedProjectIds.length} selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: _exitSelectionMode, child: const Text('Clear')),
          const Spacer(),

          // Status dropdown
          PopupMenuButton<ProjectStatus>(
            tooltip: 'Change Status',
            child: Chip(
              avatar: const Icon(Icons.flag_outlined, size: 16),
              label: const Text('Status'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            itemBuilder: (context) => ProjectStatus.values.map((status) {
              return PopupMenuItem(
                value: status,
                child: Text(status.displayName),
              );
            }).toList(),
            onSelected: (status) {
              final count = _selectedProjectIds.length;
              _executeBulkAction(
                () => ServiceLocator.projectService.bulkUpdateStatus(
                  _selectedProjectIds.toList(),
                  status,
                ),
                'Updated $count projects to ${status.name}',
              );
            },
          ),
          const SizedBox(width: 8),

          // Reassign PM
          ActionChip(
            avatar: const Icon(Icons.person_outline, size: 16),
            label: const Text('Reassign PM'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showPmPickerDialog(context),
          ),
          const SizedBox(width: 8),

          // Delete
          ActionChip(
            avatar: const Icon(
              Icons.delete_outline,
              size: 16,
              color: AppColors.error,
            ),
            label: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showBulkDeleteDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showPmPickerDialog(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final selectedIds = _selectedProjectIds.toList();
    final count = selectedIds.length;

    final chosenUserId = await showDialog<String>(
      context: context,
      builder: (context) => _PmPickerDialog(workspaceId: workspaceId),
    );

    if (chosenUserId != null && mounted) {
      _executeBulkAction(
        () => ServiceLocator.projectService.bulkReassignPM(
          selectedIds,
          chosenUserId,
        ),
        'Reassigned PM for $count projects',
      );
    }
  }

  Future<void> _showBulkDeleteDialog(BuildContext context) async {
    final count = _selectedProjectIds.length;
    final ids = _selectedProjectIds.toList();
    final projectTerminology = context
        .read<WorkspaceProvider>()
        .projectTerminology;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $projectTerminology'),
        content: Text(
          'Are you sure you want to delete $count project${count == 1 ? '' : 's'}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _executeBulkAction(
        () => ServiceLocator.projectService.bulkDelete(ids),
        'Deleted $count projects',
      );
    }
  }

  String _getSingularTerminology(BuildContext context) {
    final plural = context.watch<WorkspaceProvider>().projectTerminology;
    // Simple singularization: remove trailing 's' if present
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  double _getCreateCardHeight(double cardWidth) {
    // Mirror the perceived height of ProjectCard's compact layout across breakpoints.
    if (cardWidth < 280) return 300;
    if (cardWidth < 340) return 440;
    return 540;
  }
}

class _SavedProjectView {
  final String id;
  final String name;
  final String searchQuery;
  final ProjectStatus? status;
  final String? customerId;
  final String? projectManagerId;
  final String? supervisorId;
  final String? salespersonId;
  final JobType? jobType;
  final PriceType? priceType;
  final ProjectSortOption sortOption;
  final String? tableSortColumn;
  final bool tableSortAscending;
  final DateTime createdAt;

  const _SavedProjectView({
    required this.id,
    required this.name,
    required this.searchQuery,
    required this.status,
    required this.customerId,
    required this.projectManagerId,
    required this.supervisorId,
    required this.salespersonId,
    required this.jobType,
    required this.priceType,
    required this.sortOption,
    required this.tableSortColumn,
    required this.tableSortAscending,
    required this.createdAt,
  });

  factory _SavedProjectView.fromMap(Map<String, dynamic> map) {
    final statusName = map['status'] as String?;
    final sortName = map['sort'] as String?;
    final jobTypeName = map['job_type'] as String?;
    final priceTypeName = map['price_type'] as String?;

    ProjectStatus? parsedStatus;
    if (statusName != null && statusName.isNotEmpty) {
      for (final value in ProjectStatus.values) {
        if (value.name == statusName) {
          parsedStatus = value;
          break;
        }
      }
    }

    JobType? parsedJobType;
    if (jobTypeName != null && jobTypeName.isNotEmpty) {
      for (final value in JobType.values) {
        if (value.name == jobTypeName) {
          parsedJobType = value;
          break;
        }
      }
    }

    PriceType? parsedPriceType;
    if (priceTypeName != null && priceTypeName.isNotEmpty) {
      for (final value in PriceType.values) {
        if (value.name == priceTypeName) {
          parsedPriceType = value;
          break;
        }
      }
    }

    var parsedSort = ProjectSortOption.recent;
    if (sortName != null && sortName.isNotEmpty) {
      for (final value in ProjectSortOption.values) {
        if (value.name == sortName) {
          parsedSort = value;
          break;
        }
      }
    }

    return _SavedProjectView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      searchQuery: map['search_query'] as String? ?? '',
      status: parsedStatus,
      customerId: map['customer_id'] as String?,
      projectManagerId: map['project_manager_id'] as String?,
      supervisorId: map['supervisor_id'] as String?,
      salespersonId: map['salesperson_id'] as String?,
      jobType: parsedJobType,
      priceType: parsedPriceType,
      sortOption: parsedSort,
      tableSortColumn: map['table_sort_column'] as String?,
      tableSortAscending: map['table_sort_ascending'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'search_query': searchQuery,
      'status': status?.name,
      'customer_id': customerId,
      'project_manager_id': projectManagerId,
      'supervisor_id': supervisorId,
      'salesperson_id': salespersonId,
      'job_type': jobType?.name,
      'price_type': priceType?.name,
      'sort': sortOption.name,
      'table_sort_column': tableSortColumn,
      'table_sort_ascending': tableSortAscending,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Dialog for picking a workspace member to assign as PM
class _PmPickerDialog extends StatefulWidget {
  final String workspaceId;

  const _PmPickerDialog({required this.workspaceId});

  @override
  State<_PmPickerDialog> createState() => _PmPickerDialogState();
}

class _PmPickerDialogState extends State<_PmPickerDialog> {
  String? _selectedUserId;
  List<WorkspaceMember> _members = [];
  Map<String, AppUser> _userCache = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await ServiceLocator.workspaceMemberService
        .getWorkspaceMembers(widget.workspaceId)
        .first;

    final userFutures = members.map(
      (m) => ServiceLocator.userService.getUserById(m.userId),
    );
    final users = await Future.wait(userFutures);

    final cache = <String, AppUser>{};
    for (int i = 0; i < members.length; i++) {
      if (users[i] != null) {
        cache[members[i].userId] = users[i]!;
      }
    }

    if (mounted) {
      setState(() {
        _members = members;
        _userCache = cache;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    return AlertDialog(
      title: Text('Reassign $singular Manager'),
      content: SizedBox(
        width: 360,
        child: _isLoading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : _members.isEmpty
            ? const Text('No workspace members found.')
            : SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: _selectedUserId,
                  onChanged: (value) => setState(() => _selectedUserId = value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _members.map((member) {
                      final user = _userCache[member.userId];
                      final name = user?.displayName ?? member.userId;
                      return RadioListTile<String>(
                        title: Text(name),
                        subtitle: Text(member.displayRoleName),
                        value: member.userId,
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selectedUserId != null
              ? () => Navigator.pop(context, _selectedUserId)
              : null,
          child: const Text('Assign'),
        ),
      ],
    );
  }
}

/// Centered filter dialog for projects — replaces the old bottom sheet.
class _ProjectFilterDialog extends StatefulWidget {
  final ProjectStatus? selectedStatus;
  final String? selectedCustomerId;
  final String? selectedProjectManagerId;
  final String? selectedSupervisorId;
  final String? selectedSalespersonId;
  final JobType? selectedJobType;
  final PriceType? selectedPriceType;
  final Set<String> projectManagerIds;
  final Set<String> supervisorIds;
  final List<_SavedProjectView> savedViews;
  final String? activeSavedViewId;
  final void Function(
    ProjectStatus? status,
    String? customerId,
    String? pmId,
    String? supervisorId,
    String? salespersonId,
    JobType? jobType,
    PriceType? priceType,
  )
  onApply;
  final ValueChanged<String> onApplySavedView;
  final void Function(
    ProjectStatus? status,
    String? customerId,
    String? pmId,
    String? supervisorId,
    String? salespersonId,
    JobType? jobType,
    PriceType? priceType,
  )
  onSaveView;
  final ValueChanged<String> onDeleteSavedView;
  final VoidCallback onResetToDefaults;

  const _ProjectFilterDialog({
    required this.selectedStatus,
    required this.selectedCustomerId,
    required this.selectedProjectManagerId,
    required this.selectedSupervisorId,
    required this.selectedSalespersonId,
    required this.selectedJobType,
    required this.selectedPriceType,
    required this.projectManagerIds,
    required this.supervisorIds,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onApplySavedView,
    required this.onSaveView,
    required this.onDeleteSavedView,
    required this.onResetToDefaults,
  });

  @override
  State<_ProjectFilterDialog> createState() => _ProjectFilterDialogState();
}

class _ProjectFilterDialogState extends State<_ProjectFilterDialog> {
  late ProjectStatus? _status;
  late String? _customerId;
  late String? _pmId;
  late String? _supervisorId;
  late String? _salespersonId;
  late JobType? _jobType;
  late PriceType? _priceType;

  bool _isLoadingUsers = false;
  List<AppUser> _workspaceUsers = [];

  bool get _hasAnyFilter =>
      _status != null ||
      _customerId != null ||
      _pmId != null ||
      _supervisorId != null ||
      _salespersonId != null ||
      _jobType != null ||
      _priceType != null;

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
    _customerId = widget.selectedCustomerId;
    _pmId = widget.selectedProjectManagerId;
    _supervisorId = widget.selectedSupervisorId;
    _salespersonId = widget.selectedSalespersonId;
    _jobType = widget.selectedJobType;
    _priceType = widget.selectedPriceType;
    _loadWorkspaceUsers();
  }

  Future<void> _loadWorkspaceUsers() async {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null) return;

    setState(() => _isLoadingUsers = true);
    try {
      final members = await ServiceLocator.workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;
      final userFutures = members.map(
        (m) => ServiceLocator.userService.getUserById(m.userId),
      );
      final users = await Future.wait(userFutures);

      final existingIds = <String>{};
      final loaded = <AppUser>[];
      for (final user in users) {
        if (user != null && existingIds.add(user.id)) {
          loaded.add(user);
        }
      }
      loaded.sort((a, b) {
        final aName = (a.displayName ?? a.email).toLowerCase();
        final bName = (b.displayName ?? b.email).toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _workspaceUsers = loaded;
        _isLoadingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingUsers = false);
    }
  }

  String? _userDisplayName(String userId) {
    final user = _workspaceUsers.where((u) => u.id == userId).firstOrNull;
    if (user == null) return null;
    return user.displayName ?? user.email;
  }

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_hasAnyFilter)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _status = null;
                          _customerId = null;
                          _pmId = null;
                          _supervisorId = null;
                          _salespersonId = null;
                          _jobType = null;
                          _priceType = null;
                        });
                      },
                      child: const Text('Clear all'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Content ──
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                shrinkWrap: true,
                children: [
                  // ── Status section ──
                  _buildSection(
                    icon: Icons.flag_outlined,
                    title: 'Status',
                    subtitle: _status?.displayName ?? 'All',
                    isActive: _status != null,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _status == null,
                        onSelected: (_) => setState(() => _status = null),
                      ),
                      ...ProjectStatus.values.map((status) {
                        return ChoiceChip(
                          label: Text(status.displayName),
                          avatar: Icon(
                            Icons.circle,
                            size: 8,
                            color: ProjectStatusTheme.color(status),
                          ),
                          selected: _status == status,
                          onSelected: (_) => setState(() => _status = status),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Customer section ──
                  if (workspaceId != null) ...[
                    _buildCustomerSection(workspaceId),
                    const SizedBox(height: 12),
                  ],

                  // ── Project Manager section ──
                  _buildUserSection(
                    icon: Icons.manage_accounts_outlined,
                    title: '$singular Manager',
                    selectedId: _pmId,
                    onSelected: (id) => setState(() => _pmId = id),
                    filterToIds: widget.projectManagerIds,
                  ),
                  const SizedBox(height: 12),

                  // ── Supervisor section ──
                  _buildUserSection(
                    icon: Icons.supervisor_account_outlined,
                    title: 'Supervisor',
                    selectedId: _supervisorId,
                    onSelected: (id) => setState(() => _supervisorId = id),
                    filterToIds: widget.supervisorIds,
                  ),
                  const SizedBox(height: 12),

                  // ── Salesperson section ──
                  _buildUserSection(
                    icon: Icons.badge_outlined,
                    title: 'Sales Person',
                    selectedId: _salespersonId,
                    onSelected: (id) => setState(() => _salespersonId = id),
                  ),
                  const SizedBox(height: 12),

                  // ── Job type section ──
                  _buildSection(
                    icon: Icons.handyman_outlined,
                    title: 'Job Type',
                    subtitle: _jobType?.displayName ?? 'All',
                    isActive: _jobType != null,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _jobType == null,
                        onSelected: (_) => setState(() => _jobType = null),
                      ),
                      ...JobType.values.map((type) {
                        return ChoiceChip(
                          label: Text(type.displayName),
                          avatar: Icon(type.icon, size: 14, color: type.color),
                          selected: _jobType == type,
                          onSelected: (_) => setState(() => _jobType = type),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Price type section ──
                  _buildSection(
                    icon: Icons.payments_outlined,
                    title: 'Price Type',
                    subtitle: _priceType?.displayName ?? 'All',
                    isActive: _priceType != null,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _priceType == null,
                        onSelected: (_) => setState(() => _priceType = null),
                      ),
                      ...PriceType.values.map((type) {
                        return ChoiceChip(
                          label: Text(type.displayName),
                          selected: _priceType == type,
                          onSelected: (_) => setState(() => _priceType = type),
                        );
                      }),
                    ],
                  ),

                  // ── Saved views ──
                  if (widget.savedViews.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmark_border,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Saved Views',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...widget.savedViews.map((view) {
                      final isActive = view.id == widget.activeSavedViewId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isActive ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        title: Text(
                          view.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isActive ? AppColors.primary : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => widget.onDeleteSavedView(view.id),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: AppColors.textTertiary,
                        ),
                        onTap: () => widget.onApplySavedView(view.id),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Footer ──
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onSaveView(
                      _status,
                      _customerId,
                      _pmId,
                      _supervisorId,
                      _salespersonId,
                      _jobType,
                      _priceType,
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save View'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: widget.onResetToDefaults,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      widget.onApply(
                        _status,
                        _customerId,
                        _pmId,
                        _supervisorId,
                        _salespersonId,
                        _jobType,
                        _priceType,
                      );
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: isActive
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
            color: isActive ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(spacing: 8, runSpacing: 4, children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection(String workspaceId) {
    return Container(
      decoration: BoxDecoration(
        color: _customerId != null
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: _customerId != null
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            Icons.people_outline,
            size: 20,
            color: _customerId != null
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          title: const Text(
            'Customer',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            _customerId != null ? 'Selected' : 'All',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: StreamBuilder<List<Customer>>(
                stream: ServiceLocator.customerService.getCustomers(
                  workspaceId,
                ),
                builder: (context, snapshot) {
                  final customers = snapshot.data ?? [];
                  return SearchableFilterChips(
                    items: customers
                        // displayName falls back to companyName — `name` is
                        // the primary contact and is blank for company
                        // customers with no contact records.
                        .map((c) => (id: c.id, label: c.displayName))
                        .toList(),
                    selectedId: _customerId,
                    onAllSelected: () => setState(() => _customerId = null),
                    onItemSelected: (id) => setState(() => _customerId = id),
                    searchHint: 'Search customers...',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSection({
    required IconData icon,
    required String title,
    required String? selectedId,
    required ValueChanged<String?> onSelected,
    Set<String>? filterToIds,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: selectedId != null
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(
          color: selectedId != null
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
            color: selectedId != null
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            selectedId != null
                ? (_userDisplayName(selectedId) ?? 'Selected')
                : 'All',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _isLoadingUsers
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : SearchableFilterChips(
                      items: _workspaceUsers
                          .where(
                            (user) =>
                                filterToIds == null ||
                                filterToIds.contains(user.id),
                          )
                          .map(
                            (u) => (id: u.id, label: u.displayName ?? u.email),
                          )
                          .toList(),
                      selectedId: selectedId,
                      onAllSelected: () => onSelected(null),
                      onItemSelected: (id) => onSelected(id),
                      searchHint: 'Search...',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persisted screen-wide UI state for the project list. Mirrors a JSON blob
/// stored under [scopeKey] inside `user_preferences.preferences['views']`.
/// One row per user, debounced through [SupabaseViewPrefsService].
class _ProjectsListViewPrefs {
  static const scopeKey = 'projects.list.v1';

  final String searchQuery;
  final ProjectStatus? status;
  final String? customerId;
  final String? projectManagerId;
  final bool pmExplicitlySet;
  final String? supervisorId;
  final String? salespersonId;
  final JobType? jobType;
  final PriceType? priceType;
  final ProjectSortOption sort;
  final String? tableSortColumn;
  final bool tableSortAscending;
  final ProjectViewType viewType;
  final Map<String, double> columnWidths;
  final String? activeSavedViewId;

  const _ProjectsListViewPrefs({
    required this.searchQuery,
    required this.status,
    required this.customerId,
    required this.projectManagerId,
    required this.pmExplicitlySet,
    required this.supervisorId,
    required this.salespersonId,
    required this.jobType,
    required this.priceType,
    required this.sort,
    required this.tableSortColumn,
    required this.tableSortAscending,
    required this.viewType,
    required this.columnWidths,
    required this.activeSavedViewId,
  });

  factory _ProjectsListViewPrefs.fromJson(Map<String, dynamic> map) {
    ProjectStatus? parsedStatus;
    final statusName = map['status'] as String?;
    if (statusName != null && statusName.isNotEmpty) {
      for (final v in ProjectStatus.values) {
        if (v.name == statusName) {
          parsedStatus = v;
          break;
        }
      }
    }

    JobType? parsedJobType;
    final jobTypeName = map['job_type'] as String?;
    if (jobTypeName != null && jobTypeName.isNotEmpty) {
      for (final v in JobType.values) {
        if (v.name == jobTypeName) {
          parsedJobType = v;
          break;
        }
      }
    }

    PriceType? parsedPriceType;
    final priceTypeName = map['price_type'] as String?;
    if (priceTypeName != null && priceTypeName.isNotEmpty) {
      for (final v in PriceType.values) {
        if (v.name == priceTypeName) {
          parsedPriceType = v;
          break;
        }
      }
    }

    var parsedSort = ProjectSortOption.recent;
    final sortName = map['sort'] as String?;
    if (sortName != null && sortName.isNotEmpty) {
      for (final v in ProjectSortOption.values) {
        if (v.name == sortName) {
          parsedSort = v;
          break;
        }
      }
    }

    var parsedView = ProjectViewType.card;
    final viewName = map['view_type'] as String?;
    if (viewName != null && viewName.isNotEmpty) {
      for (final v in ProjectViewType.values) {
        if (v.name == viewName) {
          parsedView = v;
          break;
        }
      }
    }

    final widthsRaw = map['column_widths'];
    final widths = <String, double>{};
    if (widthsRaw is Map) {
      widthsRaw.forEach((k, v) {
        if (k is String && v is num) widths[k] = v.toDouble();
      });
    }

    return _ProjectsListViewPrefs(
      searchQuery: map['search_query'] as String? ?? '',
      status: parsedStatus,
      customerId: map['customer_id'] as String?,
      projectManagerId: map['project_manager_id'] as String?,
      pmExplicitlySet: map['pm_explicitly_set'] as bool? ?? false,
      supervisorId: map['supervisor_id'] as String?,
      salespersonId: map['salesperson_id'] as String?,
      jobType: parsedJobType,
      priceType: parsedPriceType,
      sort: parsedSort,
      tableSortColumn: map['table_sort_column'] as String?,
      tableSortAscending: map['table_sort_ascending'] as bool? ?? true,
      viewType: parsedView,
      columnWidths: widths,
      activeSavedViewId: map['active_saved_view_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'search_query': searchQuery,
      'status': status?.name,
      'customer_id': customerId,
      'project_manager_id': projectManagerId,
      'pm_explicitly_set': pmExplicitlySet,
      'supervisor_id': supervisorId,
      'salesperson_id': salespersonId,
      'job_type': jobType?.name,
      'price_type': priceType?.name,
      'sort': sort.name,
      'table_sort_column': tableSortColumn,
      'table_sort_ascending': tableSortAscending,
      'view_type': viewType.name,
      'column_widths': columnWidths,
      'active_saved_view_id': activeSavedViewId,
    };
  }
}
