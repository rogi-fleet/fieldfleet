import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import '../../utils/hierarchy_flatten.dart';
import '../table/composition_badges.dart';
import 'task_group_header.dart';
import 'task_row.dart';
import 'quick_add_row.dart';

/// A collapsible group container that holds a header, task rows, and a quick-add row.
class TaskGroup extends StatefulWidget {
  final String groupId;
  final String title;
  final Color groupColor;
  final List<Task> tasks;
  final List<Task> allTasks;
  final bool isExpanded;
  final bool showProjectColumn;
  final double projectColumnWidth;
  final double customerNameColumnWidth;
  final double jobNumberColumnWidth;
  final double jobAddressColumnWidth;
  final double statusColumnWidth;
  final double dueDateColumnWidth;
  final double assigneeColumnWidth;
  final double notesColumnWidth;
  final double progressColumnWidth;
  final Set<String> hiddenColumnIds;
  final Map<String, String> projectNames;
  final Map<String, Project> projectMap;
  final Map<String, Property> propertyMap;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final Map<String, bool> expansionStates;
  final VoidCallback onToggle;
  final Future<void> Function(String title) onQuickAdd;
  final VoidCallback? onEditGroup;
  final void Function(String taskId) onDeleteTask;
  final void Function(String taskId, bool expanded)? onTaskExpandToggle;

  /// Called when a task is dropped onto the group header (move into this group).
  final void Function(Task task)? onTaskDroppedOnHeader;
  final void Function(Task task, GroupHeaderDropZone zone)?
  onTaskDroppedOnHeaderWithZone;
  final Task? draggableGroupTask;
  final ValueChanged<String>? onRenameGroup;
  final String? summaryStatus;
  final DateTime? summaryDueDate;
  final int? summaryProgress;
  final List<AppUser> summaryAssignees;
  final bool showSummaryColumns;
  final ValueChanged<String>? onSummaryStatusChanged;
  final ValueChanged<String?>? onSummaryAssigneeSelected;
  final void Function(Task task)? onUngroupTask;

  /// Called when a task is dropped onto another task row (reorder / re-parent).
  final void Function(Task dragged, Task target, DropZone zone)?
  onTaskDroppedOnTask;
  final VoidCallback? onTaskDragStarted;
  final VoidCallback? onTaskDragEnded;
  final bool isAnyTaskDragging;

  final Set<String> selectedTaskIds;
  final void Function(Task task, bool isSelected)? onSelectionChanged;
  final void Function(List<Task> groupTasks, bool selectAll)? onGroupSelectAll;
  final List<AppUser> allWorkspaceUsersForSummary;
  final bool showPhaseHierarchyGuides;
  final Map<String, int> commentCounts;
  final Comparator<Task>? customSortSiblings;

  const TaskGroup({
    super.key,
    required this.groupId,
    required this.title,
    required this.groupColor,
    required this.tasks,
    required this.allTasks,
    required this.isExpanded,
    this.showProjectColumn = false,
    this.projectColumnWidth = 120,
    this.customerNameColumnWidth = 140,
    this.jobNumberColumnWidth = 90,
    this.jobAddressColumnWidth = 160,
    this.statusColumnWidth = 116,
    this.dueDateColumnWidth = 96,
    this.assigneeColumnWidth = 62,
    this.notesColumnWidth = 34,
    this.progressColumnWidth = 52,
    this.hiddenColumnIds = const {},
    this.projectNames = const {},
    this.projectMap = const {},
    this.propertyMap = const {},
    this.usersMap = const {},
    this.allWorkspaceUsers = const [],
    this.expansionStates = const {},
    required this.onToggle,
    required this.onQuickAdd,
    this.onEditGroup,
    required this.onDeleteTask,
    this.onTaskExpandToggle,
    this.onTaskDroppedOnHeader,
    this.onTaskDroppedOnHeaderWithZone,
    this.draggableGroupTask,
    this.onRenameGroup,
    this.summaryStatus,
    this.summaryDueDate,
    this.summaryProgress,
    this.summaryAssignees = const [],
    this.showSummaryColumns = false,
    this.onSummaryStatusChanged,
    this.onSummaryAssigneeSelected,
    this.onUngroupTask,
    this.onTaskDroppedOnTask,
    this.onTaskDragStarted,
    this.onTaskDragEnded,
    this.isAnyTaskDragging = false,
    this.selectedTaskIds = const {},
    this.onSelectionChanged,
    this.onGroupSelectAll,
    this.allWorkspaceUsersForSummary = const [],
    this.showPhaseHierarchyGuides = false,
    this.commentCounts = const {},
    this.customSortSiblings,
  });

