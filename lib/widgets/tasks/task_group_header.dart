import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import '../table/composition_badges.dart';
import '../task_assignee_avatars.dart';
import '../../utils/text_selection_utils.dart';

enum GroupHeaderDropZone { above, center, below, none }

/// Header row for a collapsible task group section.
/// Also acts as a DragTarget so tasks can be dropped onto a group to move them.
class TaskGroupHeader extends StatefulWidget {
  final String title;
  final int taskCount;
  final int completedCount;
  final Color groupColor;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onAddTask;
  final VoidCallback? onEditGroup;
  final void Function(Task task)? onTaskDropped;
  final void Function(Task task, GroupHeaderDropZone zone)?
  onTaskDroppedWithZone;
  final Task? draggableTask;
  final ValueChanged<String>? onRenameGroup;

  /// Tri-state: true = all selected, false = some selected, null = none selected.
  final List<CompositionBadge> statusBadges;
  final bool? isAllSelected;
  final ValueChanged<bool>? onSelectAllChanged;
  final String? summaryStatus;
  final DateTime? summaryDueDate;
  final int? summaryProgress;
  final List<AppUser> summaryAssignees;
  final Map<String, AppUser> usersMap;
  final bool showSummaryColumns;
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
  final ValueChanged<String>? onSummaryStatusChanged;
  final List<AppUser> allWorkspaceUsers;
  final ValueChanged<String?>? onSummaryAssigneeSelected;

  const TaskGroupHeader({
    super.key,
    required this.title,
    required this.taskCount,
    required this.completedCount,
    required this.groupColor,
    required this.isExpanded,
    required this.onToggle,
    this.onAddTask,
    this.onEditGroup,
    this.onTaskDropped,
    this.onTaskDroppedWithZone,
    this.draggableTask,
    this.onRenameGroup,
    this.statusBadges = const [],
    this.summaryStatus,
    this.summaryDueDate,
    this.summaryProgress,
    this.summaryAssignees = const [],
    this.usersMap = const {},
    this.showSummaryColumns = false,
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
    this.onSummaryStatusChanged,
    this.allWorkspaceUsers = const [],
    this.onSummaryAssigneeSelected,
    this.isAllSelected,
    this.onSelectAllChanged,
  });

  @override
  State<TaskGroupHeader> createState() => _TaskGroupHeaderState();
}

