import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../models/gantt_task_extensions.dart';
import '../../models/user.dart';
import '../../models/schedule_baseline.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../utils/task_ical_export.dart';
import 'unified_gantt_row.dart';
import 'timeline_calculator.dart';
import 'gantt_toolbar.dart';
import '../task_assignee_avatars.dart';
import '../mass_edit_dialog.dart';
import '../table/table_column_schema.dart';
import '../table/table_header_cells_builder.dart';
import 'package:intl/intl.dart';

class UnifiedGanttWidget extends StatefulWidget {
  final Project? project;
  final List<Task> tasks;
  final Function(Task) onTaskTap;
  final String workspaceId;
  final Function(Task)? onTaskChanged;
  final Function(String, String?)? onTaskCreated;
  final Function(String, String?)?
  onGroupCreated; // For creating groups with parentId
  final Function(Task)? onTaskDelete;
  final Function(Task, TaskType)?
  onConvertTaskType; // For converting task to group or vice versa
  final VoidCallback? onAddTask;
  final VoidCallback? onAddGroup;
  final Function(Task)?
  onSaveAsTemplate; // Save a task/group (and its subtree) as a template
  final Function(String?)?
  onImportTemplate; // Import a task template; arg is the parent id (null = root)

  const UnifiedGanttWidget({
    super.key,
    this.project,
    required this.tasks,
    required this.onTaskTap,
    required this.workspaceId,
    this.onTaskChanged,
    this.onTaskCreated,
    this.onGroupCreated,
    this.onTaskDelete,
    this.onConvertTaskType,
    this.onAddTask,
    this.onAddGroup,
    this.onSaveAsTemplate,
    this.onImportTemplate,
  });

  @override
  State<UnifiedGanttWidget> createState() => UnifiedGanttWidgetState();
}

class UnifiedGanttWidgetState extends State<UnifiedGanttWidget> {
  static const List<TableColumnSchema> _desktopFixedHeaderColumns = [
    TableColumnSchema(
      id: 'activity',
      label: 'Activity',
      defaultWidth: 280,
      minWidth: 150,
      maxWidth: 500,
      align: TextAlign.center,
      resizable: true,
    ),
    TableColumnSchema(
      id: 'actions',
      label: 'Actions',
      defaultWidth: 100,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'start',
      label: 'Start',
      defaultWidth: 80,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'duration',
      label: 'Duration',
      defaultWidth: 70,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'end',
      label: 'End',
      defaultWidth: 120,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'progress',
      label: 'Progress',
      defaultWidth: 100,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'predecessors',
      label: 'Predecessors',
      defaultWidth: 100,
      align: TextAlign.center,
      resizable: false,
    ),
    TableColumnSchema(
      id: 'successors',
      label: 'Successors',
      defaultWidth: 100,
      align: TextAlign.center,
      resizable: false,
    ),
  ];

  static const List<TableColumnSchema> _mobileFixedHeaderColumns = [
    TableColumnSchema(
      id: 'activity',
      label: 'Activity',
      defaultWidth: 280,
      minWidth: 150,
      maxWidth: 500,
      align: TextAlign.center,
      resizable: true,
    ),
  ];
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _verticalTimelineScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _horizontalHeaderScrollController = ScrollController();
  final ScrollController _fixedColumnsHorizontalScrollController =
      ScrollController();
  final ScrollController _outerHorizontalScrollController = ScrollController();
  final _taskService = ServiceLocator.taskService;
  late TimelineCalculator _calculator;
  late DateTime _rangeStart;
  DateTime? _earliestTaskDate;
  DateTime? _latestTaskDate;

  void scrollToToday() => _scrollToDate(DateTime.now());

  /// Scroll to today when it falls within the task date range; otherwise
  /// scroll to the earliest task so the timeline doesn't open on an empty
  /// region when all tasks are far from the current date.
  void scrollToRelevantDate() {
    final today = DateTime.now();
    final earliest = _earliestTaskDate;
    final latest = _latestTaskDate;
    if (earliest != null &&
        (today.isBefore(earliest) ||
            (latest != null && today.isAfter(latest)))) {
      _scrollToDate(earliest);
    } else {
      scrollToToday();
    }
  }