  @override
  State<TaskGroup> createState() => _TaskGroupState();
}

class _TaskGroupState extends State<TaskGroup> {
  final _quickAddKey = GlobalKey<QuickAddRowState>();

  void _onAddTaskPressed() {
    if (!widget.isExpanded) {
      widget.onToggle();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _quickAddKey.currentState?.activateEditing();
      });
    } else {
      _quickAddKey.currentState?.activateEditing();
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = widget.tasks.where((t) => t.isComplete).length;

    // Compute select-all state for the group header
    bool? isAllSelected;
    if (widget.tasks.isNotEmpty && widget.onSelectionChanged != null) {
      final selectedCount = widget.tasks
          .where((t) => widget.selectedTaskIds.contains(t.id))
          .length;
      if (selectedCount == 0) {
        isAllSelected = null; // none selected
      } else if (selectedCount == widget.tasks.length) {
        isAllSelected = true; // all selected
      } else {
        isAllSelected = false; // some selected
      }
    }

    // Compute status composition badges
    final statusCounts = <String, int>{};
    for (final task in widget.tasks) {
      statusCounts[task.status] = (statusCounts[task.status] ?? 0) + 1;
    }
    final statusBadges = <CompositionBadge>[
      if ((statusCounts['stuck'] ?? 0) > 0)
        CompositionBadge(
          label: 'Stuck',
          count: statusCounts['stuck']!,
          total: widget.tasks.length,
          color: AppColors.error,
        ),
      if ((statusCounts['not_started'] ?? 0) > 0)
        CompositionBadge(
          label: 'Not Started',
          count: statusCounts['not_started']!,
          total: widget.tasks.length,
          color: AppColors.textTertiary,
        ),
      if ((statusCounts['working_on_it'] ?? 0) > 0)
        CompositionBadge(
          label: 'Working',
          count: statusCounts['working_on_it']!,
          total: widget.tasks.length,
          color: AppColors.info,
        ),
      if ((statusCounts['done'] ?? 0) > 0)
        CompositionBadge(
          label: 'Done',
          count: statusCounts['done']!,
          total: widget.tasks.length,
          color: AppColors.success,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TaskGroupHeader(
          title: widget.title,
          taskCount: widget.tasks.length,
          completedCount: completedCount,
          statusBadges: statusBadges,
          groupColor: widget.groupColor,
          isExpanded: widget.isExpanded,
          onToggle: widget.onToggle,
          onAddTask: _onAddTaskPressed,
          onEditGroup: widget.onEditGroup,
          onTaskDropped: widget.onTaskDroppedOnHeader,
          onTaskDroppedWithZone: widget.onTaskDroppedOnHeaderWithZone,
          draggableTask: widget.draggableGroupTask,
          onRenameGroup: widget.onRenameGroup,
          summaryStatus: widget.summaryStatus,
          summaryDueDate: widget.summaryDueDate,
          summaryProgress: widget.summaryProgress,
          summaryAssignees: widget.summaryAssignees,
          usersMap: widget.usersMap,
          showSummaryColumns: widget.showSummaryColumns,
          showProjectColumn: widget.showProjectColumn,
          projectColumnWidth: widget.projectColumnWidth,
          customerNameColumnWidth: widget.customerNameColumnWidth,
          jobNumberColumnWidth: widget.jobNumberColumnWidth,
          jobAddressColumnWidth: widget.jobAddressColumnWidth,
          statusColumnWidth: widget.statusColumnWidth,
          dueDateColumnWidth: widget.dueDateColumnWidth,
          assigneeColumnWidth: widget.assigneeColumnWidth,
          notesColumnWidth: widget.notesColumnWidth,
          progressColumnWidth: widget.progressColumnWidth,
          hiddenColumnIds: widget.hiddenColumnIds,
          onSummaryStatusChanged: widget.onSummaryStatusChanged,
          onSummaryAssigneeSelected: widget.onSummaryAssigneeSelected,
          allWorkspaceUsers: widget.allWorkspaceUsersForSummary,
          isAllSelected: isAllSelected,
          onSelectAllChanged: widget.onGroupSelectAll != null
              ? (selectAll) => widget.onGroupSelectAll!(widget.tasks, selectAll)
              : null,
        ),
        if (widget.isExpanded) ...[
          // Build task rows - handle hierarchy within the group
          ..._buildTaskRows(),
          // Quick add row
          QuickAddRow(
            key: _quickAddKey,
            groupColor: widget.groupColor,
            onSubmit: widget.onQuickAdd,
            showPhaseHierarchyGuide: widget.showPhaseHierarchyGuides,
            groupIsEmpty:
                widget.showPhaseHierarchyGuides && widget.tasks.isEmpty,
            onTaskDropped: widget.onTaskDroppedOnHeader,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildTaskRows() {
    final entries = flattenHierarchy<Task>(
      items: widget.tasks,
      idOf: (task) => task.id,
      parentIdOf: (task) => task.parentId,
      isExpandedOf: (task) =>
          widget.expansionStates[task.id] ?? task.isExpanded,
      sortSiblings:
          widget.customSortSiblings ??
          (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );

    return entries.map((entry) {
      final task = entry.item;
      final isTaskExpanded = widget.expansionStates[task.id] ?? task.isExpanded;
      return TaskRow(
        key: ValueKey(task.id),
        task: task,
        allTasks: widget.allTasks,
        depth: entry.depth,
        treeGuides: entry.treeGuides,
        isLastChild: entry.isLastChild,
        hasChildren: entry.hasChildren,
        isExpanded: isTaskExpanded,
        showProjectColumn: widget.showProjectColumn,
        projectColumnWidth: widget.projectColumnWidth,
        customerNameColumnWidth: widget.customerNameColumnWidth,
        jobNumberColumnWidth: widget.jobNumberColumnWidth,
        jobAddressColumnWidth: widget.jobAddressColumnWidth,
        statusColumnWidth: widget.statusColumnWidth,
        dueDateColumnWidth: widget.dueDateColumnWidth,
        assigneeColumnWidth: widget.assigneeColumnWidth,
        notesColumnWidth: widget.notesColumnWidth,
        progressColumnWidth: widget.progressColumnWidth,
        hiddenColumnIds: widget.hiddenColumnIds,
        projectName: widget.projectNames[task.projectId],
        project: widget.projectMap[task.projectId],
        propertyMap: widget.propertyMap,
        usersMap: widget.usersMap,
        allWorkspaceUsers: widget.allWorkspaceUsers,
        onExpandToggle: entry.hasChildren
            ? () => widget.onTaskExpandToggle?.call(task.id, !isTaskExpanded)
            : null,
        onDelete: () => widget.onDeleteTask(task.id),
        onUngroup: task.taskType == TaskType.summary
            ? () => widget.onUngroupTask?.call(task)
            : null,
        onTaskDroppedOnTask: widget.onTaskDroppedOnTask,
        onDragStarted: widget.onTaskDragStarted,
        onDragEnded: widget.onTaskDragEnded,
        isAnyTaskDragging: widget.isAnyTaskDragging,
        isSelected: widget.selectedTaskIds.contains(task.id),
        onSelectionChanged: widget.onSelectionChanged,
        showPhaseHierarchyGuide: widget.showPhaseHierarchyGuides,
        commentCount: widget.commentCounts[task.id],
      );
    }).toList();
  }
}
