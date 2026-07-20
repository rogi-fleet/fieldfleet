import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../properties/property_detail_view.dart';
import 'mobile_task_detail_sheet.dart';

/// Compact row widget for the mobile list view.
/// Displays task info in a single dense row, unlike the card-style [MobileTaskCard].
class MobileTaskRow extends StatelessWidget {
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

  const MobileTaskRow({
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
    if (isSelectionMode) {
      return _buildRow(context);
    }

    return Slidable(
      key: ValueKey('slide_${task.id}'),
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
      child: _buildRow(context),
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

  // ── Row content ───────────────────────────────────────────────────────────

  Widget _buildRow(BuildContext context) {
    final isOverdue = task.isOverdue() && !task.isComplete;
    final statusColor = switch (task.status) {
      'done' => AppColors.success,
      'working_on_it' => AppColors.info,
      'stuck' => AppColors.error,
      _ => AppColors.textTertiary,
    };
    final propertyShortcut = _resolvePropertyShortcut();
    final contextSummary = [
      if (projectName != null) projectName!,
      if (customerName != null && customerName!.isNotEmpty) customerName!,
      if (locationLabel != null && propertyShortcut == null) locationLabel!,
    ].join(' · ');

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
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.info.withValues(alpha: 0.08) : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Selection checkbox or completion circle
            if (isSelectionMode)
              SizedBox(
                width: 20,
                height: 20,
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
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: task.isComplete
                          ? AppColors.success
                          : Colors.grey.shade400,
                      width: 1.5,
                    ),
                    color: task.isComplete
                        ? AppColors.success
                        : Colors.transparent,
                  ),
                  child: task.isComplete
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
              ),
            const SizedBox(width: 10),

            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 8),

            // Title + context info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (task.isBlockedByDependencies(allTasks)) ...[
                        Icon(Icons.lock_clock,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          task.displayTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: task.isComplete
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                            decoration: task.isComplete
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (contextSummary.isNotEmpty)
                    Text(
                      contextSummary,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (propertyShortcut != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: GestureDetector(
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
                              size: 11,
                              color: AppColors.info,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                propertyShortcut.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.info,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Due date
            if (task.dueDate != null) ...[
              const SizedBox(width: 6),
              _CompactDueDate(dueDate: task.dueDate!, isOverdue: isOverdue),
            ],

            // Assignee (single avatar)
            if (task.assignedToIds.isNotEmpty) ...[
              const SizedBox(width: 6),
              _buildAssigneeAvatar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssigneeAvatar() {
    final firstId = task.assignedToIds.first;
    final user = usersMap[firstId];
    final extra = task.assignedToIds.length - 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: AppColors.textTertiary.withValues(alpha: 0.2),
          child: Text(
            user != null
                ? (user.displayName?.isNotEmpty == true
                      ? user.displayName![0].toUpperCase()
                      : '?')
                : '?',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '+$extra',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ),
      ],
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

  void _openDetail(BuildContext context) {
    showMobileTaskDetailSheet(
      context,
      task: task,
      project: project,
      usersMap: usersMap,
      allWorkspaceUsers: allWorkspaceUsers,
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
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CompactDueDate extends StatelessWidget {
  final DateTime dueDate;
  final bool isOverdue;

  const _CompactDueDate({required this.dueDate, required this.isOverdue});

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
      label = 'Tmrw';
    } else if (diff == -1) {
      label = 'Yest';
    } else if (isOverdue) {
      label = '${(-diff)}d';
    } else {
      label = '${dueDate.month}/${dueDate.day}';
    }

    final color = isOverdue ? AppColors.error : AppColors.textTertiary;

    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: color,
        fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}
