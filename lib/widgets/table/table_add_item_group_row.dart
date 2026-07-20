import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shared footer row with "Add Item" and "Add Group" actions.
class TableAddItemGroupRow extends StatelessWidget {
  final VoidCallback onAddItem;
  final VoidCallback onAddGroup;
  final double leadingSpacing;
  final EdgeInsetsGeometry padding;
  final BorderSide? borderSide;

  const TableAddItemGroupRow({
    super.key,
    required this.onAddItem,
    required this.onAddGroup,
    this.leadingSpacing = 0,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final resolvedBorder = borderSide ?? BorderSide(color: Theme.of(context).dividerColor);

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: actionColor),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: actionColor)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(border: Border(bottom: resolvedBorder)),
      child: Row(
        children: [
          if (leadingSpacing > 0) SizedBox(width: leadingSpacing),
          actionButton(icon: Icons.add, label: 'Add Item', onTap: onAddItem),
          const SizedBox(width: 16),
          actionButton(
            icon: Icons.create_new_folder_outlined,
            label: 'Add Group',
            onTap: onAddGroup,
          ),
        ],
      ),
    );
  }
}
