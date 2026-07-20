import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/budget_item.dart';
import '../providers/workspace_provider.dart';
import '../services/service_locator.dart';
import '../utils/currency_utils.dart';
import '../utils/numeric_input.dart';
import '../theme/theme.dart';

/// A reusable widget for selecting budget items with hierarchical display.
/// Used when creating quotes, invoices, bid requests, and other documents.
class BudgetItemSelectorWidget extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final List<String> initialSelectedIds;
  final Map<String, double>? initialAmounts;
  final bool allowAmountEdit;
  final Function(List<String> selectedIds, Map<String, double> amounts, double total) onSelectionChanged;

  const BudgetItemSelectorWidget({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.initialSelectedIds = const [],
    this.initialAmounts,
    this.allowAmountEdit = true,
    required this.onSelectionChanged,
  });

  @override
  State<BudgetItemSelectorWidget> createState() => _BudgetItemSelectorWidgetState();
}

class _BudgetItemSelectorWidgetState extends State<BudgetItemSelectorWidget> {
  dynamic get _budgetService => ServiceLocator.budgetService;

  List<BudgetItem> _allItems = [];

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) => CurrencyUtils.formatCurrency(amount, _currencyCode);
  String get _currencySymbol => CurrencyUtils.getSymbol(_currencyCode);
  Set<String> _selectedIds = {};
  Map<String, double> _amounts = {};
  final Map<String, bool> _expandedItems = {};
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _amounts = Map.from(widget.initialAmounts ?? {});
    _loadBudgetItems();
  }

  Future<void> _loadBudgetItems() async {
    try {
      final items = await _budgetService.getBudgetItems(
        widget.projectId,
        workspaceId: widget.workspaceId,
      ).first;
      
      setState(() {
        _allItems = items;
        _isLoading = false;
        
        // Expand all top-level items (packages) by default
        for (final item in items.where((i) => i.hierarchyLevel == 0)) {
          _expandedItems[item.id] = true;
        }
        
        // Initialize amounts from budget item approved prices if not already set
        for (final item in items) {
          if (!_amounts.containsKey(item.id)) {
            _amounts[item.id] = item.approvedPrice;
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<BudgetItem> get _topLevelItems {
    return _allItems.where((i) => i.parentId == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<BudgetItem> _getChildren(String parentId) {
    return _allItems.where((i) => i.parentId == parentId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  bool _hasChildren(String itemId) {
    return _allItems.any((i) => i.parentId == itemId);
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
        // Also deselect all children
        _deselectChildren(itemId);
      } else {
        _selectedIds.add(itemId);
        // Also select all children
        _selectChildren(itemId);
      }
      _notifyChange();
    });
  }

  void _selectChildren(String parentId) {
    for (final child in _getChildren(parentId)) {
      _selectedIds.add(child.id);
      _selectChildren(child.id);
    }
  }

  void _deselectChildren(String parentId) {
    for (final child in _getChildren(parentId)) {
      _selectedIds.remove(child.id);
      _deselectChildren(child.id);
    }
  }

  void _updateAmount(String itemId, double amount) {
    setState(() {
      _amounts[itemId] = amount;
      _notifyChange();
    });
  }

  void _notifyChange() {
    // Only include leaf items in the total calculation and selection
    final selectedLeafIds = _selectedIds.where((id) {
      return !_hasChildren(id);
    }).toList();
    
    double total = 0;
    for (final id in selectedLeafIds) {
      total += _amounts[id] ?? 0;
    }
    
    widget.onSelectionChanged(selectedLeafIds, _amounts, total);
  }

  double get _selectedTotal {
    double total = 0;
    for (final id in _selectedIds) {
      if (!_hasChildren(id)) {
        total += _amounts[id] ?? 0;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No budget items found',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create budget items first to include them in documents',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with total
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '${_selectedIds.where((id) => !_hasChildren(id)).length} items selected',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'Total: ${_formatCurrency(_selectedTotal)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Budget items list
        Expanded(
          child: ListView.builder(
            itemCount: _topLevelItems.length,
            itemBuilder: (context, index) {
              return _buildBudgetItemTile(_topLevelItems[index], 0);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetItemTile(BudgetItem item, int depth) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasChildren = _hasChildren(item.id);
    final isExpanded = _expandedItems[item.id] ?? false;
    final isSelected = _selectedIds.contains(item.id);
    final children = _getChildren(item.id);
    
    // Calculate indentation
    final leftPadding = 16.0 + (depth * 24.0);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren 
              ? () {
                  setState(() {
                    _expandedItems[item.id] = !isExpanded;
                  });
                }
              : () => _toggleSelection(item.id),
          child: Container(
            padding: EdgeInsets.only(
              left: leftPadding,
              right: 16,
              top: 12,
              bottom: 12,
            ),
            decoration: BoxDecoration(
              color: isSelected && !hasChildren
                  ? colorScheme.primaryContainer.withValues(alpha: 0.2)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse icon for parents, checkbox for leaves
                if (hasChildren)
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  )
                else
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(item.id),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                const SizedBox(width: 8),
                
                // Hierarchy icon
                Icon(
                  _getHierarchyIcon(item.hierarchyLevel),
                  size: 18,
                  color: _getHierarchyColor(item.hierarchyLevel, colorScheme),
                ),
                const SizedBox(width: 12),
                
                // Name
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontWeight: item.hierarchyLevel == 0 
                          ? FontWeight.bold 
                          : item.hierarchyLevel == 1 
                              ? FontWeight.w600 
                              : FontWeight.normal,
                      fontSize: item.hierarchyLevel == 0 ? 15 : 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                
                // Amount (editable for leaf items)
                if (!hasChildren && widget.allowAmountEdit)
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      initialValue: (_amounts[item.id] ?? item.approvedPrice).toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        prefixText: _currencySymbol,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      keyboardType: NumericInput.keyboard,
                      inputFormatters: NumericInput.currency,
                      onChanged: (value) {
                        final amount = double.tryParse(value) ?? 0;
                        _updateAmount(item.id, amount);
                      },
                    ),
                  )
                else if (!hasChildren)
                  Text(
                    _formatCurrency(_amounts[item.id] ?? item.approvedPrice),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  )
                else
                  // Show total for parents
                  Text(
                    _formatCurrency(_calculateParentTotal(item.id)),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // Children
        if (hasChildren && isExpanded)
          ...children.map((child) => _buildBudgetItemTile(child, depth + 1)),
      ],
    );
  }

  double _calculateParentTotal(String parentId) {
    double total = 0;
    for (final child in _getChildren(parentId)) {
      if (_hasChildren(child.id)) {
        total += _calculateParentTotal(child.id);
      } else if (_selectedIds.contains(child.id)) {
        total += _amounts[child.id] ?? child.approvedPrice;
      }
    }
    return total;
  }

  IconData _getHierarchyIcon(int level) {
    switch (level) {
      case 0:
        return Icons.folder_outlined;
      case 1:
        return Icons.folder_open_outlined;
      case 2:
        return Icons.description_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _getHierarchyColor(int level, ColorScheme colorScheme) {
    switch (level) {
      case 0:
        return colorScheme.primary;
      case 1:
        return colorScheme.secondary;
      case 2:
        return colorScheme.tertiary;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}
