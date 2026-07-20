import 'package:flutter/material.dart';
import '../common/segmented_toggle_styles.dart';
import '../../theme/app_breakpoints.dart';

class TaskViewToggle extends StatelessWidget {
  final String selectedView;
  final ValueChanged<String> onSelectionChanged;
  final List<String> segmentOrder;

  const TaskViewToggle({
    super.key,
    required this.selectedView,
    required this.onSelectionChanged,
    this.segmentOrder = const [
      'cards',
      'list',
      'month',
      'gantt',
      'board',
      'availability',
    ],
  });

  static const Map<String, (IconData, String, String)> _segmentConfig = {
    'cards': (Icons.grid_view, 'Cards', 'Cards'),
    'list': (Icons.view_list, 'List', 'List'),
    'month': (Icons.calendar_month, 'Calendar', 'Calendar'),
    'gantt': (Icons.view_timeline, 'Gantt', 'Gantt'),
    'board': (Icons.view_kanban, 'Board', 'Board'),
    'availability': (Icons.groups, 'Team', 'Team Availability'),
  };

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isCompact =
        mediaQuery.size.width < AppBreakpoints.mobile || mediaQuery.size.shortestSide < 600;

    return SegmentedButton<String>(
      showSelectedIcon: !isCompact,
      segments: [
        for (final value in segmentOrder)
          if (_segmentConfig.containsKey(value))
            _buildSegment(value, isCompact),
      ],
      style: SegmentedToggleStyles.toolbar(context, compact: isCompact),
      selected: {selectedView},
      onSelectionChanged: (Set<String> newSelection) {
        onSelectionChanged(newSelection.first);
      },
    );
  }

  ButtonSegment<String> _buildSegment(String value, bool isCompact) {
    final (icon, label, tooltip) = _segmentConfig[value]!;

    return ButtonSegment<String>(
      value: value,
      icon: Icon(icon),
      label: isCompact
          ? null
          : Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
      tooltip: tooltip,
    );
  }
}
