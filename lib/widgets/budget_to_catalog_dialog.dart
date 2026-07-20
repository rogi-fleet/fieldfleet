import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/budget_item.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class BudgetToCatalogDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;

  const BudgetToCatalogDialog({
    super.key,
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<BudgetToCatalogDialog> createState() => _BudgetToCatalogDialogState();
}

class _BudgetToCatalogDialogState extends State<BudgetToCatalogDialog> {
  dynamic get _budgetService => ServiceLocator.budgetService;
  dynamic get _catalogService => ServiceLocator.catalogService;
  final _searchController = TextEditingController();

  List<BudgetItem> _allBudgetItems = const [];
  final Set<String> _selectedBudgetItemIds = {};
  String _searchQuery = '';
  bool _isCopying = false;
  bool _showOnlyItems = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSearchField(),
            const SizedBox(height: 16),
            Expanded(child: _buildBudgetItemList()),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Copy to Catalog',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Select budget items to copy to your catalog',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: StackedField(
            label: 'Search budget items',
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        FilterChip(
          label: const Text('Items only'),
          selected: _showOnlyItems,
          onSelected: (value) {
            setState(() => _showOnlyItems = value);
          },
          tooltip: 'Show only individual line items, not groups',
        ),
      ],
    );
  }

  Widget _buildBudgetItemList() {
    return StreamBuilder<List<BudgetItem>>(
      stream: _budgetService.getBudgetItems(
        widget.projectId,
        workspaceId: widget.workspaceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.assessment_outlined,
                  size: 64,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No budget items found',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        _allBudgetItems = snapshot.data!;
        var budgetItems = _allBudgetItems;

        // Filter to only item rows when toggle is on.
        if (_showOnlyItems) {
          budgetItems = budgetItems
              .where((item) => item.itemType == BudgetItemType.item)
              .toList();
        }

        // Apply search filter
        budgetItems = budgetItems
            .where(
              (item) =>
                  _searchQuery.isEmpty ||
                  item.name.toLowerCase().contains(_searchQuery) ||
                  (item.description?.toLowerCase().contains(_searchQuery) ??
                      false),
            )
            .toList();

        if (budgetItems.isEmpty) {
          return const Center(child: Text('No matching items'));
        }

        return Column(
          children: [
            // Select all / Deselect all row
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedBudgetItemIds.addAll(
                        budgetItems.map((i) => i.id),
                      );
                    });
                  },
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedBudgetItemIds.clear();
                    });
                  },
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('Deselect All'),
                ),
                const Spacer(),
                Text(
                  '${_selectedBudgetItemIds.length} selected',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: budgetItems.length,
                itemBuilder: (context, index) {
                  final item = budgetItems[index];
                  final isSelected = _selectedBudgetItemIds.contains(item.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedBudgetItemIds.add(item.id);
                        } else {
                          _selectedBudgetItemIds.remove(item.id);
                        }
                      });
                    },
                    title: Text(item.name),
                    subtitle: Row(
                      children: [
                        if (item.description != null &&
                            item.description!.isNotEmpty)
                          Expanded(
                            child: Text(
                              item.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          'Unit Cost: \$${_previewUnitCost(item).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Unit Price: \$${_previewUnitPrice(item).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    secondary: Chip(
                      label: Text(
                        item.hierarchyLevelName,
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFooter() {
    final includedIds = _includedBudgetExportIds();
    final nestedCount = includedIds.length - _selectedBudgetItemIds.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_selectedBudgetItemIds.isNotEmpty)
          Text(
            nestedCount > 0
                ? 'Will create ${includedIds.length} catalog rows ($nestedCount nested)'
                : 'Will create ${includedIds.length} catalog item${includedIds.length == 1 ? '' : 's'}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          )
        else
          const SizedBox(),
        Row(
          children: [
            TextButton(
              onPressed: _isCopying ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _selectedBudgetItemIds.isEmpty || _isCopying
                  ? null
                  : _copySelectedItems,
              icon: _isCopying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.copy_all),
              label: Text(_isCopying ? 'Copying...' : 'Copy to Catalog'),
            ),
          ],
        ),
      ],
    );
  }

  double _previewUnitCost(BudgetItem item) {
    if (item.unitCost > 0) return item.unitCost;
    if (item.quantity > 0 && item.projectedCost > 0) {
      return item.projectedCost / item.quantity;
    }
    return 0;
  }

  double _previewUnitPrice(BudgetItem item) {
    if (item.unitPrice > 0) return item.unitPrice;
    if (item.quantity > 0 && item.approvedPrice > 0) {
      return item.approvedPrice / item.quantity;
    }
    return 0;
  }

  Future<void> _copySelectedItems() async {
    if (_selectedBudgetItemIds.isEmpty) return;

    setState(() => _isCopying = true);

    try {
      final includedIds = _includedBudgetExportIds();
      final selectedItems = _allBudgetItems
          .where((item) => _selectedBudgetItemIds.contains(item.id))
          .toList();

      // Copy them to catalog
      await _catalogService.copyBudgetItemsToCatalog(
        budgetItems: selectedItems,
        workspaceId: widget.workspaceId,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Copied ${includedIds.length} budget row${includedIds.length == 1 ? '' : 's'} to catalog',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCopying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'copying items'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Set<String> _includedBudgetExportIds() {
    if (_selectedBudgetItemIds.isEmpty || _allBudgetItems.isEmpty) {
      return const <String>{};
    }

    final itemsById = {for (final item in _allBudgetItems) item.id: item};
    final childrenByParentId = <String?, List<BudgetItem>>{};
    for (final item in _allBudgetItems) {
      childrenByParentId
          .putIfAbsent(item.parentId, () => <BudgetItem>[])
          .add(item);
    }

    final includedIds = <String>{};
    for (final selectedId in _selectedBudgetItemIds) {
      final item = itemsById[selectedId];
      if (item == null) continue;
      if (_hasSelectedBudgetAncestor(item, itemsById)) continue;
      _collectBudgetBranchIds(item.id, childrenByParentId, includedIds);
    }
    return includedIds;
  }

  bool _hasSelectedBudgetAncestor(
    BudgetItem item,
    Map<String, BudgetItem> itemsById,
  ) {
    var parentId = item.parentId;
    while (parentId != null) {
      if (_selectedBudgetItemIds.contains(parentId)) return true;
      parentId = itemsById[parentId]?.parentId;
    }
    return false;
  }

  void _collectBudgetBranchIds(
    String itemId,
    Map<String?, List<BudgetItem>> childrenByParentId,
    Set<String> into,
  ) {
    if (!into.add(itemId)) return;
    for (final child in childrenByParentId[itemId] ?? const <BudgetItem>[]) {
      _collectBudgetBranchIds(child.id, childrenByParentId, into);
    }
  }
}

/// Show the budget to catalog dialog
Future<bool?> showBudgetToCatalogDialog(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) =>
        BudgetToCatalogDialog(projectId: projectId, workspaceId: workspaceId),
  );
}
