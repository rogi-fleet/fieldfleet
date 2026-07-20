import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/task_filter_engine.dart';
import '../../utils/hierarchy_utils.dart';
import '../table/tree_drop_zone.dart';
import '../task_form_popup.dart';
import 'kanban_task_card.dart';

enum KanbanGroupingMode { none, hierarchy }

/// Kanban board view with status columns and optional hierarchy grouping.
class KanbanBoardView extends StatefulWidget {
  final String? projectId;
  final String workspaceId;
  final String? externalSearchQuery;
  final String? externalPropertyFilterId;
  final bool? externalMyTasksOnly;
  final bool? externalOverdueOnly;
  final String? externalCustomerFilterId;
  final String? externalPriorityFilter;
  final String? externalAssigneeFilterId;
  final DateTime? externalDueDateStart;
  final DateTime? externalDueDateEnd;
  final Map<String, Project>? externalProjectMap;
  final KanbanGroupingMode groupingMode;

  const KanbanBoardView({
    super.key,
    this.projectId,
    required this.workspaceId,
    this.externalSearchQuery,
    this.externalPropertyFilterId,
    this.externalMyTasksOnly,
    this.externalOverdueOnly,
    this.externalCustomerFilterId,
    this.externalPriorityFilter,
    this.externalAssigneeFilterId,
    this.externalDueDateStart,
    this.externalDueDateEnd,
    this.externalProjectMap,
    this.groupingMode = KanbanGroupingMode.hierarchy,
  });

  @override
  State<KanbanBoardView> createState() => _KanbanBoardViewState();
}

class _KanbanBoardViewState extends State<KanbanBoardView> {
  String _searchQuery = '';
  bool _showMyTasks = false;
  bool _isTaskDragging = false;
  bool _isUngroupDropTargetActive = false;
  final TextEditingController _searchController = TextEditingController();

  static const _statusColumns = [
    ('not_started', 'Not Started', AppColors.textTertiary),
    ('working_on_it', 'Working on it', AppColors.info),
    ('stuck', 'Stuck', AppColors.warning),
    ('done', 'Done', AppColors.success),
  ];

  bool get _isHierarchyEnabled =>
      widget.groupingMode == KanbanGroupingMode.hierarchy;

  bool get _effectiveMyTasks => widget.externalMyTasksOnly ?? _showMyTasks;

  String get _effectiveSearchQuery =>
      (widget.externalSearchQuery ?? _searchQuery).trim().toLowerCase();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUserId = authProvider.appUser?.id;

