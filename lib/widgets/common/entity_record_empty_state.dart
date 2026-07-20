import 'package:flutter/material.dart';

import 'entity_empty_state.dart';

class EntityRecordEmptyState extends StatelessWidget {
  final bool hasFilters;
  final bool isArchivedView;
  final Animation<double> animation;
  final IconData defaultIcon;
  final String entityPluralLabel;
  final String entitySingularLabel;
  final VoidCallback onClearFilters;
  final VoidCallback onCreate;
  final VoidCallback onShowActive;

  const EntityRecordEmptyState({
    super.key,
    required this.hasFilters,
    required this.isArchivedView,
    required this.animation,
    required this.defaultIcon,
    required this.entityPluralLabel,
    required this.entitySingularLabel,
    required this.onClearFilters,
    required this.onCreate,
    required this.onShowActive,
  });

  @override
  Widget build(BuildContext context) {
    return EntityEmptyState(
      hasFilters: hasFilters,
      animation: animation,
      filteredIcon: Icons.search_off,
      defaultIcon: defaultIcon,
      filteredTitle: isArchivedView
          ? 'No archived $entityPluralLabel found'
          : 'No $entityPluralLabel found',
      defaultTitle: 'No $entityPluralLabel yet',
      filteredSubtitle: isArchivedView
          ? 'Try adjusting your filters or switch back to active $entityPluralLabel'
          : 'Try adjusting your filters or search query',
      defaultSubtitle: 'Add your first $entitySingularLabel to get started',
      onClearFilters: onClearFilters,
      createLabel: isArchivedView
          ? 'Show Active ${_capitalize(entityPluralLabel)}'
          : 'Create Your First ${_capitalize(entitySingularLabel)}',
      onCreate: isArchivedView ? onShowActive : onCreate,
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
