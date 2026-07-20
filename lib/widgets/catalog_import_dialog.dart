import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/budget_item.dart';
import '../models/catalog_item.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class CatalogImportDialog extends StatefulWidget {
  final String projectId;
  final String workspaceId;

  const CatalogImportDialog({
    super.key,
    required this.projectId,
    required this.workspaceId,
  });

  @override
  State<CatalogImportDialog> createState() => _CatalogImportDialogState();
}

class _CatalogImportDialogState extends State<CatalogImportDialog> {
  dynamic get _budgetService => ServiceLocator.budgetService;
  dynamic get _catalogService => ServiceLocator.catalogService;
  final _searchController = TextEditingController();

  List<CatalogItem> _allCatalogItems = const [];
  String? _selectedParentId;
  final Set<String> _selectedCatalogItemIds = {};
  String _searchQuery = '';
  bool _isImporting = false;

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
            _buildParentSelector(),
            const SizedBox(height: 16),
            _buildSearchField(),
            const SizedBox(height: 16),
            Expanded(child: _buildCatalogItemList()),
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
              'Import from Catalog',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Select catalog items to add to your budget',
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

  Widget _buildParentSelector() {
    return StreamBuilder<List<BudgetItem>>(
      stream: _budgetService.getBudgetItems(
        widget.projectId,
        workspaceId: widget.workspaceId,
      ),
      builder: (context, snapshot) {
        final budgetItems = snapshot.data ?? [];
        // Only groups can receive imported children.
        final parentOptions = budgetItems
            .where((item) => item.itemType == BudgetItemType.group)
            .toList();

        return StackedField(
          label: 'Add items under',
          child: DropdownButtonFormField<String?>(
            borderRadius: AppRadius.cardRadius,
            initialValue: _selectedParentId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_open),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Root level'),
              ),
              ...parentOptions.map((item) {
                final indent = '  ' * item.hierarchyLevel;
                final icon = item.hierarchyLevel == 0
                    ? Icons.folder
                    : Icons.category;
                return DropdownMenuItem<String?>(
                  value: item.id,
                  child: Row(
                    children: [
                      Text(indent),
                      Icon(icon, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        item.hierarchyLevelName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (value) {
              setState(() {
                _selectedParentId = value;
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return StackedField(
      label: 'Search catalog items',
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
    );
  }

  Widget _buildCatalogItemList() {
    return StreamBuilder<List<CatalogItem>>(
      stream: _catalogService.getCatalogItems(widget.workspaceId),
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
                  Icons.inventory_2_outlined,
                  size: 64,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No catalog items found',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add items to your catalog first',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          );
        }

        _allCatalogItems = snapshot.data!;
        final catalogItems = _allCatalogItems
            .where(
              (item) =>
                  _searchQuery.isEmpty ||
                  item.name.toLowerCase().contains(_searchQuery) ||
                  (item.description?.toLowerCase().contains(_searchQuery) ??
                      false) ||
                  (item.category?.toLowerCase().contains(_searchQuery) ??
                      false),
            )
            .toList();

        if (catalogItems.isEmpty) {
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
                      _selectedCatalogItemIds.addAll(
                        catalogItems.map((i) => i.id),
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
                      _selectedCatalogItemIds.clear();
                    });
                  },
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('Deselect All'),
                ),
                const Spacer(),
                Text(
                  '${_selectedCatalogItemIds.length} selected',
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
                itemCount: catalogItems.length,
                itemBuilder: (context, index) {
                  final item = catalogItems[index];
                  final isSelected = _selectedCatalogItemIds.contains(item.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedCatalogItemIds.add(item.id);
                        } else {
                          _selectedCatalogItemIds.remove(item.id);
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
                          'Cost: \$${item.unitCost.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Price: \$${item.unitPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    secondary: item.category != null
                        ? Chip(
                            label: Text(
                              item.category!,
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
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
    final includedIds = _includedCatalogImportIds();
    final nestedCount = includedIds.length - _selectedCatalogItemIds.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_selectedCatalogItemIds.isNotEmpty)
          Text(
            nestedCount > 0
                ? 'Will create ${includedIds.length} budget rows ($nestedCount nested)'
                : 'Will create ${includedIds.length} budget row${includedIds.length == 1 ? '' : 's'}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          )
        else
          const SizedBox(),
        Row(
          children: [
            TextButton(
              onPressed: _isImporting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _selectedCatalogItemIds.isEmpty || _isImporting
                  ? null
                  : _importSelectedItems,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isImporting ? 'Importing...' : 'Import'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importSelectedItems() async {
    if (_selectedCatalogItemIds.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final includedIds = _includedCatalogImportIds();
      // Get selected catalog items
      final allCatalogItems = await _catalogService
          .getCatalogItems(widget.workspaceId)
          .first;
      final selectedItems = allCatalogItems
          .where((item) => _selectedCatalogItemIds.contains(item.id))
          .toList();

      // Import them as budget items
      await _budgetService.importCatalogItemsToBudget(
        catalogItems: selectedItems,
        parentId: _selectedParentId,
        projectId: widget.projectId,
        workspaceId: widget.workspaceId,
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${includedIds.length} catalog row${includedIds.length == 1 ? '' : 's'} to budget',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'importing items'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Set<String> _includedCatalogImportIds() {
    if (_selectedCatalogItemIds.isEmpty || _allCatalogItems.isEmpty) {
      return const <String>{};
    }

    final itemsById = {for (final item in _allCatalogItems) item.id: item};
    final childrenByParentId = <String?, List<CatalogItem>>{};
    for (final item in _allCatalogItems) {
      childrenByParentId
          .putIfAbsent(item.parentId, () => <CatalogItem>[])
          .add(item);
    }

    final includedIds = <String>{};
    for (final selectedId in _selectedCatalogItemIds) {
      final item = itemsById[selectedId];
      if (item == null) continue;
      if (_hasSelectedCatalogAncestor(item, itemsById)) continue;
      _collectCatalogBranchIds(item.id, childrenByParentId, includedIds);
    }
    return includedIds;
  }

  bool _hasSelectedCatalogAncestor(
    CatalogItem item,
    Map<String, CatalogItem> itemsById,
  ) {
    var parentId = item.parentId;
    while (parentId != null) {
      if (_selectedCatalogItemIds.contains(parentId)) return true;
      parentId = itemsById[parentId]?.parentId;
    }
    return false;
  }

  void _collectCatalogBranchIds(
    String itemId,
    Map<String?, List<CatalogItem>> childrenByParentId,
    Set<String> into,
  ) {
    if (!into.add(itemId)) return;
    for (final child in childrenByParentId[itemId] ?? const <CatalogItem>[]) {
      _collectCatalogBranchIds(child.id, childrenByParentId, into);
    }
  }
}

/// Show the catalog import dialog
Future<bool?> showCatalogImportDialog(
  BuildContext context, {
  required String projectId,
  required String workspaceId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) =>
        CatalogImportDialog(projectId: projectId, workspaceId: workspaceId),
  );
}
