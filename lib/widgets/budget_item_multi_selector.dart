import 'dart:async';

import 'package:flutter/material.dart';
import '../models/budget_item.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';

/// Multi-select widget for choosing budget items (leaf items only)
class BudgetItemMultiSelector extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final List<String> selectedBudgetItemIds;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const BudgetItemMultiSelector({
    super.key,
    required this.projectId,
    required this.workspaceId,
    required this.selectedBudgetItemIds,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<BudgetItemMultiSelector> createState() =>
      _BudgetItemMultiSelectorState();
}

class _BudgetItemMultiSelectorState extends State<BudgetItemMultiSelector> {
  List<BudgetItem> _allItems = [];
  bool _isLoading = true;
  StreamSubscription<List<BudgetItem>>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _loadItems() {
    try {
      _subscription = ServiceLocator.budgetService
          .getBudgetItems(widget.projectId, workspaceId: widget.workspaceId)
          .listen((items) {
        if (mounted) {
          setState(() {
            _allItems = items;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _BudgetItemPickerSheet(
        allItems: _allItems,
        selectedIds: widget.selectedBudgetItemIds,
        onChanged: widget.onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_allItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedItems = _allItems
        .where((item) => widget.selectedBudgetItemIds.contains(item.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Budget Items',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            children: [
              if (selectedItems.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedItems.map((item) {
                      return Chip(
                        label: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        deleteIcon: widget.enabled
                            ? const Icon(Icons.close, size: 16)
                            : null,
                        onDeleted: widget.enabled
                            ? () {
                                final newIds = List<String>.from(
                                    widget.selectedBudgetItemIds)
                                  ..remove(item.id);
                                widget.onChanged(newIds);
                              }
                            : null,
                        backgroundColor: AppColors.info.withValues(alpha: 0.1),
                        side: BorderSide(
                            color: AppColors.info.withValues(alpha: 0.3)),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),
              if (widget.enabled)
                InkWell(
                  onTap: _showPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.add,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          selectedItems.isEmpty
                              ? 'Link budget items...'
                              : 'Link more budget items...',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetItemPickerSheet extends StatefulWidget {
  final List<BudgetItem> allItems;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _BudgetItemPickerSheet({
    required this.allItems,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<_BudgetItemPickerSheet> createState() => _BudgetItemPickerSheetState();
}

class _BudgetItemPickerSheetState extends State<_BudgetItemPickerSheet> {
  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    // Build hierarchical display: groups shown as headers, items as selectable
    final filteredItems = widget.allItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort by hierarchy level then sort order
    filteredItems.sort((a, b) {
      if (a.hierarchyLevel != b.hierarchyLevel) {
        return a.hierarchyLevel.compareTo(b.hierarchyLevel);
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Budget Items',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onChanged(_selected.toList());
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search budget items...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'No budget items in this project'
                          : 'No matching budget items',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final isLeaf = item.itemType == BudgetItemType.item;
                      final isSelected = _selected.contains(item.id);

                      if (!isLeaf) {
                        // Group header - not selectable
                        return Padding(
                          padding: EdgeInsets.only(
                            left: item.hierarchyLevel * 16.0,
                            top: index > 0 ? 8 : 0,
                          ),
                          child: Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                            left: item.hierarchyLevel * 16.0),
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selected.add(item.id);
                              } else {
                                _selected.remove(item.id);
                              }
                            });
                          },
                          title: Text(
                            item.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: item.projectedCost > 0
                              ? Text(
                                  '\$${item.projectedCost.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : null,
                          controlAffinity: ListTileControlAffinity.trailing,
                          dense: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
