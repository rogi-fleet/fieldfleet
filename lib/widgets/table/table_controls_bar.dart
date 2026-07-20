import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared top controls row for table/list screens.
///
/// Provides the same visual chrome as [TaskListToolbar]: surface background,
/// outlineVariant border-bottom, and consistent padding. Use this as the
/// toolbar shell for any list or table view (budget, gantt, task list, etc.).
class TableControlsBar extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double gap;
  final bool showBottomBorder;

  const TableControlsBar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
    this.gap = 8,
    this.showBottomBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final rowChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rowChildren.add(SizedBox(width: gap));
      rowChildren.add(children[i]);
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: chrome.background,
        border: showBottomBorder
            ? Border(bottom: BorderSide(color: chrome.divider))
            : null,
      ),
      child: Row(children: rowChildren),
    );
  }
}
