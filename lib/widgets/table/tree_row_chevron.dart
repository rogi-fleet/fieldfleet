import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Builds the expand/collapse chevron for a tree row.
///
/// Returns a list of widgets (icon + spacing) to be spread into the parent
/// Row's children list.
///
/// - If [hasChildren]: InkWell with chevron icon, then 6px spacer.
/// - If !hasChildren and [depth] == 0: 14px spacer, then 3px spacer.
/// - If !hasChildren and [depth] > 0: just a 3px spacer.
List<Widget> buildTreeChevron({
  required bool hasChildren,
  required bool isExpanded,
  required int depth,
  VoidCallback? onToggle,
}) {
  if (hasChildren) {
    return [
      InkWell(
        onTap: onToggle,
        child: Icon(
          isExpanded ? Icons.expand_more : Icons.chevron_right,
          size: 20,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(width: 6),
    ];
  } else if (depth == 0) {
    return [
      const SizedBox(width: 14),
      const SizedBox(width: 3),
    ];
  } else {
    return [const SizedBox(width: 3)];
  }
}
