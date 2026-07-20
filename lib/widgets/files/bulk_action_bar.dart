import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Sticky action bar shown above the file grid/list when one or more files
/// are selected. Each action is a simple labeled icon button; the host
/// wires them to storage_service calls.
class BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback? onMove;
  final VoidCallback? onAddTag;
  final VoidCallback? onRemoveTag;
  final VoidCallback? onDelete;

  const BulkActionBar({
    super.key,
    required this.selectedCount,
    required this.onClear,
    this.onMove,
    this.onAddTag,
    this.onRemoveTag,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount == 0) return const SizedBox.shrink();
    return Material(
      color: AppColors.primarySurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tightCount = constraints.maxWidth < 520;
            return Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear selection',
                  onPressed: onClear,
                ),
                Text(
                  tightCount ? '$selectedCount' : '$selectedCount selected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onMove != null)
                          _BulkActionButton(
                            icon: Icons.drive_file_move,
                            label: 'Move',
                            onTap: onMove!,
                          ),
                        if (onAddTag != null)
                          _BulkActionButton(
                            icon: Icons.label_outline,
                            label: 'Add tag',
                            onTap: onAddTag!,
                          ),
                        if (onRemoveTag != null)
                          _BulkActionButton(
                            icon: Icons.label_off,
                            label: 'Remove tag',
                            onTap: onRemoveTag!,
                          ),
                        if (onDelete != null)
                          _BulkActionButton(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onTap: onDelete!,
                            color: AppColors.error,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BulkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _BulkActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
      ),
    );
  }
}
