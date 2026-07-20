import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../common/status_chip.dart';
import '../properties/property_detail_view.dart';
import '../task_assignee_avatars.dart';
import '../task_form_popup.dart';

class MobileTaskCard extends StatelessWidget {
  final Task task;
  final List<Task> allTasks;
  final String? projectName;
  final Project? project;
  final String? customerName;
  final String? locationLabel;
  final Map<String, Property> propertyMap;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onLongPress;

  const MobileTaskCard({
    super.key,
    required this.task,
    this.allTasks = const [],
    this.projectName,
    this.project,
    this.customerName,
    this.locationLabel,
    this.propertyMap = const {},
    required this.usersMap,
    required this.allWorkspaceUsers,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // In selection mode, skip swipe actions entirely
    if (isSelectionMode) {
      return _buildCard(context);
    }

    return Slidable(
      key: ValueKey('slide_${task.id}'),
      // Swipe right: toggle completion
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.25,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _toggleComplete(context),
            backgroundColor: task.isComplete
                ? AppColors.info
                : AppColors.success,
            foregroundColor: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  task.isComplete ? Icons.replay : Icons.check_circle_outline,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  task.isComplete ? 'Reopen' : 'Done',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // Swipe left: status, reschedule, delete
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.65,
        children: [
          CustomSlidableAction(
            onPressed: (_) => _cycleStatus(context),
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.swap_horiz, size: 22),
                const SizedBox(height: 4),
                Text(
                  _nextStatusLabel(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (context) => _reschedule(context),
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule, size: 22),
                SizedBox(height: 4),
                Text(
                  'Reschedule',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          CustomSlidableAction(
            onPressed: (context) => _confirmDelete(context),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, size: 22),
                SizedBox(height: 4),
                Text(
                  'Delete',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
      child: _buildCard(context),
    );
  }

  // ── Swipe actions ─────────────────────────────────────────────────────────

  String _nextStatusLabel() {
    return switch (task.status) {
      'not_started' => 'Working',
      'working_on_it' => 'Stuck',
      'stuck' => 'Not Started',
      _ => 'Working',
    };
  }

  void _cycleStatus(BuildContext context) {
    final nextStatus = switch (task.status) {
      'not_started' => 'working_on_it',
      'working_on_it' => 'stuck',
      'stuck' => 'not_started',
      _ => 'working_on_it',
    };

    final (label, _) = switch (nextStatus) {
      'working_on_it' => ('Working on it', AppColors.info),
      'stuck' => ('Stuck', AppColors.error),
      _ => ('Not Started', AppColors.textTertiary),
    };

    HapticFeedback.lightImpact();
    ServiceLocator.taskService.updateTask(taskId: task.id, status: nextStatus);
    Slidable.of(context)?.close();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${task.title} → $label'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _reschedule(BuildContext context) async {
    Slidable.of(context)?.close();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Reschedule "${task.title}"',
    );

    if (picked != null && context.mounted) {
      ServiceLocator.taskService.updateTask(taskId: task.id, dueDate: picked);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${task.title} rescheduled to ${picked.month}/${picked.day}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  void _confirmDelete(BuildContext context) async {
    Slidable.of(context)?.close();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ServiceLocator.taskService.deleteTask(task.id);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('${task.title} deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  // ── Card content ──────────────────────────────────────────────────────────

  Widget _buildCard(BuildContext context) {
    final isOverdue = task.isOverdue();
    final completedChecklist = task.checklistItems
        .where((i) => i.isComplete)
        .length;
    final totalChecklist = task.checklistItems.length;
    final propertyShortcut = _resolvePropertyShortcut();

    return InkWell(
      onTap: isSelectionMode
          ? () => onSelectionChanged?.call(!isSelected)
          : () => _openDetail(context),
      onLongPress: isSelectionMode
          ? null
          : onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            }
          : null,
      borderRadius: BorderRadius.circular(AppRadius.r12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.info.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: isSelected
                ? AppColors.info.withValues(alpha: 0.5)
                : isOverdue && !task.isComplete
                ? AppColors.error.withValues(alpha: 0.35)
                : Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selection checkbox or completion circle
                if (isSelectionMode)
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (v) => onSelectionChanged?.call(v ?? false),
                      activeColor: AppColors.info,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _toggleComplete(context),
                    child: Container(
                      margin: const EdgeInsets.only(top: 1),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: task.isComplete
                              ? AppColors.success
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                        color: task.isComplete
                            ? AppColors.success
                            : Colors.transparent,
                      ),
                      child: task.isComplete
                          ? const Icon(
                              Icons.check,
                              size: 13,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                const SizedBox(width: 10),
                if (task.isBlockedByDependencies(allTasks)) ...[
                  Icon(Icons.lock_clock, size: 15, color: AppColors.warning),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    task.displayTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: task.isComplete
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                      decoration: task.isComplete
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: task.status),
              ],
            ),

            // Context row: project, customer, location
            if (projectName != null ||
                customerName != null ||
                locationLabel != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (projectName != null)
                      GestureDetector(
                        onTap: () => context.go('/projects/${task.projectId}'),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder_outlined,
                              size: 12,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                projectName!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (customerName != null && customerName!.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              customerName!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (propertyShortcut != null)
                      GestureDetector(
                        onTap: () => _openPropertyDetail(
                          context,
                          propertyShortcut.property,
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.home_work_outlined,
                              size: 12,
                              color: AppColors.info,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                propertyShortcut.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.info,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (locationLabel != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              locationLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],

            // Bottom meta row
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  // Due date
                  if (task.dueDate != null)
                    _DueDateBadge(
                      dueDate: task.dueDate!,
                      isOverdue: isOverdue && !task.isComplete,
                    ),

                  // Checklist progress
                  if (totalChecklist > 0) ...[
                    if (task.dueDate != null) const SizedBox(width: 8),
                    _ChecklistBadge(
                      completed: completedChecklist,
                      total: totalChecklist,
                    ),
                  ],

                  const Spacer(),

                  // Assignees
                  if (task.assignedToIds.isNotEmpty)
                    TaskAssigneeAvatars(
                      task: task,
                      usersMap: usersMap,
                      allWorkspaceUsers: allWorkspaceUsers,
                      maxVisible: 3,
                      avatarSize: 22,
                      readOnly: true,
                    ),

                  if (!isSelectionMode) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleComplete(BuildContext context) {
    final wasComplete = task.isComplete;
    ServiceLocator.taskService.updateTask(
      taskId: task.id,
      isComplete: !wasComplete,
      status: !wasComplete ? 'done' : 'not_started',
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasComplete
                ? '${task.title} reopened'
                : '${task.title} marked done',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  ({Property property, String label})? _resolvePropertyShortcut() {
    final currentProject = project;
    if (currentProject == null || task.propertyIds.isEmpty) {
      return null;
    }

    final linkedProperties = <Property>[];
    final seenPropertyIds = <String>{};
    for (final propertyId in task.propertyIds) {
      if (!seenPropertyIds.add(propertyId)) continue;
      final property = propertyMap[propertyId];
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

  void _openPropertyDetail(BuildContext context, Property property) {
    final currentProject = project;
    if (currentProject == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PropertyDetailView(
          project: currentProject,
          propertyId: property.id,
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showTaskFormPopup(
      context,
      projectId: task.projectId,
      taskId: task.id,
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'done' => ('Done', AppColors.success),
      'working_on_it' => ('Working', AppColors.info),
      'stuck' => ('Stuck', AppColors.error),
      _ => ('Not Started', AppColors.textTertiary),
    };

    return StatusChip(label: label, color: color, size: StatusChipSize.compact);
  }
}

class _DueDateBadge extends StatelessWidget {
  final DateTime dueDate;
  final bool isOverdue;

  const _DueDateBadge({required this.dueDate, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;

    String label;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Tomorrow';
    } else if (diff == -1) {
      label = 'Yesterday';
    } else if (isOverdue) {
      label = '${(-diff)}d overdue';
    } else {
      label = '${dueDate.month}/${dueDate.day}';
    }

    final color = isOverdue ? AppColors.error : AppColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today_outlined, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _ChecklistBadge extends StatelessWidget {
  final int completed;
  final int total;

  const _ChecklistBadge({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final allDone = completed == total;
    final color = allDone ? AppColors.success : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          allDone ? Icons.check_box_outlined : Icons.check_box_outline_blank,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text('$completed/$total', style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
