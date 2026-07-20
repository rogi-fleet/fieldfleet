import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/gantt_task_extensions.dart';
import '../../theme/theme.dart';
import 'status_cell.dart';
import 'package:intl/intl.dart';

class TaskGanttTable extends StatefulWidget {
  final List<Task> tasks;
  final double rowHeight;
  final ScrollController scrollController;
  final Function(Task) onTaskTap;
  final Function(String, String?) onTaskCreated; // (title, parentId)
  final Function(Task, bool) onExpandChanged;
  final Function(Task, String) onStatusChanged;
  final Function(Task, String) onPriorityChanged;

  const TaskGanttTable({
    super.key,
    required this.tasks,
    required this.rowHeight,
    required this.scrollController,
    required this.onTaskTap,
    required this.onTaskCreated,
    required this.onExpandChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
  });

  @override
  State<TaskGanttTable> createState() => _TaskGanttTableState();
}

class _TaskGanttTableState extends State<TaskGanttTable> {
  // Cache for TextEditingControllers to avoid recreating them on every build
  final Map<String?, TextEditingController> _footerControllers = {};

  @override
  void dispose() {
    // Dispose all cached controllers
    for (final controller in _footerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Flatten the task tree respecting expanded state
    final flattenedRows = flattenTaskTreeWithFooters(widget.tasks);

    return Container(
      width: 750, // Increased width for more columns
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(context),
          const Divider(height: 1),
          // Body
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: flattenedRows.length,
              itemExtent: widget.rowHeight, // Optimize with fixed item height
              itemBuilder: (context, index) {
                final row = flattenedRows[index];

                if (row.isFooter) {
                  return _buildFooterRow(context, row.parentId);
                } else {
                  return _buildTaskRow(context, row.task!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Row(
        children: [
          const SizedBox(width: 6), // Space for color bar
          // ID Column
          SizedBox(
            width: 40,
            child: Text(
              'ID',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Task Name Column
          Expanded(
            child: Text(
              'Task',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Status Column
          SizedBox(
            width: 120,
            child: Text(
              'Status',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Priority Column
          SizedBox(
            width: 90,
            child: Text(
              'Priority',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Start Date Column
          SizedBox(
            width: 80,
            child: Text(
              'Start',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Duration Column
          SizedBox(
            width: 60,
            child: Text(
              'Dur.',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // End Date Column
          SizedBox(
            width: 80,
            child: Text(
              'End',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          // Progress Column
          SizedBox(
            width: 80,
            child: Text(
              'Progress',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(BuildContext context, Task task) {
    final level = task.getNestingLevel(widget.tasks);
    final hasChildren = task.hasChildren(widget.tasks);
    final indent = level * 20.0;

    return InkWell(
      onTap: () => widget.onTaskTap(task),
      onHover: (hovering) {
        // TODO: Show edit buttons on hover
      },
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Color Bar (6px wide)
            Container(width: 6, height: widget.rowHeight, color: task.groupColor),
            const SizedBox(width: 10),
            // ID
            SizedBox(
              width: 40,
              child: Text(
                '${widget.tasks.indexOf(task) + 1}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // Task Name with indentation and expand icon
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: indent),
                child: Row(
                  children: [
                    if (hasChildren)
                      InkWell(
                        onTap: () => widget.onExpandChanged(task, !task.isExpanded),
                        child: Icon(
                          task.isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                        ),
                      )
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 4),
                    if (task.taskType == TaskType.summary)
                      const Icon(Icons.folder_outlined, size: 16)
                    else if (task.taskType == TaskType.milestone)
                      const Icon(Icons.flag_outlined, size: 16)
                    else
                      const Icon(Icons.check_box_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: task.taskType == TaskType.summary
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (hasChildren)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text(
                          '${task.getChildren(widget.tasks).length}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Status
            SizedBox(
              width: 120,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: StatusCell(
                  value: task.status,
                  type: StatusCellType.status,
                  onChanged: (newStatus) => widget.onStatusChanged(task, newStatus),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Priority
            SizedBox(
              width: 90,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: StatusCell(
                  value: task.priority,
                  type: StatusCellType.priority,
                  onChanged: (newPriority) =>
                      widget.onPriorityChanged(task, newPriority),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Start Date
            SizedBox(
              width: 80,
              child: Text(
                task.startDate != null
                    ? DateFormat('MM/dd').format(task.startDate!)
                    : '-',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // Duration
            SizedBox(
              width: 60,
              child: Text(
                task.estimatedDuration != null
                    ? '${(task.estimatedDuration! / 8).toStringAsFixed(1)}d'
                    : '-',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // End Date
            SizedBox(
              width: 80,
              child: Text(
                task.dueDate != null
                    ? DateFormat('MM/dd').format(task.dueDate!)
                    : '-',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            // Progress
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: task.progress / 100,
                      backgroundColor: AppColors.cardBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getProgressColor(task.progress),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${task.progress}%',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterRow(BuildContext context, String? parentId) {
    final controller = TextEditingController();

    return Container(
      height: widget.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6), // Space for color bar
          const SizedBox(width: 50), // Space for ID
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '+ Add Task',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF2B76E5)),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                filled: true,
                fillColor: Colors.transparent,
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  widget.onTaskCreated(value, parentId);
                  controller.clear();
                  // Refocus for next entry
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (context.mounted) {
                      FocusScope.of(context).requestFocus();
                    }
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress > 50) return AppColors.info;
    if (progress > 0) return AppColors.warning;
    return AppColors.textTertiary;
  }
}
