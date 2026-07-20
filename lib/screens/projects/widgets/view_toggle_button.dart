import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/theme.dart';

enum ProjectViewType { table, card, board, calendar, gantt }

class ViewToggleButton extends StatefulWidget {
  final ProjectViewType currentView;
  final ValueChanged<ProjectViewType> onViewChanged;

  const ViewToggleButton({
    super.key,
    required this.currentView,
    required this.onViewChanged,
  });

  static Future<ProjectViewType> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('projects_view_type');
    if (saved == 'table') return ProjectViewType.table;
    if (saved == 'board') return ProjectViewType.board;
    if (saved == 'calendar') return ProjectViewType.calendar;
    if (saved == 'gantt') return ProjectViewType.gantt;
    return ProjectViewType.card; // Default to cards view
  }

  @override
  State<ViewToggleButton> createState() => _ViewToggleButtonState();
}

class _ViewToggleButtonState extends State<ViewToggleButton> {
  static const String _prefKey = 'projects_view_type';

  Future<void> _savePreference(ProjectViewType viewType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, viewType.name);
  }

  void _toggleView() {
    final newView = widget.currentView == ProjectViewType.table
        ? ProjectViewType.card
        : ProjectViewType.table;
    _savePreference(newView);
    widget.onViewChanged(newView);
  }

  @override
  Widget build(BuildContext context) {
    // Show the view user can switch TO (not the current view)
    final isTable = widget.currentView == ProjectViewType.table;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleView,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.md),
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
