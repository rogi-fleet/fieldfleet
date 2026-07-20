import 'package:flutter/material.dart';

/// Shared row container for tree-based table views.
///
/// Provides consistent 48px height, rounded corners, and configurable
/// border styling for both TaskRow and BudgetViewRow.
class TreeRowContainer extends StatelessWidget {
  final Color color;
  final BorderSide leftBorder;
  final BorderSide rightBorder;
  final BorderSide topBorder;
  final BorderSide bottomBorder;
  final double? height;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const TreeRowContainer({
    super.key,
    required this.color,
    this.leftBorder = BorderSide.none,
    this.rightBorder = BorderSide.none,
    this.topBorder = BorderSide.none,
    this.bottomBorder = BorderSide.none,
    this.height = 48,
    this.minHeight = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.none,
      height: height,
      constraints: height == null
          ? BoxConstraints(minHeight: minHeight)
          : null,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: leftBorder,
          right: rightBorder,
          top: topBorder,
          bottom: bottomBorder,
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}
