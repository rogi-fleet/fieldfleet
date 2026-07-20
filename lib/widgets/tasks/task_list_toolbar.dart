import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../common/view_icon_button.dart';
import '../table/table_controls_bar.dart';
import '../table/table_dropdown_control.dart';
import '../table/table_search_field.dart';

/// Grouping mode for the task list.
enum GroupBy { phase, status, priority, assignee, property, none }

/// Toolbar with group-by selector, search, and filters.
///
/// Uses [TableControlsBar] for its visual chrome so all list/table views
/// share the same surface background and border-bottom appearance.
class TaskListToolbar extends StatefulWidget {
  static const double controlHeight = 42;

  final GroupBy groupBy;
  final String searchQuery;
  final bool showMyTasks;
  final bool hideMyTasksFilter;
  final bool allExpanded;
  final bool hideSearch;
  final ValueChanged<GroupBy> onGroupByChanged;

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onMyTasksToggled;
  final VoidCallback onToggleAllExpanded;
  final VoidCallback? onAddGroup;

  final int selectedCount;
  final VoidCallback? onMassEdit;
  final VoidCallback? onMassDelete;
  final VoidCallback? onClearSelection;
  final Widget? trailingControl;
  final bool fitToScreen;
  final VoidCallback? onFitToScreenToggle;
  final Set<String> hiddenColumnIds;
  final List<({String id, String label})> toggleableColumns;
  final ValueChanged<String>? onToggleColumn;
  final VoidCallback? onExport;
  final bool hideDone;
  final bool hideHideDoneFilter;
  final ValueChanged<bool> onHideDoneToggled;
  final bool hideExpandCollapse;
  final bool showBottomBorder;

  const TaskListToolbar({
    super.key,
    required this.groupBy,
    required this.searchQuery,
    required this.showMyTasks,
    this.hideMyTasksFilter = false,
    required this.allExpanded,
    required this.onGroupByChanged,
    required this.onSearchChanged,
    required this.onMyTasksToggled,
    required this.onToggleAllExpanded,
    this.hideSearch = false,
    this.onAddGroup,
    this.selectedCount = 0,
    this.onMassEdit,
    this.onMassDelete,
    this.onClearSelection,
    this.trailingControl,
    this.fitToScreen = true,
    this.onFitToScreenToggle,
    this.hiddenColumnIds = const {},
    this.toggleableColumns = const [],
    this.onToggleColumn,
    this.onExport,
    this.hideDone = true,
    this.hideHideDoneFilter = false,
    required this.onHideDoneToggled,
    this.hideExpandCollapse = false,
    this.showBottomBorder = true,
  });

  @override
  State<TaskListToolbar> createState() => _TaskListToolbarState();
}

