import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../models/skill.dart';
import '../services/service_locator.dart';


import '../theme/theme.dart';
import 'user_avatar.dart';
import 'task_form_popup.dart';
import 'skill_chip.dart';
import 'task_hover_tooltip.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final String? projectName;
  final String? propertyName;
  final VoidCallback? onDelete;

  const TaskCard({
    super.key,
    required this.task,
    this.projectName,
    this.propertyName,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.isOverdue();

    return TaskHoverTooltip(
      task: task,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: InkWell(
          onTap: () => showTaskFormPopup(
            context,
            projectId: task.projectId,
            taskId: task.id,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status color stripe on the left edge
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg),
                      bottomLeft: Radius.circular(AppRadius.lg),
                    ),
                  ),
                ),

                // Checkbox section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.base,
                  ),
                  child: _buildCheckbox(context),
                ),

                // Main content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                      horizontal: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
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
                            // Priority badge
                            if (task.priority != 'medium')
                              _buildPriorityBadge(),
                          ],
                        ),

                        // Description (if present)
                        if (task.description != null &&
                            task.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.description!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Details row (project, dates, progress)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Project name
                            if (projectName != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_outlined,
                                    size: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 80,
                                    ),
                                    child: Text(
                                      projectName!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                            // Property name (if linked)
                            if (propertyName != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.financialAccentLight,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.xs,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.home_outlined,
                                      size: 12,
                                      color: AppColors.financialAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 80,
                                      ),
                                      child: Text(
                                        propertyName!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.financialAccent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Due date
                            if (task.dueDate != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: isOverdue
                                        ? AppColors.error
                                        : AppColors.textTertiary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(task.dueDate!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOverdue
                                          ? AppColors.error
                                          : AppColors.textSecondary,
                                      fontWeight: isOverdue
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (isOverdue) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorLight,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.xs,
                                        ),
                                      ),
                                      child: const Text(
                                        'Overdue',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.errorDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                            // Progress
                            if (task.progress > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 60,
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
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        // Required Skills
                        if (task.requiredSkillIds.isNotEmpty) _buildSkillsRow(),
                      ],
                    ),
                  ),
                ),

                // Right section: Assigned users and actions
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Assigned user avatars
                      if (task.assignedToIds.isNotEmpty)
                        _buildAssignedAvatars(),

                      // Actions menu
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 12),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          if (onDelete != null)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: AppColors.error,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: AppColors.error),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              showTaskFormPopup(
                                context,
                                projectId: task.projectId,
                                taskId: task.id,
                              );
                              break;
                            case 'delete':
                              if (onDelete != null) onDelete!();
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox(BuildContext context) {
    return Checkbox(
      value: task.isComplete,
      onChanged: (bool? value) async {
        try {
          await ServiceLocator.taskService.toggleTaskCompletion(
            task.id,
            task.isComplete,
          );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'updating task'),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
    );
  }

  Color _getStatusColor() {
    if (task.isComplete) return AppColors.success;
    if (task.isOverdue()) return AppColors.error;
    if (task.progress > 0) return AppColors.info;
    return AppColors.textTertiary;
  }

  Color _getProgressColor(int progress) {
    if (progress >= 100) return AppColors.success;
    if (progress >= 50) return AppColors.info;
    if (progress > 0) return AppColors.secondary;
    return AppColors.textTertiary;
  }

  Widget _buildSkillsRow() {
    return StreamBuilder<List<Skill>>(
      stream: ServiceLocator.skillService.getSkills(task.workspaceId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final skills = snapshot.data!
            .where((s) => task.requiredSkillIds.contains(s.id))
            .toList();

        if (skills.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: skills
                .map((skill) => SkillChip(skill: skill, isCompact: true))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildPriorityBadge() {
    Color bgColor;
    Color textColor;

    switch (task.priority.toLowerCase()) {
      case 'high':
        bgColor = AppColors.errorLight;
        textColor = AppColors.errorDark;
        break;
      case 'low':
        bgColor = AppColors.infoLight;
        textColor = AppColors.infoDark;
        break;
      default:
        bgColor = AppColors.surfaceAlt;
        textColor = AppColors.textPrimary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        task.priority,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildAssignedAvatars() {
    const maxVisible = 3;
    final visibleIds = task.assignedToIds.take(maxVisible).toList();
    final remainingCount = task.assignedToIds.length - maxVisible;

    // Calculate width: each avatar is 24px, overlap by 8px
    final avatarWidth = 24.0;
    final overlap = 8.0;
    final totalWidth =
        visibleIds.length * avatarWidth -
        (visibleIds.length - 1) * overlap +
        (remainingCount > 0 ? avatarWidth : 0);

    return SizedBox(
      height: 24,
      width: totalWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < visibleIds.length; i++)
            Positioned(
              left: i * (avatarWidth - overlap),
              child: FutureBuilder<AppUser?>(
                future: ServiceLocator.userService.getUserById(visibleIds[i]),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                    );
                  }
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Tooltip(
                      message:
                          snapshot.data?.displayName ??
                          snapshot.data?.email ??
                          'Unknown',
                      child: UserAvatar(
                        user: snapshot.data,
                        size: AvatarSize.small,
                        onTap: null,
                      ),
                    ),
                  );
                },
              ),
            ),
          if (remainingCount > 0)
            Positioned(
              left: visibleIds.length * (avatarWidth - overlap),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$remainingCount',
                    style: const TextStyle(
                      fontSize: 9,
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';

    return '${date.month}/${date.day}/${date.year}';
  }
}