  void _scrollToDate(DateTime date) {
    if (!_horizontalScrollController.hasClients) return;
    final daysDiff = date.difference(_rangeStart).inDays;
    final targetOffset = daysDiff * _calculator.pixelsPerDay;
    final viewportWidth =
        _horizontalScrollController.position.viewportDimension;
    final centeredOffset = targetOffset - (viewportWidth / 2);
    final maxOffset = _horizontalScrollController.position.maxScrollExtent;
    final clampedOffset = centeredOffset.clamp(0.0, maxOffset);
    _horizontalScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  String _currentView = 'Day'; // Default to Day view
  final double _rowHeight = 50.0;
  double _fixedColumnsWidth =
      695.0; // Adjustable width for fixed columns (positioned after End column)
  bool _isSidebarCollapsed = false;
  Map<String, AppUser> _usersMap =
      {}; // Map of user IDs to user objects for displaying avatars
  List<AppUser> _allWorkspaceUsers =
      []; // List of all workspace users for assignment popup
  bool _hideCompleted = false; // Filter to hide completed tasks
  bool _isAllCollapsed = false; // Track if all summary tasks are collapsed
  bool _showBusinessDaysOnly = false; // Workspace setting to hide weekends
  double? _activityColumnWidthOverride; // User-resized Activity column width
  bool _isTaskDraggingForUngroup = false;
  bool _isUngroupDropTargetActive = false;

  // Dependency linking state
  Task? _dependencySourceTask; // Task we're dragging from
  bool _dependencyFromEnd =
      false; // true = dragging from end anchor, false = from start
  Offset?
  _dependencyStartPosition; // Captured anchor position at drag start (local coords)
  Offset? _dependencyDragPosition; // Current drag position (local coords)
  Task? _dependencySnapTarget; // Task we're snapping to (if any)

  // Dependency hover state for deletion
  String? _hoveredDependencyKey; // Format: "predecessorId-successorId"

  // Auto-edit state: track which task should start in inline edit mode
  String? _autoEditTaskId;

  // Selection state for mass edit
  Set<String> _selectedTaskIds = {};


  // Schedule baseline state (project-scoped; unavailable on cross-project views)
  ScheduleBaseline? _baseline;
  Map<String, BaselineTaskDates> _baselineDates = {};
  bool _showBaseline = false;

  // When true, moving a task's end date also shifts its dependent tasks
  bool _cascadeShifts = true;

  // Mobile detection and responsive column widths
  bool get _isMobileView => MediaQuery.of(context).size.width < 768;
  double get _defaultActivityWidth => _isMobileView ? 206.0 : 275.0;
  double get _activityColumnWidth =>
      _activityColumnWidthOverride ?? _defaultActivityWidth;
  double get _leftSectionWidth => _isMobileView
      ? _activityColumnWidth +
            50.0 // Activity(var) + ID/Selection(50)
      : _activityColumnWidth +
            410.0; // Activity(var) + ID/Selection(50) + Actions(100) + Start(80) + Duration(70) + End(110)

  // Per-user expansion preferences (local cache, synced to Firestore)
  Map<String, bool> _userExpansionPrefs = {};
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initializeTimeline();
    _syncScrollControllers();
    _loadWorkspaceUsers();
    _loadUserExpansionPrefs();
    _loadHideCompletedPreference();
    _loadCascadeShiftsPreference();
    _loadBaseline();
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToRelevantDate());
  }

  Future<void> _loadUserExpansionPrefs() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      if (userId == null || widget.project?.id == null) return;

      _currentUserId = userId;
      final prefs = await _taskService.getUserTaskExpansionPreferences(
        userId,
        widget.project!.id,
      );
      if (mounted) {
        setState(() {
          _userExpansionPrefs = prefs;
        });
      }
    } catch (e) {
      debugPrint('Error loading user expansion preferences: $e');
    }
  }

  Future<void> _loadHideCompletedPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hideCompleted = prefs.getBool('gantt_hide_completed') ?? false;
      if (mounted) {
        setState(() {
          _hideCompleted = hideCompleted;
        });
      }
    } catch (e) {
      debugPrint('Error loading hide completed preference: $e');
    }
  }

  Future<void> _saveHideCompletedPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gantt_hide_completed', value);
    } catch (e) {
      debugPrint('Error saving hide completed preference: $e');
    }
  }

  Future<void> _loadCascadeShiftsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cascade = prefs.getBool('gantt_cascade_shifts') ?? true;
      if (mounted) {
        setState(() => _cascadeShifts = cascade);
      }
    } catch (e) {
      debugPrint('Error loading cascade shifts preference: $e');
    }
  }

  void _toggleCascadeShifts() {
    setState(() => _cascadeShifts = !_cascadeShifts);
    _savePref('gantt_cascade_shifts', _cascadeShifts);
  }

  Future<void> _savePref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('Error saving $key preference: $e');
    }
  }

  Future<void> _loadBaseline() async {
    final projectId = widget.project?.id;
    if (projectId == null) return;
    try {
      final baseline = await ServiceLocator.scheduleBaselineService
          .getLatestBaseline(projectId);
      if (baseline == null) return;
      final dates = await ServiceLocator.scheduleBaselineService
          .getBaselineTaskDates(baseline.id);
      final prefs = await SharedPreferences.getInstance();
      final show = prefs.getBool('gantt_show_baseline') ?? true;
      if (mounted) {
        setState(() {
          _baseline = baseline;
          _baselineDates = dates;
          _showBaseline = show;
        });
      }
    } catch (e) {
      debugPrint('Error loading schedule baseline: $e');
    }
  }

  Future<void> _handleSetBaseline() async {
    final project = widget.project;
    if (project == null) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final baseline =
          await ServiceLocator.scheduleBaselineService.captureBaseline(
        workspaceId: widget.workspaceId,
        projectId: project.id,
        tasks: widget.tasks,
        name: 'Baseline ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
        createdBy: authProvider.currentUserId,
      );
      final dates = await ServiceLocator.scheduleBaselineService
          .getBaselineTaskDates(baseline.id);
      if (!mounted) return;
      setState(() {
        _baseline = baseline;
        _baselineDates = dates;
        _showBaseline = true;
      });
      _savePref('gantt_show_baseline', true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Baseline captured (${dates.length} tasks)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'capture the baseline'),
          ),
        ),
      );
    }
  }

  void _toggleShowBaseline() {
    setState(() => _showBaseline = !_showBaseline);
    _savePref('gantt_show_baseline', _showBaseline);
  }

  Future<void> _handleExportIcal() async {
    try {
      await TaskIcalExport.exportSchedule(
        tasks: widget.tasks,
        calendarName: widget.project?.name ?? 'Schedule',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'export the schedule'),
          ),
        ),
      );
    }
  }

  /// Row-level task change handler. Persists the change, then — when cascade
  /// is enabled and the task's end date moved — shifts every transitive
  /// dependent (finish-to-start semantics) by the same number of days.
  void _handleRowTaskChanged(Task updated) {
    Task? original;
    for (final t in widget.tasks) {
      if (t.id == updated.id) {
        original = t;
        break;
      }
    }
    widget.onTaskChanged?.call(updated);

    if (!_cascadeShifts || original == null) return;
    final oldEnd = original.dueDate;
    final newEnd = updated.dueDate;
    if (oldEnd == null || newEnd == null) return;
    final deltaDays = DateTime(newEnd.year, newEnd.month, newEnd.day)
        .difference(DateTime(oldEnd.year, oldEnd.month, oldEnd.day))
        .inDays;
    if (deltaDays == 0) return;

    final shifted = _shiftDependents(updated.id, deltaDays);
    if (shifted > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shifted $shifted dependent task${shifted == 1 ? '' : 's'} by '
            '${deltaDays.abs()} day${deltaDays.abs() == 1 ? '' : 's'} '
            '${deltaDays > 0 ? 'later' : 'earlier'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Shift all transitive successors of [taskId] by [deltaDays].
  /// Summary successors are shifted via their members (their own dates are
  /// derived from children). Returns the number of tasks moved.
  int _shiftDependents(String taskId, int deltaDays) {
    final visited = <String>{taskId};
    final queue = <String>[taskId];
    var shifted = 0;

    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      for (final t in widget.tasks) {
        if (!t.predecessorIds.contains(id) || visited.contains(t.id)) continue;
        visited.add(t.id);
        queue.add(t.id);
        if (t.taskType == TaskType.summary) {
          for (final member in t.getDescendants(widget.tasks)) {
            if (visited.contains(member.id)) continue;
            visited.add(member.id);
            queue.add(member.id);
            if (_shiftTaskDates(member, deltaDays)) shifted++;
          }
        } else {
          if (_shiftTaskDates(t, deltaDays)) shifted++;
        }
      }
    }
    return shifted;
  }

  bool _shiftTaskDates(Task task, int deltaDays) {
    if (task.startDate == null && task.dueDate == null) return false;
    widget.onTaskChanged?.call(
      task.copyWith(
        startDate: task.startDate?.add(Duration(days: deltaDays)),
        dueDate: task.dueDate?.add(Duration(days: deltaDays)),
      ),
    );
    return true;
  }

  /// A summary bar was dragged: shift every dated descendant by [deltaDays],
  /// then cascade to the group's own dependents when enabled.
  void _handleGroupShifted(Task group, int deltaDays) {
    if (deltaDays == 0) return;
    var shifted = 0;
    final memberIds = <String>{group.id};
    for (final member in group.getDescendants(widget.tasks)) {
      memberIds.add(member.id);
      if (_shiftTaskDates(member, deltaDays)) shifted++;
    }
    if (_cascadeShifts) {
      shifted += _shiftDependents(group.id, deltaDays);
    }
    if (shifted > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shifted "${group.title}" — $shifted task'
            '${shifted == 1 ? '' : 's'} moved '
            '${deltaDays.abs()} day${deltaDays.abs() == 1 ? '' : 's'} '
            '${deltaDays > 0 ? 'later' : 'earlier'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Create a TimelineCalculator with current settings
  TimelineCalculator _createCalculator(TimelineView viewMode) {
    return TimelineCalculator(
      viewMode: viewMode,
      anchorDate: DateTime.now(),
      showBusinessDaysOnly: _showBusinessDaysOnly,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadWorkspaceBusinessDaysSetting();
  }

  void _loadWorkspaceBusinessDaysSetting() {
    final workspaceProvider = Provider.of<WorkspaceProvider>(
      context,
      listen: false,
    );
    final showBusinessDaysOnly = workspaceProvider.showBusinessDaysOnly;
    if (showBusinessDaysOnly != _showBusinessDaysOnly) {
      setState(() {
        _showBusinessDaysOnly = showBusinessDaysOnly;
        // Recreate calculator with new setting
        _calculator = _createCalculator(_getTimelineView(_currentView));
      });
    }
  }

  /// Check if a task is expanded (using per-user preferences with fallback to default)
  bool _isTaskExpanded(Task task) {
    // First check user preferences
    if (_userExpansionPrefs.containsKey(task.id)) {
      final result = _userExpansionPrefs[task.id]!;
      // debugPrint('_isTaskExpanded(${task.title}): using pref = $result');
      return result;
    }
    // Fallback to task's default (from task.isExpanded field, defaults to true)
    // debugPrint('_isTaskExpanded(${task.title}): using task default = ${task.isExpanded}');
    return task.isExpanded;
  }

  /// Flatten task tree respecting per-user expansion preferences
  /// This must be used for any position-based calculations (like dependency drag snap)
  /// to ensure the flattened list matches the visually displayed rows.
  List<Task> _flattenTaskTreeWithUserPrefs(List<Task> tasks) {
    final flattened = <Task>[];

    // Get root tasks (no parent)
    final roots = tasks.where((task) => task.parentId == null).toList();
    roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    void addTaskAndChildren(Task task) {
      flattened.add(task);

      // Use _isTaskExpanded instead of task.isExpanded to respect per-user preferences
      if (_isTaskExpanded(task)) {
        final children = tasks.where((t) => t.parentId == task.id).toList();
        children.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        for (final child in children) {
          addTaskAndChildren(child);
        }
      }
    }

    for (final root in roots) {
      addTaskAndChildren(root);
    }

    return flattened;
  }

  Future<void> _loadWorkspaceUsers() async {
    try {
      final userService = ServiceLocator.userService;
      final memberService = ServiceLocator.workspaceMemberService;

      // Use ServiceLocator to get the correct backend service (Firebase or Supabase)
      final members = await memberService
          .getWorkspaceMembers(widget.workspaceId)
          .first;

      final Map<String, AppUser> usersMap = {};
      final List<AppUser> usersList = [];

      for (final member in members) {
        final userId = member.userId;
        final user = await userService.getUserById(userId);
        if (user != null) {
          usersMap[user.id] = user;
          usersList.add(user);
        }
      }
      if (mounted) {
        setState(() {
          _usersMap = usersMap;
          _allWorkspaceUsers = usersList;
        });
      }
    } catch (_) {
      // Silently fail - avatars just won't show
    }
  }

  void _syncScrollControllers() {
    // Sync header scroll with body scroll (horizontal)
    _horizontalScrollController.addListener(() {
      if (_horizontalHeaderScrollController.hasClients) {
        _horizontalHeaderScrollController.jumpTo(
          _horizontalScrollController.offset,
        );
      }
    });

    // Sync timeline vertical scroll with fixed columns scroll (bidirectional)
    bool isSyncingVertical = false;
    _verticalScrollController.addListener(() {
      if (isSyncingVertical) return;
      if (_verticalTimelineScrollController.hasClients) {
        isSyncingVertical = true;
        _verticalTimelineScrollController.jumpTo(
          _verticalScrollController.offset,
        );
        isSyncingVertical = false;
      }
    });

    _verticalTimelineScrollController.addListener(() {
      if (isSyncingVertical) return;
      if (_verticalScrollController.hasClients) {
        isSyncingVertical = true;
        _verticalScrollController.jumpTo(
          _verticalTimelineScrollController.offset,
        );
        isSyncingVertical = false;
      }
    });
  }

  void _initializeTimeline() {
    final today = DateTime.now();

    // Find the earliest start date and latest end date from tasks
    DateTime? earliestStart;
    DateTime? latestEnd;

    for (final task in widget.tasks) {
      if (task.startDate != null) {
        if (earliestStart == null || task.startDate!.isBefore(earliestStart)) {
          earliestStart = task.startDate;
        }
      }
      if (task.dueDate != null) {
        if (latestEnd == null || task.dueDate!.isAfter(latestEnd)) {
          latestEnd = task.dueDate;
        }
      }
    }

    _earliestTaskDate = earliestStart;
    _latestTaskDate = latestEnd;

    // Start from 1 day before the earliest task, or current date if no tasks
    if (earliestStart != null) {
      _rangeStart = earliestStart.subtract(const Duration(days: 1));
    } else {
      _rangeStart = today;
    }

    _calculator = _createCalculator(TimelineView.month);
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _verticalTimelineScrollController.dispose();
    _horizontalScrollController.dispose();
    _horizontalHeaderScrollController.dispose();
    _fixedColumnsHorizontalScrollController.dispose();
    super.dispose();
  }

  /// Handle drag-and-drop reparenting of tasks
  Future<void> _handleTaskParentChanged(Task task, String? newParentId) async {
    try {
      await ServiceLocator.taskService.updateTask(
        taskId: task.id,
        parentId: newParentId,
        clearParentId: newParentId == null,
      );

      // Show feedback
      if (mounted) {
        final parentName = newParentId != null
            ? widget.tasks
                  .firstWhere((t) => t.id == newParentId, orElse: () => task)
                  .title
            : 'root';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved "${task.title}" under "$parentName"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move task: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Handle cloning a task or group
  Future<void> _handleTaskClone(Task task) async {
    try {
      await _taskService.cloneTask(
        task: task,
        allTasks: widget.tasks,
        cloneChildren: true,
      );

      // Show feedback
      if (mounted) {
        final isGroup = task.taskType == TaskType.summary;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isGroup
                  ? 'Cloned phase "${task.title}" with all children'
                  : 'Cloned task "${task.title}"',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clone: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Wrapper for task creation that enables auto-edit mode on the new task
  /// This tracks the parent ID and looks for the newest matching child to auto-edit
  String? _pendingAutoEditParentId;
  Set<String> _previousTaskIds = {};

  void _handleTaskCreatedWithAutoEdit(String title, String? parentId) {
    // Track that we want to auto-edit the child of this parent
    // Store current task IDs so we can detect the new one
    _previousTaskIds = widget.tasks.map((t) => t.id).toSet();

    setState(() {
      _pendingAutoEditParentId = parentId;
    });

    // Call the original callback if provided
    if (widget.onTaskCreated != null) {
      widget.onTaskCreated!(title, parentId);
    }
  }

  @override
  void didUpdateWidget(UnifiedGanttWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if we're waiting for a new task to auto-edit
    if (_pendingAutoEditParentId != null) {
      // Find new tasks that weren't in the previous set
      final newTasks = widget.tasks
          .where(
            (t) =>
                !_previousTaskIds.contains(t.id) &&
                t.parentId == _pendingAutoEditParentId,
          )
          .toList();

      if (newTasks.isNotEmpty) {
        // Sort by creation date and take the newest
        newTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final newTask = newTasks.first;

        setState(() {
          _autoEditTaskId = newTask.id;
          _pendingAutoEditParentId = null;
          _previousTaskIds = {};
        });
      }
    }
  }

  void _clearAutoEdit() {
    setState(() {
      _autoEditTaskId = null;
    });
  }

  void _onTaskDragStarted() {
    if (!_isTaskDraggingForUngroup) {
      setState(() => _isTaskDraggingForUngroup = true);
    }
  }

  void _onTaskDragEnded() {
    if (_isTaskDraggingForUngroup || _isUngroupDropTargetActive) {
      setState(() {
        _isTaskDraggingForUngroup = false;
        _isUngroupDropTargetActive = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apply filters to tasks
    var filteredTasks = widget.tasks;
    if (_hideCompleted) {
      filteredTasks = filteredTasks
          .where((t) => !t.isComplete && t.progress < 100)
          .toList();
    }
    final flattenedTasks = _flattenTaskTreeWithUserPrefs(filteredTasks);

    return Listener(
      // Capture pointer moves at widget level during dependency drag
      onPointerMove: _dependencySourceTask != null
          ? (event) {
              _handleDependencyDragUpdate(event.position);
            }
          : null,
      onPointerUp: _dependencySourceTask != null
          ? (event) {
              _handleDependencyDragEnd();
            }
          : null,
      child: Stack(
        children: [
          // Main content
          Column(
            children: [
              // Toolbar
              GanttToolbar(
                currentView: _currentView,
                hideCompleted: _hideCompleted,
                onScrollToToday: scrollToToday,
                isAtMaxZoom: _currentView == 'Day',
                isAtMinZoom: _currentView == 'Year',
                cascadeShifts: _cascadeShifts,
                onToggleCascadeShifts: _toggleCascadeShifts,
                hasBaseline: _baseline != null,
                showBaseline: _showBaseline,
                onSetBaseline:
                    widget.project != null ? _handleSetBaseline : null,
                onToggleShowBaseline:
                    widget.project != null ? _toggleShowBaseline : null,
                onExportIcal: _handleExportIcal,
                onViewChanged: (view) {
                  final prevOffset = _verticalScrollController.hasClients
                      ? _verticalScrollController.offset
                      : 0.0;
                  setState(() {
                    _currentView = view;
                    _calculator = _createCalculator(_getTimelineView(view));
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_verticalTimelineScrollController.hasClients) {
                      _verticalTimelineScrollController.jumpTo(prevOffset.clamp(
                        0.0,
                        _verticalTimelineScrollController.position.maxScrollExtent,
                      ));
                    }
                    scrollToToday();
                  });
                },
                onZoomIn: () {
                  if (_currentView == 'Day') return;
                  final prevOffset = _verticalScrollController.hasClients
                      ? _verticalScrollController.offset
                      : 0.0;
                  setState(() {
                    // Zoom in: Year -> Quarter -> Month -> Week -> Day
                    switch (_currentView) {
                      case 'Year':
                        _currentView = 'Quarter';
                        break;
                      case 'Quarter':
                        _currentView = 'Month';
                        break;
                      case 'Month':
                        _currentView = 'Week';
                        break;
                      case 'Week':
                        _currentView = 'Day';
                        break;
                    }
                    _calculator = _createCalculator(
                      _getTimelineView(_currentView),
                    );
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_verticalTimelineScrollController.hasClients) {
                      _verticalTimelineScrollController.jumpTo(prevOffset.clamp(
                        0.0,
                        _verticalTimelineScrollController.position.maxScrollExtent,
                      ));
                    }
                    scrollToToday();
                  });
                },
                onZoomOut: () {
                  if (_currentView == 'Year') return;
                  final prevOffset = _verticalScrollController.hasClients
                      ? _verticalScrollController.offset
                      : 0.0;
                  setState(() {
                    // Zoom out: Day -> Week -> Month -> Quarter -> Year
                    switch (_currentView) {
                      case 'Day':
                        _currentView = 'Week';
                        break;
                      case 'Week':
                        _currentView = 'Month';
                        break;
                      case 'Month':
                        _currentView = 'Quarter';
                        break;
                      case 'Quarter':
                        _currentView = 'Year';
                        break;
                    }
                    _calculator = _createCalculator(
                      _getTimelineView(_currentView),
                    );
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_verticalTimelineScrollController.hasClients) {
                      _verticalTimelineScrollController.jumpTo(prevOffset.clamp(
                        0.0,
                        _verticalTimelineScrollController.position.maxScrollExtent,
                      ));
                    }
                    scrollToToday();
                  });
                },
                onFilter: () {
                  final newValue = !_hideCompleted;
                  setState(() {
                    _hideCompleted = newValue;
                  });
                  _saveHideCompletedPreference(newValue);
                },
                onCollapseAll: _handleCollapseAll,
                onExpandAll: _handleExpandAll,
                isAllCollapsed: _isAllCollapsed,
                onAddTask: widget.onAddTask,
                onAddGroup: widget.onAddGroup,
                onMassEdit: _selectedTaskIds.isNotEmpty
                    ? _handleMassEdit
                    : null,
                selectedCount: _selectedTaskIds.length,
              ),

              // Split layout: Fixed columns (left) + Scrollable timeline (right)
              Expanded(
                child: Container(
                  margin: ChromeColors.of(context).isDark
                      ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
                      : EdgeInsets.zero,
                  clipBehavior: ChromeColors.of(context).isDark
                      ? Clip.antiAlias
                      : Clip.none,
                  decoration: ChromeColors.of(context).isDark
                      ? BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x30000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        )
                      : const BoxDecoration(),
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (event) {
                            final e = event as PointerScrollEvent;
                            if (e.scrollDelta.dx != 0 &&
                                _horizontalScrollController.hasClients) {
                              final newX = (_horizontalScrollController.offset +
                                      e.scrollDelta.dx)
                                  .clamp(
                                    0.0,
                                    _horizontalScrollController
                                        .position.maxScrollExtent,
                                  );
                              _horizontalScrollController.jumpTo(newX);
                            }
                            if (e.scrollDelta.dy != 0 &&
                                _verticalScrollController.hasClients) {
                              final newY = (_verticalScrollController.offset +
                                      e.scrollDelta.dy)
                                  .clamp(
                                    0.0,
                                    _verticalScrollController
                                        .position.maxScrollExtent,
                                  );
                              _verticalScrollController.jumpTo(newY);
                            }
                          },
                        );
                      }
                    },
                    child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _outerHorizontalScrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fixed Columns Section
                      if (!_isSidebarCollapsed)
                        ClipRect(
                          child: SizedBox(
                            width: _isMobileView ? _leftSectionWidth : _fixedColumnsWidth,
                            child: Column(
                              children: [
                                // Header for fixed columns
                                SizedBox(
                                  height: _rowHeight,
                                  child: _buildFixedColumnsHeader(),
                                ),
                                // Rows for fixed columns
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return ScrollbarTheme(
                                        data: ScrollbarThemeData(
                                          thumbColor: WidgetStateProperty.all(
                                            AppColors.textTertiary,
                                          ),
                                          trackColor: WidgetStateProperty.all(
                                            AppColors.cardBorder,
                                          ),
                                          thickness: WidgetStateProperty.all(
                                            8.0,
                                          ),
                                          radius: const Radius.circular(4),
                                        ),
                                        child: Scrollbar(
                                          controller:
                                              _fixedColumnsHorizontalScrollController,
                                          thumbVisibility: true,
                                          trackVisibility: true,
                                          notificationPredicate:
                                              (notification) =>
                                                  notification.depth == 0,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller:
                                                _fixedColumnsHorizontalScrollController,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minWidth:
                                                    _leftSectionWidth, // Dynamic min width based on Activity column
                                              ),
                                              child: SizedBox(
                                                width: _isMobileView
                                                    ? _leftSectionWidth
                                                    : _fixedColumnsWidth, // Match the panel width to remove padding
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.vertical,
                                                  controller:
                                                      _verticalScrollController,
                                                  physics:
                                                      const ClampingScrollPhysics(),
                                                  child: Column(
                                                    children: [
                                                      for (
                                                        int i = 0;
                                                        i <
                                                            _buildItemCount(
                                                              flattenedTasks,
                                                            );
                                                        i++
                                                      )
                                                        _isMobileView
                                                            ? _buildLeftColumnsRow(
                                                                flattenedTasks,
                                                                i,
                                                              )
                                                            : _buildFixedColumnsRow(
                                                                flattenedTasks,
                                                                i,
                                                              ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Draggable Divider with Collapse Button
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            if (_isSidebarCollapsed)
                              return; // Disable resizing when collapsed
                            setState(() {
                              _fixedColumnsWidth += details.delta.dx;
                              if (_fixedColumnsWidth < 200)
                                _fixedColumnsWidth = 200;
                              if (_fixedColumnsWidth > 800)
                                _fixedColumnsWidth = 800;
                            });
                          },
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              Container(
                                width: 10, // Width of the divider
                                color: AppColors.cardBorder,
                                child: const Center(
                                  child: VerticalDivider(
                                    thickness: 1,
                                    width: 1,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                              // Collapse/Expand Button
                              Positioned(
                                top: 0,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isSidebarCollapsed =
                                          !_isSidebarCollapsed;
                                    });
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBorder,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                    child: Icon(
                                      _isSidebarCollapsed
                                          ? Icons.chevron_right
                                          : Icons.chevron_left,
                                      size: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // RIGHT SECTION: Timeline (horizontally scrollable)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Calculate timeline width based on available space
                          // On desktop: fill remaining space (like Expanded used to)
                          // On mobile: use minimum width to ensure scrolling works
                          final leftSectionWidth = _isSidebarCollapsed
                              ? 0.0
                              : (_isMobileView ? _leftSectionWidth : _fixedColumnsWidth);
                          final dividerWidth = 10.0;

                          // Get the outer scrollview's viewport width
                          // This is essentially the screen width
                          final viewportWidth = MediaQuery.of(
                            context,
                          ).size.width;

                          // Calculate available width for timeline
                          final availableWidth =
                              viewportWidth - leftSectionWidth - dividerWidth;

                          // Use the larger of: available width or 600px minimum
                          // This ensures on desktop it fills the screen, on mobile it's scrollable
                          final timelineWidth = availableWidth > 600
                              ? availableWidth
                              : 600.0;

                          return SizedBox(
                            width: timelineWidth,
                            child: ClipRect(
                              child: Column(
                                children: [
                                  // Timeline header
                                  SizedBox(
                                    height: 50,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      controller:
                                          _horizontalHeaderScrollController,
                                      physics:
                                          const NeverScrollableScrollPhysics(), // Disable direct scrolling
                                      child: SizedBox(
                                        width:
                                            _calculator.pixelsPerDay *
                                            _calculator.totalBusinessDaysInYear,
                                        child: _buildTimelineHeader(),
                                      ),
                                    ),
                                  ),

                                  // Timeline body with scrollbar
                                  Expanded(
                                    child: ScrollbarTheme(
                                      data: ScrollbarThemeData(
                                        thumbVisibility:
                                            WidgetStateProperty.all(true),
                                        trackVisibility:
                                            WidgetStateProperty.all(true),
                                        thickness: WidgetStateProperty.all(12),
                                        radius: const Radius.circular(6),
                                        thumbColor: WidgetStateProperty.all(
                                          AppColors.textSecondary,
                                        ),
                                        trackColor: WidgetStateProperty.all(
                                          AppColors.cardBorder,
                                        ),
                                      ),
                                      child: Scrollbar(
                                        controller: _horizontalScrollController,
                                        thumbVisibility: true,
                                        trackVisibility: true,
                                        thickness: 12,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          controller:
                                              _horizontalScrollController,
                                          child: SizedBox(
                                            width:
                                                _calculator.pixelsPerDay *
                                                _calculator
                                                    .totalBusinessDaysInYear,
                                            child: SingleChildScrollView(
                                              controller:
                                                  _verticalTimelineScrollController,
                                              physics:
                                                  const ClampingScrollPhysics(), // Synced bidirectionally with left
                                              child: Stack(
                                                children: [
                                                  // Timeline rows
                                                  Column(
                                                    children: List.generate(
                                                      _buildItemCount(
                                                        flattenedTasks,
                                                      ),
                                                      (index) =>
                                                          _buildTimelineRow(
                                                            flattenedTasks,
                                                            index,
                                                          ),
                                                    ),
                                                  ),
                                                  // Today vertical line indicator
                                                  Builder(
                                                    builder: (context) {
                                                      final todayX = _calculator.dateToPixel(
                                                        DateTime.now(),
                                                        _rangeStart,
                                                      );
                                                      return Positioned(
                                                        left: todayX - 12,
                                                        top: 0,
                                                        bottom: 0,
                                                        child: Column(
                                                          children: [
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: AppColors.error,
                                                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                                              ),
                                                              child: const Text(
                                                                'Today',
                                                                style: TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 9,
                                                                  fontWeight: FontWeight.w600,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Expanded(
                                                              child: Container(
                                                                width: 2,
                                                                color: AppColors.error.withValues(alpha: 0.6),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),

                                                  // Project end date vertical line indicator
                                                  if (widget
                                                          .project
                                                          ?.targetCompletionDate !=
                                                      null)
                                                    Builder(
                                                      builder: (context) {
                                                        // Check if any task extends past the target date
                                                        final targetDate = widget
                                                            .project!
                                                            .targetCompletionDate!;
                                                        final hasTasksPastTarget =
                                                            widget.tasks.any(
                                                              (task) =>
                                                                  task.dueDate !=
                                                                      null &&
                                                                  task.dueDate!
                                                                      .isAfter(
                                                                        targetDate,
                                                                      ),
                                                            );

                                                        // Use red if tasks are past target, green otherwise
                                                        final indicatorColor =
                                                            hasTasksPastTarget
                                                            ? Colors
                                                                  .red
                                                                  .shade400
                                                            : Colors
                                                                  .green
                                                                  .shade500;

                                                        return Positioned(
                                                          left:
                                                              _getTargetDatePosition() -
                                                              25, // Center the label on the target date
                                                          top: 0,
                                                          bottom: 0,
                                                          child: Column(
                                                            children: [
                                                              // Pill label at top
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          3,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      indicatorColor,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10,
                                                                      ),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: indicatorColor.withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                      blurRadius:
                                                                          4,
                                                                      offset:
                                                                          const Offset(
                                                                            0,
                                                                            2,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                child: const Text(
                                                                  'Target',
                                                                  style: TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              // Dashed vertical line
                                                              Expanded(
                                                                child: SizedBox(
                                                                  width: 2,
                                                                  child: CustomPaint(
                                                                    painter:
                                                                        _DashedLinePainter(
                                                                          color:
                                                                              indicatorColor,
                                                                        ),
                                                                    size: const Size(
                                                                      2,
                                                                      double
                                                                          .infinity,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),


                                                  // Dependency lines overlay (permanent lines for existing dependencies)
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      child: CustomPaint(
                                                        painter: DependencyOverlayPainter(
                                                          tasks: flattenedTasks,
                                                          allTasks:
                                                              widget.tasks,
                                                          calculator:
                                                              _calculator,
                                                          rangeStart:
                                                              _rangeStart,
                                                          rowHeight: _rowHeight,
                                                          horizontalScrollOffset:
                                                              0,
                                                          verticalScrollOffset:
                                                              0,
                                                          fixedColumnsWidth: 0,
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                  // Delete buttons for dependencies
                                                  ...flattenedTasks.expand((
                                                    task,
                                                  ) {
                                                    if (task
                                                        .predecessorIds
                                                        .isEmpty)
                                                      return <Widget>[];

                                                    return task.predecessorIds.map((
                                                      predId,
                                                    ) {
                                                      final predTask = widget
                                                          .tasks
                                                          .firstWhere(
                                                            (t) =>
                                                                t.id == predId,
                                                            orElse: () => task,
                                                          );
                                                      if (predTask.id ==
                                                          task.id)
                                                        return const SizedBox.shrink();

                                                      final predIndex =
                                                          flattenedTasks
                                                              .indexOf(
                                                                predTask,
                                                              );
                                                      final taskIndex =
                                                          flattenedTasks
                                                              .indexOf(task);
                                                      if (predIndex < 0 ||
                                                          taskIndex < 0)
                                                        return const SizedBox.shrink();

                                                      // Calculate positions using same logic as DependencyOverlayPainter
                                                      final taskBarCenterOffset =
                                                          12.0 + 12.0;
                                                      final predY =
                                                          (predIndex *
                                                              _rowHeight) +
                                                          taskBarCenterOffset;
                                                      final currentY =
                                                          (taskIndex *
                                                              _rowHeight) +
                                                          taskBarCenterOffset;

                                                      // Get predecessor end position
                                                      final predTaskPosition =
                                                          _calculator
                                                              .getTaskPosition(
                                                                predTask
                                                                    .startDate,
                                                                predTask
                                                                    .dueDate,
                                                                _rangeStart,
                                                              );
                                                      final predTaskWidth =
                                                          _calculator.getTaskWidth(
                                                            predTask.startDate,
                                                            predTask.dueDate,
                                                            predTask
                                                                .estimatedDuration,
                                                          );
                                                      final predEndX =
                                                          predTaskPosition +
                                                          predTaskWidth +
                                                          18;

                                                      // Get current task start position
                                                      final currentTaskPosition =
                                                          _calculator
                                                              .getTaskPosition(
                                                                task.startDate,
                                                                task.dueDate,
                                                                _rangeStart,
                                                              );
                                                      final currentStartX =
                                                          currentTaskPosition +
                                                          18;

                                                      // Calculate routing (same as DependencyOverlayPainter)
                                                      final verticalX =
                                                          predEndX + 20;
                                                      final needsExtraRouting =
                                                          currentStartX <
                                                          verticalX;

                                                      double buttonX, buttonY;
                                                      if (needsExtraRouting) {
                                                        // Complex routing - put button on the middle vertical segment
                                                        final goingDown =
                                                            currentY > predY;
                                                        final routeY = goingDown
                                                            ? predY +
                                                                  (_rowHeight /
                                                                      2) +
                                                                  5
                                                            : predY -
                                                                  (_rowHeight /
                                                                      2) -
                                                                  5;
                                                        // Button on horizontal routing segment
                                                        buttonX =
                                                            (verticalX +
                                                                (currentStartX -
                                                                    20)) /
                                                            2;
                                                        buttonY = routeY;
                                                      } else {
                                                        // Simple routing - put button on the vertical segment
                                                        buttonX = verticalX;
                                                        buttonY =
                                                            (predY + currentY) /
                                                            2;
                                                      }

                                                      final dependencyKey =
                                                          '${predTask.id}-${task.id}';
                                                      final isHovered =
                                                          _hoveredDependencyKey ==
                                                          dependencyKey;

                                                      // Use a larger hover area around the delete button for easier discovery
                                                      return Positioned(
                                                        left: buttonX - 25,
                                                        top: buttonY - 25,
                                                        child: MouseRegion(
                                                          onEnter: (_) => setState(
                                                            () => _hoveredDependencyKey =
                                                                dependencyKey,
                                                          ),
                                                          onExit: (_) => setState(
                                                            () =>
                                                                _hoveredDependencyKey =
                                                                    null,
                                                          ),
                                                          child: SizedBox(
                                                            width: 50,
                                                            height: 50,
                                                            child: Center(
                                                              child: AnimatedOpacity(
                                                                opacity:
                                                                    isHovered
                                                                    ? 1.0
                                                                    : 0.0,
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          150,
                                                                    ),
                                                                child: GestureDetector(
                                                                  onTap: () =>
                                                                      _handleDeleteDependency(
                                                                        task.id,
                                                                        predTask
                                                                            .id,
                                                                      ),
                                                                  child: Container(
                                                                    width: 20,
                                                                    height: 20,
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .red,
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      boxShadow: [
                                                                        BoxShadow(
                                                                          color: Colors.black.withValues(
                                                                            alpha:
                                                                                0.2,
                                                                          ),
                                                                          blurRadius:
                                                                              3,
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    child: const Icon(
                                                                      Icons
                                                                          .close,
                                                                      size: 14,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList();
                                                  }),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              ),
              ),
            ], // End Column children
          ), // End Column
          if (_isTaskDraggingForUngroup)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: DragTarget<Task>(
                onWillAcceptWithDetails: (_) => true,
                onAcceptWithDetails: (details) {
                  setState(() {
                    _isUngroupDropTargetActive = false;
                    _isTaskDraggingForUngroup = false;
                  });
                  _handleTaskParentChanged(details.data, null);
                },
                onMove: (_) {
                  if (!_isUngroupDropTargetActive) {
                    setState(() => _isUngroupDropTargetActive = true);
                  }
                },
                onLeave: (_) {
                  if (_isUngroupDropTargetActive) {
                    setState(() => _isUngroupDropTargetActive = false);
                  }
                },
                builder: (context, _, __) {
                  final isActive = _isUngroupDropTargetActive;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.info.withValues(alpha: 0.14)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                      border: Border.all(
                        color: isActive
                            ? AppColors.info
                            : AppColors.textTertiary,
                        width: isActive ? 2 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive ? Icons.move_up : Icons.outbox_outlined,
                          size: 18,
                          color: isActive
                              ? AppColors.info
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isActive
                              ? 'Release to move out of phase'
                              : 'Move out of phase',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? AppColors.info
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          // Ghost line overlay during dependency drag
          if (_dependencySourceTask != null && _dependencyDragPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DependencyGhostLinePainter(
                    startPoint: _dependencyStartPosition,
                    endPoint: _dependencyDragPosition,
                    hasSnapTarget: _dependencySnapTarget != null,
                  ),
                ),
              ),
            ),
        ], // End Stack children
      ), // End Stack
    ); // End Listener
  }

  int _buildItemCount(List<Task> flattenedTasks) {
    int count = 1; // Project summary row at top
    for (final _ in flattenedTasks) {
      count++; // The task row itself
    }
    count++; // Root level input row
    return count;
  }

  // Build ONLY the fixed columns header
  Widget _buildFixedColumnsHeader() {
    // On mobile, only show left section (Activity + Actions)
    // On desktop, show all columns
    if (_isMobileView) {
      return _buildLeftFixedColumnsHeader();
    }

    return Container(
      height: 50,
      decoration: const BoxDecoration(
        // Slightly darker light grey for modern look
        color: Color(0xFFF3F4F6),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          _buildSelectionHeaderCell(width: 50, showLabel: true),
          ..._buildFixedHeaderCells(_desktopFixedHeaderColumns),
        ],
      ),
    );
  }

  // Left section header for mobile: Activity + Actions
  Widget _buildLeftFixedColumnsHeader() {
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          _buildSelectionHeaderCell(width: 50, showLabel: true),
          ..._buildFixedHeaderCells(_mobileFixedHeaderColumns),
        ],
      ),
    );
  }

  List<Widget> _buildFixedHeaderCells(List<TableColumnSchema> columns) {
    final widths = <String, double>{
      for (final column in columns) column.id: column.defaultWidth,
      'activity': _activityColumnWidth,
    };
    return buildTableHeaderCells(
      context: context,
      columns: columns,
      widths: widths,
      onColumnResize: (resize) {
        if (resize.columnId != 'activity') return;
        setState(() {
          _activityColumnWidthOverride = resize.width;
        });
      },
      textStyle: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      dividerColor: Theme.of(context).dividerColor,
    );
  }

  // Build ONLY the fixed columns part of a row
  Widget _buildFixedColumnsRow(List<Task> flattenedTasks, int index) {
    // Index 0 is the project summary row
    if (index == 0) {
      return _buildProjectSummaryRowFixedColumns();
    }

    // Adjust index for tasks (subtract 1 for project summary row)
    final adjustedIndex = index - 1;

    int currentIndex = 0;
    for (int i = 0; i < flattenedTasks.length; i++) {
      final task = flattenedTasks[i];

      if (currentIndex == adjustedIndex) {
        // Return UnifiedGanttRow but configured to show only fixed columns
        return UnifiedGanttRow(
          task: task,
          allTasks: widget.tasks,
          rowIndex: i,
          calculator: _calculator,
          rangeStart: _rangeStart,
          rowHeight: _rowHeight,
          onTaskTap: widget.onTaskTap,
          onExpandToggle: _handleExpandToggle,
          isExpanded: _isTaskExpanded(task),
          onTaskChanged: _handleRowTaskChanged,
          onGroupShifted: _handleGroupShifted,
          onTaskCreated: _handleTaskCreatedWithAutoEdit,
          onGroupCreated: widget.onGroupCreated,
          onTaskDelete: widget.onTaskDelete,
          onConvertTaskType: widget.onConvertTaskType,
          onTaskClone: _handleTaskClone,
          onScrollToTask: _handleScrollToTask,
          onTaskParentChanged: _handleTaskParentChanged,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          onSaveAsTemplate: widget.onSaveAsTemplate,
          onImportTemplate: widget.onImportTemplate,
          showFixedColumnsOnly: true, // NEW PARAMETER
          usersMap: _usersMap,
          allWorkspaceUsers: _allWorkspaceUsers,
          activityColumnWidth: _activityColumnWidth,
          onDependencyDragStart: _handleDependencyDragStart,
          onDependencyDragUpdate: _handleDependencyDragUpdate,
          onDependencyDragEnd: _handleDependencyDragEnd,
          autoEditOnMount: _autoEditTaskId == task.id,
          onAutoEditComplete: _clearAutoEdit,
          isSelected: _selectedTaskIds.contains(task.id),
          onSelectionChanged: _handleTaskSelectionChanged,
        );
      }
      currentIndex++;
    }

    return _buildInputRowFixedColumns(null, 0);
  }

  // Build ONLY the left columns (Activity + Actions) for mobile layout
  Widget _buildLeftColumnsRow(List<Task> flattenedTasks, int index) {
    // Index 0 is the project summary row
    if (index == 0) {
      return _buildProjectSummaryRowLeftColumns();
    }

    // Adjust index for tasks (subtract 1 for project summary row)
    final adjustedIndex = index - 1;

    int currentIndex = 0;
    for (int i = 0; i < flattenedTasks.length; i++) {
      final task = flattenedTasks[i];

      if (currentIndex == adjustedIndex) {
        final level = task.getNestingLevel(widget.tasks);
        final hasChildren = task.hasChildren(widget.tasks);

        return GestureDetector(
          onLongPress: () => _showMobileTaskActions(context, task),
          child: Container(
            height: _rowHeight,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                // Combined ID and Selection Column
                SizedBox(
                  width: 50,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _selectedTaskIds.contains(task.id)
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: _selectedTaskIds.contains(task.id)
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.textTertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: InkWell(
                        onTap: () {
                          _handleTaskSelectionChanged(
                            task,
                            !_selectedTaskIds.contains(task.id),
                          );
                        },
                        child: Center(
                          child: Text(
                            '${index}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _selectedTaskIds.contains(task.id)
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Activity column with smaller width on mobile
                SizedBox(
                  width: _activityColumnWidth,
                  child: Builder(
                    builder: (context) {
                      // Calculate which levels should have vertical lines (because an ancestor has more children)
                      final List<bool> ancestorHasMoreChildren = List.filled(
                        level,
                        false,
                      );
                      Task? current = task;
                      for (int i = level - 1; i >= 0; i--) {
                        final parentId = current?.parentId;
                        if (parentId != null) {
                          final parent = widget.tasks.firstWhere(
                            (t) => t.id == parentId,
                          );
                          final siblings = widget.tasks
                              .where((t) => t.parentId == parentId)
                              .toList();
                          siblings.sort(
                            (a, b) => a.createdAt.compareTo(b.createdAt),
                          );
                          final isLastChild =
                              siblings.isNotEmpty &&
                              siblings.last.id == current?.id;
                          ancestorHasMoreChildren[i] = !isLastChild;
                          current = parent;
                        } else {
                          // Root level
                          final roots = widget.tasks
                              .where((t) => t.parentId == null)
                              .toList();
                          roots.sort(
                            (a, b) => a.createdAt.compareTo(b.createdAt),
                          );
                          final isLastChild =
                              roots.isNotEmpty && roots.last.id == current?.id;
                          ancestorHasMoreChildren[i] = !isLastChild;
                          current = null;
                        }
                      }

                      return Row(
                        children: [
                          // Tree lines for each level (16px each for balanced look)
                          for (int i = 0; i < level; i++)
                            SizedBox(
                              width: 16,
                              height: _rowHeight,
                              child: CustomPaint(
                                painter: TreeLinesPainter(
                                  isLastLevel: i == level - 1,
                                  hasMoreAtThisLevel: ancestorHasMoreChildren[i],
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),

                          // Expand/collapse icon area (18px if has children, else 0px)
                          if (hasChildren)
                            SizedBox(
                              width: 18,
                              height: _rowHeight,
                              child: InkWell(
                                onTap: () => _handleExpandToggle(
                                  task,
                                  !_isTaskExpanded(task),
                                ),
                                child: Center(
                                  child: Icon(
                                    _isTaskExpanded(task)
                                        ? Icons.expand_more
                                        : Icons.chevron_right,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),

                          // Task type icon
                          _getTaskTypeIcon(task),
                          const SizedBox(width: 2),
                          // Progress pie chart - tappable for non-summary tasks
                          GestureDetector(
                            onTap: task.taskType != TaskType.summary &&
                                    widget.onTaskChanged != null
                                ? () => _showMobileProgressPicker(context, task)
                                : null,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CustomPaint(
                                painter: _ProgressCirclePainter(
                                  progress: task.progress / 100.0,
                                  color: _getProgressColor(task.progress),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Task name
                          Expanded(
                            child: InkWell(
                              onTap: () => widget.onTaskTap(task),
                              child: Text(
                                task.title,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: hasChildren
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          // More actions button
                          GestureDetector(
                            onTap: () => _showMobileTaskActions(context, task),
                            child: const SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                Icons.more_vert,
                                size: 16,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }
      currentIndex++;
    }

    return _buildInputRowLeftColumns();
  }

  // Build input row for left columns section
  Widget _buildInputRowLeftColumns() {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 50), // Selection column spacer
          SizedBox(
            width: _activityColumnWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildAddNewGroupButton(),
            ),
          ),
        ],
      ),
    );
  }

  // Show actions bottom sheet for mobile long-press
  void _showMobileTaskActions(BuildContext context, Task task) {
    final hasChildren = task.hasChildren(widget.tasks);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                task.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            // Progress setter - only for non-summary tasks
            if (task.taskType != TaskType.summary &&
                widget.onTaskChanged != null)
              ListTile(
                leading: SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(
                    painter: _ProgressCirclePainter(
                      progress: task.progress / 100.0,
                      color: _getProgressColor(task.progress),
                    ),
                  ),
                ),
                title: Text('Progress: ${task.progress}%'),
                onTap: () {
                  Navigator.pop(context);
                  _showMobileProgressPicker(context, task);
                },
              ),
            if (task.startDate != null)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(
                  hasChildren
                      ? 'Jump to phase on timeline'
                      : 'Jump to task on timeline',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleScrollToTask(task);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(hasChildren ? 'Edit phase' : 'Edit task'),
              onTap: () {
                Navigator.pop(context);
                widget.onTaskTap(task);
              },
            ),
            if (widget.onTaskCreated != null &&
                task.taskType == TaskType.summary)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add task to phase'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onTaskCreated!('', task.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Clone'),
              onTap: () {
                Navigator.pop(context);
                _handleTaskClone(task);
              },
            ),
            if (widget.onConvertTaskType != null)
              ListTile(
                leading: Icon(
                  task.taskType == TaskType.summary
                      ? Icons.task_outlined
                      : Icons.create_new_folder_outlined,
                ),
                title: Text(
                  task.taskType == TaskType.summary
                      ? 'Convert to task'
                      : 'Convert to phase',
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onConvertTaskType!(
                    task,
                    task.taskType == TaskType.summary
                        ? TaskType.standard
                        : TaskType.summary,
                  );
                },
              ),
            if (widget.onTaskDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onTaskDelete!(task);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Show progress picker dialog for mobile
  void _showMobileProgressPicker(BuildContext context, Task task) {
    double currentProgress = task.progress.toDouble();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Update Progress',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${currentProgress.toInt()}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getProgressColor(currentProgress.toInt()),
                    ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: currentProgress,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${currentProgress.toInt()}%',
                onChanged: (value) {
                  setDialogState(() {
                    currentProgress = value;
                  });
                },
              ),
              // Quick-set buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [0, 25, 50, 75, 100].map((v) {
                  return TextButton(
                    onPressed: () {
                      setDialogState(() {
                        currentProgress = v.toDouble();
                      });
                    },
                    child: Text('$v%'),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final updated = task.copyWith(
                  progress: currentProgress.toInt(),
                );
                widget.onTaskChanged?.call(updated);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get task type icon
  Widget _getTaskTypeIcon(Task task) {
    switch (task.taskType) {
      case TaskType.summary:
        return Icon(Icons.folder_outlined, size: 16, color: AppColors.infoDark);
      case TaskType.milestone:
        return Icon(
          Icons.flag_outlined,
          size: 16,
          color: AppColors.warningDark,
        );
      case TaskType.standard:
        return Icon(
          Icons.radio_button_unchecked,
          size: 16,
          color: AppColors.textSecondary,
        );
    }
  }

  // Helper method to get progress color
  Color _getProgressColor(int progress) {
    if (progress >= 100) {
      return AppColors.success; // Green for complete
    } else if (progress >= 50) {
      return AppColors.infoDark; // Blue for in progress (50%+)
    } else if (progress > 0) {
      return AppColors.warningDark; // Orange for started (1-49%)
    } else {
      return AppColors.textTertiary; // Grey for not started (0%)
    }
  }

  // Build ONLY the timeline part of a row
  Widget _buildTimelineRow(List<Task> flattenedTasks, int index) {
    // Index 0 is the project summary row
    if (index == 0) {
      return _buildProjectSummaryRowTimeline();
    }

    // Adjust index for tasks (subtract 1 for project summary row)
    final adjustedIndex = index - 1;

    int currentIndex = 0;
    for (int i = 0; i < flattenedTasks.length; i++) {
      final task = flattenedTasks[i];

      if (currentIndex == adjustedIndex) {
        // Return UnifiedGanttRow but configured to show only timeline
        return UnifiedGanttRow(
          task: task,
          allTasks: widget.tasks,
          rowIndex: i,
          calculator: _calculator,
          rangeStart: _rangeStart,
          rowHeight: _rowHeight,
          onTaskTap: widget.onTaskTap,
          onExpandToggle: _handleExpandToggle,
          isExpanded: _isTaskExpanded(task),
          onTaskChanged: _handleRowTaskChanged,
          onGroupShifted: _handleGroupShifted,
          baselineDates:
              _showBaseline ? _baselineDates[task.id] : null,
          onTaskCreated: _handleTaskCreatedWithAutoEdit,
          onGroupCreated: widget.onGroupCreated,
          onTaskDelete: widget.onTaskDelete,
          onConvertTaskType: widget.onConvertTaskType,
          onTaskClone: _handleTaskClone,
          onScrollToTask: _handleScrollToTask,
          onTaskDragStarted: _onTaskDragStarted,
          onTaskDragEnded: _onTaskDragEnded,
          onSaveAsTemplate: widget.onSaveAsTemplate,
          onImportTemplate: widget.onImportTemplate,
          showTimelineOnly: true, // NEW PARAMETER
          usersMap: _usersMap,
          allWorkspaceUsers: _allWorkspaceUsers,
          activityColumnWidth: _activityColumnWidth,
          onDependencyDragStart: _handleDependencyDragStart,
          onDependencyDragUpdate: _handleDependencyDragUpdate,
          onDependencyDragEnd: _handleDependencyDragEnd,
          autoEditOnMount: _autoEditTaskId == task.id,
          onAutoEditComplete: _clearAutoEdit,
          isSelected: _selectedTaskIds.contains(task.id),
          onSelectionChanged: _handleTaskSelectionChanged,
        );
      }
      currentIndex++;
    }

    return _buildInputRowTimelineOnly();
  }

  /// Calculate aggregated project data from all tasks
  Map<String, dynamic> _calculateProjectSummary() {
    DateTime? earliestStart;
    DateTime? latestEnd;
    int totalTasks = 0;
    int completedTasks = 0;
    final allAssigneeIds = <String>{};

    for (final task in widget.tasks) {
      // Collect all unique assignee IDs
      allAssigneeIds.addAll(task.assignedToIds);

      // Only count actual tasks (not groups) for completion
      if (task.taskType == TaskType.standard ||
          task.taskType == TaskType.milestone) {
        totalTasks++;
        if (task.isComplete || task.status == 'done') {
          completedTasks++;
        }
      }

      // Find earliest start date
      if (task.startDate != null) {
        if (earliestStart == null || task.startDate!.isBefore(earliestStart)) {
          earliestStart = task.startDate;
        }
      }

      // Find latest end date (use dueDate)
      if (task.dueDate != null) {
        if (latestEnd == null || task.dueDate!.isAfter(latestEnd)) {
          latestEnd = task.dueDate;
        }
      }
    }

    // Calculate duration in days
    int? durationDays;
    if (earliestStart != null && latestEnd != null) {
      durationDays = latestEnd.difference(earliestStart).inDays + 1;
    }

    // Calculate progress percentage
    final progress = totalTasks > 0
        ? (completedTasks / totalTasks * 100).round()
        : 0;

    return {
      'earliestStart': earliestStart,
      'latestEnd': latestEnd,
      'durationDays': durationDays,
      'totalTasks': totalTasks,
      'completedTasks': completedTasks,
      'progress': progress,
      'allAssigneeIds': allAssigneeIds.toList(),
    };
  }

  /// Build the fixed columns portion of the project summary row
  Widget _buildProjectSummaryRowFixedColumns() {
    final summary = _calculateProjectSummary();
    final projectTermLower = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    final earliestStart = summary['earliestStart'] as DateTime?;
    final latestEnd = summary['latestEnd'] as DateTime?;
    final durationDays = summary['durationDays'] as int?;
    final progress = summary['progress'] as int;
    final projectName = widget.project?.name ?? 'All Tasks';
    final allAssigneeIds = summary['allAssigneeIds'] as List<String>;

    // Format dates to match task row format
    final startStr = earliestStart != null
        ? DateFormat('MM/dd/yy').format(earliestStart)
        : '-';
    final endStr = latestEnd != null
        ? DateFormat('MM/dd/yy').format(latestEnd)
        : '-';
    final durationStr = durationDays != null ? '$durationDays days' : '-';

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        // Accept any task - dropping here makes it a root-level task
        return true;
      },
      onAcceptWithDetails: (details) {
        // Make the task a root-level task (clear parentId)
        _handleTaskParentChanged(details.data, null);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            color: isHovering
                ? AppColors.infoLight
                : const Color(
                    0xFFF8FAFC,
                  ), // Slightly different background for summary
            border: Border(
              bottom: BorderSide(
                color: isHovering
                    ? AppColors.info
                    : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: isHovering ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Combined ID and Selection Column spacer with "-" indicator
              SizedBox(
                width: 50,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _isProjectSummarySelected()
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _isProjectSummarySelected()
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.textTertiary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: InkWell(
                      onTap: () {
                        _handleProjectSummarySelectionChanged(
                          !_isProjectSummarySelected(),
                        );
                      },
                      child: Center(
                        child: Text(
                          '-',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _isProjectSummarySelected()
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Activity column
              SizedBox(
                width: _activityColumnWidth,
                child: Row(
                  children: [
                    // Add button area (14px to match child groups)
                    SizedBox(
                      width: 14,
                      height: _rowHeight,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: Colors.indigo.shade700,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Add to $projectTermLower root',
                        onSelected: (value) {
                          if (value == 'add_task' &&
                              widget.onTaskCreated != null) {
                            widget.onTaskCreated!('New Task', null);
                          } else if (value == 'add_group' &&
                              widget.onGroupCreated != null) {
                            widget.onGroupCreated!('New Phase', null);
                          } else if (value == 'import_template' &&
                              widget.onImportTemplate != null) {
                            widget.onImportTemplate!(null);
                          }
                        },
                        itemBuilder: (context) => [
                          if (widget.onTaskCreated != null)
                            const PopupMenuItem<String>(
                              value: 'add_task',
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 18),
                                  SizedBox(width: 8),
                                  Text('Add task'),
                                ],
                              ),
                            ),
                          if (widget.onGroupCreated != null)
                            const PopupMenuItem<String>(
                              value: 'add_group',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.create_new_folder_outlined,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Add phase'),
                                ],
                              ),
                            ),
                          if (widget.onImportTemplate != null)
                            const PopupMenuItem<String>(
                              value: 'import_template',
                              child: Row(
                                children: [
                                  Icon(Icons.library_add_check, size: 18),
                                  SizedBox(width: 8),
                                  Text('Import from template'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Gap to match child groups (2px + 4px = 6px total before title)
                    const SizedBox(width: 6),
                    // Project name
                    Expanded(
                      child: Text(
                        projectName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Aggregated assignees from all tasks
                    const SizedBox(width: 4),
                    TaskAssigneeAvatars(
                      usersMap: _usersMap,
                      allWorkspaceUsers: _allWorkspaceUsers,
                      maxVisible: 3,
                      avatarSize: 22,
                      assigneeIdsOverride: allAssigneeIds,
                      readOnly: true,
                    ),
                  ],
                ),
              ),
              // Actions column with pie chart (100px, matching task rows)
              if (!_isMobileView) ...[
                SizedBox(
                  width: 100,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Progress pie chart
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CustomPaint(
                            painter: _ProgressCirclePainter(
                              progress: progress / 100,
                              color: _getProgressColor(progress),
                            ),
                          ),
                        ),
                        // Spacers for jump, edit, more buttons (to maintain alignment)
                        const SizedBox(width: 16), // Jump button space
                        const SizedBox(width: 24), // Edit button space
                        const SizedBox(width: 24), // More button space
                      ],
                    ),
                  ),
                ),
                // Start date
                SizedBox(
                  width: 80,
                  child: Center(
                    child: Text(
                      startStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                // Duration
                SizedBox(
                  width: 70,
                  child: Center(
                    child: Text(
                      durationStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                // End date
                SizedBox(
                  width: 120,
                  child: Center(
                    child: Text(
                      endStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Build the left columns portion of the project summary row (mobile layout)
  Widget _buildProjectSummaryRowLeftColumns() {
    final summary = _calculateProjectSummary();
    final projectTermLower = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    final progress = summary['progress'] as int;
    final projectName = widget.project?.name ?? 'All Tasks';
    final allAssigneeIds = summary['allAssigneeIds'] as List<String>;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _handleTaskParentChanged(details.data, null);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            color: isHovering ? AppColors.infoLight : const Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(
                color: isHovering
                    ? AppColors.info
                    : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: isHovering ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Combined ID and Selection Column spacer with "-" indicator
              SizedBox(
                width: 50,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _isProjectSummarySelected()
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _isProjectSummarySelected()
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.textTertiary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: InkWell(
                      onTap: () {
                        _handleProjectSummarySelectionChanged(
                          !_isProjectSummarySelected(),
                        );
                      },
                      child: Center(
                        child: Text(
                          '-',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _isProjectSummarySelected()
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Activity column
              SizedBox(
                width: _activityColumnWidth,
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: Row(
                      children: [
                        // Add button moved to front - allows adding tasks/groups to the project root
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: Colors.indigo.shade700,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Add to $projectTermLower root',
                          onSelected: (value) {
                            if (value == 'add_task' &&
                                widget.onTaskCreated != null) {
                              widget.onTaskCreated!('New Task', null);
                            } else if (value == 'add_group' &&
                                widget.onGroupCreated != null) {
                              widget.onGroupCreated!('New Phase', null);
                            }
                          },
                          itemBuilder: (context) => [
                            if (widget.onTaskCreated != null)
                              const PopupMenuItem<String>(
                                value: 'add_task',
                                child: Row(
                                  children: [
                                    Icon(Icons.add, size: 18),
                                    SizedBox(width: 8),
                                    Text('Add task'),
                                  ],
                                ),
                              ),
                            if (widget.onGroupCreated != null)
                              const PopupMenuItem<String>(
                                value: 'add_group',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Add phase'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        // Progress pie chart
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CustomPaint(
                            painter: _ProgressCirclePainter(
                              progress: progress / 100.0,
                              color: _getProgressColor(progress),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Project name
                        Expanded(
                          child: Text(
                            projectName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Aggregated assignees
                        const SizedBox(width: 4),
                        TaskAssigneeAvatars(
                          usersMap: _usersMap,
                          allWorkspaceUsers: _allWorkspaceUsers,
                          maxVisible: 2,
                          avatarSize: 20,
                          assigneeIdsOverride: allAssigneeIds,
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build the timeline portion of the project summary row
  Widget _buildProjectSummaryRowTimeline() {
    final summary = _calculateProjectSummary();
    final earliestStart = summary['earliestStart'] as DateTime?;
    final latestEnd = summary['latestEnd'] as DateTime?;
    final progress = summary['progress'] as int;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _handleTaskParentChanged(details.data, null);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            color: isHovering ? AppColors.infoLight : const Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(
                color: isHovering ? AppColors.info : const Color(0xFFE2E8F0),
                width: isHovering ? 2 : 1,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Project summary bar
              if (earliestStart != null && latestEnd != null)
                Builder(
                  builder: (context) {
                    final startPixel = _calculator.dateToPixel(
                      earliestStart,
                      _rangeStart,
                    );
                    final endPixel = _calculator.dateToPixel(
                      latestEnd.add(const Duration(days: 1)),
                      _rangeStart,
                    );
                    final barWidth = endPixel - startPixel;

                    if (barWidth <= 0) return const SizedBox.shrink();

                    return Positioned(
                      left: startPixel,
                      top: 8,
                      child: Container(
                        width: barWidth,
                        height: _rowHeight - 16,
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: Colors.indigo.shade300,
                            width: 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Progress fill
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade400,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputRowFixedColumns(String? parentId, int level) {
    final isRootRow = parentId == null;

    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Fixed columns area
          SizedBox(
            width: 920,
            child: Row(
              children: [
                const SizedBox(width: 50), // Combined ID/Selection column
                // Activity column with indentation - show add task and add group options
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: (level * 4.0) + 8),
                    child: isRootRow
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: _buildAddNewGroupButton(),
                          )
                        : Row(
                            children: [
                              // Add task option
                              if (widget.onTaskCreated != null)
                                InkWell(
                                  onTap: () {
                                    widget.onTaskCreated!('New Task', parentId);
                                  },
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.add,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Add task',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 16),
                              // Add group option for nested rows
                              if (widget.onGroupCreated != null)
                                InkWell(
                                  onTap: () {
                                    widget.onGroupCreated!(
                                      'New Phase',
                                      parentId,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.create_new_folder_outlined,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Add phase',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                // Actions column
                SizedBox(
                  width: 100,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // Start column
                SizedBox(
                  width: 80,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // Duration column
                SizedBox(
                  width: 70,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // End column
                SizedBox(
                  width: 120,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // Progress column
                SizedBox(
                  width: 100,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // Predecessors column
                SizedBox(
                  width: 100,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
                // Successors column
                SizedBox(
                  width: 100,
                  child: isRootRow ? const SizedBox.shrink() : null,
                ),
              ],
            ),
          ),

          // Vertical divider line
          Container(width: 2, color: Theme.of(context).dividerColor),

          // Timeline area for input row (empty for now)
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildAddNewGroupButton() {
    final isEnabled = widget.onGroupCreated != null;
    return OutlinedButton.icon(
      onPressed: isEnabled
          ? () => widget.onGroupCreated!('New Phase', null)
          : null,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add new phase'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: BorderSide(
          color: AppColors.textTertiary.withValues(alpha: 0.45),
          width: 1.2,
        ),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        textStyle: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  // Input row for timeline-only section (just empty space)
  Widget _buildInputRowTimelineOnly() {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHeaderCell({
    double width = 30,
    bool showLabel = false,
  }) {
    return SizedBox(
      width: width,
      child: Center(
        child: InkWell(
          onTap: () {
            final isAllSelected = _isAllSelected();
            _handleSelectAll(!isAllSelected);
          },
          child: Container(
            width: showLabel ? 40 : 24,
            height: 24,
            decoration: BoxDecoration(
              color: _isAllSelected() == true
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: _isAllSelected() == true
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.textTertiary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Center(
              child: Text(
                showLabel ? 'ID' : '',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _isAllSelected() == true
                      ? Colors.white
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineHeader() {
    final totalDays = _calculator.totalBusinessDaysInYear;
    final pixelsPerDay = _calculator.pixelsPerDay;

    return Container(
      width: pixelsPerDay * totalDays,
      height: 50,
      decoration: const BoxDecoration(
        // Slightly darker light grey for modern look (matches left header)
        color: Color(0xFFF3F4F6),
        borderRadius: BorderRadius.only(topRight: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Stack(
        children: [
          // Month labels at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 25,
            child: _buildMonthLabels(totalDays, pixelsPerDay),
          ),

          // Day numbers at bottom
          Positioned(
            top: 25,
            left: 0,
            right: 0,
            height: 25,
            child: _buildDayNumbers(totalDays, pixelsPerDay),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthLabels(int totalDays, double pixelsPerDay) {
    final labels = <Widget>[];
    DateTime currentDate = _rangeStart;
    double position = 0;
    final totalWidth = pixelsPerDay * totalDays;

    while (position < totalWidth) {
      final nextMonthStart = DateTime(
        currentDate.year,
        currentDate.month + 1,
        1,
      );

      // Calculate how many days of this month are visible
      int visibleDaysInMonth;
      if (_showBusinessDaysOnly) {
        // Count business days from current position to end of month
        visibleDaysInMonth = _calculator.countBusinessDays(
          currentDate,
          nextMonthStart,
        );
      } else {
        if (currentDate == _rangeStart && currentDate.day > 1) {
          // First month - starts mid-month, so only count remaining days
          visibleDaysInMonth = nextMonthStart.difference(currentDate).inDays;
        } else {
          // Full month
          final monthStart = DateTime(currentDate.year, currentDate.month, 1);
          visibleDaysInMonth = nextMonthStart.difference(monthStart).inDays;
        }
      }

      final monthWidth = visibleDaysInMonth * pixelsPerDay;

      // Don't exceed the total width
      final actualWidth = (position + monthWidth > totalWidth)
          ? totalWidth - position
          : monthWidth;

      if (actualWidth > 0) {
        labels.add(
          Positioned(
            left: position,
            child: Container(
              width: actualWidth,
              height: 25,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: const Color(0xFFE5E7EB).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${_getMonthName(currentDate.month)} ${currentDate.year}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF374151), // Dark grey text
                ),
              ),
            ),
          ),
        );
      }

      position += actualWidth;
      currentDate = nextMonthStart;
    }

    return Stack(children: labels);
  }

  Widget _buildDayNumbers(int totalDays, double pixelsPerDay) {
    final dayLabels = <Widget>[];
    DateTime currentDate = _rangeStart;

    // Get the project target completion date for highlighting
    final targetDate = widget.project?.targetCompletionDate;

    // Check if any task extends past the target date (for color scheme)
    final hasTasksPastTarget =
        targetDate != null &&
        widget.tasks.any(
          (task) => task.dueDate != null && task.dueDate!.isAfter(targetDate),
        );

    int positionIndex =
        0; // Track position for rendering (consecutive even when skipping weekends)
    int daysProcessed = 0; // Track how many calendar days we've gone through

    while (positionIndex < totalDays && daysProcessed < 400) {
      // 400 as safety limit
      // Skip weekends if business days only mode is enabled
      if (_showBusinessDaysOnly && _calculator.isWeekend(currentDate)) {
        currentDate = currentDate.add(const Duration(days: 1));
        daysProcessed++;
        continue;
      }

      // Check if this day is the target completion date
      final isTargetDate =
          targetDate != null &&
          currentDate.year == targetDate.year &&
          currentDate.month == targetDate.month &&
          currentDate.day == targetDate.day;

      // Use red if tasks are past target, green otherwise
      final targetBgColor = hasTasksPastTarget
          ? AppColors.errorLight
          : AppColors.successLight;
      final targetBorderColor = hasTasksPastTarget
          ? AppColors.error
          : AppColors.success;
      final targetTextColor = hasTasksPastTarget
          ? AppColors.errorDark
          : AppColors.successDark;

      // Get single-letter day abbreviation
      final dayLetter = _getDayLetter(currentDate.weekday);

      dayLabels.add(
        Positioned(
          left: positionIndex * pixelsPerDay,
          width: pixelsPerDay,
          child: Container(
            width: pixelsPerDay,
            height: 25,
            decoration: BoxDecoration(
              color: isTargetDate ? targetBgColor : null,
              border: Border(
                right: BorderSide(
                  color: isTargetDate
                      ? targetBorderColor
                      : const Color(0xFFE5E7EB),
                  width: isTargetDate ? 2 : 1,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dayLetter,
                  style: TextStyle(
                    fontSize: 8,
                    color: isTargetDate
                        ? targetTextColor
                        : const Color(0xFFBBBBBB),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${currentDate.day}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isTargetDate
                        ? targetTextColor
                        : const Color(0xFF9CA3AF),
                    fontWeight: isTargetDate
                        ? FontWeight.bold
                        : FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      positionIndex++;
      currentDate = currentDate.add(const Duration(days: 1));
      daysProcessed++;
    }

    return Stack(children: dayLabels);
  }

  /// Get single-letter day abbreviation (M, T, W, T, F, S, S)
  String _getDayLetter(int weekday) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[weekday - 1]; // weekday is 1-7 (Mon-Sun)
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  TimelineView _getTimelineView(String view) {
    switch (view) {
      case 'Day':
        return TimelineView.day;
      case 'Week':
        return TimelineView.week;
      case 'Month':
        return TimelineView.month;
      case 'Quarter':
        return TimelineView.quarter;
      case 'Year':
        return TimelineView.year;
      default:
        return TimelineView.month;
    }
  }

  void _handleExpandToggle(Task task, bool isExpanded) async {
    // Update local state immediately for responsive UI
    setState(() {
      _userExpansionPrefs[task.id] = isExpanded;
    });

    // Persist preference (per-user)
    if (_currentUserId != null && widget.project?.id != null) {
      try {
        await _taskService.updateUserTaskExpansion(
          _currentUserId!,
          widget.project!.id,
          task.id,
          isExpanded,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'saving preference'),
              ),
            ),
          );
        }
      }
    }
  }

  /// Collapse all parent tasks that have leaf children (hide leaf tasks only)
  void _handleCollapseAll() async {
    // Find all parent tasks that are currently expanded
    final parentTasks = widget.tasks
        .where((t) => t.hasChildren(widget.tasks) && _isTaskExpanded(t))
        .toList();

    // Build batch update map
    final Map<String, bool> expansionStates = {};
    for (final task in parentTasks) {
      expansionStates[task.id] = false;
    }

    // Update local state immediately
    setState(() {
      _userExpansionPrefs.addAll(expansionStates);
      _isAllCollapsed = true;
    });

    // Persist to Firestore (per-user) as batch
    if (_currentUserId != null &&
        widget.project?.id != null &&
        expansionStates.isNotEmpty) {
      try {
        await _taskService.updateUserTaskExpansionBatch(
          _currentUserId!,
          widget.project!.id,
          expansionStates,
        );
      } catch (_) {
        // Best-effort persistence
      }
    }
  }

  /// Expand all parent tasks (show their children)
  void _handleExpandAll() async {
    // Find all parent tasks that are currently collapsed
    final parentTasks = widget.tasks
        .where((t) => t.hasChildren(widget.tasks) && !_isTaskExpanded(t))
        .toList();

    // Build batch update map
    final Map<String, bool> expansionStates = {};
    for (final task in parentTasks) {
      expansionStates[task.id] = true;
    }

    // Update local state immediately
    setState(() {
      _userExpansionPrefs.addAll(expansionStates);
      _isAllCollapsed = false;
    });

    // Persist to Firestore (per-user) as batch
    if (_currentUserId != null &&
        widget.project?.id != null &&
        expansionStates.isNotEmpty) {
      try {
        await _taskService.updateUserTaskExpansionBatch(
          _currentUserId!,
          widget.project!.id,
          expansionStates,
        );
      } catch (_) {
        // Best-effort persistence
      }
    }
  }

  /// Calculate the horizontal position for the project target completion date line
  double _getTargetDatePosition() {
    final targetDate = widget.project?.targetCompletionDate;
    if (targetDate == null) return 0;

    // Calculate days from range start to target date
    final daysDiff = targetDate.difference(_rangeStart).inDays;
    // Position at the end of that day (right edge)
    return (daysDiff + 1) * _calculator.pixelsPerDay;
  }

  /// Handle start of dependency drag from a task's anchor dot
  void _handleDependencyDragStart(Task sourceTask, bool fromEnd) {
    // Calculate the anchor position immediately
    final anchorPosition = _calculateTaskAnchorPosition(sourceTask, fromEnd);

    setState(() {
      _dependencySourceTask = sourceTask;
      _dependencyFromEnd = fromEnd;
      _dependencyStartPosition = anchorPosition;
      _dependencyDragPosition = anchorPosition; // Start at anchor
      _dependencySnapTarget = null;
    });
  }

  /// Handle update of dependency drag position
  void _handleDependencyDragUpdate(Offset globalPosition) {
    // Convert global position to local position relative to widget
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(globalPosition);

    // Detect snap targets - find tasks near the drag position
    Task? snapTarget;
    final flattenedTasks = _flattenTaskTreeWithUserPrefs(widget.tasks);

    // Get the current vertical scroll offset to compensate for scrolling
    final verticalScrollOffset = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    for (int i = 0; i < flattenedTasks.length; i++) {
      final task = flattenedTasks[i];
      if (task.id == _dependencySourceTask?.id) continue; // Can't link to self
      if (task.startDate == null && task.dueDate == null) continue;

      // Calculate task's Y position (row center)
      // 50 = toolbar, 50 = header, then subtract scroll offset to get screen position
      final absoluteY = 50.0 + 50.0 + (i * _rowHeight) + (_rowHeight / 2);
      final taskY = absoluteY - verticalScrollOffset;

      // Calculate task's X start/end positions
      final taskPosition = _calculator.getTaskPosition(
        task.startDate,
        task.dueDate,
        _rangeStart,
      );
      final taskWidth = _calculator.getTaskWidth(
        task.startDate,
        task.dueDate,
        task.estimatedDuration,
      );

      final taskStartX = _leftSectionWidth + taskPosition;
      final taskEndX = taskStartX + taskWidth;

      // Simplified snap detection: check if cursor is within task row vertically
      // and near the task horizontally (within 60px of either edge)
      final yDiff = (localPosition.dy - taskY).abs();
      final isInTaskRow = yDiff < 30;

      // Near start or end of task bar
      final isNearTaskBar =
          localPosition.dx >= (taskStartX - 60) &&
          localPosition.dx <= (taskEndX + 60);

      if (isInTaskRow && isNearTaskBar) {
        snapTarget = task;
        break;
      }
    }

    setState(() {
      _dependencyDragPosition = localPosition;
      _dependencySnapTarget = snapTarget;
    });
  }

  /// Handle end of dependency drag
  void _handleDependencyDragEnd() async {
    if (_dependencySourceTask != null && _dependencySnapTarget != null) {
      // Create the dependency
      final sourceTask = _dependencySourceTask!;
      final targetTask = _dependencySnapTarget!;

      try {
        if (_dependencyFromEnd) {
          // Dragging from sourceTask's END to targetTask's START
          // This means: sourceTask is predecessor, targetTask is successor
          // Add sourceTask.id to targetTask's predecessorIds
          final newPredecessors = List<String>.from(targetTask.predecessorIds);
          if (!newPredecessors.contains(sourceTask.id)) {
            newPredecessors.add(sourceTask.id);
            await _taskService.updateTask(
              taskId: targetTask.id,
              predecessorIds: newPredecessors,
            );
          }
        } else {
          // Dragging from sourceTask's START to targetTask's END
          // This means: targetTask is predecessor, sourceTask is successor
          // Add targetTask.id to sourceTask's predecessorIds
          final newPredecessors = List<String>.from(sourceTask.predecessorIds);
          if (!newPredecessors.contains(targetTask.id)) {
            newPredecessors.add(targetTask.id);
            await _taskService.updateTask(
              taskId: sourceTask.id,
              predecessorIds: newPredecessors,
            );
          }
        }
      } catch (_) {
        // Dependency creation failed silently
      }
    }

    setState(() {
      _dependencySourceTask = null;
      _dependencyFromEnd = false;
      _dependencyStartPosition = null;
      _dependencyDragPosition = null;
      _dependencySnapTarget = null;
    });
  }

  /// Handle deletion of a dependency
  void _handleDeleteDependency(String successorId, String predecessorId) async {
    // Find the successor task
    final successorTask = widget.tasks.firstWhere(
      (t) => t.id == successorId,
      orElse: () => widget.tasks.first,
    );

    if (successorTask.id != successorId) return; // Not found

    try {
      // Remove predecessor from the list
      final newPredecessors = List<String>.from(successorTask.predecessorIds);
      newPredecessors.remove(predecessorId);

      await _taskService.updateTask(
        taskId: successorId,
        predecessorIds: newPredecessors,
      );

      // Clear hover state
      setState(() {
        _hoveredDependencyKey = null;
      });
    } catch (_) {
      // Dependency deletion failed silently
    }
  }

  /// Calculate the screen position of a task's anchor point (local coordinates)
  Offset? _calculateTaskAnchorPosition(Task task, bool fromEnd) {
    if (task.startDate == null && task.dueDate == null) {
      return null;
    }

    // Find the task's row index
    final flattenedTasks = _flattenTaskTreeWithUserPrefs(widget.tasks);
    final taskIndex = flattenedTasks.indexWhere((t) => t.id == task.id);

    if (taskIndex < 0) {
      return null;
    }

    // Get the current vertical scroll offset to compensate for scrolling
    final verticalScrollOffset = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    // Calculate Y position (center of the row), accounting for scroll
    final absoluteY =
        50.0 + // toolbar height
        50.0 + // header height
        (taskIndex * _rowHeight) +
        (_rowHeight / 2);
    final rowY = absoluteY - verticalScrollOffset;

    // Calculate X position based on task's timeline position
    final taskPosition = _calculator.getTaskPosition(
      task.startDate,
      task.dueDate,
      _rangeStart,
    );
    final taskWidth = _calculator.getTaskWidth(
      task.startDate,
      task.dueDate,
      task.estimatedDuration,
    );

    // X position: either start or end of task bar
    final baseX = _leftSectionWidth + taskPosition;
    final anchorX = fromEnd
        ? baseX +
              taskWidth +
              18 // End anchor (right side + anchor dot offset)
        : baseX - 18; // Start anchor (left side - anchor dot offset)

    return Offset(anchorX, rowY);
  }

  void _handleScrollToTask(Task task) {
    if (task.startDate == null && task.dueDate == null) return;

    // Calculate the position of the task on the timeline
    final taskPosition = _calculator.getTaskPosition(
      task.startDate,
      task.dueDate,
      _rangeStart,
    );

    // Scroll the timeline's internal scrollview to the task position
    // Use a small padding (20px) to ensure the task bar is clearly visible
    final targetOffset = (taskPosition - 20).clamp(
      0.0,
      _horizontalScrollController.position.maxScrollExtent,
    );

    _horizontalScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleTaskSelectionChanged(Task task, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTaskIds.add(task.id);
        // If selecting a group/summary task, select all its descendants
        if (task.taskType == TaskType.summary) {
          final descendants = _getAllDescendants(task);
          _selectedTaskIds.addAll(descendants.map((t) => t.id));
        }
      } else {
        _selectedTaskIds.remove(task.id);
        // If deselecting a group/summary task, deselect all its descendants
        if (task.taskType == TaskType.summary) {
          final descendants = _getAllDescendants(task);
          _selectedTaskIds.removeAll(descendants.map((t) => t.id).toSet());
        }
      }
    });
  }

  List<Task> _getAllDescendants(Task task) {
    final descendants = <Task>[];
    _collectDescendants(task, descendants);
    return descendants;
  }

  void _collectDescendants(Task task, List<Task> descendants) {
    for (final t in widget.tasks) {
      if (t.parentId == task.id) {
        descendants.add(t);
        _collectDescendants(t, descendants);
      }
    }
  }

  void _handleSelectAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        var filteredTasks = widget.tasks;
        if (_hideCompleted) {
          filteredTasks = filteredTasks
              .where((t) => !t.isComplete && t.progress < 100)
              .toList();
        }
        _selectedTaskIds = filteredTasks.map((t) => t.id).toSet();
      } else {
        _selectedTaskIds.clear();
      }
    });
  }

  bool _isAllSelected() {
    var filteredTasks = widget.tasks;
    if (_hideCompleted) {
      filteredTasks = filteredTasks
          .where((t) => !t.isComplete && t.progress < 100)
          .toList();
    }
    if (filteredTasks.isEmpty) return false;
    return _selectedTaskIds.length == filteredTasks.length;
  }

  void _handleMassEdit() {
    final selectedTasks = widget.tasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList();

    if (selectedTasks.isEmpty) return;

    showMassEditDialog(
      context,
      tasks: selectedTasks,
      allTasks: widget.tasks,
      allWorkspaceUsers: _allWorkspaceUsers,
      onTasksUpdated: (updatedTasks) {
        for (final updatedTask in updatedTasks) {
          if (widget.onTaskChanged != null) {
            widget.onTaskChanged!(updatedTask);
          }
        }
        setState(() {
          _selectedTaskIds.clear();
        });
      },
      onClone: () => _handleMassClone(selectedTasks),
    );
  }

  Future<void> _handleMassClone(List<Task> selectedTasks) async {
    try {
      await _taskService.cloneMultipleTasks(
        selectedTasks: selectedTasks,
        allTasks: widget.tasks,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cloned ${selectedTasks.length} item${selectedTasks.length > 1 ? 's' : ''}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          _selectedTaskIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clone: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _isProjectSummarySelected() {
    if (widget.tasks.isEmpty) return false;
    return widget.tasks.every((task) => _selectedTaskIds.contains(task.id));
  }

  void _handleProjectSummarySelectionChanged(bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedTaskIds = widget.tasks.map((t) => t.id).toSet();
      } else {
        _selectedTaskIds.clear();
      }
    });
  }
}

/// Custom painter for dependency lines
class DependencyOverlayPainter extends CustomPainter {
  final List<Task> tasks;
  final List<Task> allTasks;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final double rowHeight;
  final double horizontalScrollOffset;
  final double verticalScrollOffset;
  final double fixedColumnsWidth;

  DependencyOverlayPainter({
    required this.tasks,
    required this.allTasks,
    required this.calculator,
    required this.rangeStart,
    required this.rowHeight,
    required this.horizontalScrollOffset,
    required this.verticalScrollOffset,
    required this.fixedColumnsWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          const Color(0xFF78909C) // Softer blue-grey
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw dependency lines for each task
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];

      if (task.predecessorIds.isEmpty) continue;
      if (task.startDate == null && task.dueDate == null) continue;

      for (final predId in task.predecessorIds) {
        final predTask = allTasks.firstWhere(
          (t) => t.id == predId,
          orElse: () => task, // Skip if not found
        );

        if (predTask.id == task.id) continue; // Skip invalid dependency
        if (predTask.startDate == null && predTask.dueDate == null) continue;

        final predIndex = tasks.indexOf(predTask);
        if (predIndex < 0) continue;

        // Calculate positions
        // Task bar is positioned at top: 12 in the row, and has height 24
        // So center of task bar = 12 + 12 = 24 from top of row
        final taskBarCenterOffset = 12.0 + 12.0; // top offset + half bar height

        // Predecessor end X (right side of task bar + offset for anchor dot area)
        final predTaskPosition = calculator.getTaskPosition(
          predTask.startDate,
          predTask.dueDate,
          rangeStart,
        );
        final predTaskWidth = calculator.getTaskWidth(
          predTask.startDate,
          predTask.dueDate,
          predTask.estimatedDuration,
        );
        final predEndX =
            predTaskPosition +
            predTaskWidth +
            18; // 18 = SizedBox placeholder width when not hovering

        final predY =
            (predIndex * rowHeight) +
            taskBarCenterOffset -
            verticalScrollOffset;

        // Current task start X (left side of task bar + offset for anchor dot area)
        final currentTaskPosition = calculator.getTaskPosition(
          task.startDate,
          task.dueDate,
          rangeStart,
        );
        final currentStartX =
            currentTaskPosition + 18; // 18 = left anchor SizedBox placeholder

        final currentY =
            (i * rowHeight) + taskBarCenterOffset - verticalScrollOffset;

        // Skip if not visible
        if (currentY < -50 || currentY > size.height + 50) continue;

        // Determine if going up or down
        final goingDown = currentY > predY;

        // Calculate midpoint for routing
        // Route the vertical segment between the two rows (outside the task bar area)
        final verticalX = predEndX + 20; // 20px to the right of predecessor end

        // For the horizontal segment to successor, determine if we need to go around
        // If the successor task starts before the vertical line X, route around
        final needsExtraRouting = currentStartX < verticalX;

        // Draw right-angle orthogonal lines
        final path = Path();
        path.moveTo(predEndX, predY);

        if (needsExtraRouting) {
          // Complex routing with right angles
          final routeY = goingDown
              ? predY + (rowHeight / 2) + 5
              : predY - (rowHeight / 2) - 5;

          // First segment: horizontal right
          path.lineTo(verticalX, predY);
          // Second segment: vertical to routing level
          path.lineTo(verticalX, routeY);
          // Third segment: horizontal left
          path.lineTo(currentStartX - 20, routeY);
          // Fourth segment: vertical to target row
          path.lineTo(currentStartX - 20, currentY);
          // Fifth segment: horizontal to target
          path.lineTo(currentStartX, currentY);
        } else {
          // Simple right-angle routing from predecessor end to successor start
          // Calculate midpoint X for the vertical segment
          final midX = predEndX + 20;

          // Horizontal right from predecessor
          path.lineTo(midX, predY);
          // Vertical to successor row
          path.lineTo(midX, currentY);
          // Horizontal to successor
          path.lineTo(currentStartX, currentY);
        }

        canvas.drawPath(path, paint);

        // Draw arrow head pointing right
        _drawArrowHead(canvas, currentStartX, currentY, paint);
      }
    }
  }

  void _drawArrowHead(Canvas canvas, double x, double y, Paint paint) {
    final arrowPath = Path();
    arrowPath.moveTo(x, y);
    arrowPath.lineTo(x - 6, y - 4);
    arrowPath.lineTo(x - 6, y + 4);
    arrowPath.close();

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke; // Reset
  }

  @override
  bool shouldRepaint(DependencyOverlayPainter oldDelegate) {
    return oldDelegate.horizontalScrollOffset != horizontalScrollOffset ||
        oldDelegate.verticalScrollOffset != verticalScrollOffset ||
        oldDelegate.tasks != tasks;
  }
}

/// Custom painter for ghost line during dependency drag
class DependencyGhostLinePainter extends CustomPainter {
  final Offset? startPoint;
  final Offset? endPoint;
  final bool hasSnapTarget;

  DependencyGhostLinePainter({
    required this.startPoint,
    required this.endPoint,
    this.hasSnapTarget = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (startPoint == null || endPoint == null) return;

    final paint = Paint()
      ..color = hasSnapTarget ? AppColors.success : AppColors.info
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashWidth = 8.0;
    const dashSpace = 4.0;

    final path = Path();
    path.moveTo(startPoint!.dx, startPoint!.dy);

    // Use smart routing similar to permanent dependency lines
    final goingDown = endPoint!.dy > startPoint!.dy;
    final verticalX = startPoint!.dx + 20; // Go right first
    final needsExtraRouting = endPoint!.dx < verticalX;

    if (needsExtraRouting) {
      // Route around: Right → Down/Up past row → Left → Down/Up to target → Right
      path.lineTo(verticalX, startPoint!.dy);

      // Calculate routing Y (offset from start to avoid task bars)
      final routeY = goingDown
          ? startPoint!.dy +
                30 // Below starting row
          : startPoint!.dy - 30; // Above starting row

      path.lineTo(verticalX, routeY);
      path.lineTo(endPoint!.dx - 20, routeY);
      path.lineTo(endPoint!.dx - 20, endPoint!.dy);
      path.lineTo(endPoint!.dx, endPoint!.dy);
    } else {
      // Simple routing: Right → Down → Right
      path.lineTo(verticalX, startPoint!.dy);
      path.lineTo(verticalX, endPoint!.dy);
      path.lineTo(endPoint!.dx, endPoint!.dy);
    }

    // Draw dashed
    final dashPath = Path();
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final nextDistance = distance + dashWidth;
        if (nextDistance > metric.length) break;
        dashPath.addPath(
          metric.extractPath(distance, nextDistance),
          Offset.zero,
        );
        distance = nextDistance + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);

    // Draw arrow head at end point
    if (hasSnapTarget) {
      _drawArrowHead(canvas, endPoint!.dx, endPoint!.dy, paint);
    }

    // Draw circle at end point
    canvas.drawCircle(
      endPoint!,
      6,
      Paint()
        ..color = hasSnapTarget ? AppColors.success : AppColors.info
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      endPoint!,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawArrowHead(Canvas canvas, double x, double y, Paint paint) {
    final arrowPath = Path();
    arrowPath.moveTo(x, y);
    arrowPath.lineTo(x - 8, y - 5);
    arrowPath.lineTo(x - 8, y + 5);
    arrowPath.close();

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(DependencyGhostLinePainter oldDelegate) {
    return oldDelegate.startPoint != startPoint ||
        oldDelegate.endPoint != endPoint ||
        oldDelegate.hasSnapTarget != hasSnapTarget;
  }
}

// Custom painter for circular progress indicator
class _ProgressCirclePainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color color;

  _ProgressCirclePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Draw background circle (border)
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw progress arc (pie chart style)
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final rect = Rect.fromCircle(center: center, radius: radius);
      const startAngle = -3.14159 / 2; // Start at top
      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, true, progressPaint);
    }

    // Draw checkmark if complete
    if (progress >= 1.0) {
      final checkPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(center.dx - radius * 0.4, center.dy)
        ..lineTo(center.dx - radius * 0.1, center.dy + radius * 0.3)
        ..lineTo(center.dx + radius * 0.4, center.dy - radius * 0.3);

      canvas.drawPath(path, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_ProgressCirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

/// Custom painter for dashed vertical lines
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({
    required this.color,
  });

  static const double _dashHeight = 5;
  static const double _dashGap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + _dashHeight), paint);
      startY += _dashHeight + _dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
