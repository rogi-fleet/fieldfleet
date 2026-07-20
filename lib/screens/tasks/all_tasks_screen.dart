import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../services/service_locator.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/user.dart';
import '../../widgets/timeline/monthly_calendar_widget.dart';
import '../../widgets/timeline/day_tasks_popup.dart';
import '../../widgets/task_form_popup.dart';
import '../../widgets/tasks/grouped_task_list_view.dart';
import '../../widgets/tasks/kanban_board_view.dart';
import '../../widgets/tasks/tasks_map_panel.dart';
import '../../widgets/tasks/team_availability_view.dart';
import '../schedule/schedule_dashboard_screen.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../utils/task_filter_engine.dart';
import '../../utils/app_time_formatter.dart';
import '../../widgets/common/searchable_filter_chips.dart';

class AllTasksScreen extends StatefulWidget {
  final bool initialOverdue;

  /// Optional view to open with (e.g. 'month' for the schedule calendar),
  /// from the ?view= query param. Overrides the persisted view preference
  /// for this visit without overwriting it.
  final String? initialView;

  const AllTasksScreen({super.key, this.initialOverdue = false, this.initialView});

  @override
  State<AllTasksScreen> createState() => _AllTasksScreenState();
}

class _AllTasksScreenState extends State<AllTasksScreen> {
  static const String _viewTypePrefKey = 'all_tasks_view_type';
  static const Set<String> _supportedViewTypes = {
    'cards',
    'list',
    'month',
    'gantt',
    'board',
    'availability',
  };

  bool? _myTasksOverride; // null = follow isFieldMode
  String _viewType =
      'cards'; // 'cards', 'list', 'month', 'gantt', 'board', or 'availability'
  String _searchQuery = '';
  String? _selectedProjectId; // Project (job) filter
  String? _selectedPropertyId; // Property filter (scoped to selected project)
  late bool _overdueOnly;
  bool _hideDone = true;
  bool _showMapPanel = true;
  double? _mapWidth; // null = use responsive default
  static const double _mapMinWidth = 220.0;
  static const double _mapMaxFraction = 0.75;
  static const Set<String> _mapEnabledViews = {'cards', 'list', 'month', 'board'};
  String? _selectedCustomerId;
  String? _selectedPriority;
  String? _selectedAssigneeId;
  DateTime? _dueDateStart;
  DateTime? _dueDateEnd;
  List<_SavedTaskView> _savedViews = [];
  String? _activeSavedViewId;
  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    _overdueOnly = widget.initialOverdue;
    final requestedView = widget.initialView;
    if (requestedView != null && _supportedViewTypes.contains(requestedView)) {
      _viewType = requestedView;
    } else {
      _loadViewTypePreference();
    }
    _loadSavedViews();
    // Saved views come from per-user preferences. On a fresh page load the
    // Supabase session may not be restored yet when initState runs, so the
    // first load can return empty. Reload once auth becomes available.
    _authSub = ServiceLocator.authService.userChanges.listen((user) {
      if (user != null && _savedViews.isEmpty) {
        _loadSavedViews();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadViewTypePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_viewTypePrefKey);
    if (saved != null && _supportedViewTypes.contains(saved) && mounted) {
      setState(() => _viewType = saved);
    }
  }

  Future<void> _saveViewTypePreference(String viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewTypePrefKey, viewType);
  }

  static const String _savedViewsPrefKey = 'saved_task_views';

  Future<void> _loadSavedViews() async {
    final raw = await ServiceLocator.userPreferencesService
        .getSavedViews(_savedViewsPrefKey);
    if (!mounted) return;

    setState(() {
      _savedViews = raw.map(_SavedTaskView.fromMap).toList();
    });
  }

  Map<String, AppUser> _cachedUsersMap = {};
  String? _usersLoadedForWorkspace;

  void _ensureUsersLoaded(String workspaceId) {
    if (_usersLoadedForWorkspace == workspaceId) return;
    _usersLoadedForWorkspace = workspaceId;
    final requestedWorkspace = workspaceId;
    ServiceLocator.userService.getWorkspaceUsersMap(workspaceId).then((map) {
      if (mounted && _usersLoadedForWorkspace == requestedWorkspace) {
        setState(() => _cachedUsersMap = map);
      }
    });
  }

  bool get _showMyTasksOnly {
    if (_myTasksOverride != null) return _myTasksOverride!;
    return context.read<AuthProvider>().isFieldMode;
  }

