import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/service_locator.dart';
import '../../widgets/common/entity_tab_bar.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/tasks/grouped_task_list_view.dart';
import '../../widgets/tasks/kanban_board_view.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/tasks/team_availability_view.dart';
import '../../widgets/files/project_files_screen.dart';
import '../../widgets/timeline/monthly_calendar_widget.dart';
import '../../widgets/timeline/day_tasks_popup.dart';
import '../../widgets/task_form_popup.dart';

import 'tabs/project_messages_tab.dart';
import 'tabs/project_notes_tab.dart';
import 'tabs/project_inventory_tab.dart';
import 'tabs/project_overview_tab.dart';
import 'tabs/project_info_tab.dart';
import '../../widgets/projects/project_header.dart';
import 'project_schedule_screen.dart';
import '../time_tracking/admin_timesheet_dashboard.dart';
import '../time_tracking/clock_in_out_screen.dart';
import '../time_tracking/daily_timesheet_screen.dart';
import '../time_tracking/employee_time_table_screen.dart';
import '../time_tracking/time_approval_screen.dart';
import '../time_tracking/weekly_timesheet_screen.dart';
import '../time_tracking/widgets/time_tracking_view_bar.dart';
import '../plans/plans_list_screen.dart';
import 'budget_view_screen.dart';
import '../../widgets/task_scheduler_wizard.dart';
import '../../widgets/ai_task_generator_wizard.dart';