class _TaskListToolbarState extends State<TaskListToolbar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant TaskListToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return TableControlsBar(
      showBottomBorder: widget.showBottomBorder,
      padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
      children: [
        // Group by dropdown
        _buildGroupByDropdown(context),
        // Search field
        if (!widget.hideSearch)
          Expanded(
            child: TableSearchField(
              controller: _searchController,
              onChanged: widget.onSearchChanged,
              hintText: 'Search tasks...',
              height: TaskListToolbar.controlHeight,
            ),
          ),
        // My tasks filter
        if (!widget.hideMyTasksFilter)
          ChoiceChip(
            label: Text(
              widget.showMyTasks ? 'My Tasks' : 'All Tasks',
              style: TextStyle(
                fontSize: 12,
                color: widget.showMyTasks ? AppColors.secondary : chrome.text,
              ),
            ),
            selected: widget.showMyTasks,
            onSelected: widget.onMyTasksToggled,
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            backgroundColor: Colors.transparent,
            selectedColor: Colors.transparent,
            side: BorderSide.none,
            avatar: Icon(
              widget.showMyTasks ? Icons.assignment_ind : Icons.assignment,
              size: 18,
              color: widget.showMyTasks ? AppColors.secondary : chrome.text,
            ),
          ),
        // Hide done filter
        if (!widget.hideHideDoneFilter)
          IconButton(
            icon: Icon(
              widget.hideDone ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: widget.hideDone ? AppColors.secondary : chrome.text,
            ),
            onPressed: () => widget.onHideDoneToggled(!widget.hideDone),
            tooltip: widget.hideDone
                ? 'Done tasks hidden'
                : 'Showing done tasks',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        // Bulk action bar
        if (widget.selectedCount > 0) _buildSelectionBar(context),
        if (widget.trailingControl != null) widget.trailingControl!,
        // Utility controls
        // Column visibility toggle
        if (widget.toggleableColumns.isNotEmpty &&
            widget.onToggleColumn != null)
          _buildColumnToggle(context),
        // Fit / scroll toggle
        if (widget.onFitToScreenToggle != null)
          IconButton(
            icon: Icon(
              widget.fitToScreen ? Icons.open_in_full : Icons.close_fullscreen,
              size: 18,
              color: widget.fitToScreen ? chrome.text : AppColors.secondary,
            ),
            onPressed: widget.onFitToScreenToggle,
            tooltip: widget.fitToScreen
                ? 'Expand table (scrollable)'
                : 'Fit to screen',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        // Expand/Collapse all
        if (!widget.hideExpandCollapse)
          ViewIconButton(
            icon: widget.allExpanded ? Icons.unfold_less : Icons.unfold_more,
            tooltip: widget.allExpanded ? 'Collapse all' : 'Expand all',
            isSelected: false,
            onTap: widget.onToggleAllExpanded,
          ),
        // Export
        if (widget.onExport != null)
          IconButton(
            icon: Icon(Icons.download, size: 18, color: chrome.text),
            onPressed: widget.onExport,
            tooltip: 'Export to CSV',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.selectedCount} selected',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 26,
            child: FilledButton.icon(
              onPressed: widget.onMassEdit,
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (widget.onMassDelete != null) ...[
            const SizedBox(width: 4),
            SizedBox(
              height: 26,
              child: FilledButton.icon(
                onPressed: widget.onMassDelete,
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('Delete', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(
            width: 26,
            height: 26,
            child: IconButton(
              onPressed: widget.onClearSelection,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear selection',
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnToggle(BuildContext context) {
    final chrome = ChromeColors.of(context);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.view_column_outlined,
        size: 18,
        color: widget.hiddenColumnIds.isEmpty
            ? chrome.text
            : AppColors.secondary,
      ),
      tooltip: 'Toggle columns',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => widget.toggleableColumns.map((col) {
        final isVisible = !widget.hiddenColumnIds.contains(col.id);
        return PopupMenuItem<String>(
          value: col.id,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVisible ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: isVisible ? AppColors.secondary : AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                col.label,
                style: TextStyle(
                  fontSize: 13,
                  color: isVisible
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: widget.onToggleColumn,
    );
  }

  Widget _buildGroupByDropdown(BuildContext context) {
    return TableDropdownControl<GroupBy>(
      value: widget.groupBy,
      width: 200,
      height: TaskListToolbar.controlHeight,
      items: const [
        DropdownMenuItem(value: GroupBy.phase, child: Text('Group by Phase')),
        DropdownMenuItem(value: GroupBy.status, child: Text('Group by Status')),
        DropdownMenuItem(
          value: GroupBy.priority,
          child: Text('Group by Priority'),
        ),
        DropdownMenuItem(
          value: GroupBy.assignee,
          child: Text('Group by Assignee'),
        ),
        DropdownMenuItem(
          value: GroupBy.property,
          child: Text('Group by Property'),
        ),
        DropdownMenuItem(value: GroupBy.none, child: Text('No Grouping')),
      ],
      onChanged: (value) {
        if (value != null) widget.onGroupByChanged(value);
      },
    );
  }
}