class _TaskGroupHeaderState extends State<TaskGroupHeader> {
  static const double _columnGap = 8;
  bool _isHovered = false;
  bool _isDragTarget = false;
  GroupHeaderDropZone _dropZone = GroupHeaderDropZone.none;
  bool _isEditingTitle = false;
  late final TextEditingController _titleController;
  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
  }

  @override
  void didUpdateWidget(covariant TaskGroupHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingTitle && oldWidget.title != widget.title) {
      _titleController.text = widget.title;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  GroupHeaderDropZone _computeDropZone(DragTargetDetails<Task> details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return GroupHeaderDropZone.center;
    final local = box.globalToLocal(details.offset);
    final fraction = local.dy / box.size.height;
    if (fraction < 0.25) return GroupHeaderDropZone.above;
    if (fraction > 0.75) return GroupHeaderDropZone.below;
    return GroupHeaderDropZone.center;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(date.year, date.month, date.day);
    final diff = value.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${date.month}/${date.day}/${date.year}';
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

  void _enterTitleEdit() {
    if (widget.onRenameGroup == null) return;
    setState(() {
      _isEditingTitle = true;
      _titleController.text = widget.title;
      selectAllText(_titleController);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _saveTitleEdit() {
    final trimmed = _titleController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.title) {
      widget.onRenameGroup?.call(trimmed);
    }
    if (mounted) setState(() => _isEditingTitle = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chrome = ChromeColors.of(context);

    final Widget baseHeader = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          height: 40,
          // Match task-row leading inset so parent and child checkboxes align.
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _isDragTarget
                ? AppColors.info.withValues(alpha: 0.15)
                : _isHovered
                ? (chrome.isDark ? const Color(0xFFE8EDF3) : colorScheme.surfaceContainerHighest)
                : (chrome.isDark ? const Color(0xFFF1F5F9) : colorScheme.surfaceContainerLow),
            border: Border(
              left: BorderSide(color: widget.groupColor, width: 3),
              top: _dropZone == GroupHeaderDropZone.above
                  ? const BorderSide(color: AppColors.info, width: 2)
                  : BorderSide.none,
              bottom: BorderSide(
                color: _dropZone == GroupHeaderDropZone.below
                    ? AppColors.info
                    : _isDragTarget
                    ? AppColors.info
                    : Theme.of(context).colorScheme.outlineVariant,
                width: (_isDragTarget || _dropZone == GroupHeaderDropZone.below)
                    ? 2
                    : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Select-all checkbox
              if (widget.onSelectAllChanged != null)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: widget.isAllSelected == true
                        ? true
                        : (widget.isAllSelected == false ? null : false),
                    tristate: true,
                    onChanged: (_) => widget.onSelectAllChanged?.call(
                      widget.isAllSelected != true,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              // Expand/collapse chevron
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 20,
                color: ChromeColors.of(context).text,
              ),
              const SizedBox(width: 8),
              // Group color dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.groupColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // Group name
              GestureDetector(
                onDoubleTap: widget.onRenameGroup != null
                    ? _enterTitleEdit
                    : null,
                child: _isEditingTitle
                    ? SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _titleController,
                          focusNode: _titleFocus,
                          autofocus: true,
                          onSubmitted: (_) => _saveTitleEdit(),
                          onTapOutside: (_) => _saveTitleEdit(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          ),
                        ),
                      )
                    : Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ),
              // Edit group button (next to title)
              if (widget.onEditGroup != null)
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () {
                      if (widget.onRenameGroup != null) {
                        _enterTitleEdit();
                      } else {
                        widget.onEditGroup?.call();
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Edit group',
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              // Add task button (next to title)
              if (widget.onAddTask != null)
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: widget.onAddTask,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Add task to group',
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const SizedBox(width: 12),
              // Task count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  '${widget.taskCount} task${widget.taskCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Progress summary
              if (widget.taskCount > 0)
                Text(
                  '${widget.completedCount}/${widget.taskCount} complete',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              // Status composition badges
              if (widget.statusBadges.isNotEmpty) ...[
                const SizedBox(width: 8),
                CompositionBadges(badges: widget.statusBadges),
              ],
              // Drag target hint
              if (_isDragTarget) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Text(
                    'Drop here',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.info,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (widget.showSummaryColumns) ...[
                if (widget.showProjectColumn && !widget.hiddenColumnIds.contains('project')) ...[
                  SizedBox(width: widget.projectColumnWidth),
                  const SizedBox(width: _columnGap),
                ],
                if (!widget.hiddenColumnIds.contains('customer_name')) ...[
                  SizedBox(width: widget.customerNameColumnWidth),
                  const SizedBox(width: _columnGap),
                ],
                if (!widget.hiddenColumnIds.contains('job_number')) ...[
                  SizedBox(width: widget.jobNumberColumnWidth),
                  const SizedBox(width: _columnGap),
                ],
                if (!widget.hiddenColumnIds.contains('job_address')) ...[
                  SizedBox(width: widget.jobAddressColumnWidth),
                  const SizedBox(width: _columnGap),
                ],
                SizedBox(
                  width: widget.statusColumnWidth,
                  child: _buildSummaryStatusCell(),
                ),
                const SizedBox(width: _columnGap),
                SizedBox(
                  width: widget.dueDateColumnWidth,
                  child: _buildSummaryDueDateCell(),
                ),
                const SizedBox(width: _columnGap),
                SizedBox(
                  width: widget.assigneeColumnWidth,
                  child: _buildSummaryAssigneeCell(),
                ),
                const SizedBox(width: _columnGap),
                SizedBox(
                  width: widget.notesColumnWidth,
                  child: const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.remove,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: _columnGap),
                SizedBox(
                  width: widget.progressColumnWidth,
                  child: _buildSummaryProgressCell(),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Wrap with DragTarget to accept tasks dropped onto this group
    Widget header = baseHeader;
    if (widget.onTaskDropped != null || widget.onTaskDroppedWithZone != null) {
      header = DragTarget<Task>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          final zone = _computeDropZone(details);
          setState(() {
            _isDragTarget = false;
            _dropZone = GroupHeaderDropZone.none;
          });
          if (widget.onTaskDroppedWithZone != null) {
            widget.onTaskDroppedWithZone?.call(details.data, zone);
          } else {
            widget.onTaskDropped?.call(details.data);
          }
        },
        onMove: (details) {
          final zone = _computeDropZone(details);
          if (!_isDragTarget || _dropZone != zone) {
            setState(() {
              _isDragTarget = true;
              _dropZone = zone;
            });
          }
        },
        onLeave: (_) {
          if (_isDragTarget || _dropZone != GroupHeaderDropZone.none) {
            setState(() {
              _isDragTarget = false;
              _dropZone = GroupHeaderDropZone.none;
            });
          }
        },
        builder: (context, candidateData, rejectedData) => baseHeader,
      );
    }

    if (widget.draggableTask != null) {
      final isMobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);
      final feedbackWidget = Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 260,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.info, width: 2),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.drag_indicator,
                size: 16,
                color: AppColors.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final whenDragging = Container(
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.28),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      );
      if (isMobile) {
        return LongPressDraggable<Task>(
          data: widget.draggableTask!,
          feedback: feedbackWidget,
          childWhenDragging: whenDragging,
          hapticFeedbackOnStart: true,
          child: header,
        );
      }
      return Draggable<Task>(
        data: widget.draggableTask!,
        feedback: feedbackWidget,
        childWhenDragging: whenDragging,
        child: header,
      );
    }

    return header;
  }

  Widget _buildSummaryStatusCell() {
    final status = widget.summaryStatus ?? 'not_started';
    final color = _statusColor(status);
    return PopupMenuButton<String>(
      onSelected: (value) => widget.onSummaryStatusChanged?.call(value),
      tooltip: 'Change phase status',
      offset: const Offset(0, 30),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'not_started', child: Text('Not Started')),
        PopupMenuItem(value: 'working_on_it', child: Text('Working on it')),
        PopupMenuItem(value: 'stuck', child: Text('Stuck')),
        PopupMenuItem(value: 'done', child: Text('Done')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _assigneeStack() {
    final assigneeIds = widget.summaryAssignees.map((u) => u.id).toList();
    return TaskAssigneeAvatars(
      usersMap: widget.usersMap,
      allWorkspaceUsers: widget.allWorkspaceUsers,
      assigneeIdsOverride: assigneeIds,
      maxVisible: 3,
      avatarSize: 20,
      readOnly: true,
    );
  }

  Widget _buildSummaryDueDateCell() {
    final dueDate = widget.summaryDueDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue =
        dueDate != null &&
        DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(today);
    final textColor = dueDate == null
        ? AppColors.textTertiary
        : (isOverdue ? AppColors.error : AppColors.textSecondary);
    final label = dueDate == null ? 'No date' : _formatDate(dueDate);

    return Container(
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
              label,
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
    );
  }

  Widget _buildSummaryProgressCell() {
    final progress = widget.summaryProgress;
    if (progress == null) {
      return const Align(
        alignment: Alignment.center,
        child: Text(
          '-',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final color = _getProgressColor(progress);
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(
              painter: _SummaryProgressCirclePainter(
                progress: progress / 100,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$progress%',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAssigneeCell() {
    final enabled =
        widget.onSummaryAssigneeSelected != null &&
        widget.allWorkspaceUsers.isNotEmpty;
    final anchor = widget.summaryAssignees.isNotEmpty
        ? _assigneeStack()
        : Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.cardBorder,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textTertiary, width: 1),
            ),
            child: const Icon(
              Icons.person_add_outlined,
              size: 13,
              color: AppColors.textSecondary,
            ),
          );

    final cell = Align(alignment: Alignment.centerLeft, child: anchor);
    if (!enabled) return cell;

    final selectedIds = widget.summaryAssignees.map((u) => u.id).toSet();
    const unassignSentinel = '__unassign_all__';
    return PopupMenuButton<String>(
      tooltip: 'Assign all tasks in phase',
      offset: const Offset(0, 30),
      onSelected: (userId) => widget.onSummaryAssigneeSelected?.call(
        userId == unassignSentinel ? null : userId,
      ),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: unassignSentinel,
          child: Row(
            children: [
              const Icon(Icons.person_off_outlined, size: 16),
              const SizedBox(width: 8),
              const Text('Unassign all'),
              if (selectedIds.isEmpty) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        ),
        ...widget.allWorkspaceUsers.map((user) {
          final isSelected = selectedIds.contains(user.id);
          return PopupMenuItem<String>(
            value: user.id,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 9,
                  backgroundColor: AppColors.info.withValues(alpha: 0.85),
                  child: Text(
                    user.getInitials(),
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.displayName?.isNotEmpty == true
                        ? user.displayName!
                        : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) const Icon(Icons.check, size: 16),
              ],
            ),
          );
        }),
      ],
      child: cell,
    );
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress >= 50) return const Color(0xFF4A90A4);
    if (progress > 0) return AppColors.warning;
    return AppColors.textTertiary;
  }
}

class _SummaryProgressCirclePainter extends CustomPainter {
  final double progress;
  final Color color;

  _SummaryProgressCirclePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

    final backgroundPaint = Paint()
      ..color = AppColors.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    if (progress > 0) {
      const startAngle = -1.5708;
      final sweepAngle = 6.2832 * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SummaryProgressCirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
