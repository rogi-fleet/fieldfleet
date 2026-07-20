import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// A reusable selection bar for document lists.
/// Shows selected count, bulk action buttons, and a clear button.
class DocumentSelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onDelete;
  final VoidCallback onApprove;

  const DocumentSelectionBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDelete,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == totalCount && totalCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: AppColors.info.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Select-all checkbox
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: allSelected,
              tristate: !allSelected && selectedCount > 0,
              onChanged: (_) {
                if (allSelected) {
                  onClearSelection();
                } else {
                  onSelectAll();
                }
              },
              activeColor: AppColors.info,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          // Selection count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.info,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '$selectedCount selected',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          // Approve button
          IconButton(
            icon: const Icon(Icons.verified_outlined),
            tooltip: 'Approve selected',
            onPressed: onApprove,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            color: AppColors.financialAccent,
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete selected',
            onPressed: onDelete,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            color: AppColors.error,
          ),
          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear selection',
            onPressed: onClearSelection,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
