import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/gantt_task_extensions.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../table/hover_action_row.dart';
import '../table/inline_edit_cell.dart';
import '../table/tree_line_painter.dart';
import '../table/tree_drop_zone.dart';
import '../table/tree_row_container.dart';
import '../table/tree_row_chevron.dart';
import '../table/tree_row_drop_wrapper.dart';
import '../task_comments_widget.dart';
import '../task_form_popup.dart';
import '../task_assignee_avatars.dart';
import '../properties/property_detail_view.dart';
import '../../utils/text_selection_utils.dart';

export '../table/tree_drop_zone.dart' show DropZone;

/// Inline-editable row for a single task in the grouped task list view.
class TaskRow extends StatefulWidget {
  final Task task;
  final List<Task> allTasks;
  final int depth;
  final List<bool> treeGuides;
  final bool isLastChild;
  final bool hasChildren;
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
  final String? projectName;
  final Project? project;
  final Map<String, Property> propertyMap;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onUngroup;
  final void Function(Task dragged, Task target, DropZone zone)?
  onTaskDroppedOnTask;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;
  final bool isAnyTaskDragging;
  final bool isSelected;
  final void Function(Task task, bool isSelected)? onSelectionChanged;
  final bool showPhaseHierarchyGuide;
  final int? commentCount;

  const TaskRow({
    super.key,
    required this.task,
    required this.allTasks,
    this.depth = 0,
    this.treeGuides = const [],
    this.isLastChild = true,
    this.hasChildren = false,
    this.isExpanded = false,
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
    this.projectName,
    this.project,
    this.propertyMap = const {},
    this.usersMap = const {},
    this.allWorkspaceUsers = const [],
    this.onExpandToggle,
    this.onDelete,
    this.onUngroup,
    this.onTaskDroppedOnTask,
    this.onDragStarted,
    this.onDragEnded,
    this.isAnyTaskDragging = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.showPhaseHierarchyGuide = false,
    this.commentCount,
  });

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  static const double _columnGap = 8;
  static const double _dropInsertionGap = 48;
  // Keep rows flush so tree connectors remain continuous between siblings.
  static const double _rowVerticalGap = 0;
  bool _isHovered = false;
  DropZone _dropZone = DropZone.none;
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  final FocusNode _titleFocus = FocusNode();
  int? _commentCount;

  static const _statusOptions = [
    ('not_started', 'Not Started'),
    ('working_on_it', 'Working on it'),
    ('stuck', 'Stuck'),
    ('done', 'Done'),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _commentCount = widget.commentCount;
    if (widget.commentCount == null) {
      _loadCommentCount();
    }
  }

