import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import 'entity_action_item.dart';

class EntityCardActionItem extends EntityActionItem {
  const EntityCardActionItem({
    required super.value,
    required super.label,
    required super.icon,
    super.isDestructive = false,
  });
}

class EntityCardActionsMenu extends StatelessWidget {
  final List<EntityActionItem> items;
  final ValueChanged<String> onSelected;
  final bool compact;
  final Color? backgroundColor;
  final Color? iconColor;

  const EntityCardActionsMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.compact = false,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill = backgroundColor ?? Colors.black.withValues(alpha: 0.45);
    final foreground = iconColor ?? Colors.white;

    return Material(
      color: fill,
      borderRadius: AppRadius.badgeRadius,
      child: PopupMenuButton<String>(
        tooltip: 'Actions',
        padding: EdgeInsets.zero,
        iconSize: compact ? 18 : 20,
        icon: Icon(Icons.more_horiz, color: foreground),
        onSelected: onSelected,
        itemBuilder: (context) {
          return items.map((item) {
            final itemColor = item.isDestructive
                ? AppColors.error
                : AppColors.textPrimary;
            return PopupMenuItem<String>(
              value: item.value,
              child: Row(
                children: [
                  Icon(item.icon, size: 18, color: itemColor),
                  const SizedBox(width: 10),
                  Text(item.label, style: TextStyle(color: itemColor)),
                ],
              ),
            );
          }).toList();
        },
      ),
    );
  }
}
