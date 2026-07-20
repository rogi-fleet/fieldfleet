import 'package:flutter/material.dart';
import 'tree_drop_zone.dart';

/// Wraps a child widget (typically [TreeRowContainer]) with an
/// [AnimatedContainer] that adds an insertion-gap margin above or below
/// the row while a dragged item is hovering in the [DropZone.above] or
/// [DropZone.below] zones.
class TreeRowDropWrapper extends StatelessWidget {
  final DropZone dropZone;

  /// Size of the insertion gap shown above/below the row during drag.
  final double insertionGap;

  /// Base vertical margin added regardless of drop zone (usually 0).
  final double verticalGap;

  final Widget child;

  const TreeRowDropWrapper({
    super.key,
    required this.dropZone,
    this.insertionGap = 28,
    this.verticalGap = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(
        top: verticalGap + (dropZone == DropZone.above ? insertionGap : 0),
        bottom: verticalGap + (dropZone == DropZone.below ? insertionGap : 0),
      ),
      child: child,
    );
  }
}
