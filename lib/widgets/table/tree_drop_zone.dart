import 'package:flutter/material.dart';

/// Drop zone detected when dragging over a tree row.
enum DropZone { above, child, below, unparent, none }

/// Computes which [DropZone] the drag cursor is currently in.
///
/// [context] is the build context of the row widget.
/// [globalOffset] is the global offset from the drag details.
/// [depth] is the nesting depth of the target row.
/// [hasParent] whether the target row has a parent (enables unparent zone).
/// [hasVisibleChildren] whether the target row has expanded children visible.
///   When false, the child zone is suppressed so users can easily reach the
///   below zone without accidentally nesting the dragged task.
DropZone computeDropZone(
  BuildContext context,
  Offset globalOffset, {
  required int depth,
  required bool hasParent,
  bool hasVisibleChildren = true,
}) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return DropZone.child;

  final local = box.globalToLocal(globalOffset);
  final height = box.size.height;

  // Drag to the left guide area on a child item -> outdent (unparent).
  final unparentThreshold = (40 + (depth * 24.0)).clamp(40.0, 180.0);
  if (local.dx < unparentThreshold && hasParent) {
    return DropZone.unparent;
  }

  final fraction = local.dy / height;

  // When a row has no visible children, skip the child zone so the bottom half
  // always registers as "below". This prevents accidentally nesting a task when
  // the user is simply trying to reorder to the last position in a group.
  if (!hasVisibleChildren) {
    return fraction < 0.50 ? DropZone.above : DropZone.below;
  }

  // Make reorder targets easier to hit:
  // top 40% -> above, bottom 40% -> below, middle 20% -> child.
  if (fraction < 0.40) return DropZone.above;
  if (fraction > 0.60) return DropZone.below;
  return DropZone.child;
}
