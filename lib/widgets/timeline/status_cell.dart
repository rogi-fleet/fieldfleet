import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Monday.com-style status cell with full-cell coloring and popover menu
class StatusCell extends StatelessWidget {
  final String value;
  final Function(String) onChanged;
  final StatusCellType type;

  const StatusCell({
    super.key,
    required this.value,
    required this.onChanged,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    return InkWell(
      onTap: () => _showStatusMenu(context),
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: config.color,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  _StatusCellConfig _getConfig() {
    if (type == StatusCellType.status) {
      return _getStatusConfig(value);
    } else {
      return _getPriorityConfig(value);
    }
  }

  _StatusCellConfig _getStatusConfig(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'complete':
        return _StatusCellConfig('Done', AppColors.success); // Green
      case 'working_on_it':
      case 'in_progress':
        return _StatusCellConfig('Working on it', AppColors.warning); // Orange
      case 'stuck':
      case 'blocked':
        return _StatusCellConfig('Stuck', AppColors.error); // Red
      case 'not_started':
      default:
        return _StatusCellConfig('Not Started', AppColors.textTertiary); // Grey
    }
  }

  _StatusCellConfig _getPriorityConfig(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return _StatusCellConfig('High', AppColors.error); // Red
      case 'medium':
        return _StatusCellConfig('Medium', AppColors.warning); // Orange
      case 'low':
        return _StatusCellConfig('Low', AppColors.info); // Blue
      default:
        return _StatusCellConfig('Medium', AppColors.success); // Green
    }
  }

  void _showStatusMenu(BuildContext context) {
    final options = type == StatusCellType.status
        ? ['not_started', 'working_on_it', 'stuck', 'done']
        : ['low', 'medium', 'high'];

    showMenu<String>(
      context: context,
      position: _getMenuPosition(context),
      items: options.map((option) {
        final config = type == StatusCellType.status
            ? _getStatusConfig(option)
            : _getPriorityConfig(option);

        return PopupMenuItem<String>(
          value: option,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: config.color,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              option,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        onChanged(selected);
      }
    });
  }

  RelativeRect _getMenuPosition(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    return position;
  }
}

enum StatusCellType {
  status,
  priority,
}

class _StatusCellConfig {
  final String label;
  final Color color;

  _StatusCellConfig(this.label, this.color);
}