import '../../models/property.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/ai/ai_project_setup_wizard.dart';
import '../../widgets/budget_document_wizard.dart';
import '../../widgets/common/searchable_filter_chips.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final String? initialTab;
  final String? initialTaskId;
  final String? initialTaskView;
  final String? initialTaskMetric;
  final bool showAiSetup;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.initialTab,
    this.initialTaskId,
    this.initialTaskView,
    this.initialTaskMetric,
    this.showAiSetup = false,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  Set<String> _loadedTabIds = const <String>{};
  String _taskViewType =
      'cards'; // View type for Tasks tab: 'cards', 'list', 'gantt', 'month'
  bool _taskHideDone = true;
  bool _taskMyTasksOnly = false;
  String _taskSearchQuery = '';

  // Task filter state
  String? _taskPropertyFilterId;
  String? _taskPriorityFilter;
  String? _taskAssigneeFilterId;
  DateTime? _taskDueDateStart;
  DateTime? _taskDueDateEnd;
  List<String> _enabledTabs = []; // Currently enabled tabs
  String _projectTerminology = 'Projects';
  bool _aiSetupShown = false;
  bool _initialTaskOpened = false;
  StreamSubscription<Map<String, dynamic>?>? _workspaceSubscription;
  String? _subscribedWorkspaceId;

  // Cached project future – must not be recreated on setState
  Future<Project?>? _projectFuture;

  // Guards the one-shot active-workspace adoption for cross-workspace links.
  bool _workspaceAdoptionTriggered = false;

  // True once a deep-linked ?tab= has been applied (or the tab selection has
  // changed for any other reason). Until then the requested tab outranks the
  // sticky previous selection when the tab controller is rebuilt — on cold
  // load the first controller is built from a provisional tab list that may
  // not contain the requested tab yet (workspace-gated tabs arrive async),
  // and the rebuild used to fall back to "previously selected" = Overview.
  bool _initialTabConsumed = false;

  // Tracks which time tracking view is shown inside the Time Tracking tab,
  // so toolbar icon taps swap the inner view instead of leaving the project.
  TimeTrackingView _timeTrackingView = TimeTrackingView.clock;

  // GlobalKey for the Files tab widget — used to call openDocumentCreate()
  // from the budget tab without rebuilding the widget.
  final _filesScreenKey = GlobalKey<ProjectFilesScreenState>();

  // Pending budget → create doc handoff when the Files tab hasn't been
  // lazily loaded yet at the time the budget callback fires.
  BudgetDocumentWizardResult? _pendingDocumentCreate;
  // Tab index the user was on when they triggered document creation, so the
  // Create Document screen's Back arrow returns them there (e.g. Financials)
  // instead of stranding them on the Files tab.
  int? _documentCreateOriginTabIndex;

  // All available tabs with their display names and icons
  // Note: 'documents' and 'forms' have been merged into 'files'.
  static const _allTabDefinitions = {
    'overview': {'name': 'Overview', 'icon': Icons.dashboard},
    'info': {'name': 'Properties', 'icon': Icons.home_work_outlined},
    'tasks': {'name': 'Tasks', 'icon': Icons.task},
    'budget': {'name': 'Financials', 'icon': Icons.attach_money},
    'inventory': {'name': 'Inventory', 'icon': Icons.warehouse_outlined},
    'messages': {'name': 'Messages', 'icon': Icons.message},
    'time-tracking': {'name': 'Time', 'icon': Icons.access_time},
    'plans': {'name': 'Plans', 'icon': Icons.map},
    'files': {'name': 'Files', 'icon': Icons.attach_file},
    'notes': {'name': 'Notes', 'icon': Icons.sticky_note_2},
    // 'daily-logs', 'inspections', 'punch-list', 'warranties' moved
    // into Files (rendered as virtual-folder sections under Content).
  };

  // Ordered list of all tabs.
  // 'documents' and 'forms' removed — they are now sections within 'files'.
  static const _allTabsOrdered = [
    'overview',
    'info',
    'tasks',
    // Financials hosts the Budget / Purchase Orders / Bills/Expenses /
    // Invoices / etc. sub-views via its in-tab dropdown selector.
    // Purchase Orders used to be a top-level tab but is now a sub-view
    // of Financials, ordered between Budget and Bills/Expenses.
    'budget',
    'inventory',
    'messages',
    'time-tracking',
    'plans',
    'files',
    'notes',
  ];

  @override
  void initState() {
    super.initState();
    _projectFuture = ServiceLocator.projectService.getProject(widget.projectId);
    final initialTaskView = _normalizedInitialTaskView;
    if (initialTaskView != null) {
      _taskViewType = initialTaskView;
    }
    _loadTaskViewPreference();
    ServiceLocator.userPreferencesService.recordProjectView(widget.projectId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    _initializeTabs();
  }

  @override
  void didUpdateWidget(covariant ProjectDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.projectId != oldWidget.projectId) {
      _projectFuture = ServiceLocator.projectService.getProject(
        widget.projectId,
      );
      _workspaceAdoptionTriggered = false;
    }

    final previousTab = _normalizeTabId(oldWidget.initialTab);
    final requestedTab = _normalizeTabId(widget.initialTab);
    if (requestedTab == previousTab) {
      return;
    }

    final controller = _tabController;
    if (controller == null || requestedTab == null || requestedTab.isEmpty) {
      return;
    }

    final targetIndex = _enabledTabs.indexOf(requestedTab);
    if (targetIndex >= 0 && controller.index != targetIndex) {
      _activateTab(targetIndex);
    }
  }

  void _initializeTabs() {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      _workspaceSubscription?.cancel();
      _workspaceSubscription = null;
      _subscribedWorkspaceId = null;
      _setupTabController(List.from(_allTabsOrdered));
      return;
    }

    if (_subscribedWorkspaceId == workspaceId) return;

    _workspaceSubscription?.cancel();
    _subscribedWorkspaceId = workspaceId;
    _workspaceSubscription = ServiceLocator.workspaceService
        .getWorkspace(workspaceId)
        .listen((data) {
          if (!mounted) return;
          final term = (data?['projectTerminology'] as String?) ?? 'Projects';
          if (term != _projectTerminology) {
            setState(() => _projectTerminology = term);
          }
          _setupTabController(_resolveEnabledTabs(data));
        });
  }

  void _maybeAdoptProjectWorkspace(Project project) {
    if (_workspaceAdoptionTriggered) return;
    final auth = context.read<AuthProvider>();
    final activeWorkspaceId = auth.appUser?.currentWorkspaceId;
    if (activeWorkspaceId == null ||
        activeWorkspaceId == project.workspaceId) {
      return;
    }
    _workspaceAdoptionTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await auth.switchWorkspace(project.workspaceId);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Switched workspace to view "${project.name}"',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (_) {
        // Switch failed (e.g. membership revoked mid-session) — leave the
        // active workspace alone; RLS keeps the data gated either way.
      }
    });
  }

  List<String> _resolveEnabledTabs(Map<String, dynamic>? data) {
    final enabledProjectTabs = data?['enabledProjectTabs'] as List<dynamic>?;
    if (enabledProjectTabs == null || enabledProjectTabs.isEmpty) {
      return List.from(_allTabsOrdered);
    }

    final workspaceEnabled = enabledProjectTabs
        .map((tab) => _normalizeTabId('$tab'))
        .whereType<String>()
        .toSet();
    final resolved = _allTabsOrdered
        .where((tab) => workspaceEnabled.contains(tab))
        .toList();
    return resolved.isEmpty ? List.from(_allTabsOrdered) : resolved;
  }

  String? _normalizeTabId(String? tabId) {
    final normalized = tabId?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (normalized == 'financials') {
      return 'budget';
    }
    // The tab is labeled "Time" in the UI; accept the obvious shorthand
    // (and underscore variant) for hand-typed or generated deep links.
    if (normalized == 'time' || normalized == 'time_tracking') {
      return 'time-tracking';
    }
    // Daily Logs / Inspections / Punch List / Warranties moved into
    // the Files tab as virtual-folder sections. Redirect any stored
    // route or workspace setting referencing the old tab IDs.
    if (normalized == 'daily-logs' ||
        normalized == 'inspections' ||
        normalized == 'specifications' ||
        normalized == 'punch-list' ||
        normalized == 'warranties') {
      return 'files';
    }
    if (normalized == 'properties' || normalized == 'property') {
      return 'info';
    }
    // backward-compat: old 'materials' and 'assets' tabs are now 'inventory'
    if (normalized == 'materials' || normalized == 'assets') {
      return 'inventory';
    }
    // backward-compat: 'work-orders' and 'subcontracts' merged into
    // 'purchase-orders', which itself has now been folded into the
    // Financials/Budget tab as a sub-view selectable from its dropdown.
    if (normalized == 'work-orders' ||
        normalized == 'work_orders' ||
        normalized == 'subcontracts' ||
        normalized == 'purchase-orders' ||
        normalized == 'purchase_orders') {
      return 'budget';
    }
    // Selections moved into the Financials dropdown.
    if (normalized == 'selections') {
      return 'budget';
    }
    return normalized;
  }

  /// True when the current URL was asking for the Purchase Orders sub-view
  /// of the Financials tab (either directly or via legacy aliases).
  bool _requestedPurchaseOrdersSubView() {
    final raw = widget.initialTab?.trim().toLowerCase();
    return raw == 'purchase-orders' ||
        raw == 'purchase_orders' ||
        raw == 'work-orders' ||
        raw == 'work_orders' ||
        raw == 'subcontracts';
  }

  /// True when the current URL was asking for the Selections sub-view
  /// of the Financials tab.
  bool _requestedSelectionsSubView() {
    final raw = widget.initialTab?.trim().toLowerCase();
    return raw == 'selections';
  }

  void _setupTabController(List<String> enabledTabs) {
    if (_listEquals(_enabledTabs, enabledTabs) &&
        _tabController?.length == enabledTabs.length) {
      return;
    }

    final previousTabs = List<String>.from(_enabledTabs);
    final previousIndex = _tabController?.index ?? 0;
    final previousSelectedTab =
        previousIndex >= 0 && previousIndex < previousTabs.length
        ? previousTabs[previousIndex]
        : null;

    _tabController?.removeListener(_handleTabChanged);
    _tabController?.dispose();
    _enabledTabs = enabledTabs;

    final initialIndex = _determineInitialTabIndex(
      enabledTabs,
      previousSelectedTab: previousSelectedTab,
    );

    _tabController = TabController(
      length: _enabledTabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController!.addListener(_handleTabChanged);
    _loadedTabIds = {
      ..._loadedTabIds.where(enabledTabs.contains),
      if (enabledTabs.isNotEmpty) enabledTabs[initialIndex],
    };

    if (mounted) {
      setState(() {});
    }
    _tryOpenInitialTask();
  }

  int _determineInitialTabIndex(
    List<String> enabledTabs, {
    String? previousSelectedTab,
  }) {
    if (enabledTabs.isEmpty) return 0;

    // A pending deep-linked tab wins over the sticky previous selection —
    // see _initialTabConsumed.
    if (!_initialTabConsumed) {
      final pendingTab = _normalizeTabId(widget.initialTab);
      if (pendingTab != null && pendingTab.isNotEmpty) {
        final pendingIndex = enabledTabs.indexOf(pendingTab);
        if (pendingIndex >= 0) {
          _initialTabConsumed = true;
          return pendingIndex;
        }
      }
    }

    if (previousSelectedTab != null) {
      final previousTabIndex = enabledTabs.indexOf(previousSelectedTab);
      if (previousTabIndex >= 0) {
        return previousTabIndex;
      }
    }

    if (widget.initialTaskId != null && widget.initialTaskId!.isNotEmpty) {
      final taskTabIndex = enabledTabs.indexOf('tasks');
      if (taskTabIndex >= 0) {
        return taskTabIndex;
      }
    }

    final requestedTab = _normalizeTabId(widget.initialTab);
    if (requestedTab != null && requestedTab.isNotEmpty) {
      final requestedIndex = enabledTabs.indexOf(requestedTab);
      if (requestedIndex >= 0) {
        return requestedIndex;
      }
    }

    return 0;
  }

  void _handleTabChanged() {
    final controller = _tabController;
    if (!mounted || controller == null) return;
    // Any tab change (user tap or programmatic activation) retires the
    // deep-linked initial tab — a later controller rebuild must not yank
    // the user back to it.
    _initialTabConsumed = true;
    _loadTabAtIndex(controller.index);
    if (controller.indexIsChanging) return;
    // TabSwitchNotification is dispatched by EntityTabBar, which listens to
    // the same controller.
    _tryOpenInitialTask();

    // Handle pending budget → create doc handoff: the Files tab widget was not
    // yet built when the budget callback fired, so we deferred the call here.
    if (_pendingDocumentCreate != null &&
        _enabledTabs[controller.index] == 'files') {
      final result = _pendingDocumentCreate!;
      _pendingDocumentCreate = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _filesScreenKey.currentState?.openDocumentCreate(
          result,
          onClose: _handleDocumentCreateClosed,
        );
      });
    }
  }

  /// Returns the user to whichever tab they were on when they triggered
  /// document creation (e.g. Financials), so the embedded Create Document
  /// Back arrow doesn't strand them on the Files tab.
  void _handleDocumentCreateClosed() {
    final originIndex = _documentCreateOriginTabIndex;
    _documentCreateOriginTabIndex = null;
    if (originIndex == null) return;
    if (originIndex < 0 || originIndex >= _enabledTabs.length) return;
    _activateTab(originIndex);
  }

  void _loadTabAtIndex(int index) {
    if (index < 0 || index >= _enabledTabs.length) return;
    final tabId = _enabledTabs[index];
    if (_loadedTabIds.contains(tabId)) return;
    setState(() {
      _loadedTabIds = {..._loadedTabIds, tabId};
    });
  }

  void _activateTab(int index, {bool updateRoute = false}) {
    if (index < 0 || index >= _enabledTabs.length) return;
    _loadTabAtIndex(index);
    _tabController?.animateTo(index);
    if (updateRoute) {
      final tabId = _enabledTabs[index];
      final routeTabId = tabId == 'budget' ? 'financials' : tabId;
      context.go('/projects/${widget.projectId}?tab=$routeTabId');
    }
  }

  void _tryOpenInitialTask() {
    final taskId = widget.initialTaskId;
    if (_initialTaskOpened || taskId == null || taskId.isEmpty || !mounted) {
      return;
    }
    final taskTabIndex = _enabledTabs.indexOf('tasks');
    if (taskTabIndex < 0 || _tabController == null) return;
    if (_tabController!.index != taskTabIndex) return;

    _initialTaskOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTaskFormPopup(context, projectId: widget.projectId, taskId: taskId);
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const String _taskViewPrefKey = 'project_task_view_type';
  static const Set<String> _supportedTaskViews = {
    'cards',
    'list',
    'board',
    'month',
    'gantt',
    'availability',
  };

  String? get _normalizedInitialTaskView {
    final raw = widget.initialTaskView?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    return _supportedTaskViews.contains(raw) ? raw : null;
  }

  int get _taskFilterCount =>
      (_taskPropertyFilterId != null ? 1 : 0) +
      (_taskPriorityFilter != null ? 1 : 0) +
      (_taskAssigneeFilterId != null ? 1 : 0) +
      (_taskDueDateStart != null || _taskDueDateEnd != null ? 1 : 0) +
      (_taskMyTasksOnly ? 1 : 0) +
      (!_taskHideDone ? 1 : 0);

  TaskMetricFilter? get _initialTaskMetricFilter {
    switch (widget.initialTaskMetric?.trim().toLowerCase()) {
      case 'open':
        return TaskMetricFilter.open;
      case 'overdue':
      case 'overvue':
        return TaskMetricFilter.overdue;
      case 'due':
      case 'due_today':
      case 'duetoday':
        return TaskMetricFilter.dueToday;
      default:
        return null;
    }
  }

  Future<void> _loadTaskViewPreference() async {
    if (_normalizedInitialTaskView != null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_taskViewPrefKey);
    final viewType = (saved != null && _supportedTaskViews.contains(saved))
        ? saved
        : 'cards';
    if (mounted) {
      setState(() {
        _taskViewType = viewType;
      });
    }
  }

  Future<void> _saveTaskViewPreference(String viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taskViewPrefKey, viewType);
  }

  @override
  void dispose() {
    _workspaceSubscription?.cancel();
    _tabController?.removeListener(_handleTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Project?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text(
                UserFacingError.uiMessage(
                  snapshot.error,
                  action:
                      'load this ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology).toLowerCase()}',
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final project = snapshot.data;

        if (project == null) {
          return Center(
            child: SelectableText(
              '${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology)} not found',
            ),
          );
        }

        // Cross-workspace link (Recently Viewed, notifications, shared URLs):
        // every tab's data is scoped to the ACTIVE workspace, so a project
        // from another workspace renders empty budgets/financials. Adopt the
        // project's workspace as active. The project loaded through RLS, so
        // the user is a member of it. Hold rendering until the switch lands —
        // otherwise tab panels cache results from the wrong workspace.
        _maybeAdoptProjectWorkspace(project);
        final activeWorkspaceId = context
            .watch<AuthProvider>()
            .appUser
            ?.currentWorkspaceId;
        if (activeWorkspaceId != null &&
            activeWorkspaceId != project.workspaceId) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_tabController == null) {
          return const Center(child: CircularProgressIndicator());
        }

        _tryOpenInitialTask();

        // Show AI setup wizard if requested (after project creation)
        if (widget.showAiSetup && !_aiSetupShown) {
          _aiSetupShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showAiProjectSetupWizard(
              context,
              project: project,
              workspaceId: project.workspaceId,
            );
          });
        }

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: StreamBuilder<List<Project>>(
                    stream: ServiceLocator.projectService.getProjects(
                      project.workspaceId,
                    ),
                    builder: (context, projectsSnapshot) {
                      final allProjects = projectsSnapshot.data ?? [];
                      final liveProject = allProjects
                          .where(
                            (candidate) => candidate.id == widget.projectId,
                          )
                          .cast<Project?>()
                          .firstWhere(
                            (candidate) => candidate != null,
                            orElse: () => null,
                          );
                      return ProjectHeader(
                        project: liveProject ?? project,
                        switchableProjects: allProjects.isNotEmpty
                            ? allProjects
                            : null,
                        onSwitchProject: (p) => context.go('/projects/${p.id}'),
                        onTasksTap: () {
                          final idx = _enabledTabs.indexOf('tasks');
                          if (idx >= 0) _activateTab(idx);
                        },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: EntityTabBar(
                    tabs: [
                      for (final tabId in _enabledTabs)
                        EntityTabDefinition(
                          label:
                              (_allTabDefinitions[tabId]?['name'] ?? tabId)
                                  as String,
                          icon: _allTabDefinitions[tabId]?['icon'] as IconData?,
                        ),
                    ],
                    controller: _tabController!,
                    onTabSelected: (index) =>
                        _activateTab(index, updateRoute: true),
                  ),
                ),
              ];
            },
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: [
                for (final tabId in _enabledTabs)
                  _loadedTabIds.contains(tabId)
                      ? Semantics(
                          label: (_allTabDefinitions[tabId]?['name'] as String?) ?? tabId,
                          child: KeyedSubtree(
                            key: ValueKey('project-tab-$tabId'),
                            child: _buildTabContent(tabId, project),
                          ),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build the tab content widget for a given tab ID
  Widget _buildTabContent(String tabId, Project project) {
    switch (tabId) {
      case 'overview':
        return _buildOverviewTab(project);
      case 'info':
        return ProjectInfoTab(
          project: project,
          onNavigateToTasks: () {
            final tasksIndex = _enabledTabs.indexOf('tasks');
            if (tasksIndex >= 0) _activateTab(tasksIndex, updateRoute: true);
          },
          onOpenTasksForProperty: (propertyId) {
            final tasksIndex = _enabledTabs.indexOf('tasks');
            if (tasksIndex < 0) return;
            setState(() => _taskPropertyFilterId = propertyId);
            _activateTab(tasksIndex, updateRoute: true);
          },
        );
      case 'tasks':
        return _buildTasksTab(project);
      case 'budget':
        return BudgetViewScreen(
          projectId: project.id,
          embedded: true,
          initialMode: _requestedPurchaseOrdersSubView()
              ? BudgetViewMode.purchaseOrders
              : _requestedSelectionsSubView()
                  ? BudgetViewMode.selections
                  : null,
          onCreateDocument: (result) {
            // Switch to the Files tab and open the embedded document create
            // screen inside its Documents virtual folder. Remember the tab
            // the user came from so the Back arrow restores it.
            final filesIndex = _enabledTabs.indexOf('files');
            if (filesIndex < 0) return;
            final originIndex = _tabController?.index;
            _documentCreateOriginTabIndex =
                (originIndex != null && originIndex != filesIndex)
                    ? originIndex
                    : null;
            final filesState = _filesScreenKey.currentState;
            if (filesState != null) {
              _activateTab(filesIndex);
              filesState.openDocumentCreate(
                result,
                onClose: _handleDocumentCreateClosed,
              );
            } else {
              // Files tab not yet lazily built — store and handle in
              // _handleTabChanged once the tab activates.
              _pendingDocumentCreate = result;
              _activateTab(filesIndex);
            }
          },
        );
      case 'messages':
        return _buildMessagesTab(project);
      case 'time-tracking':
        return _buildTimeTrackingTab(project);
      // 'purchase-orders' and 'selections' are no longer top-level tabs —
      // both render as sub-views of the Financials/Budget tab via its
      // in-tab dropdown. Legacy URLs are redirected by _normalizeTabId →
      // 'budget' with initialMode set via the matching helpers.
      case 'inventory':
        return ColoredBox(
          color: AppColors.background,
          child: ProjectInventoryTab(project: project),
        );
      case 'plans':
        return _buildPlansTab(project);
      case 'files':
        return _buildFilesTab(project);
      case 'notes':
        return ProjectNotesTab(project: project);
      default:
        return Center(child: Text('Unknown tab: $tabId'));
    }
  }

  // Overview Tab - Dashboard-style project overview
  Widget _buildOverviewTab(Project project) {
    return ProjectOverviewTab(project: project);
  }

  // Tasks Tab (with List/Gantt/Month toggle)
  Widget _buildTasksTab(Project project) {
    return Column(
      children: [
        ViewToolbar(
          searchHint: 'Search tasks...',
          searchQuery: _taskSearchQuery,
          onSearch: (value) =>
              setState(() => _taskSearchQuery = value.toLowerCase()),
          centerSlot: _buildProjectTaskViewIcons(),
          showBottomBorder: false,
          filterCount: _taskFilterCount,
          onFilterTap: () => _showProjectTaskFilterDialog(project),
          quickToggles: [_buildScheduleButton(project)],
        ),
        Expanded(child: _buildTasksContent(project)),
      ],
    );
  }

  static const _taskViewConfig = <String, (IconData, String)>{
    'cards': (Icons.grid_view, 'Cards'),
    'list': (Icons.view_list, 'List'),
    'month': (Icons.calendar_month, 'Calendar'),
    'gantt': (Icons.view_timeline, 'Gantt'),
    'board': (Icons.view_kanban, 'Board'),
    'availability': (Icons.groups, 'Team'),
  };

  // On mobile only show 3 views: cards, board, calendar — gantt/team/list are too
  // wide or complex for a narrow screen, and 5+ icons overflow at 390px.
  static const _mobileTaskViews = {'cards', 'board', 'month'};

  Widget _buildProjectTaskViewIcons() {
    final isMobile = AppBreakpoints.isMobileContext(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _taskViewConfig.entries)
          if (!isMobile || _mobileTaskViews.contains(entry.key))
            ViewIconButton(
              icon: entry.value.$1,
              tooltip: entry.value.$2,
              isSelected: _taskViewType == entry.key,
              onTap: () {
                setState(() => _taskViewType = entry.key);
                _saveTaskViewPreference(entry.key);
              },
            ),
      ],
    );
  }

  Widget _buildScheduleButton(Project project) {
    return PopupMenuButton<String>(
      tooltip: 'AI Tools',
      offset: const Offset(0, 40),
      onSelected: (value) {
        final workspaceId =
            context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
        switch (value) {
          case 'schedule':
            showTaskSchedulerWizard(
              context,
              project: project,
              workspaceId: workspaceId,
            );
          case 'generate':
            showAiTaskGeneratorWizard(
              context,
              projectId: project.id,
              workspaceId: project.workspaceId,
              project: project,
            );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'schedule',
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: AppColors.secondaryDark),
            title: Text('Schedule Tasks'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'generate',
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: AppColors.secondaryDark),
            title: Text('Generate Tasks'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
      child: const Icon(
        Icons.auto_awesome,
        size: 21,
        color: AppColors.secondaryDark,
      ),
    );
  }

  void _showProjectTaskFilterDialog(Project project) {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    showDialog(
      context: context,
      builder: (_) => _ProjectTaskFilterDialog(
        projectId: project.id,
        workspaceId: workspaceId,
        selectedPropertyId: _taskPropertyFilterId,
        selectedPriority: _taskPriorityFilter,
        selectedAssigneeId: _taskAssigneeFilterId,
        dueDateStart: _taskDueDateStart,
        dueDateEnd: _taskDueDateEnd,
        myTasksOnly: _taskMyTasksOnly,
        hideDone: _taskHideDone,
        onApply:
            (
              propertyId,
              priority,
              assigneeId,
              dateStart,
              dateEnd,
              myTasksOnly,
              hideDone,
            ) {
              setState(() {
                _taskPropertyFilterId = propertyId;
                _taskPriorityFilter = priority;
                _taskAssigneeFilterId = assigneeId;
                _taskDueDateStart = dateStart;
                _taskDueDateEnd = dateEnd;
                _taskMyTasksOnly = myTasksOnly;
                _taskHideDone = hideDone;
              });
              Navigator.of(context).pop();
            },
      ),
    );
  }

  Widget _buildTasksContent(Project project) {
    switch (_taskViewType) {
      case 'gantt':
        return ProjectScheduleScreen(
          projectId: project.id,
          externalMyTasksOnly: _taskMyTasksOnly,
          externalSearchQuery: _taskSearchQuery,
          externalHideDone: _taskHideDone,
        );
      case 'month':
        return _buildMonthlyCalendarView(project);
      case 'availability':
        return _buildAvailabilityView(project);
      case 'board':
        final workspaceIdBoard =
            context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
        return KanbanBoardView(
          projectId: project.id,
          workspaceId: workspaceIdBoard,
          externalMyTasksOnly: _taskMyTasksOnly,
          externalSearchQuery: _taskSearchQuery,
          externalPropertyFilterId: _taskPropertyFilterId,
          externalPriorityFilter: _taskPriorityFilter,
          externalAssigneeFilterId: _taskAssigneeFilterId,
          externalDueDateStart: _taskDueDateStart,
          externalDueDateEnd: _taskDueDateEnd,
        );
      case 'cards':
        final workspaceIdCards =
            context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
        return GroupedTaskListView(
          projectId: project.id,
          externalProject: project,
          workspaceId: workspaceIdCards,
          initialMetricFilter: _initialTaskMetricFilter,
          externalHideDone: _taskHideDone,
          externalMyTasksOnly: _taskMyTasksOnly,
          externalSearchQuery: _taskSearchQuery,
          externalPropertyFilterId: _taskPropertyFilterId,
          externalPriorityFilter: _taskPriorityFilter,
          externalAssigneeFilterId: _taskAssigneeFilterId,
          externalDueDateStart: _taskDueDateStart,
          externalDueDateEnd: _taskDueDateEnd,
          hideToolbarSearch: true,
          hideToolbarHideDone: true,
          hideToolbarMyTasksFilter: true,
          forceCardView: true,
        );
      case 'list':
      default:
        final workspaceId =
            context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
        return GroupedTaskListView(
          projectId: project.id,
          externalProject: project,
          workspaceId: workspaceId,
          initialMetricFilter: _initialTaskMetricFilter,
          externalHideDone: _taskHideDone,
          externalMyTasksOnly: _taskMyTasksOnly,
          externalSearchQuery: _taskSearchQuery,
          externalPropertyFilterId: _taskPropertyFilterId,
          externalPriorityFilter: _taskPriorityFilter,
          externalAssigneeFilterId: _taskAssigneeFilterId,
          externalDueDateStart: _taskDueDateStart,
          externalDueDateEnd: _taskDueDateEnd,
          hideToolbarSearch: true,
          hideToolbarHideDone: true,
          hideToolbarMyTasksFilter: true,
        );
    }
  }

  Widget _buildMonthlyCalendarView(Project project) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final currentUserId = authProvider.appUser?.id;

    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getTasks(
        project.id,
        workspaceId: workspaceId,
      ),
      builder: (context, taskSnapshot) {
        if (taskSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var tasks = taskSnapshot.data ?? [];

        // Apply my tasks filter
        if (_taskMyTasksOnly && currentUserId != null) {
          tasks = tasks
              .where((task) => task.assignedToIds.contains(currentUserId))
              .toList();
        }

        // Apply hide-done filter
        if (_taskHideDone) {
          tasks = tasks
              .where((task) => !task.isComplete && task.status != 'done')
              .toList();
        }

        // Apply search filter
        if (_taskSearchQuery.isNotEmpty) {
          tasks = tasks.where((task) {
            return task.title.toLowerCase().contains(_taskSearchQuery) ||
                (task.description?.toLowerCase().contains(_taskSearchQuery) ??
                    false);
          }).toList();
        }

        return FutureBuilder<Map<String, AppUser>>(
          future: ServiceLocator.userService.getWorkspaceUsersMap(workspaceId),
          builder: (context, usersSnapshot) {
            final usersMap = usersSnapshot.data ?? {};

            return MonthlyCalendarWidget(
              project: project,
              tasks: tasks,
              usersMap: usersMap,
              projectAddress: project.address,
              onTaskTap: (task) {
                // Show task form as popup
                showTaskFormPopup(
                  context,
                  projectId: project.id,
                  taskId: task.id,
                );
              },
              onAddTaskForDate: (date) {
                // Show task creation popup with the selected date as start date
                showTaskFormPopup(
                  context,
                  projectId: project.id,
                  initialStartDate: date,
                );
              },
              onShowMoreTasks: (date, dayTasks) {
                // Show day tasks popup
                showDayTasksPopup(
                  context,
                  date: date,
                  tasks: dayTasks,
                  usersMap: usersMap,
                  projectAddress: project.address,
                  colorContextTasks: tasks,
                  preferPhaseColors: true,
                  onTaskTap: (task) {
                    showTaskFormPopup(
                      context,
                      projectId: project.id,
                      taskId: task.id,
                    );
                  },
                  onAddTask: () {
                    showTaskFormPopup(context, projectId: project.id);
                  },
                );
              },
              onTaskDateChanged: (task, newDate) async {
                // Calculate offset if task has both start and due dates
                DateTime? newStartDate = newDate;
                DateTime? newDueDate = newDate;

                if (task.startDate != null && task.dueDate != null) {
                  // Get original dates normalized to start of day
                  final originalStart = DateTime(
                    task.startDate!.year,
                    task.startDate!.month,
                    task.startDate!.day,
                  );
                  final originalDue = DateTime(
                    task.dueDate!.year,
                    task.dueDate!.month,
                    task.dueDate!.day,
                  );
                  final duration = originalDue.difference(originalStart);

                  // Shift both dates by the same offset
                  newStartDate = newDate;
                  newDueDate = newDate.add(duration);
                } else if (task.dueDate != null) {
                  // Only has due date
                  newDueDate = newDate;
                  newStartDate = null;
                } else {
                  // Only has start date or neither
                  newStartDate = newDate;
                  newDueDate = null;
                }

                try {
                  await ServiceLocator.taskService.updateTask(
                    taskId: task.id,
                    startDate: newStartDate,
                    dueDate: newDueDate,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          UserFacingError.uiMessage(e, action: 'updating task'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAvailabilityView(Project project) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final currentUserId = authProvider.appUser?.id;

    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getTasks(
        project.id,
        workspaceId: workspaceId,
      ),
      builder: (context, taskSnapshot) {
        if (taskSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var tasks = taskSnapshot.data ?? [];

        // Apply my tasks filter
        if (_taskMyTasksOnly && currentUserId != null) {
          tasks = tasks
              .where((task) => task.assignedToIds.contains(currentUserId))
              .toList();
        }

        // Apply hide-done filter
        if (_taskHideDone) {
          tasks = tasks
              .where((task) => !task.isComplete && task.status != 'done')
              .toList();
        }

        // Apply search filter
        if (_taskSearchQuery.isNotEmpty) {
          tasks = tasks.where((task) {
            return task.title.toLowerCase().contains(_taskSearchQuery) ||
                (task.description?.toLowerCase().contains(_taskSearchQuery) ??
                    false);
          }).toList();
        }

        return FutureBuilder<Map<String, AppUser>>(
          future: ServiceLocator.userService.getWorkspaceUsersMap(workspaceId),
          builder: (context, usersSnapshot) {
            final usersMap = usersSnapshot.data ?? {};

            return TeamAvailabilityView(
              tasks: tasks,
              usersMap: usersMap,
              onTaskTap: (task) {
                showTaskFormPopup(
                  context,
                  projectId: project.id,
                  taskId: task.id,
                );
              },
              onAddTaskForDate: (date, userId) {
                showTaskFormPopup(
                  context,
                  projectId: project.id,
                  initialStartDate: date,
                  initialAssignedUserIds: userId.isEmpty ? null : [userId],
                );
              },
              onShowMoreTasks: (date, dayTasks, userId) {
                showDayTasksPopup(
                  context,
                  date: date,
                  tasks: dayTasks,
                  usersMap: usersMap,
                  projectAddress: project.address,
                  onTaskTap: (task) {
                    showTaskFormPopup(
                      context,
                      projectId: project.id,
                      taskId: task.id,
                    );
                  },
                  onAddTask: () {
                    showTaskFormPopup(
                      context,
                      projectId: project.id,
                      initialStartDate: date,
                      initialAssignedUserIds: userId.isEmpty ? null : [userId],
                    );
                  },
                );
              },
              onTaskMoved: (task, newDate, newAssigneeId) async {
                DateTime? newStartDate = newDate;
                DateTime? newDueDate = newDate;

                if (task.startDate != null && task.dueDate != null) {
                  final originalStart = DateTime(
                    task.startDate!.year,
                    task.startDate!.month,
                    task.startDate!.day,
                  );
                  final originalDue = DateTime(
                    task.dueDate!.year,
                    task.dueDate!.month,
                    task.dueDate!.day,
                  );
                  final duration = originalDue.difference(originalStart);
                  newStartDate = newDate;
                  newDueDate = newDate.add(duration);
                } else if (task.dueDate != null) {
                  newDueDate = newDate;
                  newStartDate = null;
                } else {
                  newStartDate = newDate;
                  newDueDate = null;
                }

                List<String>? newAssigneeIds;
                if (newAssigneeId.isNotEmpty) {
                  newAssigneeIds = [newAssigneeId];
                } else {
                  newAssigneeIds = [];
                }

                try {
                  await ServiceLocator.taskService.updateTask(
                    taskId: task.id,
                    startDate: newStartDate,
                    dueDate: newDueDate,
                    assignedToIds: newAssigneeIds,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          UserFacingError.uiMessage(e, action: 'updating task'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  // Messages Tab
  Widget _buildMessagesTab(Project project) {
    return ProjectMessagesTab(
      key: ValueKey('project-messages-${project.id}'),
      project: project,
    );
  }

  // Time Tracking Tab
  Widget _buildTimeTrackingTab(Project project) {
    void onViewChanged(TimeTrackingView view) {
      setState(() => _timeTrackingView = view);
    }

    switch (_timeTrackingView) {
      case TimeTrackingView.clock:
        return ClockInOutScreen(
          key: const ValueKey('project-tt-clock'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
      case TimeTrackingView.timesheet:
        return DailyTimesheetScreen(
          key: const ValueKey('project-tt-timesheet'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
      case TimeTrackingView.weekly:
        return WeeklyTimesheetScreen(
          key: const ValueKey('project-tt-weekly'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
      case TimeTrackingView.dashboard:
        return AdminTimesheetDashboard(
          key: const ValueKey('project-tt-dashboard'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
      case TimeTrackingView.approvals:
        return TimeApprovalScreen(
          key: const ValueKey('project-tt-approvals'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
      case TimeTrackingView.employees:
        return EmployeeTimeTableScreen(
          key: const ValueKey('project-tt-employees'),
          projectId: project.id,
          onViewChanged: onViewChanged,
        );
    }
  }

  // Plans Tab
  Widget _buildPlansTab(Project project) {
    return PlansListScreen(projectId: project.id);
  }

  // Files Tab — also owns Documents, Field Forms, Daily Logs,
  // Inspections, Punch List and Warranties sections via the sidebar.
  Widget _buildFilesTab(Project project) {
    return ProjectFilesScreen(
      key: _filesScreenKey,
      projectId: widget.projectId,
      workspaceId: project.workspaceId,
      project: project,
    );
  }
}

// ── Project Task Filter Dialog ──

class _ProjectTaskFilterDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String? selectedPropertyId;
  final String? selectedPriority;
  final String? selectedAssigneeId;
  final DateTime? dueDateStart;
  final DateTime? dueDateEnd;
  final bool myTasksOnly;
  final bool hideDone;
  final void Function(
    String? propertyId,
    String? priority,
    String? assigneeId,
    DateTime? dueDateStart,
    DateTime? dueDateEnd,
    bool myTasksOnly,
    bool hideDone,
  )
  onApply;

  const _ProjectTaskFilterDialog({
    required this.projectId,
    required this.workspaceId,
    required this.selectedPropertyId,
    required this.selectedPriority,
    required this.selectedAssigneeId,
    required this.dueDateStart,
    required this.dueDateEnd,
    required this.myTasksOnly,
    required this.hideDone,
    required this.onApply,
  });

  @override
  State<_ProjectTaskFilterDialog> createState() =>
      _ProjectTaskFilterDialogState();
}

class _ProjectTaskFilterDialogState extends State<_ProjectTaskFilterDialog> {
  late String? _propertyId;
  late String? _priority;
  late String? _assigneeId;
  late DateTime? _dueDateStart;
  late DateTime? _dueDateEnd;
  late bool _myTasksOnly;
  late bool _hideDone;

  List<Property> _properties = [];
  Map<String, AppUser> _usersMap = {};
  bool _loading = true;

  bool get _hasAnyFilter =>
      _propertyId != null ||
      _priority != null ||
      _assigneeId != null ||
      _dueDateStart != null ||
      _dueDateEnd != null ||
      _myTasksOnly ||
      !_hideDone;

  @override
  void initState() {
    super.initState();
    _propertyId = widget.selectedPropertyId;
    _priority = widget.selectedPriority;
    _assigneeId = widget.selectedAssigneeId;
    _dueDateStart = widget.dueDateStart;
    _dueDateEnd = widget.dueDateEnd;
    _myTasksOnly = widget.myTasksOnly;
    _hideDone = widget.hideDone;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final propertiesFuture =
          ServiceLocator.propertyService
                  .getProperties(
                    widget.projectId,
                    workspaceId: widget.workspaceId,
                  )
                  .first
              as Future<List<Property>>;
      final usersFuture =
          ServiceLocator.userService.getWorkspaceUsersMap(widget.workspaceId)
              as Future<Map<String, AppUser>>;

      final properties = await propertiesFuture;
      final usersMap = await usersFuture;

      if (!mounted) return;
      setState(() {
        _properties = properties;
        _usersMap = usersMap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<MapEntry<String, AppUser>> get _sortedUsers {
    final entries = _usersMap.entries.toList();
    entries.sort(
      (a, b) => (a.value.displayName ?? a.value.email).toLowerCase().compareTo(
        (b.value.displayName ?? b.value.email).toLowerCase(),
      ),
    );
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
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
                          _propertyId = null;
                          _priority = null;
                          _assigneeId = null;
                          _dueDateStart = null;
                          _dueDateEnd = null;
                          _myTasksOnly = false;
                          _hideDone = true;
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
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  shrinkWrap: true,
                  children: [
                    // ── My tasks toggle ──
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        _myTasksOnly
                            ? Icons.assignment_ind
                            : Icons.assignment,
                        size: 20,
                        color: _myTasksOnly
                            ? AppColors.secondary
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        'My tasks only',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _myTasksOnly
                              ? AppColors.secondary
                              : AppColors.textPrimary,
                        ),
                      ),
                      value: _myTasksOnly,
                      onChanged: (v) => setState(() => _myTasksOnly = v),
                      activeThumbColor: AppColors.secondary,
                    ),
                    // ── Hide done toggle ──
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        _hideDone ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: _hideDone
                            ? AppColors.secondary
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        'Hide done tasks',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _hideDone
                              ? AppColors.secondary
                              : AppColors.textPrimary,
                        ),
                      ),
                      value: _hideDone,
                      onChanged: (v) => setState(() => _hideDone = v),
                      activeThumbColor: AppColors.secondary,
                    ),
                    const SizedBox(height: 12),
                    // ── Priority ──
                    _buildPrioritySection(),
                    const SizedBox(height: 12),

                    // ── Due Date ──
                    _buildDueDateSection(),

                    // ── Location ──
                    if (_properties.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildFilterSection(
                        icon: Icons.location_on_outlined,
                        title: 'Location',
                        subtitle: _propertyId == null
                            ? 'All Locations'
                            : _getPropertyLabel(_propertyId!),
                        isActive: _propertyId != null,
                        child: SearchableFilterChips(
                          items: _properties.map((p) {
                            final label = p.name.isNotEmpty
                                ? (p.identifier.isNotEmpty
                                      ? '${p.name} (${p.identifier})'
                                      : p.name)
                                : p.identifier;
                            return (id: p.id, label: label);
                          }).toList(),
                          selectedId: _propertyId,
                          allLabel: 'All Locations',
                          onAllSelected: () =>
                              setState(() => _propertyId = null),
                          onItemSelected: (id) =>
                              setState(() => _propertyId = id),
                          searchHint: 'Search locations...',
                        ),
                      ),
                    ],

                    // ── Assignee ──
                    if (_sortedUsers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildFilterSection(
                        icon: Icons.person_outline,
                        title: 'Assignee',
                        subtitle: _assigneeId == null
                            ? 'Anyone'
                            : _usersMap[_assigneeId]?.displayName ??
                                  _usersMap[_assigneeId]?.email ??
                                  '',
                        isActive: _assigneeId != null,
                        child: SearchableFilterChips(
                          items: _sortedUsers
                              .map(
                                (e) => (
                                  id: e.key,
                                  label: e.value.displayName ?? e.value.email,
                                ),
                              )
                              .toList(),
                          selectedId: _assigneeId,
                          allLabel: 'Anyone',
                          onAllSelected: () =>
                              setState(() => _assigneeId = null),
                          onItemSelected: (id) =>
                              setState(() => _assigneeId = id),
                          searchHint: 'Search team members...',
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // ── Footer ──
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onApply(
                      _propertyId,
                      _priority,
                      _assigneeId,
                      _dueDateStart,
                      _dueDateEnd,
                      _myTasksOnly,
                      _hideDone,
                    ),
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

  String _getPropertyLabel(String propertyId) {
    final p = _properties.where((p) => p.id == propertyId).firstOrNull;
    if (p == null) return '';
    return p.name.isNotEmpty
        ? (p.identifier.isNotEmpty ? '${p.name} (${p.identifier})' : p.name)
        : p.identifier;
  }

  Widget _buildPrioritySection() {
    const priorities = [
      ('high', 'High', Icons.keyboard_arrow_up, AppColors.error),
      ('medium', 'Medium', Icons.remove, AppColors.warning),
      ('low', 'Low', Icons.keyboard_arrow_down, AppColors.info),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _priority != null
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: _priority != null
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: 20,
                color: _priority != null
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                'Priority',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _priority != null
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: priorities.map((p) {
              final (value, label, icon, color) = p;
              final isSelected = _priority == value;
              return ChoiceChip(
                avatar: Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : color,
                ),
                label: Text(label),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _priority = selected ? value : null);
                },
                selectedColor: color,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateSection() {
    final hasDateFilter = _dueDateStart != null || _dueDateEnd != null;
    return Container(
      decoration: BoxDecoration(
        color: hasDateFilter
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: hasDateFilter
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 20,
                color: hasDateFilter
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                'Due Date',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasDateFilter
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (hasDateFilter)
                GestureDetector(
                  onTap: () => setState(() {
                    _dueDateStart = null;
                    _dueDateEnd = null;
                  }),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: 'From',
                  date: _dueDateStart,
                  onTap: () => _pickDate(true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
              Expanded(
                child: _buildDateButton(
                  label: 'To',
                  date: _dueDateEnd,
                  onTap: () => _pickDate(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date != null ? '${date.month}/${date.day}/${date.year}' : label,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_dueDateStart ?? now) : (_dueDateEnd ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _dueDateStart = picked;
          if (_dueDateEnd != null && _dueDateEnd!.isBefore(picked)) {
            _dueDateEnd = picked;
          }
        } else {
          _dueDateEnd = picked;
          if (_dueDateStart != null && _dueDateStart!.isAfter(picked)) {
            _dueDateStart = picked;
          }
        }
      });
    }
  }

  Widget _buildFilterSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required Widget child,
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
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
