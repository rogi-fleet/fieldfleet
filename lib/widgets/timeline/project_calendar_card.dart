import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../../theme/theme.dart';

/// Compact project card for displaying in calendar day cells.
class ProjectCalendarCard extends StatefulWidget {
  final Project project;
  final ProjectTaskMetrics? taskMetrics;
  final String? customerName;
  final Color? accentColor;
  final VoidCallback? onTap;

  const ProjectCalendarCard({
    super.key,
    required this.project,
    this.taskMetrics,
    this.customerName,
    this.accentColor,
    this.onTap,
  });

  @override
  State<ProjectCalendarCard> createState() => _ProjectCalendarCardState();
}

class _ProjectCalendarCardState extends State<ProjectCalendarCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.accentColor ?? ProjectStatusTheme.color(widget.project.status);

    return MouseRegion(
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
                // Project name + status dot
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                // Customer name or status label
                if (widget.customerName != null &&
                    widget.customerName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.business_outlined,
                        size: 10,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          widget.customerName!,
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
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.project.status.displayName,
                    style: TextStyle(
                      fontSize: 9,
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
