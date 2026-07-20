import 'package:flutter/material.dart';
import '../../models/budget_item.dart';
import '../../screens/projects/budget_view_screen.dart'; // for BudgetViewMode
import '../../theme/theme.dart';
import '../../utils/budget_tab_metrics.dart';
import '../../utils/hierarchy_flatten.dart';
import '../../widgets/budget/budget_holdback_view.dart';
import '../../widgets/budget/budget_profit_view.dart';
import '../../widgets/common/item_card.dart';
import '../../widgets/common/metric_chip.dart';
import '../../widgets/table/table_add_item_group_row.dart';

class BudgetMobileView extends StatelessWidget {
  // Core data
  final List<BudgetItem> displayedItems;
  final String workspaceId;
  final BudgetViewMode viewMode;
  final String Function(double) formatCurrency;

  // Hierarchy state (read-only)
  final Set<String> expandedItems;
  final Set<String> selectedItemIds;
  final Map<String, List<BudgetItem>> childrenByParentId;
  final Map<String, List<BudgetItem>> leafDescendantsByItemId;
  final Map<String, String> hierarchicalItemIds;

  // Metadata (read-only)
  final Map<String, double> actualCosts;
  final Map<String, double> invoicedAmounts;
  final Map<String, String> changeOrderStatuses;

  // Search & sort
  final String searchQuery;
  final Comparator<BudgetItem>? sortComparator;

  // Adding state
  final String? addingToParentId;
  final int? addingHierarchyLevel;

  // Shared widget slots (pre-built by parent)
  final Widget controlsBar;

  // Specialized view data (pre-computed by parent for profit/holdback)
  final ProfitBreakdown? profitBreakdown;
  final HoldbackBreakdown? holdbackBreakdown;

  // Callbacks — item actions
  final void Function(String itemId) onToggleExpansion;
  final void Function(BudgetItem item, bool selected) onSelectionChanged;
  final void Function(BudgetItem item) onEdit;
  final Future<void> Function(BudgetItem item) onDelete;
  final Future<void> Function(BudgetItem item) onDuplicate;
  final Future<void> Function(BudgetItem item) onGroup;
  final Future<void> Function(BudgetItem item) onUngroup;
  final void Function(String? parentId, int level, {required bool isGroup}) onAdd;
  final Future<void> Function(BudgetItem item) onSaveAsTemplate;
  final Future<void> Function(BudgetItem item, int direction) onMove;
  final void Function(BudgetItem item)? onItemChanged;
  final ValueChanged<String> onSearchChanged;

  // Inline add row builder
  final Widget Function({
    required String workspaceId,
    required String? parentId,
    required int hierarchyLevel,
    required int indentLevel,
  }) buildInlineAddRow;

  // Subtree check (shared logic from parent)
  final bool Function(List<HierarchyFlatEntry<BudgetItem>> entries,
      {required int rowIndex,
      required String parentId}) isLastVisibleRowInParentSubtree;

  // Search visibility filter
  final bool Function(BudgetItem item) isItemVisibleInSearch;

  // Pre-built workflow widget (null when not in workflow mode or still loading)
  final Widget? workflowContent;

  final Widget? selectionsContent;

  // Pre-built purchase-orders list widget (null when not in purchaseOrders mode)
  final Widget? purchaseOrdersContent;

  final bool hasApprovedEstimate;

  // Empty state content
  final ({IconData icon, String title, String subtitle, String ctaLabel})
      emptyStateContent;

  const BudgetMobileView({
    super.key,
    required this.displayedItems,
    required this.workspaceId,
    required this.viewMode,
    required this.formatCurrency,
    required this.expandedItems,
    required this.selectedItemIds,
    required this.childrenByParentId,
    required this.leafDescendantsByItemId,
    required this.hierarchicalItemIds,
    required this.actualCosts,
    required this.invoicedAmounts,
    required this.changeOrderStatuses,
    required this.searchQuery,
    required this.sortComparator,
    required this.addingToParentId,
    required this.addingHierarchyLevel,
    required this.controlsBar,
    required this.profitBreakdown,
    required this.holdbackBreakdown,
    required this.onToggleExpansion,
    required this.onSelectionChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onGroup,
    required this.onUngroup,
    required this.onAdd,
    required this.onSaveAsTemplate,
    required this.onMove,
    this.onItemChanged,
    required this.onSearchChanged,
    required this.buildInlineAddRow,
    required this.isLastVisibleRowInParentSubtree,
    required this.isItemVisibleInSearch,
    this.workflowContent,
    this.selectionsContent,
    this.purchaseOrdersContent,
    this.hasApprovedEstimate = false,
    required this.emptyStateContent,
  });

