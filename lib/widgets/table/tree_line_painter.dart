import 'package:flutter/material.dart';

/// Types of tree connector lines drawn in hierarchical table rows.
enum TreeLineType { none, vertical, tee, elbow }

/// Paints a single tree connector segment with rounded bezier corners.
class TreeLinePainter extends CustomPainter {
  final TreeLineType type;
  final Color color;

  /// Fixed Y position for the horizontal branch. When null, defaults to
  /// vertical center of the cell.
  final double? fixedBranchY;

  TreeLinePainter({
    required this.type,
    required this.color,
    this.fixedBranchY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (type == TreeLineType.none) return;

    const cornerRadius = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midX = size.width / 2;
    final midY = fixedBranchY ?? size.height / 2;

    switch (type) {
      case TreeLineType.vertical:
        canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
      case TreeLineType.tee:
        canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
        final branch = Path()
          ..moveTo(midX, midY - cornerRadius)
          ..quadraticBezierTo(midX, midY, midX + cornerRadius, midY)
          ..lineTo(size.width, midY);
        canvas.drawPath(branch, paint);
      case TreeLineType.elbow:
        final branch = Path()
          ..moveTo(midX, 0)
          ..lineTo(midX, midY - cornerRadius)
          ..quadraticBezierTo(midX, midY, midX + cornerRadius, midY)
          ..lineTo(size.width, midY);
        canvas.drawPath(branch, paint);
      case TreeLineType.none:
        break;
    }
  }

  @override
  bool shouldRepaint(TreeLinePainter oldDelegate) =>
      type != oldDelegate.type ||
      color != oldDelegate.color ||
      fixedBranchY != oldDelegate.fixedBranchY;
}

/// Builds tree guide widgets for a hierarchical row.
///
/// [depth] is the nesting level of the item.
/// [treeGuides] indicates which ancestor levels have more siblings below.
/// [isLastChild] whether this is the last sibling at its level.
/// [colorScheme] provides theme colors for the lines.
/// [showPhaseHierarchyGuide] adds an extra guide at level 0 for phase headers.
/// [cellWidth] and [cellHeight] control each guide cell's dimensions.
List<Widget> buildTreeGuides({
  required int depth,
  required List<bool> treeGuides,
  required bool isLastChild,
  required ColorScheme colorScheme,
  bool showPhaseHierarchyGuide = false,
  double cellWidth = 24,
  double? cellHeight = 48,
}) {
  final totalDepth = depth + (showPhaseHierarchyGuide ? 1 : 0);
  if (totalDepth <= 0) return const <Widget>[];

  return List.generate(totalDepth, (i) {
    TreeLineType type;

    if (showPhaseHierarchyGuide && i == 0) {
      if (depth == 0) {
        type = isLastChild ? TreeLineType.elbow : TreeLineType.tee;
      } else {
        type = TreeLineType.vertical;
      }
    } else {
      final depthIndex = showPhaseHierarchyGuide ? i - 1 : i;
      final isCurrentLevel = depthIndex == depth - 1;

      if (isCurrentLevel) {
        type = isLastChild ? TreeLineType.elbow : TreeLineType.tee;
      } else {
        type = depthIndex < treeGuides.length && treeGuides[depthIndex]
            ? TreeLineType.vertical
            : TreeLineType.none;
      }
    }

    final guide = CustomPaint(
      painter: TreeLinePainter(
        type: type,
        color: colorScheme.outline.withValues(alpha: 0.7),
      ),
    );

    if (cellHeight == null) {
      return SizedBox(
        width: cellWidth,
        child: CustomPaint(
          painter: TreeLinePainter(
            type: type,
            color: colorScheme.outline.withValues(alpha: 0.7),
            fixedBranchY: 26,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    return SizedBox(width: cellWidth, height: cellHeight, child: guide);
  });
}
