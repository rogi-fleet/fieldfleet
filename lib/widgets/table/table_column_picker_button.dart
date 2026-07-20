import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Shared column visibility picker button with a visible/total badge.
class TableColumnPickerButton extends StatelessWidget {
  final List<String> columnIds;
  final bool Function(String columnId) isColumnVisible;
  final ValueChanged<String> onToggleColumn;
  final String Function(String columnId) columnLabel;
  final String tooltip;
  final Color? badgeBackgroundColor;
  final Color? badgeTextColor;

  const TableColumnPickerButton({
    super.key,
    required this.columnIds,
    required this.isColumnVisible,
    required this.onToggleColumn,
    required this.columnLabel,
    this.tooltip = 'Show/Hide Columns',
    this.badgeBackgroundColor,
    this.badgeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final visibleCount = columnIds.where(isColumnVisible).length;
    return PopupMenuButton<String>(
      icon: Badge(
        label: Text('$visibleCount/${columnIds.length}'),
        backgroundColor: badgeBackgroundColor,
        textColor: badgeTextColor,
        child: Icon(Icons.view_column, color: chrome.text),
      ),
      tooltip: tooltip,
      offset: const Offset(0, 40),
      itemBuilder: (context) => columnIds
          .map((columnId) {
            return PopupMenuItem<String>(
              value: columnId,
              child: StatefulBuilder(
                builder: (context, setMenuState) {
                  final visible = isColumnVisible(columnId);
                  return Row(
                    children: [
                      Checkbox(
                        value: visible,
                        onChanged: (_) {
                          onToggleColumn(columnId);
                          setMenuState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(columnLabel(columnId)),
                    ],
                  );
                },
              ),
            );
          })
          .toList(growable: false),
      onSelected: onToggleColumn,
    );
  }
}

class TableDefaultColumnPickerButton extends StatelessWidget {
  final List<String> columnIds;
  final bool Function(String columnId) isColumnVisible;
  final ValueChanged<String> onToggleColumn;
  final Map<String, String> columnNames;
  final String tooltip;

  const TableDefaultColumnPickerButton({
    super.key,
    required this.columnIds,
    required this.isColumnVisible,
    required this.onToggleColumn,
    required this.columnNames,
    this.tooltip = 'Show/Hide Columns',
  });

  @override
  Widget build(BuildContext context) {
    return TableColumnPickerButton(
      columnIds: columnIds,
      isColumnVisible: isColumnVisible,
      onToggleColumn: onToggleColumn,
      columnLabel: (columnId) => columnNames[columnId] ?? columnId,
      tooltip: tooltip,
      badgeBackgroundColor: AppColors.infoLight,
      badgeTextColor: AppColors.infoDark,
    );
  }
}
