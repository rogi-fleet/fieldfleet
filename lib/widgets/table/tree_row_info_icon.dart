import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Builds the (ⓘ) info icon for a tree row item that has a description.
///
/// Returns [null] if [hasDescription] is false.
///
/// The [tooltipBuilder] callback receives the raw icon widget and wraps it
/// in the caller's own tooltip (e.g. TaskHoverTooltip or BudgetItemHoverTooltip).
Widget? buildTreeInfoIcon({
  required bool hasDescription,
  required Widget Function(Widget icon) tooltipBuilder,
}) {
  if (!hasDescription) return null;
  return tooltipBuilder(
    const Padding(
      padding: EdgeInsets.only(top: 1),
      child: Icon(
        Icons.info_outline,
        size: 13,
        color: AppColors.infoDark,
      ),
    ),
  );
}
