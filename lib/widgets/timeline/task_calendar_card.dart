import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../models/user.dart';
import '../../theme/theme.dart';
import '../task_assignee_avatars.dart';
import '../task_hover_tooltip.dart';

/// Compact task card for displaying in calendar day cells
class TaskCalendarCard extends StatefulWidget {
  final Task task;
  final Map<String, AppUser> usersMap;
  final List<AppUser> allWorkspaceUsers;
  final String? location;
  final Color? accentColor;
  final Color? statusIndicatorColor;
  final VoidCallback? onTap;

  const TaskCalendarCard({
    super.key,
    required this.task,
    this.usersMap = const {},
    this.allWorkspaceUsers = const [],
    this.location,
    this.accentColor,
    this.statusIndicatorColor,
    this.onTap,
  });

  @override
  State<TaskCalendarCard> createState() => _TaskCalendarCardState();
}

class _TaskCalendarCardState extends State<TaskCalendarCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor ?? _getFallbackColor();
    final showStatusIndicator =
        widget.statusIndicatorColor != null &&
        widget.statusIndicatorColor!.toARGB32() != accentColor.toARGB32();

    return TaskHoverTooltip(
      task: widget.task,
      usersMap: widget.usersMap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: _isHovered
                  ? accentColor.withValues(alpha: 0.25)
                  : accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border(left: BorderSide(color: accentColor, width: 3)),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Task title
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.task.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                            decoration: widget.task.isComplete
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showStatusIndicator) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: widget.statusIndicatorColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      TaskAssigneeAvatars(
                        task: widget.task,
                        usersMap: widget.usersMap,
                        allWorkspaceUsers: widget.allWorkspaceUsers,
                        maxVisible: 2,
                        avatarSize: 14,
                        readOnly: true,
                      ),
                    ],
                  ),
                  // Location (optional)
                  if (widget.location != null &&
                      widget.location!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 10,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            widget.location!,
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getFallbackColor() {
    // Use group color if defined and not default blue
    if (widget.task.groupColor.toARGB32() != Colors.blue.toARGB32() &&
        widget.task.groupColor.toARGB32() != AppColors.info.toARGB32()) {
      return widget.task.groupColor;
    }

    // Otherwise color by status
    switch (widget.task.status.toLowerCase()) {
      case 'done':
      case 'complete':
      case 'completed':
        return AppColors.success;
      case 'working on it':
      case 'in progress':
        return AppColors.info;
      case 'stuck':
      case 'blocked':
        return AppColors.error;
      case 'not started':
      default:
        return AppColors.textTertiary;
    }
  }
}
