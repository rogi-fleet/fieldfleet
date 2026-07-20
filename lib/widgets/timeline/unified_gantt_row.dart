import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/gantt_task_extensions.dart';
import '../../models/schedule_baseline.dart';
import '../../models/user.dart';
import '../../models/skill.dart';
import '../../services/service_locator.dart';

import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import 'timeline_calculator.dart';
import 'package:intl/intl.dart';
import '../task_form_popup.dart';
import '../group_form_popup.dart';
import '../task_assignee_avatars.dart';
import '../task_comments_widget.dart';
import '../skill_chip.dart';
import '../table/inline_edit_text_field.dart';
import '../task_hover_tooltip.dart';
import '../../utils/text_selection_utils.dart';

/// Unified Gantt row that contains both data columns AND timeline bar
/// This replaces the separated table/timeline approach
class UnifiedGanttRow extends StatefulWidget {
  final Task task;
  final List<Task> allTasks;
  final int rowIndex;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final double rowHeight;
  final Function(Task) onTaskTap;
  final Function(Task, bool) onExpandToggle;
  final Function(Task)? onTaskChanged;
  final Function(String, String?)? onTaskCreated;
  final Function(String, String?)?
  onGroupCreated; // For creating groups with parentId
  final Function(Task)? onTaskDelete;
  final Function(Task, TaskType)?
  onConvertTaskType; // For converting task to group or vice versa
  final Function(Task)? onTaskClone; // Callback to clone a task or group
  final Function(Task)?
  onSaveAsTemplate; // Save this task/group (and subtree) as a template
  final Function(String?)?
  onImportTemplate; // Import a template under this group (arg = parent id)
  final Function(Task)?
  onScrollToTask; // NEW: Callback to scroll timeline to task
  final Function(Task, String?)?
  onTaskParentChanged; // Callback when task is dropped onto another to change parent
  final VoidCallback? onTaskDragStarted;
  final VoidCallback? onTaskDragEnded;
  final bool showFixedColumnsOnly; // NEW: Show only fixed columns
  final bool showTimelineOnly; // NEW: Show only timeline
  final Map<String, AppUser> usersMap; // Map of user IDs to users for avatars
  final List<AppUser>
  allWorkspaceUsers; // All workspace users for assignment popup
  final double activityColumnWidth; // Dynamic width for the Activity column
  // Dependency linking callbacks
  final Function(Task, bool)?
  onDependencyDragStart; // (sourceTask, fromEnd) - true if dragging from end anchor
  final Function(Offset)?
  onDependencyDragUpdate; // Called with current drag position
  final VoidCallback? onDependencyDragEnd; // Called when drag ends
  final bool isExpanded; // Per-user expansion state passed from parent
  final bool autoEditOnMount; // If true, start in inline edit mode
  final VoidCallback? onAutoEditComplete; // Called when auto-edit is done
  final bool isSelected; // Whether this task is selected for mass edit
  final Function(Task, bool)?
  onSelectionChanged; // Callback when selection changes
  final Function(Task, int)?
  onGroupShifted; // (group, dayOffset) — summary bar dragged horizontally
  final BaselineTaskDates?
  baselineDates; // Snapshot dates to render as a ghost bar (null = hidden)

  const UnifiedGanttRow({
    super.key,
    required this.task,
    required this.allTasks,
    required this.rowIndex,
    required this.calculator,
    required this.rangeStart,
    required this.rowHeight,
    required this.onTaskTap,
    required this.onExpandToggle,
    required this.isExpanded,
    this.onTaskChanged,
    this.onTaskCreated,
    this.onGroupCreated,
    this.onTaskDelete,
    this.onConvertTaskType,
    this.onTaskClone,
    this.onSaveAsTemplate,
    this.onImportTemplate,
    this.onScrollToTask,
    this.onTaskParentChanged,
    this.onTaskDragStarted,
    this.onTaskDragEnded,
    this.showFixedColumnsOnly = false,
    this.showTimelineOnly = false,
    this.usersMap = const {},
    this.allWorkspaceUsers = const [],
    this.activityColumnWidth = 250.0, // Default width
    this.onDependencyDragStart,
    this.onDependencyDragUpdate,
    this.onDependencyDragEnd,
    this.autoEditOnMount = false,
    this.onAutoEditComplete,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onGroupShifted,
    this.baselineDates,
  });

  @override
  State<UnifiedGanttRow> createState() => _UnifiedGanttRowState();
}

