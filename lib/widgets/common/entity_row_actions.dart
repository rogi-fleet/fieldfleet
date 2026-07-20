import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'entity_action_item.dart';
import 'entity_archived_badge.dart';

class EntityRowActions extends StatelessWidget {
  final bool isArchived;
  final String tooltip;
  final List<EntityActionItem> items;
  final ValueChanged<String> onSelected;

  const EntityRowActions({
    super.key,
    required this.isArchived,
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isArchived)
          const EntityArchivedBadge(margin: EdgeInsets.only(right: 8)),
        PopupMenuButton<String>(
          tooltip: tooltip,
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
      ],
    );
  }
}
