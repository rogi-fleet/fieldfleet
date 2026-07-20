import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/document_line_item.dart';
import '../models/document_type.dart';
import '../models/budget_item.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../utils/currency_utils.dart';
import '../utils/project_terminology.dart';
import '../theme/theme.dart';
import '../utils/text_selection_utils.dart';

/// A widget for editing document line items with hierarchical display,
/// visibility controls, and budget item import.
class DocumentLineItemEditor extends StatefulWidget {
  final String? projectId;
  final String? workspaceId;
  final List<DocumentLineItem> initialItems;
  final LineItemVisibility initialVisibility;
  final DocumentType? documentType;
  final Function(
    List<DocumentLineItem> items,
    LineItemVisibility visibility,
    double total,
  )
  onChanged;

  const DocumentLineItemEditor({
    super.key,
    this.projectId,
    this.workspaceId,
    this.initialItems = const [],
    this.initialVisibility = LineItemVisibility.all,
    this.documentType,
    required this.onChanged,
  });

  @override
  State<DocumentLineItemEditor> createState() => _DocumentLineItemEditorState();
}

class _DocumentLineItemEditorState extends State<DocumentLineItemEditor> {
  final _uuid = const Uuid();

  List<DocumentLineItem> _items = [];
  final Map<String, BudgetItem> _budgetById = {};

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String get _projectTerminologySingular => singularProjectTerminology(
        context.read<WorkspaceProvider>().projectTerminology,
      );
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);
  String get _currencySymbol => CurrencyUtils.getSymbol(_currencyCode);
  bool get _usesBudgetUnitCost =>
      widget.documentType?.usesBudgetUnitCostForLineItems ?? false;

  /// Change orders amend the existing approved scope of work — they may
  /// only reference budget items that have already been approved /
  /// contracted (`approvedAt IS NOT NULL`). When this is true the editor
  /// hides the "Add item / group" toolbar buttons, filters the budget
  /// import picker to approved items, and `create_document_screen`
  /// refuses to save the document unless every line item carries a
  /// `budgetItemId`. Without this guard a CO can introduce brand-new
  /// scope that was never in the contract, which silently inflates the
  /// budget summary and breaks the contract-vs-CO audit trail.
  bool get _isChangeOrder =>
      widget.documentType == DocumentType.changeOrder;

  LineItemVisibility _visibility = LineItemVisibility.all;
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    _visibility = widget.initialVisibility;
    // Expand all groups by default
    for (final item in _items.where((i) => i.isGroup)) {
      _expandedGroups[item.id] = true;
    }
    _loadBudgetReferenceItems();
  }

  void _notifyChange() {
    final total = _calculateTotal();
    widget.onChanged(_items, _visibility, total);
  }

  double _calculateTotal() {
    return _items
        .where((item) => item.isItem && item.isVisible)
        .fold(0.0, (sum, item) => sum + item.total);
  }

  List<DocumentLineItem> get _topLevelItems {
    final items = _items.where((i) => i.parentId == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return items;
  }

  @override
  void didUpdateWidget(DocumentLineItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialItems != oldWidget.initialItems) {
      setState(() {
        _items = List.from(widget.initialItems);
      });
    }
    if (widget.initialVisibility != oldWidget.initialVisibility) {
      setState(() {
        _visibility = widget.initialVisibility;
      });
    }
    if (widget.projectId != oldWidget.projectId ||
        widget.workspaceId != oldWidget.workspaceId) {
      _loadBudgetReferenceItems();
    }
  }

  Future<void> _loadBudgetReferenceItems() async {
    if (widget.projectId == null || widget.workspaceId == null) return;
    try {
      final budgetService = ServiceLocator.budgetService;
      final items =
          await budgetService
                  .getBudgetItems(
                    widget.projectId!,
                    workspaceId: widget.workspaceId!,
                  )
                  .first
              as List<BudgetItem>;
      if (!mounted) return;
      setState(() {
        _budgetById
          ..clear()
          ..addEntries(items.map((item) => MapEntry(item.id, item)));
      });
    } catch (_) {
      // Non-blocking: editor still works without budget reference map.
    }
  }

  List<DocumentLineItem> _getChildren(String parentId) {
    return _items.where((i) => i.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  void _addGroup() {
    final newGroup = DocumentLineItem(
      id: _uuid.v4(),
      type: DocumentLineItemType.group,
      sortOrder: _topLevelItems.length,
      name: 'New Group',
    );
    setState(() {
      _items.add(newGroup);
      _expandedGroups[newGroup.id] = true;
    });
    _notifyChange();
  }

  void _addItem({String? parentId}) {
    final siblings = parentId == null ? _topLevelItems : _getChildren(parentId);

    final newItem = DocumentLineItem(
      id: _uuid.v4(),
      type: DocumentLineItemType.item,
      parentId: parentId,
      sortOrder: siblings.length,
      name: 'New Item',
      quantity: 1.0,
      unitPrice: 0.0,
    );
    setState(() {
      _items.add(newItem);
    });
    _notifyChange();
  }

  void _deleteItem(String itemId) {
    setState(() {
      // Recursively collect all descendant IDs
      final toRemove = <String>{itemId};
      var added = true;
      while (added) {
        added = false;
        for (final item in _items) {
          if (item.parentId != null &&
              toRemove.contains(item.parentId) &&
              !toRemove.contains(item.id)) {
            toRemove.add(item.id);
            added = true;
          }
        }
      }
      _items.removeWhere((i) => toRemove.contains(i.id));
      for (final id in toRemove) {
        _expandedGroups.remove(id);
      }
    });
    _notifyChange();
  }

  void _updateItem(DocumentLineItem updated) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == updated.id);
      if (index != -1) {
        _items[index] = updated;
      }
    });
    _notifyChange();
  }

  bool _isCustomizedFromBudget(DocumentLineItem item) {
    final budgetId = item.budgetItemId;
    if (budgetId == null) return false;
    final budgetItem = _budgetById[budgetId];
    if (budgetItem == null) return false;
    final budgetUnitPrice = _documentUnitPriceFromBudget(budgetItem);

    return item.name != budgetItem.name ||
        (item.description ?? '') != (budgetItem.description ?? '') ||
        item.quantity != budgetItem.quantity ||
        (item.unit ?? '') != (budgetItem.unit ?? '') ||
        item.unitPrice != budgetUnitPrice;
  }

  double _documentUnitPriceFromBudget(BudgetItem budgetItem) {
    return _usesBudgetUnitCost ? budgetItem.unitCost : budgetItem.unitPrice;
  }

  void _resetToBudgetValues(DocumentLineItem item) {
    final budgetId = item.budgetItemId;
    if (budgetId == null) return;
    final budgetItem = _budgetById[budgetId];
    if (budgetItem == null) return;

    _updateItem(
      item.copyWith(
        name: budgetItem.name,
        description: budgetItem.description,
        quantity: budgetItem.quantity,
        unit: budgetItem.unit,
        unitPrice: _documentUnitPriceFromBudget(budgetItem),
        isTaxable: budgetItem.isTaxable,
        customizedFields: {},
      ),
    );
  }

  void _toggleVisibility(String itemId) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == itemId);
      if (index != -1) {
        _items[index] = _items[index].copyWith(
          isVisible: !_items[index].isVisible,
        );
      }
    });
    _notifyChange();
  }

  /// Toggle whether a line is taxed. Tax is charged only on taxable lines, so
  /// this changes the document's tax/total. [M002]
  void _toggleTaxable(String itemId) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == itemId);
      if (index != -1) {
        _items[index] = _items[index].copyWith(
          isTaxable: !_items[index].isTaxable,
        );
      }
    });
    _notifyChange();
  }

  Future<void> _importFromBudget() async {
    if (widget.projectId == null || widget.workspaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select a ${_projectTerminologySingular.toLowerCase()} first',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<List<BudgetItem>>(
      context: context,
      builder: (context) => _BudgetImportDialog(
        projectId: widget.projectId!,
        workspaceId: widget.workspaceId!,
        existingBudgetItemIds: _items
            .where((i) => i.budgetItemId != null)
            .map((i) => i.budgetItemId!)
            .toSet(),
        // Change orders may only amend items already in the approved
        // contract — surface only approved items in the picker.
        requireApproved: _isChangeOrder,
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        // Map budget item IDs to new document line item IDs to preserve hierarchy
        final budgetIdToLineItemId = <String, String>{};
        for (final budgetItem in result) {
          budgetIdToLineItemId[budgetItem.id] = _uuid.v4();
        }

        // Sort by hierarchy level then sort order so parents are added before children
        final sorted = List<BudgetItem>.from(result)
          ..sort((a, b) {
            if (a.hierarchyLevel != b.hierarchyLevel) {
              return a.hierarchyLevel.compareTo(b.hierarchyLevel);
            }
            return a.sortOrder.compareTo(b.sortOrder);
          });

        var nextTopSortOrder = _topLevelItems.length;
        // Track per-parent sort counters for children
        final childSortCounters = <String, int>{};

        for (final budgetItem in sorted) {
          // Resolve parentId: only set if the parent was also imported
          final mappedParentId = budgetItem.parentId != null
              ? budgetIdToLineItemId[budgetItem.parentId!]
              : null;

          final int sortOrder;
          if (mappedParentId == null) {
            sortOrder = nextTopSortOrder++;
          } else {
            sortOrder = childSortCounters[mappedParentId] ?? 0;
            childSortCounters[mappedParentId] = sortOrder + 1;
          }

          final newId = budgetIdToLineItemId[budgetItem.id]!;
          _items.add(
            DocumentLineItem(
              id: newId,
              budgetItemId: budgetItem.id,
              parentId: mappedParentId,
              type: budgetItem.itemType == BudgetItemType.group
                  ? DocumentLineItemType.group
                  : DocumentLineItemType.item,
              sortOrder: sortOrder,
              name: budgetItem.name,
              description: budgetItem.description,
              quantity: budgetItem.quantity,
              unit: budgetItem.unit,
              unitPrice: _documentUnitPriceFromBudget(budgetItem),
              isTaxable: budgetItem.isTaxable,
            ),
          );
          if (budgetItem.itemType == BudgetItemType.group) {
            _expandedGroups[newId] = true;
          }
        }
      });
      _notifyChange();
    }
  }

  void _reorderItems(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final topItems = _topLevelItems;
      final item = topItems.removeAt(oldIndex);
      topItems.insert(newIndex, item);

      // Update sort orders
      for (int i = 0; i < topItems.length; i++) {
        final index = _items.indexWhere((it) => it.id == topItems[i].id);
        if (index != -1) {
          _items[index] = _items[index].copyWith(sortOrder: i);
        }
      }
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = _calculateTotal();
    final isBidRequest =
        widget.documentType == DocumentType.requestForBid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBidRequest)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prices entered here are for your internal estimate and '
                    'are not sent to the vendor. The vendor will fill in '
                    'their bid prices per line.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Header with visibility dropdown and action buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Visibility dropdown in a styled container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: colorScheme.surface,
                ),
                child: DropdownButton<LineItemVisibility>(
                  value: _visibility,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  isDense: true,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  items: LineItemVisibility.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                v == LineItemVisibility.none
                                    ? Icons.visibility_off
                                    : v == LineItemVisibility.topLevel
                                    ? Icons.unfold_less
                                    : Icons.visibility,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                v.displayName,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _visibility = v);
                      _notifyChange();
                    }
                  },
                ),
              ),
              // Action buttons cluster
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: colorScheme.surface,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.projectId != null) ...[
                      _ToolbarButton(
                        onPressed: _importFromBudget,
                        icon: Icons.download_rounded,
                        label: 'Budget',
                        isPrimary: true,
                        colorScheme: colorScheme,
                      ),
                      if (!_isChangeOrder)
                        SizedBox(
                          height: 28,
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                    // Change orders amend the existing contract, so the
                    // "Group" and free-form "Item" actions are hidden —
                    // every line on a CO has to come from an existing
                    // approved budget item picked via Budget.
                    if (!_isChangeOrder) ...[
                      _ToolbarButton(
                        onPressed: _addGroup,
                        icon: Icons.create_new_folder_outlined,
                        label: 'Group',
                        colorScheme: colorScheme,
                      ),
                      SizedBox(
                        height: 28,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      _ToolbarButton(
                        onPressed: () => _addItem(),
                        icon: Icons.add,
                        label: 'Item',
                        colorScheme: colorScheme,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Line items list
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.list_alt_outlined,
                    size: 48,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No line items yet',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add items manually or import from the ${_projectTerminologySingular.toLowerCase()} budget',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: _topLevelItems.length,
              onReorder: _reorderItems,
              itemBuilder: (context, index) {
                final item = _topLevelItems[index];
                return _buildItemTile(item, index, 0);
              },
            ),
          ),

        // Footer with total
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_items.where((i) => i.isItem && i.isVisible).length} items',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              if (!isBidRequest)
                Row(
                  children: [
                    const Text(
                      'Total: ',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatCurrency(total),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Internal estimate: ${_formatCurrency(total)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemTile(DocumentLineItem item, int index, int depth) {
    if (depth > 20) {
      debugPrint(
        'WARNING: Potential infinite recursion in _buildItemTile at depth $depth for item ${item.id}',
      );
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final isGroup = item.isGroup;
    final isExpanded = _expandedGroups[item.id] ?? false;
    final children = _getChildren(item.id);
    final leftPadding = 16.0 + (depth * 24.0);
    final isNarrow = MediaQuery.of(context).size.width < 480;
    final isCustomized = _isCustomizedFromBudget(item);
    final budgetReference = item.budgetItemId != null
        ? _budgetById[item.budgetItemId!]
        : null;

    return Column(
      key: ValueKey(item.id),
      children: [
        Container(
          decoration: BoxDecoration(
            color: !item.isVisible
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : null,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: leftPadding,
              right: 8,
              top: 8,
              bottom: 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (depth == 0)
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 20),
                    const SizedBox(width: 4),
                    if (isGroup)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedGroups[item.id] = !isExpanded;
                          });
                        },
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 20),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _toggleVisibility(item.id),
                      child: Icon(
                        item.isVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 18,
                        color: item.isVisible
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                      ),
                    ),
                    if (!isGroup) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _toggleTaxable(item.id),
                        child: Tooltip(
                          message: item.isTaxable
                              ? 'Taxable — tap to exempt'
                              : 'Non-taxable — tap to tax',
                          child: Icon(
                            item.isTaxable ? Icons.percent : Icons.money_off,
                            size: 16,
                            color: item.isTaxable
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _EditableText(
                        value: item.name,
                        style: TextStyle(
                          fontWeight: isGroup
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: !item.isVisible
                              ? colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                )
                              : null,
                        ),
                        onChanged: (value) => _updateItem(
                          item.copyWith(
                            name: value,
                            customizedFields: item.budgetItemId != null
                                ? {...item.customizedFields, 'name'}
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (!isGroup) ...[
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 48,
                        child: _EditableNumber(
                          value: item.quantity,
                          suffix: item.unit,
                          onChanged: (value) => _updateItem(
                            item.copyWith(
                              quantity: value,
                              customizedFields: item.budgetItemId != null
                                  ? {...item.customizedFields, 'quantity'}
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 70,
                        child: _EditableNumber(
                          value: item.unitPrice,
                          prefix: _currencySymbol,
                          onChanged: (value) => _updateItem(
                            item.copyWith(
                              unitPrice: value,
                              customizedFields: item.budgetItemId != null
                                  ? {...item.customizedFields, 'unitPrice'}
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 74,
                      child: Text(
                        isGroup
                            ? _formatCurrency(_calculateGroupTotal(item.id))
                            : _formatCurrency(item.total),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: !item.isVisible
                              ? colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                )
                              : null,
                        ),
                      ),
                    ),
                    // On a change order the inline "+" on a group is
                    // suppressed for the same reason the top-level
                    // group/item buttons are: every CO line must come
                    // from an existing approved budget item.
                    if (isGroup && !_isChangeOrder)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.add, size: 18),
                          tooltip: 'Add item to group',
                          onPressed: () => _addItem(parentId: item.id),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    else
                      const SizedBox(width: 32),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        tooltip: 'Remove',
                        onPressed: () => _deleteItem(item.id),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                if (!isGroup) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: isNarrow ? 16 : 64),
                    child: Row(
                      children: [
                        SizedBox(
                          width: isNarrow ? 56 : 90,
                          child: _EditableText(
                            value: item.unit ?? '',
                            onChanged: (value) => _updateItem(
                              item.copyWith(
                                unit: value.trim().isEmpty
                                    ? null
                                    : value.trim(),
                                customizedFields: item.budgetItemId != null
                                    ? {...item.customizedFields, 'unit'}
                                    : null,
                              ),
                            ),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        SizedBox(width: isNarrow ? 8 : 12),
                        Expanded(
                          child: _EditableText(
                            value: item.description ?? '',
                            onChanged: (value) => _updateItem(
                              item.copyWith(
                                description: value.trim().isEmpty
                                    ? null
                                    : value.trim(),
                                customizedFields: item.budgetItemId != null
                                    ? {...item.customizedFields, 'description'}
                                    : null,
                              ),
                            ),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(width: isNarrow ? 4 : 8),
                        if (item.budgetItemId != null) ...[
                          if (isCustomized)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow ? 6 : 8,
                                vertical: isNarrow ? 2 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(AppRadius.r12),
                              ),
                              child: Text(
                                'Customized',
                                style: TextStyle(
                                  fontSize: isNarrow ? 10 : 11,
                                  color: colorScheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: isNarrow
                                ? const EdgeInsets.all(AppSpacing.xs)
                                : null,
                            constraints: isNarrow
                                ? const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  )
                                : null,
                            tooltip: budgetReference == null
                                ? 'Budget source unavailable'
                                : 'Reset to budget values',
                            onPressed: budgetReference == null
                                ? null
                                : () => _resetToBudgetValues(item),
                            icon: const Icon(Icons.history, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Render children if expanded
        if (isGroup && isExpanded)
          ...children.asMap().entries.map((entry) {
            return _buildItemTile(entry.value, entry.key, depth + 1);
          }),
      ],
    );
  }

  double _calculateGroupTotal(String groupId) {
    double total = 0;
    for (final child in _getChildren(groupId)) {
      if (child.isGroup) {
        total += _calculateGroupTotal(child.id);
      } else if (child.isVisible) {
        total += child.total;
      }
    }
    return total;
  }
}

/// Compact toolbar button used in the line-item action bar.
class _ToolbarButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final ColorScheme colorScheme;

  const _ToolbarButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isPrimary = false,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isPrimary
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                color: isPrimary
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable text field with inline editing
class _EditableText extends StatefulWidget {
  final String value;
  final TextStyle? style;
  final Function(String) onChanged;

  const _EditableText({
    required this.value,
    this.style,
    required this.onChanged,
  });

  @override
  State<_EditableText> createState() => _EditableTextState();
}

class _EditableTextState extends State<_EditableText> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_EditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isEditing) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return TextField(
        controller: _controller,
        autofocus: true,
        style: widget.style,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          widget.onChanged(value);
        },
        onSubmitted: (value) {
          widget.onChanged(value);
          setState(() => _isEditing = false);
        },
        onTapOutside: (_) {
          widget.onChanged(_controller.text);
          setState(() => _isEditing = false);
        },
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() => _isEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            selectAllText(_controller);
          }
        });
      },
      child: Text(
        widget.value,
        style: widget.style,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Editable number field with inline editing
class _EditableNumber extends StatefulWidget {
  final double value;
  final String? prefix;
  final String? suffix;
  final Function(double) onChanged;

  const _EditableNumber({
    required this.value,
    this.prefix,
    this.suffix,
    required this.onChanged,
  });

  @override
  State<_EditableNumber> createState() => _EditableNumberState();
}

class _EditableNumberState extends State<_EditableNumber> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_EditableNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isEditing) {
      _controller.text = widget.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          isDense: true,
          prefixText: widget.prefix,
          suffixText: widget.suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = double.tryParse(value) ?? 0;
          widget.onChanged(parsed);
        },
        onSubmitted: (value) {
          final parsed = double.tryParse(value) ?? 0;
          widget.onChanged(parsed);
          setState(() => _isEditing = false);
        },
        onTapOutside: (_) {
          final parsed = double.tryParse(_controller.text) ?? 0;
          widget.onChanged(parsed);
          setState(() => _isEditing = false);
        },
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() => _isEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            selectAllText(_controller);
          }
        });
      },
      child: Text(
        '${widget.prefix ?? ''}${widget.value.toStringAsFixed(2)}${widget.suffix != null ? ' ${widget.suffix}' : ''}',
        textAlign: TextAlign.right,
      ),
    );
  }
}

/// Dialog for importing budget items
class _BudgetImportDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final Set<String> existingBudgetItemIds;

  /// When true (set by change-order documents), the picker hides budget
  /// items that haven't yet been approved into the contract — a CO can
  /// only amend scope that's already part of the agreement.
  final bool requireApproved;

  const _BudgetImportDialog({
    required this.projectId,
    required this.workspaceId,
    required this.existingBudgetItemIds,
    this.requireApproved = false,
  });

  @override
  State<_BudgetImportDialog> createState() => _BudgetImportDialogState();
}

class _BudgetImportDialogState extends State<_BudgetImportDialog> {
  dynamic get _budgetService => ServiceLocator.budgetService;
  List<BudgetItem> _budgetItems = [];

  /// Pre-filter `_budgetItems` total before `requireApproved` is applied,
  /// so the empty state can tell the user "nothing is approved yet" vs.
  /// "everything is already imported".
  int _totalCandidateCount = 0;

  final Set<String> _selectedIds = {};
  bool _isLoading = true;

  // Currency formatting helper
  String _formatCurrency(double amount) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }

  String _emptyStateMessage() {
    // requireApproved + no remaining candidates: most often means nothing
    // in the budget is approved yet, so a CO has nothing to amend. Tell
    // the user instead of leaving them at a blank "all imported" screen.
    if (widget.requireApproved && _totalCandidateCount == 0) {
      return 'No approved budget items yet. A change order can only amend '
          'items already contracted via a signed / approved document.';
    }
    return 'All budget items already imported';
  }

  @override
  void initState() {
    super.initState();
    _loadBudgetItems();
  }

  Future<void> _loadBudgetItems() async {
    try {
      final items = await _budgetService
          .getBudgetItems(widget.projectId, workspaceId: widget.workspaceId)
          .first;

      final notYetImported = (items as List<BudgetItem>)
          .where((i) => !widget.existingBudgetItemIds.contains(i.id))
          .toList();
      setState(() {
        _totalCandidateCount = notYetImported.length;
        _budgetItems = widget.requireApproved
            ? notYetImported.where((i) => i.isApproved).toList()
            : notYetImported;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.requireApproved
          ? 'Pick an approved budget item to amend'
          : 'Import from Budget'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _budgetItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: 12),
                    Text(_emptyStateMessage()),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _budgetItems.length,
                itemBuilder: (context, index) {
                  final item = _budgetItems[index];
                  final isSelected = _selectedIds.contains(item.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(item.id);
                        } else {
                          _selectedIds.remove(item.id);
                        }
                      });
                    },
                    title: Text(item.name),
                    subtitle: item.description != null
                        ? Text(
                            item.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    secondary: Text(
                      _formatCurrency(item.approvedPrice),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  // Selecting a group should bring its line items too —
                  // otherwise the import is an empty $0 group shell (R016).
                  final effectiveIds = <String>{..._selectedIds};
                  bool added = true;
                  while (added) {
                    added = false;
                    for (final i in _budgetItems) {
                      if (i.parentId != null &&
                          effectiveIds.contains(i.parentId) &&
                          !effectiveIds.contains(i.id)) {
                        effectiveIds.add(i.id);
                        added = true;
                      }
                    }
                  }
                  final selectedItems = _budgetItems
                      .where((i) => effectiveIds.contains(i.id))
                      .toList();
                  Navigator.pop(context, selectedItems);
                },
          child: Text(
            'Import ${_selectedIds.isEmpty ? '' : '(${_selectedIds.length})'}',
          ),
        ),
      ],
    );
  }
}