class _UnifiedGanttRowState extends State<UnifiedGanttRow> {
  bool _isHovered = false;
  bool _isDragTarget = false; // Tracks if this row is a potential drop target
  bool _isDragging = false;
  bool _isResizingStart = false;
  bool _isResizingEnd = false;
  double _dragOffset = 0;
  double _totalDragDistance = 0;
  bool _isEditingName = false;
  bool _isTimelineBarHovered = false; // For showing dependency anchor dots
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task.title);
    // Auto-start in edit mode if flag is set (for newly created tasks)
    if (widget.autoEditOnMount) {
      _isEditingName = true;
      // Clear the empty title for new tasks
      if (widget.task.title == 'New Subtask' || widget.task.title.isEmpty) {
        _nameController.text = '';
      }
      // Schedule callback to clear the auto-edit flag after mount
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAutoEditComplete?.call();
      });
    }
  }

  @override
  void didUpdateWidget(UnifiedGanttRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if autoEditOnMount just became true (wasn't true before, but is now)
    if (!oldWidget.autoEditOnMount &&
        widget.autoEditOnMount &&
        !_isEditingName) {
      setState(() {
        _isEditingName = true;
        // Clear the empty title for new tasks
        if (widget.task.title == 'New Subtask' || widget.task.title.isEmpty) {
          _nameController.text = '';
        }
      });
      // Schedule callback to clear the auto-edit flag
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAutoEditComplete?.call();
      });
    }

    // Update the controller if the task title changed externally
    if (widget.task.title != oldWidget.task.title && !_isEditingName) {
      _nameController.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Conditional rendering based on flags
    if (widget.showFixedColumnsOnly) {
      return _buildFixedColumnsOnly();
    } else if (widget.showTimelineOnly) {
      return _buildTimelineOnly();
    }

    // Default: render both (for backward compatibility)
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          color: _isHovered
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Fixed data columns (left side)
            SizedBox(
              width: 920,
              child: Row(
                children: [
                  _buildCombinedIDSelectionColumn(),
                  _buildActivityColumn(
                    widget.task.getNestingLevel(widget.allTasks),
                    widget.task.hasChildren(widget.allTasks),
                  ),
                  _buildActionsColumn(),
                  _buildStartColumn(),
                  _buildDurationColumn(),
                  _buildEndColumn(),
                  _buildProgressColumn(),
                  _buildPredecessorsColumn(),
                  _buildSuccessorsColumn(),
                ],
              ),
            ),

            // Vertical divider line
            Container(width: 2, color: Theme.of(context).dividerColor),

            // Timeline section (right side)
            Expanded(child: _buildTimelineBar()),
          ],
        ),
      ),
    );
  }

  // Build ONLY fixed columns
  Widget _buildFixedColumnsOnly() {
    final level = widget.task.getNestingLevel(widget.allTasks);
    final hasChildren = widget.task.hasChildren(widget.allTasks);
    // Build the fixed columns row content
    final rowContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          // Alternating row backgrounds - white/light grey for left panel
          color: _isDragTarget
              ? AppColors.info.withValues(alpha: 0.2)
              : _isHovered
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : widget.rowIndex.isEven
              ? Colors.white
              : const Color(0xFFF8F9FA), // Very light grey
          border: Border(
            bottom: BorderSide(
              color: _isDragTarget
                  ? AppColors.info
                  : Theme.of(context).dividerColor.withValues(alpha: 0.5),
              width: _isDragTarget ? 2 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Combined ID and Selection Column (NOT draggable)
            _buildCombinedIDSelectionColumn(),
            // The rest of the row (handle + data) is draggable
            _buildDraggableRowContent(level, hasChildren),
          ],
        ),
      ),
    );

    // Wrap with DragTarget if callback is provided
    if (widget.onTaskParentChanged == null) {
      return rowContent;
    }

    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        // Don't accept if dragging onto self or onto own child
        final draggedTask = details.data;
        if (draggedTask.id == widget.task.id) return false;
        // Don't allow dropping onto own descendants
        if (_isDescendantOf(draggedTask, widget.task)) return false;
        return true;
      },
      onAcceptWithDetails: (details) {
        final draggedTask = details.data;
        // Set this task as the parent of the dragged task
        widget.onTaskParentChanged!(draggedTask, widget.task.id);
        setState(() => _isDragTarget = false);
      },
      onMove: (details) {
        if (!_isDragTarget) setState(() => _isDragTarget = true);
      },
      onLeave: (data) {
        if (_isDragTarget) setState(() => _isDragTarget = false);
      },
      builder: (context, candidateData, rejectedData) {
        return rowContent;
      },
    );
  }

  // Helper to check if task is a descendant of another
  bool _isDescendantOf(Task parent, Task potentialDescendant) {
    String? currentParentId = potentialDescendant.parentId;
    while (currentParentId != null) {
      if (currentParentId == parent.id) return true;
      final parentTask = widget.allTasks.firstWhere(
        (t) => t.id == currentParentId,
        orElse: () => widget.task,
      );
      if (parentTask.id == currentParentId) break;
      currentParentId = parentTask.parentId;
    }
    return false;
  }

  Widget _buildCombinedIDSelectionColumn() {
    return SizedBox(
      width: 50,
      child: Center(
        // The "Checkbox" square with ID
        child: InkWell(
          onTap: () {
            if (widget.onSelectionChanged != null) {
              widget.onSelectionChanged!(widget.task, !widget.isSelected);
            }
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: widget.isSelected
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.textTertiary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Center(
              child: Text(
                '${widget.rowIndex + 1}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: widget.isSelected
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

  Widget _buildDraggableRowContent(int level, bool hasChildren) {
    Widget content = Row(
      children: [
        _buildActivityColumn(level, hasChildren),
        _buildActionsColumn(),
        _buildStartColumn(),
        _buildDurationColumn(),
        _buildEndColumn(),
        _buildProgressColumn(),
        _buildPredecessorsColumn(),
        _buildSuccessorsColumn(),
      ],
    );

    if (widget.onTaskParentChanged == null) {
      return content;
    }

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final feedbackWidget = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: widget.activityColumnWidth + 100,
        height: widget.rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.info, width: 2),
        ),
        child: Row(
          children: [
            _buildDragIndicatorIcon(AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.task.title,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    final whenDragging = Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.28),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );

    if (isMobile) {
      return LongPressDraggable<Task>(
        data: widget.task,
        onDragStarted: widget.onTaskDragStarted,
        onDragEnd: (_) => widget.onTaskDragEnded?.call(),
        feedback: feedbackWidget,
        childWhenDragging: whenDragging,
        hapticFeedbackOnStart: true,
        child: content,
      );
    }
    return Draggable<Task>(
      data: widget.task,
      onDragStarted: widget.onTaskDragStarted,
      onDragEnd: (_) => widget.onTaskDragEnded?.call(),
      feedback: feedbackWidget,
      childWhenDragging: whenDragging,
      child: content,
    );
  }

  // Build the 6-dot drag indicator icon
  Widget _buildDragIndicatorIcon(Color color) {
    return SizedBox(
      width: 16,
      height: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build ONLY timeline section
  Widget _buildTimelineOnly() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          // Alternating row backgrounds - slightly greyer for timeline area
          color: _isHovered
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : widget.rowIndex.isEven
              ? const Color(0xFFFAFBFC) // Very light grey-white
              : const Color(0xFFF3F4F6), // Light grey
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: _buildTimelineBar(),
      ),
    );
  }

  // Column 2: Activity (200px) - with indentation and expand icon
  Widget _buildActionsColumn() {
    return SizedBox(
      width: 100,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Progress indicator - clickable to show progress picker
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                // Groups cannot set progress manually - it's calculated from children
                onTap: widget.task.taskType == TaskType.summary
                    ? null
                    : () => _showProgressPicker(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter: _ProgressCirclePainter(
                      progress:
                          widget.task.getEffectiveProgress(widget.allTasks) /
                          100,
                      color: _getProgressColor(
                        widget.task.getEffectiveProgress(widget.allTasks),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Jump to task button (always visible if task has dates)
            if (widget.task.startDate != null && widget.onScrollToTask != null)
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 16),
                onPressed: () {
                  if (widget.onScrollToTask != null) {
                    widget.onScrollToTask!(widget.task);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: widget.task.taskType == TaskType.summary
                    ? 'Jump to phase on timeline'
                    : 'Jump to task on timeline',
                color: AppColors.infoDark,
              )
            else
              const SizedBox(width: 16),

            // Edit button (always visible)
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () {
                if (widget.task.taskType == TaskType.summary) {
                  showGroupFormPopup(
                    context,
                    projectId: widget.task.projectId,
                    groupId: widget.task.id,
                  );
                } else {
                  showTaskFormPopup(
                    context,
                    projectId: widget.task.projectId,
                    taskId: widget.task.id,
                  );
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: widget.task.taskType == TaskType.summary
                  ? 'Edit phase'
                  : 'Edit task',
              color: AppColors.textPrimary,
            ),

            // More options menu (...)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 16,
                color: AppColors.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'More options',
              onSelected: (value) {
                switch (value) {
                  case 'delete':
                    if (widget.onTaskDelete != null) {
                      widget.onTaskDelete!(widget.task);
                    }
                    break;
                  case 'clone':
                    if (widget.onTaskClone != null) {
                      widget.onTaskClone!(widget.task);
                    }
                    break;
                  case 'convert_to_group':
                    if (widget.onConvertTaskType != null) {
                      widget.onConvertTaskType!(widget.task, TaskType.summary);
                    }
                    break;
                  case 'convert_to_task':
                    if (widget.onConvertTaskType != null) {
                      widget.onConvertTaskType!(widget.task, TaskType.standard);
                    }
                    break;
                  case 'save_as_template':
                    if (widget.onSaveAsTemplate != null) {
                      widget.onSaveAsTemplate!(widget.task);
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
                // Save as template option
                if (widget.onSaveAsTemplate != null)
                  PopupMenuItem<String>(
                    value: 'save_as_template',
                    child: Row(
                      children: [
                        Icon(
                          Icons.bookmark_add_outlined,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.task.taskType == TaskType.summary
                              ? 'Save Phase as Template'
                              : 'Save as Template',
                        ),
                      ],
                    ),
                  ),
                // Clone option
                if (widget.onTaskClone != null)
                  PopupMenuItem<String>(
                    value: 'clone',
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy_outlined,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.task.taskType == TaskType.summary
                              ? 'Clone Phase'
                              : 'Clone Task',
                        ),
                      ],
                    ),
                  ),
                // Convert option - show opposite of current type
                if (widget.onConvertTaskType != null &&
                    widget.task.taskType == TaskType.standard)
                  const PopupMenuItem<String>(
                    value: 'convert_to_group',
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Convert to Phase'),
                      ],
                    ),
                  ),
                if (widget.onConvertTaskType != null &&
                    widget.task.taskType == TaskType.summary)
                  const PopupMenuItem<String>(
                    value: 'convert_to_task',
                    child: Row(
                      children: [
                        Icon(Icons.task_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Convert to Task'),
                      ],
                    ),
                  ),
                // Delete option
                if (widget.onTaskDelete != null)
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityColumn(int level, bool hasChildren) {
    // Calculate which levels should have vertical lines (because an ancestor has more children)
    final List<bool> ancestorHasMoreChildren = List.filled(level, false);
    Task? current = widget.task;
    for (int i = level - 1; i >= 0; i--) {
      final parentId = current?.parentId;
      if (parentId != null) {
        final parent = widget.allTasks.firstWhere((t) => t.id == parentId);
        final siblings = widget.allTasks
            .where((t) => t.parentId == parentId)
            .toList();
        siblings.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final isLastChild =
            siblings.isNotEmpty && siblings.last.id == current?.id;
        ancestorHasMoreChildren[i] = !isLastChild;
        current = parent;
      } else {
        // Root level
        final roots = widget.allTasks.where((t) => t.parentId == null).toList();
        roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final isLastChild = roots.isNotEmpty && roots.last.id == current?.id;
        ancestorHasMoreChildren[i] = !isLastChild;
        current = null;
      }
    }

    return SizedBox(
      width: widget.activityColumnWidth,
      child: Row(
        children: [
          // Tree lines for each level (16px each for balanced look)
          for (int i = 0; i < level; i++)
            SizedBox(
              width: 16,
              height: widget.rowHeight,
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
              width: 12,
              height: widget.rowHeight,
              child: InkWell(
                onTap: () =>
                    widget.onExpandToggle(widget.task, !widget.isExpanded),
                child: Center(
                  child: Icon(
                    widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),

          const SizedBox(width: 2),

          // Add button area (18px if group, else 0px)
          if (widget.task.taskType == TaskType.summary &&
              (widget.onTaskCreated != null || widget.onGroupCreated != null))
            SizedBox(
              width: 14,
              height: widget.rowHeight,
              child: PopupMenuButton<String>(
                icon: Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Add to phase',
                onSelected: (value) {
                  if (!widget.isExpanded) {
                    widget.onExpandToggle(widget.task, true);
                  }
                  if (value == 'add_task' && widget.onTaskCreated != null) {
                    widget.onTaskCreated!('New Task', widget.task.id);
                  } else if (value == 'add_group' &&
                      widget.onGroupCreated != null) {
                    widget.onGroupCreated!('New Phase', widget.task.id);
                  } else if (value == 'import_template' &&
                      widget.onImportTemplate != null) {
                    widget.onImportTemplate!(widget.task.id);
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
                          Icon(Icons.create_new_folder_outlined, size: 18),
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

          // Small gap before text
          const SizedBox(width: 4),

          // Task name - editable
          Expanded(
            child: _isEditingName
                ? MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: InlineEditTextField(
                      controller: _nameController,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: widget.task.hasChildren(widget.allTasks)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      borderColor: AppColors.infoDark,
                      onSubmitted: (_) {
                        final trimmedValue = _nameController.text.trim();
                        if (trimmedValue.isNotEmpty &&
                            widget.onTaskChanged != null) {
                          widget.onTaskChanged!(
                            widget.task.copyWith(title: trimmedValue),
                          );
                        }
                        setState(() {
                          _isEditingName = false;
                        });
                      },
                      onTapOutside: (_) {
                        setState(() {
                          _isEditingName = false;
                          _nameController.text =
                              widget.task.title; // Reset if not saved
                        });
                      },
                    ),
                  )
                : TaskHoverTooltip(
                    task: widget.task,
                    usersMap: widget.usersMap,
                    waitDuration: const Duration(milliseconds: 500),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isEditingName = true;
                            _nameController.text = widget.task.title;
                            selectAllText(_nameController);
                          });
                        },
                        child: Row(
                          children: [
                            if (widget.task.description != null &&
                                widget.task.description!.trim().isNotEmpty) ...[
                              Tooltip(
                                message: widget.task.description!.trim(),
                                waitDuration: const Duration(milliseconds: 300),
                                child: const Icon(
                                  Icons.info_outline,
                                  size: 13,
                                  color: AppColors.infoDark,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                widget.task.title,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight:
                                          widget.task.hasChildren(
                                            widget.allTasks,
                                          )
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          // Required skills indicator (only for non-group tasks with skills)
          if (widget.task.taskType != TaskType.summary &&
              widget.task.requiredSkillIds.isNotEmpty)
            _buildSkillsIndicator(),
          // Assigned user avatars - clickable for quick assignment
          // For groups, show aggregated assignees from all descendants
          const SizedBox(width: 4),
          TaskAssigneeAvatars(
            task: widget.task,
            usersMap: widget.usersMap,
            allWorkspaceUsers: widget.allWorkspaceUsers,
            maxVisible: 3,
            avatarSize: 22,
            assigneeIdsOverride: widget.task.taskType == TaskType.summary
                ? widget.task.getAggregatedAssigneeIds(widget.allTasks)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsIndicator() {
    return StreamBuilder<List<Skill>>(
      stream: ServiceLocator.skillService.getSkills(widget.task.workspaceId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final skills = snapshot.data!
            .where((s) => widget.task.requiredSkillIds.contains(s.id))
            .toList();

        if (skills.isEmpty) return const SizedBox.shrink();

        // Show max 2 skills inline, with +N indicator if more
        const maxVisible = 2;
        final visibleSkills = skills.take(maxVisible).toList();
        final remainingCount = skills.length - maxVisible;

        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...visibleSkills.map(
                (skill) => Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: SkillChip(skill: skill, isCompact: true),
                ),
              ),
              if (remainingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    '+$remainingCount',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Column 4: Start (80px)
  Widget _buildStartColumn() {
    final isGroup = widget.task.taskType == TaskType.summary;
    final effectiveStartDate = widget.task.getEffectiveStartDate(
      widget.allTasks,
    );

    return SizedBox(
      width: 80,
      child: InkWell(
        // Groups cannot set dates manually - they're calculated from children
        onTap: isGroup ? null : () => _showStartDatePicker(),
        child: Center(
          child: Text(
            effectiveStartDate != null
                ? DateFormat('MM/dd/yy').format(effectiveStartDate)
                : '-',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isGroup ? AppColors.textSecondary : AppColors.infoDark,
              decoration: isGroup ? null : TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  // Column 5: Duration (100px)
  Widget _buildDurationColumn() {
    final isGroup = widget.task.taskType == TaskType.summary;
    // For groups, calculate duration from effective dates
    String durationText = '-';

    if (isGroup) {
      final effectiveStart = widget.task.getEffectiveStartDate(widget.allTasks);
      final effectiveEnd = widget.task.getEffectiveEndDate(widget.allTasks);
      if (effectiveStart != null && effectiveEnd != null) {
        final days = effectiveEnd.difference(effectiveStart).inDays;
        durationText = '$days days';
      }
    } else if (widget.task.estimatedDuration != null) {
      durationText =
          '${(widget.task.estimatedDuration! / 8).toStringAsFixed(0)} days';
    }

    return SizedBox(
      width: 70,
      child: Center(
        child: Text(durationText, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  // Column 6: End (120px)
  Widget _buildEndColumn() {
    final isGroup = widget.task.taskType == TaskType.summary;
    final effectiveEndDate = widget.task.getEffectiveEndDate(widget.allTasks);

    return SizedBox(
      width: 120,
      child: InkWell(
        // Groups cannot set dates manually - they're calculated from children
        onTap: isGroup ? null : () => _showEndDatePicker(),
        child: Center(
          child: Text(
            effectiveEndDate != null
                ? DateFormat('MM/dd/yy').format(effectiveEndDate)
                : '-',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isGroup ? AppColors.textSecondary : AppColors.infoDark,
              decoration: isGroup ? null : TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  // Column 7: Progress (100px)
  Widget _buildProgressColumn() {
    final effectiveProgress = widget.task.getEffectiveProgress(widget.allTasks);
    return SizedBox(
      width: 100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.base),
        child: Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: effectiveProgress / 100,
                backgroundColor: AppColors.cardBorder,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getProgressColor(effectiveProgress),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('$effectiveProgress%', style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(int progress) {
    // Modern desaturated color palette
    if (progress >= 100) {
      return const Color(0xFF2E9E6B); // Emerald green for complete
    } else if (progress >= 50) {
      return const Color(0xFF4A90A4); // Teal for in progress (50%+)
    } else if (progress > 0) {
      return const Color(0xFFD4836D); // Coral/burnt umber for started (1-49%)
    } else {
      return const Color(0xFF9CA3AF); // Cool grey for not started (0%)
    }
  }

  // Column 8: Predecessors (80px)
  Widget _buildPredecessorsColumn() {
    return SizedBox(
      width: 100,
      child: Center(
        child: Text(
          widget.task.predecessorIds.isNotEmpty
              ? widget.task.predecessorIds
                    .map((id) {
                      final index = widget.allTasks.indexWhere(
                        (t) => t.id == id,
                      );
                      return index >= 0 ? '${index + 1}' : '?';
                    })
                    .join(',')
              : '-',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.infoDark),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // Column 9: Successors (80px)
  Widget _buildSuccessorsColumn() {
    // Find tasks that list this task as a predecessor
    final successors = widget.allTasks
        .where((t) => t.predecessorIds.contains(widget.task.id))
        .toList();

    return SizedBox(
      width: 100,
      child: Center(
        child: Text(
          successors.isNotEmpty
              ? successors
                    .map((t) {
                      final index = widget.allTasks.indexOf(t);
                      return '${index + 1}';
                    })
                    .join(',')
              : '-',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.infoDark),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // Timeline bar (inline with the row)
  Widget _buildTimelineBar() {
    // For groups, use computed dates from children
    final effectiveStartDate = widget.task.getEffectiveStartDate(
      widget.allTasks,
    );
    final effectiveEndDate = widget.task.getEffectiveEndDate(widget.allTasks);

    if (effectiveStartDate == null || effectiveEndDate == null) {
      return const SizedBox.shrink();
    }

    final originalPosition = widget.calculator.getTaskPosition(
      effectiveStartDate,
      effectiveEndDate,
      widget.rangeStart,
    );
    final originalWidth = widget.calculator.getTaskWidth(
      effectiveStartDate,
      effectiveEndDate,
      widget.task.taskType == TaskType.summary
          ? null
          : widget.task.estimatedDuration,
    );

    // Apply drag/resize offsets
    final position = originalPosition + _dragOffset;
    final width =
        (_isDragging
                ? originalWidth
                : originalWidth + (_isResizingEnd ? _dragOffset : -_dragOffset))
            .clamp(widget.calculator.pixelsPerDay * 0.5, double.infinity);

    // Total timeline width (span several months)
    final totalTimelineWidth =
        widget.calculator.pixelsPerDay * 365; // ~1 year visible

    return SizedBox(
      width: totalTimelineWidth,
      height: widget.rowHeight,
      child: Stack(
        children: [
          // Day separator lines in background
          Positioned.fill(
            child: CustomPaint(
              painter: _DaySeparatorPainter(
                pixelsPerDay: widget.calculator.pixelsPerDay,
                rowHeight: widget.rowHeight,
              ),
            ),
          ),

          // Baseline ghost bar (planned schedule at capture time)
          if (widget.baselineDates?.startDate != null &&
              widget.baselineDates?.dueDate != null)
            _buildBaselineGhostBar(effectiveEndDate),

          // Task bar with dependency anchor dots
          Positioned(
            left: _isResizingStart
                ? position
                : originalPosition + (_isDragging ? _dragOffset : 0),
            top: 12,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isTimelineBarHovered = true),
              onExit: (_) => setState(() => _isTimelineBarHovered = false),
              cursor: _isDragging
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.move,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // START ANCHOR DOT (for creating "before" dependency)
                  if (_isTimelineBarHovered &&
                      !_isDragging &&
                      !_isResizingStart &&
                      !_isResizingEnd)
                    Tooltip(
                      message: 'Drag to link predecessor',
                      child: GestureDetector(
                        onPanStart: (details) {
                          // Start dependency dragging from start anchor
                          widget.onDependencyDragStart?.call(
                            widget.task,
                            false,
                          );
                        },
                        onPanUpdate: (details) {
                          widget.onDependencyDragUpdate?.call(
                            details.globalPosition,
                          );
                        },
                        onPanEnd: (details) {
                          widget.onDependencyDragEnd?.call();
                        },
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.info, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.arrow_back,
                              size: 8,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: 18,
                    ), // Placeholder to maintain spacing
                  // MAIN TASK BAR
                  TaskHoverTooltip(
                    task: widget.task,
                    usersMap: widget.usersMap,
                    waitDuration: const Duration(milliseconds: 500),
                    child: GestureDetector(
                      onHorizontalDragStart: _handleDragStart,
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: _handleDragEnd,
                      child: _buildBar(width),
                    ),
                  ),

                  // END ANCHOR DOT (for creating "after" dependency)
                  if (_isTimelineBarHovered &&
                      !_isDragging &&
                      !_isResizingStart &&
                      !_isResizingEnd)
                    Tooltip(
                      message: 'Drag to link successor',
                      child: GestureDetector(
                        onPanStart: (details) {
                          // Start dependency dragging from end anchor
                          widget.onDependencyDragStart?.call(widget.task, true);
                        },
                        onPanUpdate: (details) {
                          widget.onDependencyDragUpdate?.call(
                            details.globalPosition,
                          );
                        },
                        onPanEnd: (details) {
                          widget.onDependencyDragEnd?.call();
                        },
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.info, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.arrow_forward,
                              size: 8,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: 18,
                    ), // Placeholder to maintain spacing
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Thin grey bar under the task bar showing where this task was scheduled
  /// when the baseline was captured, with the slip in days on hover.
  Widget _buildBaselineGhostBar(DateTime? currentEndDate) {
    final baseline = widget.baselineDates!;
    final baselineStart = baseline.startDate!;
    final baselineEnd = baseline.dueDate!;

    final position = widget.calculator.getTaskPosition(
      baselineStart,
      baselineEnd,
      widget.rangeStart,
    );
    final width = widget.calculator.getTaskWidth(
      baselineStart,
      baselineEnd,
      null,
    );

    String slipText = 'On baseline';
    Color barColor = AppColors.textTertiary;
    if (currentEndDate != null) {
      final slipDays = DateTime(
        currentEndDate.year,
        currentEndDate.month,
        currentEndDate.day,
      ).difference(
        DateTime(baselineEnd.year, baselineEnd.month, baselineEnd.day),
      ).inDays;
      if (slipDays > 0) {
        slipText = '$slipDays day${slipDays == 1 ? '' : 's'} behind baseline';
        barColor = AppColors.error;
      } else if (slipDays < 0) {
        slipText =
            '${-slipDays} day${slipDays == -1 ? '' : 's'} ahead of baseline';
        barColor = AppColors.success;
      }
    }

    return Positioned(
      // 18 = left anchor SizedBox placeholder before the main bar
      left: position + 18,
      top: widget.rowHeight - 9,
      child: Tooltip(
        message:
            'Baseline: ${DateFormat('MMM d').format(baselineStart)} – '
            '${DateFormat('MMM d').format(baselineEnd)} · $slipText',
        child: Container(
          width: width.clamp(2.0, double.infinity),
          height: 5,
          decoration: BoxDecoration(
            color: barColor.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  void _handleDragStart(DragStartDetails details) {
    // Groups can be moved as a whole (shifts every member); resizing stays
    // disabled because their dates are calculated from children.
    if (widget.task.taskType == TaskType.summary) {
      if (widget.onGroupShifted == null) return;
      setState(() {
        _dragOffset = 0;
        _totalDragDistance = 0;
        _isDragging = true;
      });
      return;
    }

    final localX = details.localPosition.dx;
    final originalWidth = widget.calculator.getTaskWidth(
      widget.task.startDate,
      widget.task.dueDate,
      widget.task.estimatedDuration,
    );

    setState(() {
      _dragOffset = 0;
      _totalDragDistance = 0;

      if (localX < 10) {
        // Resize left edge
        _isResizingStart = true;
      } else if (localX > originalWidth - 10) {
        // Resize right edge
        _isResizingEnd = true;
      } else {
        // Move entire task
        _isDragging = true;
      }
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dx;
      _totalDragDistance += details.delta.dx.abs();
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    // If very small movement, treat as tap
    if (_totalDragDistance < 5) {
      widget.onTaskTap(widget.task);
      setState(() {
        _isDragging = false;
        _isResizingStart = false;
        _isResizingEnd = false;
        _dragOffset = 0;
        _totalDragDistance = 0;
      });
      return;
    }

    // Calculate new dates - SNAP TO DAY BOUNDARIES
    final dayOffset = (_dragOffset / widget.calculator.pixelsPerDay).round();

    // Whole-group move: delegate the member shift to the parent widget
    if (widget.task.taskType == TaskType.summary) {
      if (_isDragging && dayOffset != 0) {
        widget.onGroupShifted?.call(widget.task, dayOffset);
      }
      setState(() {
        _isDragging = false;
        _dragOffset = 0;
        _totalDragDistance = 0;
      });
      return;
    }

    Task? updatedTask;

    if (_isDragging) {
      // Move both dates by the same offset
      final newStartDate = widget.task.startDate?.add(
        Duration(days: dayOffset),
      );
      final newDueDate = widget.task.dueDate?.add(Duration(days: dayOffset));

      // Normalize to midnight
      updatedTask = widget.task.copyWith(
        startDate: newStartDate != null
            ? DateTime(newStartDate.year, newStartDate.month, newStartDate.day)
            : null,
        dueDate: newDueDate != null
            ? DateTime(newDueDate.year, newDueDate.month, newDueDate.day)
            : null,
      );
    } else if (_isResizingStart) {
      // Adjust start date only
      final newStartDate = widget.task.startDate?.add(
        Duration(days: dayOffset),
      );
      final normalizedStart = newStartDate != null
          ? DateTime(newStartDate.year, newStartDate.month, newStartDate.day)
          : null;

      // Recalculate duration based on new date range
      double? newDuration;
      if (normalizedStart != null && widget.task.dueDate != null) {
        final daysDiff = widget.task.dueDate!
            .difference(normalizedStart)
            .inDays;
        newDuration = (daysDiff * 8).toDouble(); // 8 hours per day
      }

      updatedTask = widget.task.copyWith(
        startDate: normalizedStart,
        estimatedDuration: newDuration,
      );
    } else if (_isResizingEnd) {
      // Adjust end date only
      final newDueDate = widget.task.dueDate?.add(Duration(days: dayOffset));
      final normalizedEnd = newDueDate != null
          ? DateTime(newDueDate.year, newDueDate.month, newDueDate.day)
          : null;

      // Recalculate duration based on new date range
      double? newDuration;
      if (widget.task.startDate != null && normalizedEnd != null) {
        final daysDiff = normalizedEnd
            .difference(widget.task.startDate!)
            .inDays;
        newDuration = (daysDiff * 8).toDouble(); // 8 hours per day
      }

      updatedTask = widget.task.copyWith(
        dueDate: normalizedEnd,
        estimatedDuration: newDuration,
      );
    }

    // Call callback if provided - this will trigger database update and UI refresh
    if (updatedTask != null && widget.onTaskChanged != null) {
      widget.onTaskChanged!(updatedTask);
    }

    setState(() {
      _isDragging = false;
      _isResizingStart = false;
      _isResizingEnd = false;
      _dragOffset = 0;
      _totalDragDistance = 0;
    });
  }

  // Show date picker for start date
  Future<void> _showStartDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.task.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && widget.onTaskChanged != null) {
      // Normalize to midnight
      final normalizedDate = DateTime(picked.year, picked.month, picked.day);

      // Recalculate duration if both dates exist
      double? newDuration;
      if (widget.task.dueDate != null) {
        final daysDiff = widget.task.dueDate!.difference(normalizedDate).inDays;
        newDuration = (daysDiff * 8).toDouble(); // 8 hours per day
      }

      widget.onTaskChanged!(
        widget.task.copyWith(
          startDate: normalizedDate,
          estimatedDuration: newDuration,
        ),
      );
    }
  }

  // Show date picker for end date
  Future<void> _showEndDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.task.dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && widget.onTaskChanged != null) {
      // Normalize to midnight
      final normalizedDate = DateTime(picked.year, picked.month, picked.day);

      // Recalculate duration if both dates exist
      double? newDuration;
      if (widget.task.startDate != null) {
        final daysDiff = normalizedDate
            .difference(widget.task.startDate!)
            .inDays;
        newDuration = (daysDiff * 8).toDouble(); // 8 hours per day
      }

      widget.onTaskChanged!(
        widget.task.copyWith(
          dueDate: normalizedDate,
          estimatedDuration: newDuration,
        ),
      );
    }
  }

  // Show progress picker dialog with embedded comments widget
  Future<void> _showProgressPicker(BuildContext context) async {
    double currentProgress = widget.task.progress.toDouble();

    // Capture current user BEFORE opening dialog to avoid context issues
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.appUser;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r16),
              ),
              child: Container(
                width: 500,
                height: MediaQuery.of(context).size.height * 0.8,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: 700,
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.trending_up, color: AppColors.info),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Update Progress: ${widget.task.title}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Progress section (fixed at top)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        border: Border(
                          bottom: BorderSide(color: AppColors.cardBorder),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Progress percentage display
                          Text(
                            '${currentProgress.toInt()}%',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _getProgressColor(
                                    currentProgress.toInt(),
                                  ),
                                ),
                          ),
                          const SizedBox(height: 8),

                          // Slider
                          Slider(
                            value: currentProgress,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${currentProgress.toInt()}%',
                            onChanged: (value) {
                              setState(() {
                                currentProgress = value;
                              });
                            },
                          ),

                          const SizedBox(height: 8),

                          // Quick select buttons
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (int percent in [0, 25, 50, 75, 100])
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      currentProgress = percent.toDouble();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        currentProgress.toInt() == percent
                                        ? AppColors.infoDark
                                        : null,
                                    foregroundColor:
                                        currentProgress.toInt() == percent
                                        ? Colors.white
                                        : null,
                                    minimumSize: const Size(50, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                    ),
                                  ),
                                  child: Text('$percent%'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Comments section (scrollable) - TaskCommentsWidget has its own header
                    Expanded(
                      child: TaskCommentsWidget(
                        taskId: widget.task.id,
                        workspaceId: widget.task.workspaceId,
                      ),
                    ),

                    // Footer with save button
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: AppColors.cardBorder),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (widget.onTaskChanged != null) {
                                // Update task progress
                                widget.onTaskChanged!(
                                  widget.task.copyWith(
                                    progress: currentProgress.toInt(),
                                    isComplete: currentProgress >= 100,
                                  ),
                                );

                                // If progress changed, add an automatic comment
                                if (currentProgress.toInt() !=
                                        widget.task.progress &&
                                    currentUser != null) {
                                  try {
                                    await ServiceLocator.taskCommentService
                                        .addComment(
                                          taskId: widget.task.id,
                                          content:
                                              '📊 Progress updated to ${currentProgress.toInt()}%',
                                          senderId: currentUser.id,
                                          senderName:
                                              currentUser.displayName ??
                                              currentUser.email,
                                          workspaceId: widget.task.workspaceId,
                                        );
                                  } catch (_) {
                                    // Non-critical: progress comment failed
                                  }
                                }
                              }
                              Navigator.of(dialogContext).pop();
                            },
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('Save Progress'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBar(double width) {
    final isGroup = widget.task.taskType == TaskType.summary;
    final minWidth = width.clamp(20.0, double.infinity);

    if (isGroup) {
      // Group: thin colored line with text to the right
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thin line bar
          Container(
            width: minWidth,
            height: 8,
            decoration: BoxDecoration(
              color: widget.task.groupColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // Title to the right
          Text(
            widget.task.title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    // Standard task: gradient bar with text to the right
    final effectiveProgress = widget.task.getEffectiveProgress(widget.allTasks);
    final barColor = _getProgressColor(effectiveProgress);

    // Calculate lighter and darker shades for gradient
    final lighterColor = Color.lerp(barColor, Colors.white, 0.15)!;
    final darkerColor = Color.lerp(barColor, Colors.black, 0.1)!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Task bar
        Container(
          width: minWidth,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [lighterColor, barColor, darkerColor],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: barColor.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Title to the right
        Text(
          widget.task.title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
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

/// Custom painter for drawing tree lines to show hierarchy
class TreeLinesPainter extends CustomPainter {
  final bool isLastLevel;
  final bool hasMoreAtThisLevel;
  final bool isContinuation;
  final Color color;

  TreeLinesPainter({
    required this.isLastLevel,
    required this.hasMoreAtThisLevel,
    this.isContinuation = false,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final double midX = size.width / 2;
    final double midY = size.height / 2;

    if (isContinuation) {
      // Draw full horizontal line
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
      return;
    }

    if (isLastLevel) {
      // Draw vertical line from top to middle
      canvas.drawLine(Offset(midX, 0), Offset(midX, midY), paint);
      // Draw horizontal line from middle to right (balanced length: 70% of width)
      canvas.drawLine(
        Offset(midX, midY),
        Offset(midX + (size.width - midX) * 0.7, midY),
        paint,
      );

      if (hasMoreAtThisLevel) {
        // Draw vertical line from middle to bottom
        canvas.drawLine(Offset(midX, midY), Offset(midX, size.height), paint);
      }
    } else {
      if (hasMoreAtThisLevel) {
        // Draw full vertical line
        canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(TreeLinesPainter oldDelegate) {
    return oldDelegate.isLastLevel != isLastLevel ||
        oldDelegate.hasMoreAtThisLevel != hasMoreAtThisLevel ||
        oldDelegate.isContinuation != isContinuation ||
        oldDelegate.color != color;
  }
}

/// Painter for vertical day separator lines
class _DaySeparatorPainter extends CustomPainter {
  final double pixelsPerDay;
  final double rowHeight;

  _DaySeparatorPainter({required this.pixelsPerDay, required this.rowHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          const Color(0xFFE5E7EB) // Light grey for grid lines
      ..strokeWidth = 1;

    // Draw solid vertical line at each day boundary (performant)
    for (double x = pixelsPerDay; x < size.width; x += pixelsPerDay) {
      canvas.drawLine(Offset(x, 0), Offset(x, rowHeight), paint);
    }
  }

  @override
  bool shouldRepaint(_DaySeparatorPainter oldDelegate) {
    return oldDelegate.pixelsPerDay != pixelsPerDay ||
        oldDelegate.rowHeight != rowHeight;
  }
}
