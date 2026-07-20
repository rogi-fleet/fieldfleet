import 'package:flutter/material.dart';

class EntityRecordFilterToggle extends StatelessWidget {
  final bool showArchived;
  final ValueChanged<bool> onChanged;
  final String activeLabel;
  final String archivedLabel;

  const EntityRecordFilterToggle({
    super.key,
    required this.showArchived,
    required this.onChanged,
    this.activeLabel = 'Active',
    this.archivedLabel = 'Archived',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChoiceChip(
          label: Text(activeLabel),
          selected: !showArchived,
          onSelected: (_) => onChanged(false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(archivedLabel),
          selected: showArchived,
          onSelected: (_) => onChanged(true),
        ),
      ],
    );
  }
}
