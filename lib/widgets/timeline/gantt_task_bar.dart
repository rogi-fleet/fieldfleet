import 'package:flutter/material.dart';
import '../../models/task.dart';
import 'timeline_calculator.dart';
import '../../theme/theme.dart';

/// Enhanced task bar that supports different task types
/// - Summary: Bracket with end-ticks
/// - Standard: Rounded rectangle with progress
/// - Milestone: Diamond shape
class GanttTaskBar extends StatelessWidget {
  final Task task;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final VoidCallback onTap;

  const GanttTaskBar({
    super.key,
    required this.task,
    required this.calculator,
    required this.rangeStart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (task.taskType) {
      case TaskType.summary:
        return _buildSummaryBar();
      case TaskType.milestone:
        return _buildMilestoneBar();
      case TaskType.standard:
        return _buildStandardBar();
    }
  }

  /// Summary task: thick bracket with end-ticks
  Widget _buildSummaryBar() {
    final position = calculator.getTaskPosition(
      task.startDate,
      task.dueDate,
      rangeStart,
    );
    final width = calculator.getTaskWidth(
      task.startDate,
      task.dueDate,
      task.estimatedDuration,
    );

    return Positioned(
      left: position,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          size: Size(width, 48),
          painter: _SummaryBarPainter(
            color: task.groupColor,
          ),
          child: SizedBox(
            width: width,
            height: 48,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Standard task: rounded rectangle with progress fill
  Widget _buildStandardBar() {
    final position = calculator.getTaskPosition(
      task.startDate,
      task.dueDate,
      rangeStart,
    );
    final width = calculator.getTaskWidth(
      task.startDate,
      task.dueDate,
      task.estimatedDuration,
    );

    // Get color based on status
    final barColor = _getStatusColor();

    return Positioned(
      left: position,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Background
                    Container(
                      decoration: BoxDecoration(
                        color: barColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(
                          color: barColor.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                    ),
                    // Progress fill
                    FractionallySizedBox(
                      widthFactor: task.progress / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              barColor,
                              barColor.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (width > 80)
                            Text(
                              '${task.progress}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Milestone: diamond shape
  Widget _buildMilestoneBar() {
    // Milestones use startDate as the single point
    final position = calculator.getTaskPosition(
      task.startDate,
      task.startDate,
      rangeStart,
    );

    return Positioned(
      left: position - 15, // Center the diamond
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(24, 24),
                painter: _DiamondPainter(
                  color: const Color(0xFFFFD700), // Gold
                  completed: task.progress >= 100,
                ),
              ),
              if (task.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (task.status.toLowerCase()) {
      case 'done':
      case 'complete':
        return AppColors.success; // Green
      case 'working_on_it':
      case 'in_progress':
        return AppColors.warning; // Orange
      case 'stuck':
      case 'blocked':
        return AppColors.error; // Red
      case 'not_started':
      default:
        return AppColors.textTertiary; // Grey
    }
  }
}

/// Painter for summary task brackets
class _SummaryBarPainter extends CustomPainter {
  final Color color;

  _SummaryBarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tickHeight = 12.0;
    final y = size.height / 2;

    // Left tick
    canvas.drawLine(
      Offset(0, y - tickHeight / 2),
      Offset(0, y + tickHeight / 2),
      paint,
    );

    // Horizontal line
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      paint,
    );

    // Right tick
    canvas.drawLine(
      Offset(size.width, y - tickHeight / 2),
      Offset(size.width, y + tickHeight / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SummaryBarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Painter for milestone diamonds
class _DiamondPainter extends CustomPainter {
  final Color color;
  final bool completed;

  _DiamondPainter({required this.color, this.completed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0) // Top
      ..lineTo(size.width, size.height / 2) // Right
      ..lineTo(size.width / 2, size.height) // Bottom
      ..lineTo(0, size.height / 2) // Left
      ..close();

    canvas.drawPath(path, paint);

    // Add border
    final borderPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, borderPaint);

    // Add checkmark if completed
    if (completed) {
      final checkPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final checkPath = Path()
        ..moveTo(size.width * 0.25, size.height * 0.5)
        ..lineTo(size.width * 0.4, size.height * 0.65)
        ..lineTo(size.width * 0.75, size.height * 0.35);

      canvas.drawPath(checkPath, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_DiamondPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.completed != completed;
}
