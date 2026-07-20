import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../models/project_task_metrics.dart';
import '../project_hover_tooltip.dart';
import 'timeline_calculator.dart';
import '../../theme/theme.dart';

/// Minimum bar width to show one line of text inside the bar.
const double _kOneLineMinWidth = 60.0;


/// Renders a single project as a horizontal bar on the Gantt timeline.
///
/// Color is derived from [ProjectStatusTheme]. Terminal statuses
/// (complete, lost, canceled) render at reduced opacity.
class ProjectGanttBar extends StatelessWidget {
  final Project project;
  final TimelineCalculator calculator;
  final DateTime rangeStart;
  final double rowHeight;
  final ProjectTaskMetrics? taskMetrics;
  final VoidCallback? onTap;

  const ProjectGanttBar({
    super.key,
    required this.project,
    required this.calculator,
    required this.rangeStart,
    this.rowHeight = 56,
    this.taskMetrics,
    this.onTap,
  });

  /// Returns the street portion of [address] (everything before the first comma).
  String _shortAddress(String address) {
    final comma = address.indexOf(',');
    return comma > 0 ? address.substring(0, comma).trim() : address.trim();
  }

  /// Builds the text widget rendered inside the bar (project name only).
  /// Customer and address are always shown outside the bar.
  Widget _buildInsideText() {
    return Text(
      project.name,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        shadows: [
          Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black45),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  /// Builds the overflow text shown to the right of the bar when it is too
  /// narrow to fit all information inside. Returns `null` when there is
  /// nothing extra to display outside the bar.
  Widget? _buildOutsideText(double width) {
    final lines = <({String text, bool bold})>[];

    // If the bar is too narrow to show the name inside, include it here.
    if (width < _kOneLineMinWidth) {
      lines.add((text: project.name, bold: true));
    }

    // Always show customer name outside the bar.
    if (project.customerName != null && project.customerName!.isNotEmpty) {
      lines.add((text: project.customerName!, bold: false));
    }

    // Always show address outside the bar.
    final shortAddr = _shortAddress(project.address);
    if (shortAddr.isNotEmpty) {
      // Avoid duplicating if customer name IS the address.
      if (project.customerName?.isNotEmpty != true ||
          shortAddr != project.customerName) {
        lines.add((text: shortAddr, bold: false));
      }
    }

    if (lines.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        height: rowHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: lines
              .map(
                (l) => Text(
                  l.text,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: l.bold ? 11 : 10,
                    fontWeight:
                        l.bold ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStart = project.startDate ?? project.targetCompletionDate;
    final effectiveEnd = project.targetCompletionDate ?? project.startDate;
    if (effectiveStart == null && effectiveEnd == null) {
      return const SizedBox.shrink();
    }

    final position = calculator.getTaskPosition(
      effectiveStart,
      effectiveEnd,
      rangeStart,
    );
    final width = calculator.getTaskWidth(effectiveStart, effectiveEnd, null);
    final barColor = ProjectStatusTheme.color(project.status);
    final isClosed = project.status.isClosed;
    final isOverdue = project.isOverdue();

    // Determine if bar is open-ended (missing one date)
    final hasStartOnly =
        project.startDate != null && project.targetCompletionDate == null;
    final hasEndOnly =
        project.targetCompletionDate != null && project.startDate == null;

    final outsideText = _buildOutsideText(width);

    return Positioned(
      left: position,
      child: Semantics(
        label: '${project.name}, ${project.status.displayName}',
        button: onTap != null,
        child: ProjectHoverTooltip(
          project: project,
          taskMetrics: taskMetrics,
          child: GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  height: rowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Opacity(
                        opacity: isClosed ? 0.55 : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                barColor,
                                barColor.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(
                              color: isOverdue
                                  ? Colors.red.shade600
                                  : barColor.withValues(alpha: 0.6),
                              width: isOverdue ? 1.5 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Open-ended indicators
                              if (hasStartOnly)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: CustomPaint(
                                    size: const Size(8, double.infinity),
                                    painter: _DashedEdgePainter(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      isRight: true,
                                    ),
                                  ),
                                ),
                              if (hasEndOnly)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: CustomPaint(
                                    size: const Size(8, double.infinity),
                                    painter: _DashedEdgePainter(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      isRight: false,
                                    ),
                                  ),
                                ),
                              if (width >= _kOneLineMinWidth)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildInsideText(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (outsideText != null) outsideText,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints dashed vertical lines on an open-ended bar edge.
class _DashedEdgePainter extends CustomPainter {
  final Color color;
  final bool isRight;

  _DashedEdgePainter({required this.color, required this.isRight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final x = isRight ? size.width - 1 : 1.0;
    const dashLength = 4.0;
    const gapLength = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + dashLength).clamp(0, size.height)),
        paint,
      );
      y += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DashedEdgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isRight != isRight;
}
