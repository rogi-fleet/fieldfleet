import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'task_calendar_color_resolver.dart';

/// Shows a popup dialog with all tasks for a specific day
void showDayTasksPopup(
  BuildContext context, {
  required DateTime date,
  required List<Task> tasks,
  required Map<String, AppUser> usersMap,
  String? projectAddress,
  List<Task>? colorContextTasks,
  bool preferPhaseColors = false,
  void Function(Task task)? onTaskTap,
  void Function()? onAddTask,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DayTasksBottomSheet(
        date: date,
        tasks: tasks,
        usersMap: usersMap,
        projectAddress: projectAddress,
        colorResolver: TaskCalendarColorResolver(
          tasks: colorContextTasks ?? tasks,
          preferPhaseColors: preferPhaseColors,
        ),
        onTaskTap: onTaskTap,
        onAddTask: onAddTask,
      ),
    );
  } else {
    showDialog(
      context: context,
      builder: (context) => _DayTasksDialog(
        date: date,
        tasks: tasks,
        usersMap: usersMap,
        projectAddress: projectAddress,
        colorResolver: TaskCalendarColorResolver(
          tasks: colorContextTasks ?? tasks,
          preferPhaseColors: preferPhaseColors,
        ),
        onTaskTap: onTaskTap,
        onAddTask: onAddTask,
      ),
    );
  }
}

class _DayTasksBottomSheet extends StatelessWidget {
  final DateTime date;
  final List<Task> tasks;
  final Map<String, AppUser> usersMap;
  final String? projectAddress;
  final TaskCalendarColorResolver colorResolver;
  final void Function(Task task)? onTaskTap;
  final void Function()? onAddTask;

  const _DayTasksBottomSheet({
    required this.date,
    required this.tasks,
    required this.usersMap,
    this.projectAddress,
    required this.colorResolver,
    this.onTaskTap,
    this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              const Divider(height: 1),
              Expanded(child: _buildTasksList(context, scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            _formatDate(date),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          if (onAddTask != null)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.of(context).pop();
                onAddTask?.call();
              },
              tooltip: 'Add Task',
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList(
    BuildContext context,
    ScrollController? scrollController,
  ) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_outlined, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text(
              'No tasks for this day',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
            ),
            if (onAddTask != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAddTask?.call();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Task'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildExpandedTaskCard(context, task),
        );
      },
    );
  }

  Widget _buildExpandedTaskCard(BuildContext context, Task task) {
    final accentColor = colorResolver.accentColorFor(task);
    final statusColor = colorResolver.statusColorForTask(task);

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTaskTap?.call(task);
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border(left: BorderSide(color: accentColor, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      decoration: task.isComplete
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          _statusLabel(task.status),
                          style: TextStyle(fontSize: 10, color: statusColor),
                        ),
                      ),
                      if (projectAddress != null &&
                          projectAddress!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            projectAddress!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (task.assignedToIds.isNotEmpty) _buildAssigneeAvatars(task),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
          ],
        ),
      ),
    );
  }

  Widget _buildAssigneeAvatars(Task task) {
    const double size = 24;
    final displayIds = task.assignedToIds.take(2).toList();
    final remaining = task.assignedToIds.length - 2;

    return SizedBox(
      width:
          displayIds.length * (size * 0.7) + (remaining > 0 ? size * 0.7 : 0),
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < displayIds.length; i++)
            Positioned(
              left: i * (size * 0.6),
              child: _buildSingleAvatar(displayIds[i], size),
            ),
          if (remaining > 0)
            Positioned(
              left: displayIds.length * (size * 0.6),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAvatar(String userId, double size) {
    final cachedUser = usersMap[userId];
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    final colorIndex = userId.hashCode.abs() % colors.length;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors[colorIndex],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: StreamBuilder<AppUser?>(
        stream: ServiceLocator.userService.getUserStream(userId),
        builder: (context, snapshot) {
          final user = snapshot.data ?? cachedUser;
          if (user?.profilePictureUrl != null) {
            return ClipOval(
              child: CachedNetworkImage(
                imageUrl: user!.profilePictureUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _buildInitials(user, size),
              ),
            );
          }
          return _buildInitials(user, size);
        },
      ),
    );
  }

  Widget _buildInitials(AppUser? user, double size) {
    final initials = user?.getInitials() ?? '?';
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const monthNames = [
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
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    return '${dayNames[date.weekday % 7]}, ${monthNames[date.month - 1]} ${date.day}';
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'working_on_it':
      case 'working on it':
      case 'in_progress':
      case 'in progress':
        return 'Working on it';
      case 'not_started':
      case 'not started':
        return 'Not started';
      case 'done':
      case 'complete':
      case 'completed':
        return 'Done';
      case 'stuck':
      case 'blocked':
        return 'Stuck';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}

class _DayTasksDialog extends StatelessWidget {
  final DateTime date;
  final List<Task> tasks;
  final Map<String, AppUser> usersMap;
  final String? projectAddress;
  final TaskCalendarColorResolver colorResolver;
  final void Function(Task task)? onTaskTap;
  final void Function()? onAddTask;

  const _DayTasksDialog({
    required this.date,
    required this.tasks,
    required this.usersMap,
    this.projectAddress,
    required this.colorResolver,
    this.onTaskTap,
    this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(
              child: _DayTasksBottomSheet(
                date: date,
                tasks: tasks,
                usersMap: usersMap,
                projectAddress: projectAddress,
                colorResolver: colorResolver,
                onTaskTap: onTaskTap,
                onAddTask: onAddTask,
              )._buildTasksList(context, null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    const monthNames = [
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
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final dateStr =
        '${dayNames[date.weekday % 7]}, ${monthNames[date.month - 1]} ${date.day}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            dateStr,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          if (onAddTask != null)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.of(context).pop();
                onAddTask?.call();
              },
              tooltip: 'Add Task',
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