  TaskFilterOptions _buildFilterOptions(String? currentUserId) {
    return TaskFilterOptions(
      myTasksOnly: _showMyTasksOnly,
      currentUserId: currentUserId,
      projectId: _selectedProjectId,
      propertyFilterId: _selectedPropertyId,
      customerId: _selectedCustomerId,
      priority: _selectedPriority,
      assigneeId: _selectedAssigneeId,
      dueDateStart: _dueDateStart,
      dueDateEnd: _dueDateEnd,
      overdueOnly: _overdueOnly,
      hideDone: _hideDone,
      query: _searchQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final currentUserId = authProvider.appUser?.id;

    if (workspaceId == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading workspace…'),
          ],
        ),
      );
    }

    _ensureUsersLoaded(workspaceId);

    return StreamBuilder<List<Project>>(
      stream: ServiceLocator.projectService.getProjects(workspaceId),
      builder: (context, projectSnapshot) {
        final projects = projectSnapshot.data ?? [];
        final projectMap = {
          for (final project in projects) project.id: project,
        };

        return StreamBuilder<List<Property>>(
          stream: ServiceLocator.propertyService.getPropertiesByWorkspace(
            workspaceId,
          ),
          builder: (context, propertySnapshot) {
            final properties = propertySnapshot.data ?? [];
            final propertyMap = {
              for (final property in properties) property.id: property,
            };

            // Compute filter count for the badge — counts state that deviates
            // from defaults. myTasksOnly default tracks isFieldMode; hideDone
            // default is true.
            final advancedFilterCount =
                (_selectedProjectId != null ? 1 : 0) +
                (_selectedPropertyId != null ? 1 : 0) +
                (_overdueOnly ? 1 : 0) +
                (_selectedCustomerId != null ? 1 : 0) +
                (_selectedPriority != null ? 1 : 0) +
                (_selectedAssigneeId != null ? 1 : 0) +
                (_dueDateStart != null || _dueDateEnd != null ? 1 : 0) +
                (_showMyTasksOnly != authProvider.isFieldMode ? 1 : 0) +
                (!_hideDone ? 1 : 0);

            return Column(
              children: [
                const ModuleHeader(
                  icon: Icons.task_alt_outlined,
                  title: 'Tasks',
                  description:
                      'Assign work, track checklists and completion across every job.',
                ),
                ViewToolbar(
                  searchHint: 'Search tasks...',
                  searchQuery: _searchQuery,
                  onSearch: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                      _activeSavedViewId = null;
                    });
                  },
                  centerSlot: _buildViewIcons(context),
                  filterCount: advancedFilterCount,
                  onFilterTap: () => _showFilterDialog(
                    _sortedProjects(projectMap),
                    _filteredProperties(properties, projectMap),
                  ),
                ),
                // Content based on view type
                Expanded(
                  child: _buildContentWithMap(
                    context,
                    workspaceId,
                    currentUserId,
                    projectMap,
                    propertyMap,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const List<(String, IconData, String)> _viewOptions = [
    ('cards', Icons.grid_view, 'Cards'),
    ('list', Icons.view_list, 'List'),
    ('month', Icons.calendar_month, 'Calendar'),
    ('gantt', Icons.view_timeline, 'Gantt'),
    ('board', Icons.view_kanban, 'Board'),
    ('availability', Icons.groups, 'Team'),
  ];

  Widget _buildViewIcons(BuildContext context) {
    final isMobile = AppBreakpoints.isMobileContext(context);
    final mapAvailable = _mapEnabledViews.contains(_viewType) && !isMobile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, icon, tooltip) in _viewOptions)
          if (!isMobile || value != 'list')
            ViewIconButton(
              icon: icon,
              tooltip: tooltip,
              isSelected: _viewType == value,
              onTap: () {
                setState(() {
                  _viewType = value;
                  _activeSavedViewId = null;
                });
                _saveViewTypePreference(value);
              },
            ),
        if (mapAvailable) ...[
          const SizedBox(width: 4),
          ViewIconButton(
            icon: _showMapPanel ? Icons.map : Icons.map_outlined,
            tooltip: _showMapPanel ? 'Hide map' : 'Show map',
            isSelected: _showMapPanel,
            onTap: () => setState(() => _showMapPanel = !_showMapPanel),
          ),
        ],
      ],
    );
  }

  Widget _buildContentWithMap(
    BuildContext context,
    String workspaceId,
    String? currentUserId,
    Map<String, Project> projectMap,
    Map<String, Property> propertyMap,
  ) {
    final content = _buildContent(
      workspaceId,
      currentUserId,
      projectMap,
      propertyMap,
    );
    final isMobile = AppBreakpoints.isMobileContext(context);
    final showMap = _showMapPanel &&
        !isMobile &&
        _mapEnabledViews.contains(_viewType);
    if (!showMap) return content;

    final screenWidth = MediaQuery.of(context).size.width;
    final defaultMapWidth = screenWidth < AppBreakpoints.desktop ? 320.0 : 380.0;

    // Build map filter options that mirror what the active view shows.
    // The Kanban board intentionally ignores hideDone (Done is a visible
    // column) and the project filter, so the map relaxes those in board mode
    // to stay in sync with the visible task set.
    var mapFilters = _buildFilterOptions(currentUserId);
    if (_viewType == 'board') {
      mapFilters = mapFilters.copyWith(hideDone: false, projectId: null);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // Leave at least 240 px for the task list and cap the map at
        // _mapMaxFraction of the available row.
        final maxMap = (totalWidth - 240).clamp(_mapMinWidth,
            totalWidth * _mapMaxFraction);
        final mapWidth = (_mapWidth ?? defaultMapWidth)
            .clamp(_mapMinWidth, maxMap);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: content),
            _MapSplitterHandle(
              onDrag: (delta) {
                setState(() {
                  final current = _mapWidth ?? mapWidth;
                  _mapWidth =
                      (current - delta).clamp(_mapMinWidth, maxMap);
                });
              },
            ),
            SizedBox(
              width: mapWidth,
              child: TasksMapPanel(
                workspaceId: workspaceId,
                projectMap: projectMap,
                propertyMap: propertyMap,
                filterOptions: mapFilters,
                onClose: () => setState(() => _showMapPanel = false),
              ),
            ),
          ],
        );
      },
    );
  }

