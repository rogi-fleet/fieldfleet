import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../table/table_controls_bar.dart';

class GanttToolbar extends StatelessWidget {
  final VoidCallback? onScrollToToday;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final bool isAtMaxZoom;
  final bool isAtMinZoom;
  final VoidCallback? onFilter;
  final VoidCallback? onCollapseAll;
  final VoidCallback? onExpandAll;
  final VoidCallback? onAddTask;
  final VoidCallback? onAddGroup;
  final bool isAllCollapsed;
  final bool hideCompleted;
  final String currentView;
  final Function(String) onViewChanged;
  final VoidCallback? onMassEdit;
  final int selectedCount;
  final bool cascadeShifts;
  final VoidCallback? onToggleCascadeShifts;
  final bool hasBaseline;
  final bool showBaseline;
  final VoidCallback? onSetBaseline;
  final VoidCallback? onToggleShowBaseline;
  final VoidCallback? onExportIcal;

  const GanttToolbar({
    super.key,
    this.onScrollToToday,
    this.onZoomIn,
    this.onZoomOut,
    this.isAtMaxZoom = false,
    this.isAtMinZoom = false,
    this.onFilter,
    this.onCollapseAll,
    this.onExpandAll,
    this.onAddTask,
    this.onAddGroup,
    this.isAllCollapsed = false,
    this.hideCompleted = false,
    required this.currentView,
    required this.onViewChanged,
    this.onMassEdit,
    this.selectedCount = 0,
    this.cascadeShifts = true,
    this.onToggleCascadeShifts,
    this.hasBaseline = false,
    this.showBaseline = false,
    this.onSetBaseline,
    this.onToggleShowBaseline,
    this.onExportIcal,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return TableControlsBar(
      gap: 0,
      children: [
        // View selector
        _buildViewSelector(context),
        // Scroll to today
        if (onScrollToToday != null)
          IconButton(
            icon: Icon(Icons.today, color: chrome.text),
            onPressed: onScrollToToday,
            tooltip: 'Scroll to Today',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        // Cascade-shift toggle: moving a task also moves its dependents
        if (onToggleCascadeShifts != null)
          IconButton(
            icon: Icon(
              cascadeShifts ? Icons.link : Icons.link_off,
              color: cascadeShifts ? AppColors.info : chrome.text,
            ),
            onPressed: onToggleCascadeShifts,
            tooltip: cascadeShifts
                ? 'Cascade on: shifting a task moves dependent tasks too'
                : 'Cascade off: shifting a task moves only that task',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        // Baseline + calendar export menu
        if (onSetBaseline != null || onExportIcal != null)
          _buildScheduleToolsMenu(context),
        // Collapse/Expand all toggle
        if (onCollapseAll != null || onExpandAll != null)
          IconButton(
            icon: Icon(
              isAllCollapsed ? Icons.unfold_more : Icons.unfold_less,
              color: chrome.text,
            ),
            onPressed: isAllCollapsed ? onExpandAll : onCollapseAll,
            tooltip: isAllCollapsed ? 'Expand All' : 'Collapse All',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        // Zoom controls
        if (onZoomOut != null)
          IconButton(
            icon: Icon(Icons.zoom_out,
                color: isAtMinZoom ? chrome.text.withValues(alpha: 0.35) : chrome.text),
            onPressed: isAtMinZoom ? null : onZoomOut,
            tooltip: 'Zoom Out',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        if (onZoomIn != null)
          IconButton(
            icon: Icon(Icons.zoom_in,
                color: isAtMaxZoom ? chrome.text.withValues(alpha: 0.35) : chrome.text),
            onPressed: isAtMaxZoom ? null : onZoomIn,
            tooltip: 'Zoom In',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        // Mass-edit selection bar
        if (onMassEdit != null && selectedCount > 0) ...[
          const SizedBox(width: 8),
          _buildSelectionBar(context),
        ],
        // Add task / group
        if (onAddTask != null || onAddGroup != null) ...[
          const SizedBox(width: 8),
          ..._buildAddActions(context),
        ],
      ],
    );
  }

  Widget _buildScheduleToolsMenu(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.history,
        color: showBaseline ? AppColors.info : chrome.text,
      ),
      tooltip: 'Baseline & calendar export',
      onSelected: (value) {
        switch (value) {
          case 'set_baseline':
            onSetBaseline?.call();
            break;
          case 'toggle_baseline':
            onToggleShowBaseline?.call();
            break;
          case 'export_ical':
            onExportIcal?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onSetBaseline != null)
          PopupMenuItem(
            value: 'set_baseline',
            child: Row(
              children: [
                const Icon(Icons.flag_circle_outlined, size: 18),
                const SizedBox(width: 8),
                Text(hasBaseline ? 'Re-capture Baseline' : 'Set Baseline'),
              ],
            ),
          ),
        if (onToggleShowBaseline != null)
          PopupMenuItem(
            value: 'toggle_baseline',
            enabled: hasBaseline,
            child: Row(
              children: [
                Icon(
                  showBaseline ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(showBaseline ? 'Hide Baseline' : 'Show Baseline'),
              ],
            ),
          ),
        if (onExportIcal != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'export_ical',
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 18),
                SizedBox(width: 8),
                Text('Export to Calendar (.ics)'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildViewSelector(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          borderRadius: AppRadius.cardRadius,
          value: currentView,
          isDense: true,
          dropdownColor: chrome.surface,
          style: TextStyle(fontSize: 14, color: chrome.textActive),
          icon: Icon(Icons.arrow_drop_down, color: chrome.text),
          items: const [
            DropdownMenuItem(value: 'Day', child: Text('Day')),
            DropdownMenuItem(value: 'Week', child: Text('Week')),
            DropdownMenuItem(value: 'Month', child: Text('Month')),
            DropdownMenuItem(value: 'Quarter', child: Text('Quarter')),
            DropdownMenuItem(value: 'Year', child: Text('Year')),
          ],
          onChanged: (value) {
            if (value != null) onViewChanged(value);
          },
        ),
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.secondaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onMassEdit,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryDark,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAddActions(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return [
      if (onAddGroup != null)
        TextButton.icon(
          onPressed: onAddGroup,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('Add Phase'),
          style: TextButton.styleFrom(
            foregroundColor: chrome.isDark ? AppColors.secondaryLight : AppColors.secondary,
          ),
        ),
      if (onAddTask != null)
        TextButton.icon(
          onPressed: onAddTask,
          icon: const Icon(Icons.add_task, size: 18),
          label: const Text('Add Task'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
    ];
  }
}