    final taskStream = widget.projectId != null
        ? ServiceLocator.taskService.getTasks(
            widget.projectId!,
            workspaceId: widget.workspaceId,
          )
        : ServiceLocator.taskService.getAllWorkspaceTasks(widget.workspaceId);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Row(
            children: [
              if (widget.externalSearchQuery == null) ...[
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search tasks...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 0,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (widget.externalMyTasksOnly == null) ...[
                ChoiceChip(
                  label: Text(_showMyTasks ? 'My Tasks' : 'All Tasks'),
                  selected: _showMyTasks,
                  onSelected: (selected) {
                    setState(() => _showMyTasks = selected);
                  },
                  showCheckmark: false,
                  avatar: Icon(
                    _showMyTasks ? Icons.assignment_ind : Icons.assignment,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: taskStream,
            builder: (context, taskSnapshot) {
              if (taskSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allTasks = taskSnapshot.data ?? [];
              var tasks = TaskFilterEngine.apply(
                allTasks,
                options: TaskFilterOptions(
                  myTasksOnly: _effectiveMyTasks,
                  currentUserId: currentUserId,
                  propertyFilterId: widget.externalPropertyFilterId,
                  query: _effectiveSearchQuery,
                  overdueOnly: widget.externalOverdueOnly ?? false,
                  customerId: widget.externalCustomerFilterId,
                  priority: widget.externalPriorityFilter,
                  assigneeId: widget.externalAssigneeFilterId,
                  dueDateStart: widget.externalDueDateStart,
                  dueDateEnd: widget.externalDueDateEnd,
                ),
                context: widget.externalProjectMap != null
                    ? TaskFilterContext(projectMap: widget.externalProjectMap!)
                    : const TaskFilterContext(),
              );

              if (!_isHierarchyEnabled) {
                tasks = tasks
                    .where((t) => t.taskType != TaskType.summary)
                    .toList();
              }

              return FutureBuilder<Map<String, AppUser>>(
                future: ServiceLocator.userService.getWorkspaceUsersMap(
                  widget.workspaceId,
                ),
                builder: (context, usersSnapshot) {
                  final usersMap = usersSnapshot.data ?? {};
                  final allUsers = usersMap.values.toList();

                  // A Kanban board always shows every status column — the
                  // Done column is where completed tasks live, so it must be
                  // visible and a valid drop target at all times.
                  const columns = _statusColumns;

                  final board = LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile =
                          MediaQuery.of(context).size.width < 768;
                      final columnWidth = constraints.maxWidth >= 1000
                          ? (constraints.maxWidth / columns.length).clamp(
                              250.0,
                              400.0,
                            )
                          : isMobile
                              ? 200.0
                              : 280.0;

                      final content = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final col in columns)
                            SizedBox(
                              width: columnWidth,
                              child: _KanbanColumn(
                                compact: isMobile,
                                status: col.$1,
                                label: col.$2,
                                color: col.$3,
                                tasks: tasks
                                    .where((t) => t.status == col.$1)
                                    .toList(),
                                allTasks: allTasks,
                                usersMap: usersMap,
                                allWorkspaceUsers: allUsers,
                                hierarchyEnabled: _isHierarchyEnabled,
                                onTaskDroppedToColumn: (task) =>
                                    _onTaskDroppedToColumn(
                                      task,
                                      col.$1,
                                      allTasks,
                                    ),
                                onTaskGroupedUnder: (dragged, target) =>
                                    _onTaskGroupedUnder(
                                      dragged,
                                      target,
                                      allTasks,
                                    ),
                                onTaskDroppedOnTask: (dragged, target, zone) =>
                                    _onTaskDroppedOnTask(
                                      dragged,
                                      target,
                                      zone,
                                      allTasks,
                                    ),
                                onTaskTap: _onTaskTap,
                                onDragStarted: _onTaskDragStarted,
                                onDragEnded: _onTaskDragEnded,
                              ),
                            ),
                        ],
                      );

                      if (constraints.maxWidth >=
                          columnWidth * columns.length) {
                        return content;
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        child: content,
                      );
                    },
                  );

                  return Stack(
                    children: [
                      Positioned.fill(child: board),
                      if (_isTaskDragging && _isHierarchyEnabled)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: DragTarget<Task>(
                            onWillAcceptWithDetails: (_) => true,
                            onAcceptWithDetails: (details) {
                              setState(() {
                                _isUngroupDropTargetActive = false;
                                _isTaskDragging = false;
                              });
                              ServiceLocator.taskService.updateTask(
                                taskId: details.data.id,
                                clearParentId: true,
                              );
                            },
                            onMove: (_) {
                              if (!_isUngroupDropTargetActive) {
                                setState(
                                  () => _isUngroupDropTargetActive = true,
                                );
                              }
                            },
                            onLeave: (_) {
                              if (_isUngroupDropTargetActive) {
                                setState(
                                  () => _isUngroupDropTargetActive = false,
                                );
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
                                      color: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.move_up
                                          : Icons.outbox_outlined,
                                      size: 18,
                                      color: isActive
                                          ? AppColors.info
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isActive
                                          ? 'Release to move out of group'
                                          : 'Move out of group',
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
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _onTaskDroppedToColumn(
    Task task,
    String newStatus,
    List<Task> allTasks,
  ) async {
    final updates = <Future<void>>[];

    final taskIdsToMove = <String>{task.id};
    if (task.taskType == TaskType.summary) {
      taskIdsToMove.addAll(_collectDescendantIds(task.id, allTasks));
    }

    for (final taskId in taskIdsToMove) {
      final candidate = allTasks.firstWhere(
        (t) => t.id == taskId,
        orElse: () => task,
      );
      if (candidate.status != newStatus) {
        updates.add(
          ServiceLocator.taskService.updateTaskStatus(taskId, newStatus),
        );
      }
    }

    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }
  }

  Future<void> _onTaskGroupedUnder(
    Task dragged,
    Task target,
    List<Task> allTasks,
  ) async {
    if (dragged.id == target.id) return;
    if (_isTaskDescendant(
      ancestorId: dragged.id,
      candidateId: target.id,
      allTasks: allTasks,
    )) {
      return;
    }

    await ServiceLocator.taskService.updateTask(
      taskId: dragged.id,
      parentId: target.id,
      status: target.status,
    );
  }

  Future<void> _onTaskDroppedOnTask(
    Task dragged,
    Task target,
    DropZone zone,
    List<Task> allTasks,
  ) async {
    if (dragged.id == target.id) return;

    switch (zone) {
      case DropZone.child:
        if (_isTaskDescendant(
          ancestorId: dragged.id,
          candidateId: target.id,
          allTasks: allTasks,
        )) {
          return;
        }
        await ServiceLocator.taskService.updateTask(
          taskId: dragged.id,
          parentId: target.id,
          status: target.status,
        );
      case DropZone.above:
        final sortOrder = _computeSortOrderBefore(target, allTasks);
        if (target.parentId == null) {
          await ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            clearParentId: true,
            sortOrder: sortOrder,
            status: target.status,
          );
        } else {
          await ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            parentId: target.parentId,
            sortOrder: sortOrder,
            status: target.status,
          );
        }
      case DropZone.below:
        final sortOrder = _computeSortOrderAfter(target, allTasks);
        if (target.parentId == null) {
          await ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            clearParentId: true,
            sortOrder: sortOrder,
            status: target.status,
          );
        } else {
          await ServiceLocator.taskService.updateTask(
            taskId: dragged.id,
            parentId: target.parentId,
            sortOrder: sortOrder,
            status: target.status,
          );
        }
      case DropZone.unparent:
      case DropZone.none:
        break;
    }
  }

  List<Task> _getSiblings(Task task, List<Task> allTasks) {
    final siblings =
        allTasks.where((t) => t.parentId == task.parentId).toList();
    siblings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return siblings;
  }

  double _computeSortOrderBefore(Task target, List<Task> allTasks) {
    final siblings = _getSiblings(target, allTasks);
    final idx = siblings.indexWhere((t) => t.id == target.id);
    if (idx <= 0) {
      return target.sortOrder - 1000;
    }
    return (siblings[idx - 1].sortOrder + target.sortOrder) / 2;
  }

  double _computeSortOrderAfter(Task target, List<Task> allTasks) {
    final siblings = _getSiblings(target, allTasks);
    final idx = siblings.indexWhere((t) => t.id == target.id);
    if (idx < 0 || idx >= siblings.length - 1) {
      return target.sortOrder + 1000;
    }
    return (target.sortOrder + siblings[idx + 1].sortOrder) / 2;
  }

  Set<String> _collectDescendantIds(String parentId, List<Task> allTasks) {
    final childrenByParent = HierarchyUtils.buildChildrenMap<Task>(
      allTasks,
      idOf: (task) => task.id,
      parentIdOf: (task) => task.parentId,
    );
    return HierarchyUtils.collectDescendantIds<Task>(
      parentId,
      childrenByParent,
      idOf: (task) => task.id,
    );
  }

  bool _isTaskDescendant({
    required String ancestorId,
    required String candidateId,
    required List<Task> allTasks,
  }) {
    final taskMap = {for (final task in allTasks) task.id: task};
    return HierarchyUtils.isDescendantOf<Task>(
      ancestorId: ancestorId,
      candidateId: candidateId,
      itemsById: taskMap,
      parentIdOf: (task) => task.parentId,
    );
  }

  void _onTaskTap(Task task) {
    showTaskFormPopup(context, projectId: task.projectId, taskId: task.id);
  }

  void _onTaskDragStarted() {
    if (!_isTaskDragging) {
      setState(() => _isTaskDragging = true);
    }
  }

  void _onTaskDragEnded() {
    if (_isTaskDragging || _isUngroupDropTargetActive) {
      setState(() {
        _isTaskDragging = false;
        _isUngroupDropTargetActive = false;
      });
    }
  }
}

/// A single Kanban column for a status.
class _KanbanColumn extends StatefulWidget {
  final bool compact;
  final String status;
  final String label;
  final Color color;
  final List<Task> tasks;
  final List<Task> allTasks;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final bool hierarchyEnabled;
  final void Function(Task task) onTaskDroppedToColumn;
  final void Function(Task dragged, Task target) onTaskGroupedUnder;
  final void Function(Task dragged, Task target, DropZone zone)
      onTaskDroppedOnTask;
  final void Function(Task task) onTaskTap;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  const _KanbanColumn({
    this.compact = false,
    required this.status,
    required this.label,
    required this.color,
    required this.tasks,
    required this.allTasks,
    required this.usersMap,
    required this.allWorkspaceUsers,
    required this.hierarchyEnabled,
    required this.onTaskDroppedToColumn,
    required this.onTaskGroupedUnder,
    required this.onTaskDroppedOnTask,
    required this.onTaskTap,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  bool _isDragOver = false;
  // Track per-task drop zones by task id
  final Map<String, DropZone> _taskDropZones = {};
  final Map<String, GlobalKey> _taskKeys = {};

  @override
  Widget build(BuildContext context) {
    final entries = widget.hierarchyEnabled
        ? _buildHierarchyEntries(widget.tasks)
        : widget.tasks
              .map(
                (task) => _KanbanTaskEntry(task: task, depth: 0, childCount: 0),
              )
              .toList();

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        widget.onTaskDroppedToColumn(details.data);
      },
      onMove: (_) {
        if (!_isDragOver) setState(() => _isDragOver = true);
      },
      onLeave: (_) {
        if (_isDragOver) setState(() => _isDragOver = false);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: _isDragOver
                ? widget.color.withValues(alpha: 0.08)
                : ChromeColors.of(context).isDark
                    ? const Color(0xFF253347)
                    : Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(
              color: _isDragOver
                  ? widget.color.withValues(alpha: 0.5)
                  : ChromeColors.of(context).isDark
                      ? const Color(0xFF334155)
                      : AppColors.cardBorder.withValues(alpha: 0.5),
              width: _isDragOver ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: widget.compact
                    ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
                    : const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: widget.compact ? 8 : 10,
                      height: widget.compact ? 8 : 10,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: widget.compact ? 4 : 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: widget.compact ? 11 : 13,
                          fontWeight: FontWeight.w600,
                          color: ChromeColors.of(context).isDark
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        '${widget.tasks.length}',
                        style: TextStyle(
                          fontSize: widget.compact ? 10 : 11,
                          fontWeight: FontWeight.w600,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'No tasks',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _buildTaskItem(entry);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_KanbanTaskEntry> _buildHierarchyEntries(List<Task> tasksInColumn) {
    final taskIds = tasksInColumn.map((t) => t.id).toSet();
    final allByParent = HierarchyUtils.buildChildrenMap<Task>(
      tasksInColumn,
      idOf: (task) => task.id,
      parentIdOf: (task) => task.parentId,
      sort: (a, b) => a.createdAt.compareTo(b.createdAt),
    );
    final byParent = <String, List<Task>>{
      for (final entry in allByParent.entries)
        if (entry.key.isNotEmpty && taskIds.contains(entry.key))
          entry.key: entry.value,
    };

    final roots =
        tasksInColumn
            .where(
              (task) =>
                  task.parentId == null || !taskIds.contains(task.parentId),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final entries = <_KanbanTaskEntry>[];
    for (final root in roots) {
      _appendTaskWithChildren(root, 0, byParent, entries);
    }
    return entries;
  }

  int _appendTaskWithChildren(
    Task task,
    int depth,
    Map<String, List<Task>> byParent,
    List<_KanbanTaskEntry> entries,
  ) {
    final children = List<Task>.from(byParent[task.id] ?? const <Task>[])
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final entry = _KanbanTaskEntry(task: task, depth: depth, childCount: 0);
    entries.add(entry);

    var descendantCount = 0;
    for (final child in children) {
      descendantCount += 1;
      descendantCount += _appendTaskWithChildren(
        child,
        depth + 1,
        byParent,
        entries,
      );
    }

    entry.childCount = descendantCount;
    return descendantCount;
  }

  Widget _buildTaskItem(_KanbanTaskEntry entry) {
    final task = entry.task;
    _taskKeys.putIfAbsent(task.id, () => GlobalKey());
    final taskKey = _taskKeys[task.id]!;

    final feedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.info, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 16, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    final Widget draggableCard;
    if (isMobile) {
      // On mobile, only a dedicated drag handle initiates a drag. This
      // prevents accidental drags when the user is swiping horizontally
      // between columns or vertically through the list.
      draggableCard = Stack(
        children: [
          _buildCard(task, entry),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: LongPressDraggable<Task>(
              data: task,
              feedback: feedback,
              onDragStarted: widget.onDragStarted,
              onDragEnd: (_) => widget.onDragEnded(),
              hapticFeedbackOnStart: true,
              child: Container(
                width: 32,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      draggableCard = Draggable<Task>(
        data: task,
        feedback: feedback,
        onDragStarted: widget.onDragStarted,
        onDragEnd: (_) => widget.onDragEnded(),
        childWhenDragging:
            Opacity(opacity: 0.3, child: _buildCard(task, entry)),
        child: _buildCard(task, entry),
      );
    }

    final cardContent = DragTarget<Task>(
      onWillAcceptWithDetails: (details) => details.data.id != task.id,
      onAcceptWithDetails: (details) {
        final zone = _taskDropZones[task.id] ?? DropZone.below;
        setState(() => _taskDropZones.remove(task.id));
        if (widget.hierarchyEnabled && zone == DropZone.child) {
          widget.onTaskGroupedUnder(details.data, task);
        } else {
          widget.onTaskDroppedOnTask(details.data, task, zone);
        }
      },
      onMove: (details) {
        final keyContext = taskKey.currentContext;
        if (keyContext == null) return;
        final zone = computeDropZone(
          keyContext,
          details.offset,
          depth: entry.depth,
          hasParent: task.parentId != null,
          hasVisibleChildren:
              widget.hierarchyEnabled && entry.childCount > 0,
        );
        if (_taskDropZones[task.id] != zone) {
          setState(() => _taskDropZones[task.id] = zone);
        }
      },
      onLeave: (_) {
        if (_taskDropZones.containsKey(task.id)) {
          setState(() => _taskDropZones.remove(task.id));
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        final zone = _taskDropZones[task.id] ?? DropZone.none;
        return Column(
          key: taskKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Above insertion indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: isActive && zone == DropZone.above ? 3 : 0,
              margin: isActive && zone == DropZone.above
                  ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: AppColors.info,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Card with child-drop highlight
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: isActive &&
                        zone == DropZone.child &&
                        widget.hierarchyEnabled
                    ? Border.all(color: AppColors.success, width: 2)
                    : null,
              ),
              child: draggableCard,
            ),
            // Below insertion indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: isActive && zone == DropZone.below ? 3 : 0,
              margin: isActive && zone == DropZone.below
                  ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: AppColors.info,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        );
      },
    );

    return Container(
      margin: EdgeInsets.only(left: entry.depth * 14.0),
      child: cardContent,
    );
  }

  Widget _buildCard(Task task, _KanbanTaskEntry entry) {
    return Stack(
      children: [
        KanbanTaskCard(
          task: task,
          usersMap: widget.usersMap,
          allWorkspaceUsers: widget.allWorkspaceUsers,
          compact: widget.compact,
          onTap: () => widget.onTaskTap(task),
        ),
        if (entry.childCount > 0)
          Positioned(
            right: 14,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                '${entry.childCount}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.info,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KanbanTaskEntry {
  final Task task;
  final int depth;
  int childCount;

  _KanbanTaskEntry({
    required this.task,
    required this.depth,
    required this.childCount,
  });
}