/// Projects sorted for the filter sheet (hide inactive, keep selected).
  List<Project> _sortedProjects(Map<String, Project> projectMap) {
    const inactiveStatuses = {
      ProjectStatus.complete,
      ProjectStatus.lost,
      ProjectStatus.canceled,
    };
    return projectMap.values
        .where(
          (p) =>
              !inactiveStatuses.contains(p.status) ||
              p.id == _selectedProjectId,
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Properties scoped to the selected project (or active projects).
  List<Property> _filteredProperties(
    List<Property> properties,
    Map<String, Project> projectMap,
  ) {
    if (_selectedProjectId != null) {
      return properties
          .where((p) => p.projectId == _selectedProjectId)
          .toList();
    }
    return properties.where((p) {
      final proj = projectMap[p.projectId];
      if (proj == null) return true;
      return !const {
        ProjectStatus.complete,
        ProjectStatus.lost,
        ProjectStatus.canceled,
      }.contains(proj.status);
    }).toList();
  }

  void _showFilterDialog(
    List<Project> sortedProjects,
    List<Property> filteredProperties,
  ) {
    // Build unique customer list from projects
    final customerMap = <String, String>{};
    for (final p in sortedProjects) {
      if (p.clientId != null && p.clientId!.isNotEmpty) {
        customerMap[p.clientId!] = p.customerName ?? 'Unknown';
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return _TaskFilterDialog(
          projects: sortedProjects,
          properties: filteredProperties,
          customers: customerMap,
          users: _cachedUsersMap,
          selectedProjectId: _selectedProjectId,
          selectedPropertyId: _selectedPropertyId,
          overdueOnly: _overdueOnly,
          selectedCustomerId: _selectedCustomerId,
          selectedPriority: _selectedPriority,
          selectedAssigneeId: _selectedAssigneeId,
          dueDateStart: _dueDateStart,
          dueDateEnd: _dueDateEnd,
          myTasksOnly: _showMyTasksOnly,
          hideDone: _hideDone,
          savedViews: _savedViews,
          activeSavedViewId: _activeSavedViewId,
          onApply: (filters) {
            setState(() {
              _selectedProjectId = filters.projectId;
              _selectedPropertyId = filters.propertyFilterId;
              _overdueOnly = filters.overdueOnly;
              _selectedCustomerId = filters.customerId;
              _selectedPriority = filters.priority;
              _selectedAssigneeId = filters.assigneeId;
              _dueDateStart = filters.dueDateStart;
              _dueDateEnd = filters.dueDateEnd;
              _myTasksOverride = filters.myTasksOnly;
              _hideDone = filters.hideDone;
              _activeSavedViewId = null;
            });
            Navigator.of(ctx).pop();
          },
          onApplySavedView: (viewId) {
            Navigator.of(ctx).pop();
            _applySavedViewById(viewId);
          },
          onSaveView: (filters) {
            Navigator.of(ctx).pop();
            _showSaveViewDialog(filters);
          },
          onDeleteSavedView: (viewId) {
            _deleteSavedViewById(viewId);
          },
        );
      },
    );
  }

  void _applySavedViewById(String viewId) {
    _SavedTaskView? view;
    for (final candidate in _savedViews) {
      if (candidate.id == viewId) {
        view = candidate;
        break;
      }
    }
    if (view == null) return;
    final selectedView = view;
    setState(() {
      _viewType = selectedView.viewType;
      _searchQuery = selectedView.searchQuery;
      _myTasksOverride = selectedView.myTasksOnly;
      _hideDone = selectedView.hideDone;
      _selectedProjectId = selectedView.projectId;
      _selectedPropertyId = selectedView.propertyId;
      _overdueOnly = selectedView.overdueOnly;
      _selectedCustomerId = selectedView.customerId;
      _selectedPriority = selectedView.priority;
      _selectedAssigneeId = selectedView.assigneeId;
      _dueDateStart = selectedView.dueDateStart;
      _dueDateEnd = selectedView.dueDateEnd;
      _activeSavedViewId = selectedView.id;
    });
    _saveViewTypePreference(selectedView.viewType);
  }

  Future<void> _showSaveViewDialog(TaskFilterOptions filters) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save current view'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. My overdue high priority',
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(context).pop(trimmed);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) return;
                Navigator.of(context).pop(trimmed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    final view = _SavedTaskView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      viewType: _viewType,
      searchQuery: _searchQuery,
      myTasksOnly: filters.myTasksOnly,
      hideDone: filters.hideDone,
      projectId: filters.projectId,
      propertyId: filters.propertyFilterId,
      overdueOnly: filters.overdueOnly,
      customerId: filters.customerId,
      priority: filters.priority,
      assigneeId: filters.assigneeId,
      dueDateStart: filters.dueDateStart,
      dueDateEnd: filters.dueDateEnd,
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
    }
    await _loadSavedViews();
  }

  Widget _buildContent(
    String workspaceId,
    String? currentUserId,
    Map<String, Project> projectMap,
    Map<String, Property> propertyMap,
  ) {
    switch (_viewType) {
      case 'cards':
        return _buildCardView(workspaceId, currentUserId);
      case 'month':
        return _buildMonthView(
          workspaceId,
          currentUserId,
          projectMap,
          propertyMap,
        );
      case 'gantt':
        return ScheduleDashboardScreen(
          showAppBar: false,
          hideProjectSelector: true,
          externalMyTasksOnly: _showMyTasksOnly,
          externalHideDone: _hideDone,
          externalSearchQuery: _searchQuery,
          externalPropertyFilterId: _selectedPropertyId,
          externalOverdueOnly: _overdueOnly,
          externalCustomerFilterId: _selectedCustomerId,
          externalPriorityFilter: _selectedPriority,
          externalAssigneeFilterId: _selectedAssigneeId,
          externalDueDateStart: _dueDateStart,
          externalDueDateEnd: _dueDateEnd,
          externalProjectMap: projectMap,
        );
      case 'board':
        return KanbanBoardView(
          workspaceId: workspaceId,
          externalMyTasksOnly: _showMyTasksOnly,
          externalSearchQuery: _searchQuery,
          externalPropertyFilterId: _selectedPropertyId,
          externalOverdueOnly: _overdueOnly,
          externalCustomerFilterId: _selectedCustomerId,
          externalPriorityFilter: _selectedPriority,
          externalAssigneeFilterId: _selectedAssigneeId,
          externalDueDateStart: _dueDateStart,
          externalDueDateEnd: _dueDateEnd,
          externalProjectMap: projectMap,
        );
      case 'availability':
        return _buildAvailabilityView(
          workspaceId,
          currentUserId,
          projectMap,
          propertyMap,
        );
      case 'list':
      default:
        return _buildListView(workspaceId, currentUserId);
    }
  }

  Widget _buildMonthView(
    String workspaceId,
    String? currentUserId,
    Map<String, Project> projectMap,
    Map<String, Property> propertyMap,
  ) {
    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getAllWorkspaceTasks(workspaceId),
      builder: (context, taskSnapshot) {
        if (taskSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading tasks…'),
              ],
            ),
          );
        }

        final allTasks = taskSnapshot.data ?? [];
        final filterContext = TaskFilterContext(
          projectMap: projectMap,
          propertyMap: propertyMap,
        );
        final tasks = TaskFilterEngine.apply(
          allTasks,
          options: _buildFilterOptions(currentUserId),
          context: filterContext,
        );

        return FutureBuilder<Map<String, AppUser>>(
          future: ServiceLocator.userService.getWorkspaceUsersMap(workspaceId),
          builder: (context, usersSnapshot) {
            final usersMap = usersSnapshot.data ?? {};

            return MonthlyCalendarWidget(
              tasks: tasks,
              usersMap: usersMap,
              onTaskTap: (task) {
                showTaskFormPopup(
                  context,
                  projectId: task.projectId,
                  taskId: task.id,
                );
              },
              onAddTaskForDate: (date) {
                // For all tasks view, we need a project - show project picker or first project
                _showProjectPickerForNewTask(context, workspaceId, date);
              },
              onShowMoreTasks: (date, dayTasks) {
                showDayTasksPopup(
                  context,
                  date: date,
                  tasks: dayTasks,
                  usersMap: usersMap,
                  colorContextTasks: tasks,
                  preferPhaseColors: _selectedProjectId != null,
                  onTaskTap: (task) {
                    showTaskFormPopup(
                      context,
                      projectId: task.projectId,
                      taskId: task.id,
                    );
                  },
                  onAddTask: () {
                    _showProjectPickerForNewTask(context, workspaceId, date);
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

  Widget _buildAvailabilityView(
    String workspaceId,
    String? currentUserId,
    Map<String, Project> projectMap,
    Map<String, Property> propertyMap,
  ) {
    return StreamBuilder<List<Task>>(
      stream: ServiceLocator.taskService.getAllWorkspaceTasks(workspaceId),
      builder: (context, taskSnapshot) {
        if (taskSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading tasks…'),
              ],
            ),
          );
        }

        final allTasks = taskSnapshot.data ?? [];
        final filterContext = TaskFilterContext(
          projectMap: projectMap,
          propertyMap: propertyMap,
        );
        final tasks = TaskFilterEngine.apply(
          allTasks,
          options: _buildFilterOptions(currentUserId),
          context: filterContext,
        );

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
                  projectId: task.projectId,
                  taskId: task.id,
                );
              },
              onAddTaskForDate: (date, userId) {
                _showProjectPickerForNewTask(context, workspaceId, date);
              },
              onShowMoreTasks: (date, dayTasks, userId) {
                showDayTasksPopup(
                  context,
                  date: date,
                  tasks: dayTasks,
                  usersMap: usersMap,
                  onTaskTap: (task) {
                    showTaskFormPopup(
                      context,
                      projectId: task.projectId,
                      taskId: task.id,
                    );
                  },
                  onAddTask: () {
                    _showProjectPickerForNewTask(context, workspaceId, date);
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

                // Build new assignee list
                List<String>? newAssigneeIds;
                if (newAssigneeId.isNotEmpty) {
                  // Replace current assignees with the target user
                  newAssigneeIds = [newAssigneeId];
                } else {
                  // Dropped on unassigned row
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

  void _showProjectPickerForNewTask(
    BuildContext context,
    String workspaceId,
    DateTime? initialDate,
  ) async {
    final projectTerminology = context
        .read<WorkspaceProvider>()
        .projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final projects = await ServiceLocator.projectService.getProjectsOnce(
      workspaceId,
    );
    if (projects.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Create a ${singular.toLowerCase()} first to add tasks',
            ),
          ),
        );
      }
      return;
    }

    if (projects.length == 1) {
      // Only one project, use it directly
      if (context.mounted) {
        showTaskFormPopup(
          context,
          projectId: projects.first.id,
          initialStartDate: initialDate,
        );
      }
      return;
    }

    // Show project picker
    if (context.mounted) {
      final selectedProject = await showDialog<Project>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select $singular'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return ListTile(
                  title: Text(project.name),
                  onTap: () => Navigator.pop(context, project),
                );
              },
            ),
          ),
        ),
      );

      if (selectedProject != null && context.mounted) {
        showTaskFormPopup(
          context,
          projectId: selectedProject.id,
          initialStartDate: initialDate,
        );
      }
    }
  }

  Widget _buildCardView(String workspaceId, String? currentUserId) {
    return GroupedTaskListView(
      workspaceId: workspaceId,
      showProjectColumn: true,
      externalSearchQuery: _searchQuery,
      externalPropertyFilterId: _selectedPropertyId,
      externalProjectFilterId: _selectedProjectId,
      externalMyTasksOnly: _showMyTasksOnly,
      externalHideDone: _hideDone,
      externalOverdueOnly: _overdueOnly,
      externalCustomerFilterId: _selectedCustomerId,
      externalPriorityFilter: _selectedPriority,
      externalAssigneeFilterId: _selectedAssigneeId,
      externalDueDateStart: _dueDateStart,
      externalDueDateEnd: _dueDateEnd,
      hideToolbarSearch: true,
      hideToolbarMyTasksFilter: true,
      hideToolbarHideDone: true,
      forceCardView: true,
    );
  }

  Widget _buildListView(String workspaceId, String? currentUserId) {
    return GroupedTaskListView(
      workspaceId: workspaceId,
      showProjectColumn: true,
      externalSearchQuery: _searchQuery,
      externalPropertyFilterId: _selectedPropertyId,
      externalProjectFilterId: _selectedProjectId,
      externalMyTasksOnly: _showMyTasksOnly,
      externalHideDone: _hideDone,
      externalOverdueOnly: _overdueOnly,
      externalCustomerFilterId: _selectedCustomerId,
      externalPriorityFilter: _selectedPriority,
      externalAssigneeFilterId: _selectedAssigneeId,
      externalDueDateStart: _dueDateStart,
      externalDueDateEnd: _dueDateEnd,
      hideToolbarSearch: true,
      hideToolbarMyTasksFilter: true,
      hideToolbarHideDone: true,
    );
  }
}

