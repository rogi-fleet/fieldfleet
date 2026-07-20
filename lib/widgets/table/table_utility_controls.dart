import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class TableUtilityControls extends StatelessWidget {
  final Widget searchField;
  final Widget columnPicker;
  final bool hasExpandedItems;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final bool fitToScreen;
  final VoidCallback onToggleFitToScreen;
  final double gap;

  const TableUtilityControls({
    super.key,
    required this.searchField,
    required this.columnPicker,
    required this.hasExpandedItems,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.fitToScreen,
    required this.onToggleFitToScreen,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: searchField),
        SizedBox(width: gap),
        columnPicker,
        SizedBox(width: gap),
        IconButton(
          icon: Icon(
            hasExpandedItems ? Icons.unfold_less : Icons.unfold_more,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onPressed: hasExpandedItems ? onCollapseAll : onExpandAll,
          tooltip: hasExpandedItems ? 'Collapse all' : 'Expand all',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        SizedBox(width: gap),
        IconButton(
          icon: Icon(
            fitToScreen ? Icons.open_in_full : Icons.close_fullscreen,
            size: 18,
            color: fitToScreen ? AppColors.textSecondary : AppColors.info,
          ),
          onPressed: onToggleFitToScreen,
          tooltip: fitToScreen ? 'Expand table (scrollable)' : 'Fit to screen',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}
