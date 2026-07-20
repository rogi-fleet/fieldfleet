import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget_item.dart';
import '../models/template_category.dart';
import '../providers/workspace_provider.dart';
import '../services/supabase/budget_service.dart';
import '../theme/theme.dart';
import '../utils/currency_utils.dart';
import '../utils/numeric_input.dart';

/// Step 2 of the budget-to-document wizard.
/// Shows budget items with financial tracking and lets users select items
/// and set per-item amounts for the document.
class BudgetItemSelectionTable extends StatefulWidget {
  final List<BudgetItem> budgetItems;
  final Map<String, BudgetItemDocumentStatus> documentStatusMap;
  final TemplateCategory templateCategory;
  final Set<String>? preSelectedItemIds;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final ValueChanged<Map<String, double>> onConfirm;

  const BudgetItemSelectionTable({
    super.key,
    required this.budgetItems,
    required this.documentStatusMap,
    required this.templateCategory,
    this.preSelectedItemIds,
    required this.onBack,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<BudgetItemSelectionTable> createState() =>
      _BudgetItemSelectionTableState();
}

class _BudgetItemSelectionTableState extends State<BudgetItemSelectionTable> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedIds = {};
  final Map<String, double> _editedAmounts = {};
  final Map<String, TextEditingController> _amountControllers = {};

  @override
  void initState() {
    super.initState();
    // Pre-select items
    if (widget.preSelectedItemIds != null) {
      for (final item in _leafItems) {
        if (widget.preSelectedItemIds!.contains(item.id) &&
            !_isFullyTracked(item)) {
          _selectedIds.add(item.id);
        }
      }
    } else {
      // Select all selectable leaf items by default.
      for (final item in widget.budgetItems) {
        if (item.itemType == BudgetItemType.item && !_isFullyTracked(item)) {
          _selectedIds.add(item.id);
        }
      }
    }
    // Initialize amounts to remaining
    for (final item in _leafItems) {
      final remaining = _remainingAmount(item);
      _editedAmounts[item.id] = remaining;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<BudgetItem> get _leafItems => widget.budgetItems
      .where((i) => i.itemType == BudgetItemType.item)
      .toList();

  String get _trackedColumnLabel {
    switch (widget.templateCategory) {
      case TemplateCategory.customerInvoice:
        return 'Invoiced';
      case TemplateCategory.customerOrder:
        return 'Quoted';
      case TemplateCategory.vendorBill:
        return 'Billed';
      case TemplateCategory.vendorOrder:
        return 'Committed';
    }
  }

  double _trackedAmount(BudgetItem item) {
    final status = widget.documentStatusMap[item.id];
    if (status == null) return 0.0;
    switch (widget.templateCategory) {
      case TemplateCategory.customerInvoice:
        return status.invoicedAmount;
      case TemplateCategory.customerOrder:
        return status.quotedAmount;
      case TemplateCategory.vendorBill:
        return status.billedAmount;
      case TemplateCategory.vendorOrder:
        return status.committedAmount;
    }
  }

  bool get _isVendorDocument =>
      widget.templateCategory == TemplateCategory.vendorOrder ||
      widget.templateCategory == TemplateCategory.vendorBill;

  String get _baseColumnLabel => _isVendorDocument ? 'Projected' : 'Approved';

  double _baseAmount(BudgetItem item) =>
      _isVendorDocument ? item.projectedCost : item.approvedPrice;

  double _remainingAmount(BudgetItem item) {
    final tracked = _trackedAmount(item);
    return (_baseAmount(item) - tracked).clamp(0.0, double.infinity);
  }

  bool _isFullyTracked(BudgetItem item) => _remainingAmount(item) <= 0;

  bool _isSelectable(BudgetItem item) =>
      item.itemType == BudgetItemType.item && !_isFullyTracked(item);

  BudgetItem? _findLeafItemById(String id) {
    for (final item in _leafItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  String get _fullyTrackedLabel {
    switch (widget.templateCategory) {
      case TemplateCategory.customerInvoice:
        return 'Fully invoiced';
      case TemplateCategory.customerOrder:
        return 'Fully quoted';
      case TemplateCategory.vendorBill:
        return 'Fully billed';
      case TemplateCategory.vendorOrder:
        return 'Fully committed';
    }
  }

  bool get _hasCreatableSelection {
    for (final id in _selectedIds) {
      final item = _findLeafItemById(id);
      if (item == null || !_isSelectable(item)) continue;
      final amount = _editedAmounts[id] ?? _remainingAmount(item);
      if (amount > 0) return true;
    }
    return false;
  }

  String get _currencySymbol {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.getSymbol(currencyCode);
  }

  String _formatCurrency(double amount) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }

  String _formatPercent(double part, double whole) {
    if (whole == 0) return '0%';
    return '${(part / whole * 100).toStringAsFixed(0)}%';
  }

  bool _matchesSearch(BudgetItem item) {
    if (_searchQuery.isEmpty) return true;
    return item.name.toLowerCase().contains(_searchQuery);
  }

  void _toggleSelectAll() {
    final visibleLeafs = _leafItems
        .where((item) => _matchesSearch(item) && _isSelectable(item))
        .toList();
    final allSelected = visibleLeafs.every((i) => _selectedIds.contains(i.id));
    setState(() {
      if (allSelected) {
        for (final item in visibleLeafs) {
          _selectedIds.remove(item.id);
        }
      } else {
        for (final item in visibleLeafs) {
          _selectedIds.add(item.id);
        }
      }
    });
  }

  // Build a flat display list respecting hierarchy
  List<BudgetItem> get _displayItems {
    // Sort by hierarchy and sort order - parents first, then children
    final sorted = List<BudgetItem>.from(widget.budgetItems);
    sorted.sort((a, b) {
      if (a.hierarchyLevel != b.hierarchyLevel) {
        return a.hierarchyLevel.compareTo(b.hierarchyLevel);
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });

    // Build ordered list: for each top-level item, add its descendants
    final result = <BudgetItem>[];
    final byParent = <String?, List<BudgetItem>>{};
    for (final item in sorted) {
      byParent.putIfAbsent(item.parentId, () => []).add(item);
    }

    void addWithChildren(BudgetItem item) {
      result.add(item);
      final children = byParent[item.id];
      if (children != null) {
        for (final child in children) {
          addWithChildren(child);
        }
      }
    }

    final roots = byParent[null] ?? [];
    for (final root in roots) {
      addWithChildren(root);
    }

    return result;
  }

  // Aggregate values for group items
  double _groupBase(BudgetItem group) {
    double total = 0;
    for (final item in _leafItems) {
      if (_isDescendantOf(item, group.id)) {
        total += _baseAmount(item);
      }
    }
    return total;
  }

  double _groupTracked(BudgetItem group) {
    double total = 0;
    for (final item in _leafItems) {
      if (_isDescendantOf(item, group.id)) {
        total += _trackedAmount(item);
      }
    }
    return total;
  }

  double _groupThisDocument(BudgetItem group) {
    double total = 0;
    for (final item in _leafItems) {
      if (_isDescendantOf(item, group.id) && _selectedIds.contains(item.id)) {
        total += _editedAmounts[item.id] ?? _remainingAmount(item);
      }
    }
    return total;
  }

  bool _isDescendantOf(BudgetItem item, String ancestorId) {
    // Walk up the parent chain with visited-set guard against cycles
    String? currentParent = item.parentId;
    final allItems = widget.budgetItems;
    final visited = <String>{};
    while (currentParent != null) {
      if (currentParent == ancestorId) return true;
      if (!visited.add(currentParent)) break; // cycle detected
      final idx = allItems.indexWhere((i) => i.id == currentParent);
      if (idx == -1) break; // orphaned — parent not found
      currentParent = allItems[idx].parentId;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _displayItems.where(_matchesSearch).toList();
    final visibleLeafs = _leafItems
        .where((item) => _matchesSearch(item) && _isSelectable(item))
        .toList();
    final allSelected =
        visibleLeafs.isNotEmpty &&
        visibleLeafs.every((i) => _selectedIds.contains(i.id));
    // Summary calculations
    double totalBase = 0;
    double totalTracked = 0;
    double totalRemaining = 0;
    double totalThisDoc = 0;
    for (final item in _leafItems) {
      if (_selectedIds.contains(item.id)) {
        totalBase += _baseAmount(item);
        totalTracked += _trackedAmount(item);
        totalRemaining += _remainingAmount(item);
        totalThisDoc += _editedAmounts[item.id] ?? _remainingAmount(item);
      }
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                    tooltip: 'Back to template selection',
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onCancel,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search items...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _toggleSelectAll,
                    icon: Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 18,
                    ),
                    label: Text(allSelected ? 'Deselect All' : 'Select All'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Table header + data + footer (horizontally scrollable on narrow screens)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minTableWidth = 580.0;
              final tableWidth = constraints.maxWidth < minTableWidth
                  ? minTableWidth
                  : constraints.maxWidth;

              Widget tableContent = SizedBox(
                width: tableWidth,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 40), // checkbox space
                          const Expanded(
                            flex: 3,
                            child: Text(
                              'Item',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _baseColumnLabel,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _trackedColumnLabel,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'Remaining',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'This Document',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Item rows
                    Expanded(
                      child: visibleItems.isEmpty
                          ? Center(
                              child: Text(
                                'No items found',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visibleItems.length,
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                if (item.itemType == BudgetItemType.group) {
                                  return _buildGroupRow(item);
                                }
                                return _buildItemRow(item);
                              },
                            ),
                    ),

                    // Summary footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        border: Border(
                          top: BorderSide(color: AppColors.cardBorder, width: 2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${_selectedIds.length} item${_selectedIds.length == 1 ? '' : 's'} selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatCurrency(totalBase),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatCurrency(totalTracked),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatCurrency(totalRemaining),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatCurrency(totalThisDoc),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              if (constraints.maxWidth < minTableWidth) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: tableContent,
                );
              }
              return tableContent;
            },
          ),
        ),

        // Action buttons
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: !_hasCreatableSelection
                    ? null
                    : () {
                        final amounts = <String, double>{};
                        for (final id in _selectedIds) {
                          final item = _findLeafItemById(id);
                          if (item == null || !_isSelectable(item)) continue;
                          final amount =
                              _editedAmounts[id] ?? _remainingAmount(item);
                          if (amount <= 0) continue;
                          amounts[id] = amount;
                        }
                        if (amounts.isEmpty) return;
                        widget.onConfirm(amounts);
                      },
                icon: const Icon(Icons.description, size: 18),
                label: const Text('Create Document'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupRow(BudgetItem group) {
    final base = _groupBase(group);
    final tracked = _groupTracked(group);
    final remaining = (base - tracked).clamp(0.0, double.infinity);
    final thisDoc = _groupThisDocument(group);

    return Container(
      padding: EdgeInsets.only(
        left: 16.0 + (group.hierarchyLevel * 16.0),
        right: 16,
        top: 10,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withAlpha(80),
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder.withAlpha(120)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40), // align with checkboxes
          Expanded(
            flex: 3,
            child: Text(
              group.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(base),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(tracked),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(remaining),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(thisDoc),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BudgetItem item) {
    final isSelected = _selectedIds.contains(item.id);
    final tracked = _trackedAmount(item);
    final remaining = _remainingAmount(item);
    final fullyTracked = _isFullyTracked(item);
    final amount = _editedAmounts[item.id] ?? remaining;

    // Get or create controller for this item
    if (!_amountControllers.containsKey(item.id)) {
      _amountControllers[item.id] = TextEditingController(
        text: amount.toStringAsFixed(2),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 16.0 + (item.hierarchyLevel * 16.0),
        right: 16,
        top: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(30)
            : null,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder.withAlpha(80)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Checkbox(
              value: isSelected,
              onChanged: fullyTracked
                  ? null
                  : (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(item.id);
                        } else {
                          _selectedIds.remove(item.id);
                        }
                      });
                    },
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fullyTracked ? AppColors.textTertiary : null,
                  ),
                ),
                if (fullyTracked)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Tooltip(
                      message:
                          'This item has no remaining amount for this document type.',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _fullyTrackedLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(_baseAmount(item)),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatCurrency(tracked),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: tracked > 0 ? AppColors.info : null,
                  ),
                ),
                if (tracked > 0)
                  Text(
                    _formatPercent(tracked, _baseAmount(item)),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(remaining),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: remaining <= 0
                    ? AppColors.textTertiary
                    : AppColors.success,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: fullyTracked
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _fullyTrackedLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : isSelected
                ? Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _amountControllers[item.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: NumericInput.currency,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: amount > remaining && remaining > 0
                                ? BorderSide(color: AppColors.warning)
                                : const BorderSide(),
                          ),
                          enabledBorder: amount > remaining && remaining > 0
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: AppColors.warning,
                                  ),
                                )
                              : null,
                          helperText: amount > remaining && remaining > 0
                              ? 'Exceeds remaining'
                              : null,
                          helperStyle: TextStyle(
                            fontSize: 10,
                            color: AppColors.warning,
                          ),
                          prefixText: '$_currencySymbol ',
                          prefixStyle: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            setState(() {
                              _editedAmounts[item.id] = parsed;
                            });
                          }
                        },
                      ),
                    ),
                  )
                : Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
          ),
        ],
      ),
    );
  }
}