class _SavedTaskView {
  final String id;
  final String name;
  final String viewType;
  final String searchQuery;
  final bool myTasksOnly;
  final bool hideDone;
  final String? projectId;
  final String? propertyId;
  final bool overdueOnly;
  final String? customerId;
  final String? priority;
  final String? assigneeId;
  final DateTime? dueDateStart;
  final DateTime? dueDateEnd;
  final DateTime createdAt;

  const _SavedTaskView({
    required this.id,
    required this.name,
    required this.viewType,
    required this.searchQuery,
    required this.myTasksOnly,
    required this.hideDone,
    required this.projectId,
    required this.propertyId,
    required this.overdueOnly,
    required this.customerId,
    required this.priority,
    required this.assigneeId,
    required this.dueDateStart,
    required this.dueDateEnd,
    required this.createdAt,
  });

  factory _SavedTaskView.fromMap(Map<String, dynamic> map) {
    final rawViewType = map['view_type'] as String?;
    final viewType =
        _AllTasksScreenState._supportedViewTypes.contains(rawViewType)
        ? rawViewType!
        : 'cards';

    return _SavedTaskView(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Saved view',
      viewType: viewType,
      searchQuery: map['search_query'] as String? ?? '',
      myTasksOnly: map['my_tasks_only'] as bool? ?? false,
      hideDone: map['hide_done'] as bool? ?? true,
      projectId: map['project_id'] as String?,
      propertyId: map['property_id'] as String?,
      overdueOnly: map['overdue_only'] as bool? ?? false,
      customerId: map['customer_id'] as String?,
      priority: map['priority'] as String?,
      assigneeId: map['assignee_id'] as String?,
      dueDateStart: DateTime.tryParse(map['due_date_start'] as String? ?? ''),
      dueDateEnd: DateTime.tryParse(map['due_date_end'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'view_type': viewType,
      'search_query': searchQuery,
      'my_tasks_only': myTasksOnly,
      'hide_done': hideDone,
      'project_id': projectId,
      'property_id': propertyId,
      'overdue_only': overdueOnly,
      'customer_id': customerId,
      'priority': priority,
      'assignee_id': assigneeId,
      'due_date_start': dueDateStart?.toIso8601String(),
      'due_date_end': dueDateEnd?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class _TaskFilterDialog extends StatefulWidget {
  final List<Project> projects;
  final List<Property> properties;
  final Map<String, String> customers; // clientId -> name
  final Map<String, AppUser> users;
  final String? selectedProjectId;
  final String? selectedPropertyId;
  final bool overdueOnly;
  final String? selectedCustomerId;
  final String? selectedPriority;
  final String? selectedAssigneeId;
  final DateTime? dueDateStart;
  final DateTime? dueDateEnd;
  final bool myTasksOnly;
  final bool hideDone;
  final List<_SavedTaskView> savedViews;
  final String? activeSavedViewId;
  final void Function(TaskFilterOptions filters) onApply;
  final ValueChanged<String> onApplySavedView;
  final ValueChanged<TaskFilterOptions> onSaveView;
  final ValueChanged<String> onDeleteSavedView;

  const _TaskFilterDialog({
    required this.projects,
    required this.properties,
    required this.customers,
    required this.users,
    required this.selectedProjectId,
    required this.selectedPropertyId,
    required this.overdueOnly,
    required this.selectedCustomerId,
    required this.selectedPriority,
    required this.selectedAssigneeId,
    required this.dueDateStart,
    required this.dueDateEnd,
    required this.myTasksOnly,
    required this.hideDone,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApply,
    required this.onApplySavedView,
    required this.onSaveView,
    required this.onDeleteSavedView,
  });

  @override
  State<_TaskFilterDialog> createState() => _TaskFilterDialogState();
}

class _TaskFilterDialogState extends State<_TaskFilterDialog> {
  late String? _projectId;
  late String? _propertyId;
  late bool _overdueOnly;
  late String? _customerId;
  late String? _priority;
  late String? _assigneeId;
  late DateTime? _dueDateStart;
  late DateTime? _dueDateEnd;
  late bool _myTasksOnly;
  late bool _hideDone;

  @override
  void initState() {
    super.initState();
    _projectId = widget.selectedProjectId;
    _propertyId = widget.selectedPropertyId;
    _overdueOnly = widget.overdueOnly;
    _customerId = widget.selectedCustomerId;
    _priority = widget.selectedPriority;
    _assigneeId = widget.selectedAssigneeId;
    _dueDateStart = widget.dueDateStart;
    _dueDateEnd = widget.dueDateEnd;
    _myTasksOnly = widget.myTasksOnly;
    _hideDone = widget.hideDone;
  }

  bool get _hasAnyFilter =>
      _projectId != null ||
      _propertyId != null ||
      _overdueOnly ||
      _customerId != null ||
      _priority != null ||
      _assigneeId != null ||
      _dueDateStart != null ||
      _dueDateEnd != null ||
      _myTasksOnly ||
      !_hideDone;

  List<Property> get _scopedProperties {
    if (_projectId == null) return widget.properties;
    return widget.properties.where((p) => p.projectId == _projectId).toList();
  }

  late final List<MapEntry<String, AppUser>> _sortedUsers = () {
    final entries = widget.users.entries.toList();
    entries.sort(
      (a, b) => (a.value.displayName ?? a.value.email).toLowerCase().compareTo(
        (b.value.displayName ?? b.value.email).toLowerCase(),
      ),
    );
    return entries;
  }();

  late final List<MapEntry<String, String>> _sortedCustomers = () {
    final entries = widget.customers.entries.toList();
    entries.sort(
      (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
    );
    return entries;
  }();

  String _formatDate(DateTime date) {
    return AppTimeFormatter.formatDate(date, pattern: 'M/d/yyyy');
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

  TaskFilterOptions _currentFilters() {
    return TaskFilterOptions(
      projectId: _projectId,
      propertyFilterId: _propertyId,
      overdueOnly: _overdueOnly,
      customerId: _customerId,
      priority: _priority,
      assigneeId: _assigneeId,
      dueDateStart: _dueDateStart,
      dueDateEnd: _dueDateEnd,
      myTasksOnly: _myTasksOnly,
      hideDone: _hideDone,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
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
                          _projectId = null;
                          _propertyId = null;
                          _overdueOnly = false;
                          _customerId = null;
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
                  const SizedBox(height: 4),
                  // ── Overdue toggle ──
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: _overdueOnly
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      'Overdue only',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _overdueOnly
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    value: _overdueOnly,
                    onChanged: (v) => setState(() => _overdueOnly = v),
                    activeThumbColor: AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  // ── Priority chips ──
                  _buildPrioritySection(),
                  const SizedBox(height: 12),
                  // ── Due Date range ──
                  _buildDueDateSection(),
                  const SizedBox(height: 12),
                  // ── Job section ──
                  _buildFilterSection(
                    icon: Icons.work_outline,
                    title: 'Job',
                    subtitle: _projectId == null
                        ? 'All Jobs'
                        : _getSelectedProjectLabel(),
                    isActive: _projectId != null,
                    initiallyExpanded: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                        child: SearchableFilterChips(
                          items: widget.projects.map((p) {
                            final sn = p.serialNumber?.trim();
                            final label = (sn != null && sn.isNotEmpty)
                                ? '${p.name} #$sn'
                                : p.name;
                            return (id: p.id, label: label);
                          }).toList(),
                          selectedId: _projectId,
                          allLabel: 'All Jobs',
                          onAllSelected: () {
                            setState(() {
                              final changed = _projectId != null;
                              _projectId = null;
                              if (changed) _propertyId = null;
                            });
                          },
                          onItemSelected: (id) {
                            setState(() {
                              final changed = id != _projectId;
                              _projectId = id;
                              if (changed) _propertyId = null;
                            });
                          },
                          searchHint: 'Search jobs...',
                        ),
                      ),
                    ],
                  ),
                  // ── Customer section ──
                  if (_sortedCustomers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildFilterSection(
                      icon: Icons.people_outline,
                      title: 'Customer',
                      subtitle: _customerId == null
                          ? 'All Customers'
                          : widget.customers[_customerId] ?? '',
                      isActive: _customerId != null,
                      initiallyExpanded: _customerId != null,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                          child: SearchableFilterChips(
                            items: _sortedCustomers
                                .map((e) => (id: e.key, label: e.value))
                                .toList(),
                            selectedId: _customerId,
                            allLabel: 'All Customers',
                            onAllSelected: () =>
                                setState(() => _customerId = null),
                            onItemSelected: (id) =>
                                setState(() => _customerId = id),
                            searchHint: 'Search customers...',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // ── Location section ──
                  if (_scopedProperties.isNotEmpty)
                    _buildFilterSection(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      subtitle: _propertyId == null
                          ? 'All Locations'
                          : _getSelectedPropertyLabel(),
                      isActive: _propertyId != null,
                      initiallyExpanded: true,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                          child: SearchableFilterChips(
                            items: _scopedProperties.map((p) {
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
                    ),
                  // ── Assignee section ──
                  if (_sortedUsers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildFilterSection(
                      icon: Icons.person_outline,
                      title: 'Assignee',
                      subtitle: _assigneeId == null
                          ? 'Anyone'
                          : widget.users[_assigneeId]?.displayName ??
                                widget.users[_assigneeId]?.email ??
                                '',
                      isActive: _assigneeId != null,
                      initiallyExpanded: _assigneeId != null,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
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
                    ),
                  ],
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
                ],
              ),
            ),
            // ── Footer ──
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onSaveView(_currentFilters()),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save View'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onApply(_currentFilters()),
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

  // ── Priority section (inline chips) ──
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

  // ── Due Date range section ──
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
                date != null ? _formatDate(date) : label,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            Icon(Icons.calendar_today, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _getSelectedProjectLabel() {
    final p = widget.projects.where((p) => p.id == _projectId).firstOrNull;
    if (p == null) return '';
    final sn = p.serialNumber?.trim();
    return (sn != null && sn.isNotEmpty) ? '${p.name} #$sn' : p.name;
  }

  String _getSelectedPropertyLabel() {
    final p = _scopedProperties.where((p) => p.id == _propertyId).firstOrNull;
    if (p == null) return '';
    return p.name.isNotEmpty
        ? (p.identifier.isNotEmpty ? '${p.name} (${p.identifier})' : p.name)
        : p.identifier;
  }

  Widget _buildFilterSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? AppColors.primary : AppColors.textTertiary,
            ),
          ),
          initiallyExpanded: initiallyExpanded,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: children,
        ),
      ),
    );
  }
}

/// Vertical draggable splitter that sits between the task list and the
/// map panel. Drag left/right to resize. A subtle hover/active highlight
/// makes the affordance discoverable without taking up space.
class _MapSplitterHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const _MapSplitterHandle({required this.onDrag});

  @override
  State<_MapSplitterHandle> createState() => _MapSplitterHandleState();
}

class _MapSplitterHandleState extends State<_MapSplitterHandle> {
  bool _hover = false;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = _active || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragEnd: (_) => setState(() => _active = false),
        onHorizontalDragCancel: () => setState(() => _active = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: highlight ? 4 : 2,
              decoration: BoxDecoration(
                color: highlight
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
