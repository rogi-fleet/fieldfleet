import 'package:flutter/material.dart';
import '../../theme/theme.dart';

enum EntityViewType { table, card }

class EntityViewToggleButton extends StatelessWidget {
  final EntityViewType currentView;
  final VoidCallback onToggle;

  const EntityViewToggleButton({
    super.key,
    required this.currentView,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isTable = currentView == EntityViewType.table;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTable ? Icons.grid_view : Icons.view_list,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isTable ? 'Cards' : 'Table',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