  void _loadCommentCount() {
    ServiceLocator.taskCommentService.getCommentCount(widget.task.id).then((
      count,
    ) {
      if (mounted) setState(() => _commentCount = count);
    });
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.title != oldWidget.task.title && !_isEditingTitle) {
      _titleController.text = widget.task.title;
    }
    if (widget.task.id != oldWidget.task.id) {
      _commentCount = widget.commentCount;
      if (widget.commentCount == null) {
        _loadCommentCount();
      }
    } else if (widget.commentCount != oldWidget.commentCount &&
        widget.commentCount != null) {
      _commentCount = widget.commentCount;
    }
    if (widget.isAnyTaskDragging &&
        !oldWidget.isAnyTaskDragging &&
        _isHovered) {
      _isHovered = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'working_on_it':
        return AppColors.info;
      case 'stuck':
        return AppColors.warning;
      case 'done':
        return AppColors.success;
      default:
        return AppColors.textTertiary;
    }
  }

  DropZone _computeDropZone(DragTargetDetails<Task> details) {
    return computeDropZone(
      context,
      details.offset,
      depth: widget.depth,
      hasParent: widget.task.parentId != null,
      hasVisibleChildren: widget.hasChildren && widget.isExpanded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isComplete = task.isComplete;
    final isOverdue = task.isOverdue();
    final colorScheme = Theme.of(context).colorScheme;

    // Row background color based on drop zone.
    // Content area is always white regardless of dark mode (dark chrome design).
    Color rowColor = Colors.white;
    if (_dropZone == DropZone.child) {
      rowColor = AppColors.info.withValues(alpha: 0.15);
    } else if (_dropZone == DropZone.unparent) {
      rowColor = AppColors.warning.withValues(alpha: 0.10);
    } else if (_isHovered && !widget.isAnyTaskDragging) {
      rowColor = AppColors.background;
    } else if (isComplete) {
      rowColor = AppColors.surfaceAlt;
    }

    // Keep row border styling consistent for grouped and regular tasks.
    const leftBorder = BorderSide.none;

    final topBorder = BorderSide.none;

    BorderSide rightBorder = BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    );

    final bottomBorder = BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    );

    final innerContent = HoverActionRow(
      enabled: !widget.isAnyTaskDragging,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      builder: (isHovered) {
        final guides = _buildHierarchyGuides(colorScheme);
        // Width of guide area: checkbox(24) + gap(4) + guides
        final guideLeftOffset =
            24.0 + 4.0 + 10.0; // checkbox + gap + container padding
        final guideWidth = guides.length * 24.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            TreeRowDropWrapper(
              dropZone: _dropZone,
              insertionGap: _dropInsertionGap,
              verticalGap: _rowVerticalGap,
              child: TreeRowContainer(
                color: rowColor,
                leftBorder: leftBorder,
                rightBorder: rightBorder,
                topBorder: topBorder,
                bottomBorder: bottomBorder,
                child: Row(
                  children: [
                    // Checkbox (leftmost) — toggles selection
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onSelectionChanged?.call(
                          widget.task,
                          !widget.isSelected,
                        ),
                        activeColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Reserve space for tree guides (painted via Positioned overlay)
                    SizedBox(width: guideWidth),
                    // Expand/collapse for tasks with children
                    ...buildTreeChevron(
                      hasChildren: widget.hasChildren,
                      isExpanded: widget.isExpanded,
                      depth: widget.depth,
                      onToggle: widget.onExpandToggle,
                    ),
                    // Primary row content: title + quick actions
                    Expanded(child: _buildTitleCell(isComplete, isHovered)),
                    if (widget.showProjectColumn &&
                        !widget.hiddenColumnIds.contains('project'))
                      SizedBox(
                        width: widget.projectColumnWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          child: _buildProjectChip(),
                        ),
                      ),
                    if (!widget.hiddenColumnIds.contains('customer_name')) ...[
                      const SizedBox(width: _columnGap),
                      SizedBox(
                        width: widget.customerNameColumnWidth,
                        child: _buildTextCell(widget.project?.customerName),
                      ),
                    ],
                    if (!widget.hiddenColumnIds.contains('job_number')) ...[
                      const SizedBox(width: _columnGap),
                      SizedBox(
                        width: widget.jobNumberColumnWidth,
                        child: _buildTextCell(widget.project?.serialNumber),
                      ),
                    ],
                    if (!widget.hiddenColumnIds.contains('job_address')) ...[
                      const SizedBox(width: _columnGap),
                      SizedBox(
                        width: widget.jobAddressColumnWidth,
                        child: _buildTextCell(widget.project?.address),
                      ),
                    ],
                    const SizedBox(width: _columnGap),
                    SizedBox(
                      width: widget.statusColumnWidth,
                      child: _buildStatusDropdown(task),
                    ),
                    const SizedBox(width: _columnGap),
                    SizedBox(
                      width: widget.dueDateColumnWidth,
                      child: _buildDueDate(task, isOverdue),
                    ),
                    const SizedBox(width: _columnGap),
                    SizedBox(
                      width: widget.assigneeColumnWidth,
                      child: _buildAssigneeAvatars(task),
                    ),
                    const SizedBox(width: _columnGap),
                    SizedBox(
                      width: widget.notesColumnWidth,
                      child: _buildCommentCount(task),
                    ),
                    const SizedBox(width: _columnGap),
                    SizedBox(
                      width: widget.progressColumnWidth,
                      child: _buildProgress(task),
                    ),
                  ],
                ),
              ),
            ),
            if (_dropZone == DropZone.child)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.info.withValues(alpha: 0.28),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Make subtask',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Tree guide lines as overlay — extends beyond row bounds
            if (guides.isNotEmpty)
              Positioned(
                left: guideLeftOffset,
                top: 0,
                bottom: -6,
                width: guideWidth,
                child: IgnorePointer(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: guides,
                  ),
                ),
              ),
          ],
        );
      },
    );

    // Wrap with DragTarget to accept drops (reorder / re-parent)
    final rowContent = DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        // Don't accept self
        if (dragged.id == task.id) return false;
        // Don't accept own descendants (prevent circular)
        if (_isDescendantOf(dragged.id, task.id)) return false;
        return true;
      },
      onAcceptWithDetails: (details) {
        final zone = _computeDropZone(details);
        setState(() => _dropZone = DropZone.none);
        widget.onTaskDroppedOnTask?.call(details.data, task, zone);
      },
      onMove: (details) {
        final zone = _computeDropZone(details);
        if (zone != _dropZone) setState(() => _dropZone = zone);
      },
      onLeave: (_) {
        if (_dropZone != DropZone.none) {
          setState(() => _dropZone = DropZone.none);
        }
      },
      builder: (context, candidateData, rejectedData) => innerContent,
    );

    // Wrap with Draggable
    final dragFeedback = Opacity(
      opacity: 0.55,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 300,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
                  task.displayTitle,
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
      ),
    );

    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    onDragStarted() {
      // Reset stale visual states before drag begins.
      if (_isHovered || _dropZone != DropZone.none) {
        setState(() {
          _isHovered = false;
          _dropZone = DropZone.none;
        });
      }
      widget.onDragStarted?.call();
    }

    onDragEnd(_) {
      // MouseRegion may miss onExit during drag; force-clear row highlights.
      if (_isHovered || _dropZone != DropZone.none) {
        setState(() {
          _isHovered = false;
          _dropZone = DropZone.none;
        });
      }
      widget.onDragEnded?.call();
    }

    final whenDragging = IgnorePointer(
      child: Opacity(opacity: 0.16, child: rowContent),
    );

    if (isMobile) {
      return LongPressDraggable<Task>(
        data: task,
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        feedback: dragFeedback,
        childWhenDragging: whenDragging,
        hapticFeedbackOnStart: true,
        child: rowContent,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<Task>(
        data: task,
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        feedback: dragFeedback,
        childWhenDragging: whenDragging,
        child: rowContent,
      ),
    );
  }

  /// Check if potentialDescendantId is a descendant of ancestorId
  bool _isDescendantOf(String ancestorId, String potentialDescendantId) {
    int iterations = 0;
    String? currentId = potentialDescendantId;
    while (currentId != null && iterations < 100) {
      iterations++;
      final task = widget.allTasks.firstWhere(
        (t) => t.id == currentId,
        orElse: () => widget.task,
      );
      if (task.parentId == ancestorId) return true;
      if (task.parentId == null ||
          task.id == currentId && task.parentId == null) {
        break;
      }
      currentId = task.parentId;
    }
    return false;
  }

  List<Widget> _buildHierarchyGuides(ColorScheme colorScheme) {
    return buildTreeGuides(
      depth: widget.depth,
      treeGuides: widget.treeGuides,
      isLastChild: widget.isLastChild,
      colorScheme: colorScheme,
      showPhaseHierarchyGuide: widget.showPhaseHierarchyGuide,
      cellHeight: null,
    );
  }

  Widget _buildTitleCell(bool isComplete, bool isHovered) {
    final showActions = isHovered && !_isEditingTitle;
    final propertyShortcut = _resolvePropertyShortcut();
    final blockers = widget.task.incompletePredecessors(widget.allTasks);
    final isBlocked = !widget.task.isComplete && blockers.isNotEmpty;
    return Row(
      children: [
        if (widget.task.isRecurring) ...[
          Icon(Icons.repeat, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 4),
        ],
        if (isBlocked) ...[
          Tooltip(
            message:
                'Blocked — waiting on: ${blockers.map((t) => t.displayTitle).take(3).join(', ')}'
                '${blockers.length > 3 ? '…' : ''}',
            child: Icon(Icons.lock_clock, size: 14, color: AppColors.warning),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: InlineEditCell(
                  value: widget.task.title,
                  placeholder: '(Untitled task)',
                  onSave: (text) {
                    if (text.isNotEmpty && text != widget.task.title) {
                      ServiceLocator.taskService.updateTask(
                        taskId: widget.task.id,
                        title: text,
                      );
                    }
                  },
                  onCancel: _cancelTitleEdit,
                  cellType: InlineEditCellType.text,
                  required: true,
                  controller: _titleController,
                  focusNode: _titleFocus,
                  isEditing: _isEditingTitle,
                  onEnterEdit: _enterTitleEdit,
                  onEditStateChanged: (isEditing) {
                    if (!isEditing && _isEditingTitle) {
                      setState(() => _isEditingTitle = false);
                    }
                  },
                  editBorderColor: AppColors.info,
                  displayStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: isComplete
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    decoration: isComplete ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (showActions) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    onPressed: () => showTaskFormPopup(
                      context,
                      projectId: widget.task.projectId,
                      taskId: widget.task.id,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Edit full details',
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              // Keep PopupMenuButton always in tree so onSelected fires
              // even when hover is lost while the popup overlay is open.
              Visibility(
                visible: showActions,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: SizedBox(
                  width: 28,
                  child: _buildMoreMenu(context, widget.task),
                ),
              ),
              if (showActions) ...[
                if (widget.onDelete != null && context.read<AuthProvider>().canDeleteTasks)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: AppColors.error,
                      ),
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (propertyShortcut != null) ...[
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: _buildPropertyShortcutChip(
              label: propertyShortcut.label,
              onTap: () => _openPropertyDetail(propertyShortcut.property),
            ),
          ),
        ],
      ],
    );
  }

  ({Property property, String label})? _resolvePropertyShortcut() {
    final project = widget.project;
    if (project == null || widget.task.propertyIds.isEmpty) {
      return null;
    }

    final linkedProperties = <Property>[];
    final seenPropertyIds = <String>{};
    for (final propertyId in widget.task.propertyIds) {
      if (!seenPropertyIds.add(propertyId)) continue;
      final property = widget.propertyMap[propertyId];
      if (property != null) {
        linkedProperties.add(property);
      }
    }

    if (linkedProperties.isEmpty) {
      return null;
    }

    final primaryProperty = linkedProperties.first;
    final extraCount = linkedProperties.length - 1;
    final baseLabel = _formatPropertyLabel(primaryProperty);
    final label = extraCount > 0 ? '$baseLabel +$extraCount' : baseLabel;
    return (property: primaryProperty, label: label);
  }

  String _formatPropertyLabel(Property property) {
    final name = property.name.trim();
    final identifier = property.identifier.trim();
    if (name.isNotEmpty && identifier.isNotEmpty) {
      return '$name ($identifier)';
    }
    if (name.isNotEmpty) {
      return name;
    }
    return identifier;
  }

  Widget _buildPropertyShortcutChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.home_work_outlined,
                size: 12,
                color: AppColors.info,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPropertyDetail(Property property) {
    final project = widget.project;
    if (project == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PropertyDetailView(project: project, propertyId: property.id),
      ),
    );
  }

  Widget _buildStatusDropdown(Task task) {
    return PopupMenuButton<String>(
      onSelected: (status) => _updateStatus(status),
      tooltip: 'Change status',
      offset: const Offset(0, 32),
      itemBuilder: (_) => _statusOptions.map((opt) {
        return PopupMenuItem<String>(
          value: opt.$1,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor(opt.$1),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(opt.$2, style: const TextStyle(fontSize: 13)),
              if (opt.$1 == task.status) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _statusColor(task.status).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          _statusLabel(task.status),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _statusColor(task.status),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAssigneeAvatars(Task task) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TaskAssigneeAvatars(
        task: task,
        usersMap: widget.usersMap,
        allWorkspaceUsers: widget.allWorkspaceUsers,
        maxVisible: 2,
        avatarSize: 20,
      ),
    );
  }

  Widget _buildDueDate(Task task, bool isOverdue) {
    final dueText = task.dueDate == null
        ? 'No date'
        : _formatDate(task.dueDate!);
    final textColor = task.dueDate == null
        ? AppColors.textTertiary
        : (isOverdue ? AppColors.error : AppColors.textSecondary);

    return _buildDueDatePill(
      dueText: dueText,
      textColor: textColor,
      isOverdue: isOverdue,
    );
  }

  Widget _buildDueDatePill({
    required String dueText,
    required Color textColor,
    required bool isOverdue,
  }) {
    return GestureDetector(
      onTap: () => _pickDueDate(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isOverdue
                  ? AppColors.error.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 12, color: textColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  dueText,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    fontWeight: isOverdue ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextCell(String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildProjectChip() {
    final proj = widget.project;
    final name = proj?.name ?? widget.projectName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final sn = proj?.serialNumber?.trim();
    final displayLabel = (sn != null && sn.isNotEmpty) ? '$name #$sn' : name;
    final projectId = proj?.id ?? widget.task.projectId;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        displayLabel,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Tooltip(
      message: displayLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.go('/projects/$projectId'),
          child: chip,
        ),
      ),
    );
  }

  Widget _buildProgress(Task task) {
    final effectiveProgress = task.getEffectiveProgress(widget.allTasks);
    final color = _getProgressColor(effectiveProgress);
    final canEditProgress = task.taskType != TaskType.summary;
    final tooltipMessage = canEditProgress
        ? 'Progress: $effectiveProgress% - click to update'
        : 'Progress: $effectiveProgress% - calculated from child tasks';

    return GestureDetector(
      onTap: canEditProgress ? () => _showProgressPicker(context) : null,
      child: MouseRegion(
        cursor: canEditProgress
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Tooltip(
          message: tooltipMessage,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CustomPaint(
                  painter: _ProgressCirclePainter(
                    progress: effectiveProgress / 100,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$effectiveProgress%',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress >= 50) return const Color(0xFF4A90A4);
    if (progress > 0) return AppColors.warning;
    return AppColors.textTertiary;
  }

  Widget _buildCommentCount(Task task) {
    final count = _commentCount ?? 0;
    final hasNotes = count > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showTaskFormPopup(
          context,
          projectId: task.projectId,
          taskId: task.id,
          initialTabIndex: 4,
        ),
        child: Tooltip(
          message: hasNotes
              ? '$count note${count == 1 ? '' : 's'}'
              : 'Add note',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasNotes
                    ? Icons.chat_bubble_outline
                    : Icons.add_comment_outlined,
                size: 13,
                color: hasNotes ? AppColors.textTertiary : AppColors.infoDark,
              ),
              if (hasNotes) ...[
                const SizedBox(width: 2),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProgressPicker(BuildContext context) async {
    if (widget.task.taskType == TaskType.summary) {
      return;
    }

    double currentProgress = widget.task.progress.toDouble();
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

                    // Progress section
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
                          Slider(
                            value: currentProgress,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${currentProgress.toInt()}%',
                            onChanged: (value) {
                              setState(() => currentProgress = value);
                            },
                          ),
                          const SizedBox(height: 8),
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

                    // Comments section
                    Expanded(
                      child: TaskCommentsWidget(
                        taskId: widget.task.id,
                        workspaceId: widget.task.workspaceId,
                      ),
                    ),

                    // Footer
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
                              await ServiceLocator.taskService.updateTask(
                                taskId: widget.task.id,
                                progress: currentProgress.toInt(),
                              );

                              // Auto-comment on progress change
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
                                  _loadCommentCount();
                                } catch (e) {
                                  debugPrint(
                                    'Error adding progress comment: $e',
                                  );
                                }
                              }
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
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

  Widget _buildMoreMenu(BuildContext context, Task task) {
    final authProvider = context.read<AuthProvider>();
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AppColors.textTertiary,
      ),
      padding: EdgeInsets.zero,
      iconSize: 18,
      offset: const Offset(0, 32),
      itemBuilder: (_) => [
        if (authProvider.canCreateTasks)
          const PopupMenuItem(
            value: 'add_subtask',
            child: Row(
              children: [
                Icon(Icons.subdirectory_arrow_right, size: 16),
                SizedBox(width: 8),
                Text('Add subtask'),
              ],
            ),
          ),
        if (authProvider.canCreateTasks)
          const PopupMenuItem(
            value: 'duplicate',
            child: Row(
              children: [
                Icon(Icons.copy_outlined, size: 16),
                SizedBox(width: 8),
                Text('Duplicate'),
              ],
            ),
          ),
        if (task.taskType != TaskType.summary)
          PopupMenuItem(
            value: 'convert_to_group',
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16),
                SizedBox(width: 8),
                Text(
                  task.parentId == null
                      ? 'Convert to Phase'
                      : 'Convert to Grouped Task',
                ),
              ],
            ),
          ),
        if (task.taskType == TaskType.summary &&
            widget.hasChildren &&
            widget.onUngroup != null)
          const PopupMenuItem(
            value: 'ungroup',
            child: Row(
              children: [
                Icon(Icons.format_indent_decrease, size: 16),
                SizedBox(width: 8),
                Text('Ungroup'),
              ],
            ),
          ),
        if (authProvider.canDeleteTasks) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        ],
      ],
      onSelected: (value) async {
        switch (value) {
          case 'add_subtask':
            await ServiceLocator.taskService.createTask(
              workspaceId: task.workspaceId,
              projectId: task.projectId,
              title: 'New Subtask',
              parentId: task.id,
            );
          case 'duplicate':
            await ServiceLocator.taskService.cloneTask(
              task: task,
              allTasks: widget.allTasks,
            );
          case 'convert_to_group':
            await ServiceLocator.taskService.updateTaskType(
              task.id,
              TaskType.summary,
            );
          case 'ungroup':
            widget.onUngroup?.call();
          case 'delete':
            widget.onDelete?.call();
        }
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'not_started':
        return 'Not Started';
      case 'working_on_it':
        return 'Working on it';
      case 'stuck':
        return 'Stuck';
      case 'done':
        return 'Done';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _enterTitleEdit() {
    setState(() {
      _isEditingTitle = true;
      _titleController.text = widget.task.title;
      selectAllText(_titleController);
    });
  }

  void _cancelTitleEdit() {
    setState(() {
      _isEditingTitle = false;
      _titleController.text = widget.task.title;
    });
  }

  void _updateStatus(String status) {
    ServiceLocator.taskService.updateTaskStatus(widget.task.id, status);
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          widget.task.dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      ServiceLocator.taskService.updateTask(
        taskId: widget.task.id,
        dueDate: picked,
      );
    }
  }
}

// Custom painter for circular progress indicator (pie chart style)
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
      const startAngle = -math.pi / 2; // Start at top
      final sweepAngle = 2 * math.pi * progress;

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