  @override
  Widget build(BuildContext context) {
    final entries = flattenHierarchy<BudgetItem>(
      items: displayedItems,
      idOf: (item) => item.id,
      parentIdOf: (item) => item.parentId,
      isExpandedOf: (item) => expandedItems.contains(item.id),
      sortSiblings:
          sortComparator ?? (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );
    final visibleEntries = entries
        .where((entry) => isItemVisibleInSearch(entry.item))
        .toList(growable: false);

    final rows = <Widget>[
      controlsBar,
      if (viewMode == BudgetViewMode.workflow && workflowContent != null)
        workflowContent!,
      if (viewMode == BudgetViewMode.profit)
        BudgetProfitView(
          breakdown: profitBreakdown!,
          formatCurrency: formatCurrency,
        ),
      if (viewMode == BudgetViewMode.holdback)
        BudgetHoldbackView(
          breakdown: holdbackBreakdown!,
          formatCurrency: formatCurrency,
        ),
      // Purchase orders render as shrink-wrapped cards (cardLayout: true), so
      // they scroll with the outer ListView like the budget item cards do —
      // no fixed-height embed.
      if (viewMode == BudgetViewMode.purchaseOrders &&
          purchaseOrdersContent != null)
        purchaseOrdersContent!,
      if (viewMode == BudgetViewMode.selections && selectionsContent != null)
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: selectionsContent!,
        ),
    ];

    // Specialized views show their own content instead of item cards
    final showItemCards = viewMode != BudgetViewMode.profit &&
        viewMode != BudgetViewMode.holdback &&
        viewMode != BudgetViewMode.workflow &&
        viewMode != BudgetViewMode.purchaseOrders &&
        viewMode != BudgetViewMode.selections;

    if (showItemCards &&
        addingToParentId == null &&
        addingHierarchyLevel == 0) {
      rows.add(
        buildInlineAddRow(
          workspaceId: workspaceId,
          parentId: null,
          hierarchyLevel: 0,
          indentLevel: 0,
        ),
      );
    }

    if (!showItemCards) {
      // Specialized view already added above — no item cards needed
    } else if (displayedItems.isEmpty && addingHierarchyLevel == null) {
      rows.add(_buildMobileBudgetEmptyState(context));
    } else if (visibleEntries.isEmpty) {
      rows.add(_buildMobileNoResultsState());
    } else {
      for (var i = 0; i < visibleEntries.length; i++) {
        final entry = visibleEntries[i];
        rows.add(_buildMobileBudgetCard(context, entry));

        if (addingToParentId != null &&
            addingHierarchyLevel != null &&
            isLastVisibleRowInParentSubtree(
              visibleEntries,
              rowIndex: i,
              parentId: addingToParentId!,
            )) {
          rows.add(
            buildInlineAddRow(
              workspaceId: entry.item.workspaceId,
              parentId: addingToParentId!,
              hierarchyLevel: addingHierarchyLevel!,
              indentLevel: (entry.depth + 1).clamp(0, 4),
            ),
          );
        }
      }
    }

    if (showItemCards &&
        (displayedItems.isNotEmpty || addingHierarchyLevel != null)) {
      rows.add(
        TableAddItemGroupRow(
          onAddItem: () => onAdd(null, 0, isGroup: false),
          onAddGroup: () => onAdd(null, 0, isGroup: true),
        ),
      );
    }

    final navBarBottomPadding = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(top: 8, bottom: 16 + navBarBottomPadding),
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBudgetCard(
      BuildContext context, HierarchyFlatEntry<BudgetItem> entry) {
    final item = entry.item;
    final isGroup = item.itemType == BudgetItemType.group;
    final isExpanded = expandedItems.contains(item.id);
    final siblings =
        childrenByParentId[item.parentId ?? ''] ?? const <BudgetItem>[];
    final siblingIndex = siblings.indexWhere(
      (sibling) => sibling.id == item.id,
    );
    final canMoveUp = siblingIndex > 0;
    final canMoveDown = siblingIndex >= 0 && siblingIndex < siblings.length - 1;
    final childCount =
        (childrenByParentId[item.id] ?? const <BudgetItem>[]).length;
    final descendantLeafCount =
        (leafDescendantsByItemId[item.id] ?? const <BudgetItem>[]).length;
    final indent = (entry.depth * 16.0).clamp(0.0, 64.0);
    final cardColor = isGroup ? AppColors.background : Colors.white;
    final metrics = _buildMobileMetrics(context, item);

    return ItemCard(
      color: cardColor,
      indent: indent,
      onTap: isGroup
          ? childCount == 0
                ? null
                : () => onToggleExpansion(item.id)
          : () => onEdit(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selectedItemIds.contains(item.id),
                onChanged: (checked) => onSelectionChanged(
                  item,
                  checked ?? false,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              if (isGroup)
                IconButton(
                  onPressed: childCount == 0
                      ? null
                      : () => onToggleExpansion(item.id),
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: isExpanded ? 'Collapse' : 'Expand',
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item.isAllowance) ...[
                          _buildAllowanceChip(),
                          const SizedBox(width: 6),
                        ],
                        _buildMobileTypeChip(item, descendantLeafCount),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hierarchicalItemIds[item.id] ?? 'Unnumbered',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if ((item.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (value) async {
                  switch (value) {
                    case 'move_up':
                      await onMove(item, -1);
                      break;
                    case 'move_down':
                      await onMove(item, 1);
                      break;
                    case 'edit':
                      onEdit(item);
                      break;
                    case 'duplicate':
                      await onDuplicate(item);
                      break;
                    case 'group':
                      await onGroup(item);
                      break;
                    case 'save_template':
                      await onSaveAsTemplate(item);
                      break;
                    case 'ungroup':
                      await onUngroup(item);
                      break;
                    case 'add_item':
                      onAdd(
                        item.id,
                        item.hierarchyLevel + 1,
                        isGroup: false,
                      );
                      break;
                    case 'add_group':
                      onAdd(
                        item.id,
                        item.hierarchyLevel + 1,
                        isGroup: true,
                      );
                      break;
                    case 'upgrade_accept':
                      onItemChanged?.call(
                        item.copyWith(
                          upgradeStatus: UpgradeStatus.accepted,
                          updatedAt: DateTime.now(),
                        ),
                      );
                      break;
                    case 'upgrade_decline':
                      onItemChanged?.call(
                        item.copyWith(
                          upgradeStatus: UpgradeStatus.declined,
                          updatedAt: DateTime.now(),
                        ),
                      );
                      break;
                    case 'upgrade_reset':
                      onItemChanged?.call(
                        item.copyWith(
                          upgradeStatus: UpgradeStatus.offered,
                          updatedAt: DateTime.now(),
                        ),
                      );
                      break;
                    case 'delete':
                      await onDelete(item);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'move_up',
                    enabled: canMoveUp,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.arrow_upward,
                        color: canMoveUp ? null : AppColors.textTertiary,
                      ),
                      title: Text(
                        'Move up',
                        style: canMoveUp
                            ? null
                            : TextStyle(color: AppColors.textTertiary),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'move_down',
                    enabled: canMoveDown,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.arrow_downward,
                        color: canMoveDown
                            ? null
                            : AppColors.textTertiary,
                      ),
                      title: Text(
                        'Move down',
                        style: canMoveDown
                            ? null
                            : TextStyle(color: AppColors.textTertiary),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.copy_outlined),
                      title: Text('Duplicate'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (!isGroup)
                    const PopupMenuItem(
                      value: 'group',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.folder_outlined),
                        title: Text('Group'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (isGroup)
                    const PopupMenuItem(
                      value: 'ungroup',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.format_indent_decrease),
                        title: Text('Ungroup'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'save_template',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.save_outlined),
                      title: Text('Save as Template'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (isGroup) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'add_item',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.add),
                        title: Text('Add Item'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_group',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.create_new_folder_outlined),
                        title: Text('Add Group'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (item.sourceType == BudgetItemSource.upgrade &&
                      !isGroup &&
                      onItemChanged != null) ...[
                    const PopupMenuDivider(),
                    if (item.upgradeStatus != UpgradeStatus.accepted)
                      const PopupMenuItem(
                        value: 'upgrade_accept',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.check_circle_outline),
                          title: Text('Mark as Accepted'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (item.upgradeStatus != UpgradeStatus.declined)
                      const PopupMenuItem(
                        value: 'upgrade_decline',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.cancel_outlined),
                          title: Text('Mark as Declined'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (item.upgradeStatus != UpgradeStatus.offered)
                      const PopupMenuItem(
                        value: 'upgrade_reset',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.undo),
                          title: Text('Reset to Offered'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.delete_outline,
                        color: AppColors.error,
                      ),
                      title: Text(
                        'Delete',
                        style: TextStyle(color: AppColors.error),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Primary metrics in equal-width row
          if (metrics.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < metrics.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _buildMobileMetricChip(metrics[i])),
                ],
                if (!isGroup &&
                    item.quantity > 0 &&
                    item.unit != null &&
                    item.unit!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMobileMetricChip(
                      _MobileBudgetMetric(
                        label: 'Quantity',
                        value:
                            '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}'
                                .trim(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAllowanceChip() {
    const color = AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: const Text(
        'Allowance',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMobileTypeChip(BudgetItem item, int descendantLeafCount) {
    final isGroup = item.itemType == BudgetItemType.group;
    final color = isGroup ? AppColors.warningDark : AppColors.infoDark;
    final background = color.withValues(alpha: 0.12);
    final label = isGroup
        ? descendantLeafCount > 0
              ? '$descendantLeafCount items'
              : 'Group'
        : item.isComplete
        ? 'Complete'
        : 'Item';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<_MobileBudgetMetric> _buildMobileMetrics(
      BuildContext context, BudgetItem item) {
    final sourceItems = item.itemType == BudgetItemType.group
        ? (leafDescendantsByItemId[item.id] ?? const <BudgetItem>[])
        : <BudgetItem>[item];

    if (sourceItems.isEmpty) {
      return const [];
    }

    double sumBy(double Function(BudgetItem item) selector) =>
        sourceItems.fold(0.0, (sum, item) => sum + selector(item));
    double sumMap(Map<String, double> values) =>
        sourceItems.fold(0.0, (sum, item) => sum + (values[item.id] ?? 0.0));

    final estimateLabel = hasApprovedEstimate ? 'Approved' : 'Estimated';

    switch (viewMode) {
      case BudgetViewMode.workflow:
        return const []; // Workflow uses its own canvas
      case BudgetViewMode.estimating:
        final approved = sumBy((i) => i.approvedPrice);
        final profit = sumBy((i) => i.projectedProfit);
        final margin = approved > 0 ? (profit / approved) * 100 : 0.0;
        return [
          _MobileBudgetMetric(
            label: estimateLabel,
            value: formatCurrency(approved),
            color: Theme.of(context).colorScheme.primary,
          ),
          _MobileBudgetMetric(
            label: 'Profit',
            value: formatCurrency(profit),
            color: profit >= 0 ? AppColors.success : AppColors.error,
          ),
          _MobileBudgetMetric(
            label: 'Margin',
            value: '${margin.toStringAsFixed(0)}%',
          ),
        ];
      case BudgetViewMode.costing:
        final projected = sumBy((i) => i.projectedCost);
        final actual = sumMap(actualCosts);
        final variance = projected - actual;
        return [
          _MobileBudgetMetric(
            label: 'Projected',
            value: formatCurrency(projected),
          ),
          _MobileBudgetMetric(label: 'Actual', value: formatCurrency(actual)),
          _MobileBudgetMetric(
            label: 'Variance',
            value: formatCurrency(variance),
            color: variance >= 0 ? AppColors.success : AppColors.error,
          ),
        ];
      case BudgetViewMode.invoicing:
        final approved = sumBy((i) => i.approvedPrice);
        final invoiced = sumMap(invoicedAmounts);
        return [
          _MobileBudgetMetric(
            label: estimateLabel,
            value: formatCurrency(approved),
          ),
          _MobileBudgetMetric(
            label: 'Invoiced',
            value: formatCurrency(invoiced),
          ),
          _MobileBudgetMetric(
            label: 'Remaining',
            value: formatCurrency(approved - invoiced),
            color: AppColors.warningDark,
          ),
        ];
      case BudgetViewMode.profit:
        final approved = sumBy((i) => i.approvedPrice);
        final actual = sumMap(actualCosts);
        final profit = approved - actual;
        return [
          _MobileBudgetMetric(
            label: estimateLabel,
            value: formatCurrency(approved),
          ),
          _MobileBudgetMetric(label: 'Actual', value: formatCurrency(actual)),
          _MobileBudgetMetric(
            label: 'Profit',
            value: formatCurrency(profit),
            color: profit >= 0 ? AppColors.success : AppColors.error,
          ),
        ];
      case BudgetViewMode.changeOrders:
        final approved = sumBy((i) => i.approvedPrice);
        final cost = sumBy((i) => i.projectedCost);
        return [
          _MobileBudgetMetric(
            label: 'Revenue',
            value: formatCurrency(approved),
          ),
          _MobileBudgetMetric(label: 'Cost', value: formatCurrency(cost)),
          _MobileBudgetMetric(
            label: 'Net',
            value: formatCurrency(approved - cost),
            color: approved - cost >= 0 ? AppColors.success : AppColors.error,
          ),
        ];
      case BudgetViewMode.upgrades:
        final approved = sumBy((i) => i.approvedPrice);
        final cost = sumBy((i) => i.projectedCost);
        final statuses = sourceItems
            .map((i) => i.upgradeStatus?.name)
            .whereType<String>()
            .toSet();
        return [
          _MobileBudgetMetric(label: 'Price', value: formatCurrency(approved)),
          _MobileBudgetMetric(label: 'Cost', value: formatCurrency(cost)),
          _MobileBudgetMetric(
            label: 'Status',
            value: statuses.isEmpty ? 'Offered' : statuses.join(', '),
          ),
        ];
      case BudgetViewMode.purchaseOrders:
      case BudgetViewMode.selections:
        return const [];
      case BudgetViewMode.holdback:
        final approved = sumBy((i) => i.approvedPrice);
        final holdback = sumBy((i) => i.holdbackAmount);
        final collectible = sumBy((i) => i.collectibleAmount);
        return [
          _MobileBudgetMetric(
            label: estimateLabel,
            value: formatCurrency(approved),
          ),
          _MobileBudgetMetric(
            label: 'Holdback',
            value: formatCurrency(holdback),
            color: AppColors.warningDark,
          ),
          _MobileBudgetMetric(
            label: 'Collectible',
            value: formatCurrency(collectible),
            color: AppColors.successDark,
          ),
        ];
    }
  }

  Widget _buildMobileMetricChip(_MobileBudgetMetric metric) {
    return MetricChip(
      label: metric.label,
      value: metric.value,
      color: metric.color,
    );
  }

  Widget _buildMobileBudgetEmptyState(BuildContext context) {
    final content = emptyStateContent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      child: Column(
        children: [
          Icon(content.icon, size: 52, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            content.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            content.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => onAdd(null, 0, isGroup: false),
            icon: const Icon(Icons.add),
            label: Text(content.ctaLabel),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => onAdd(null, 0, isGroup: true),
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text('Add Group'),
          ),
          const SizedBox(height: 4),
          Text(
            'Use ${content.ctaLabel} or Add Group to get started',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNoResultsState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 44, color: AppColors.textTertiary),
          const SizedBox(height: 10),
          const Text(
            'No budget items match your search',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => onSearchChanged(''),
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }
}

class _MobileBudgetMetric {
  final String label;
  final String value;
  final Color? color;

  const _MobileBudgetMetric({
    required this.label,
    required this.value,
    this.color,
  });
}
