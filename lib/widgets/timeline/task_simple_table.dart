import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import '../task_assignee_avatars.dart';
import 'package:intl/intl.dart';

class TaskSimpleTable extends StatelessWidget {
  final List<Task> tasks;
  final double rowHeight;
  final ScrollController scrollController;
  final Function(Task) onTaskTap;
  final Function(String) onTaskCreated;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;

  const TaskSimpleTable({
    super.key,
    required this.tasks,
    required this.rowHeight,
    required this.scrollController,
    required this.onTaskTap,
    required this.onTaskCreated,
    this.usersMap = const {},
    this.allWorkspaceUsers = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          SizedBox(
            height: 50, // Match timeline header height
            child: Row(
              children: [
                const SizedBox(width: 16),
                // ID Column
                SizedBox(
                  width: 40,
                  child: Text(
                    'ID',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Task Name Column
                Expanded(
                  child: Text(
                    'Task',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Start Date Column
                SizedBox(
                  width: 80,
                  child: Text(
                    'Start',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Duration Column
                SizedBox(
                  width: 60,
                  child: Text(
                    'Dur.',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // End Date Column
                SizedBox(
                  width: 80,
                  child: Text(
                    'End',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Progress Column
                SizedBox(
                  width: 80,
                  child: Text(
                    'Progress',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Responsible Column
                SizedBox(
                  width: 60,
                  child: Text(
                    'Resp.',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: tasks.length + 1, // +1 for input row
              itemBuilder: (context, index) {
                if (index == tasks.length) {
                  // Input row
                  return Container(
                    height: rowHeight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: '+ Add Task',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                onTaskCreated(value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final task = tasks[index];
                return InkWell(
                  onTap: () => onTaskTap(task),
                  child: Container(
                    height: rowHeight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // ID
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        // Task Name
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
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
                        // Responsible - Quick assignment avatars
                        SizedBox(
                          width: 60,
                          child: TaskAssigneeAvatars(
                            task: task,
                            usersMap: usersMap,
                            allWorkspaceUsers: allWorkspaceUsers,
                            maxVisible: 2,
                            avatarSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
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
