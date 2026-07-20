import 'dart:async';

import 'package:flutter/material.dart';
import '../models/budget_item.dart';
import '../models/catalog_item.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'table/inline_add_row_mixin.dart';

class BudgetInlineAddRow extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final String? parentId;
  final int hierarchyLevel;
  final int indentLevel;
  final bool isGroup;
  final double defaultMarkup;
  final VoidCallback onCancel;
  final Future<void> Function(BudgetItem) onSave;
  final BudgetItemSource sourceType;

  const BudgetInlineAddRow({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.parentId,
    required this.hierarchyLevel,
    required this.indentLevel,
    required this.isGroup,
    this.defaultMarkup = 20.0,
    required this.onCancel,
    required this.onSave,
    this.sourceType = BudgetItemSource.base,
  });

  @override
  State<BudgetInlineAddRow> createState() => _BudgetInlineAddRowState();
}

class _BudgetInlineAddRowState extends State<BudgetInlineAddRow>
    with InlineAddRowMixin {
  static const double _overlayWidth = 460;
  static const double _budgetLeadingInset = 80;

  dynamic get _catalogService => ServiceLocator.catalogService;
  dynamic get _budgetService => ServiceLocator.budgetService;

  // Shared controllers/focus nodes provided by InlineAddRowMixin.
  // Budget-specific extras:
  final _qtyController = TextEditingController();
  final _qtyFocus = FocusNode();

  final _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  List<CatalogItem> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  BudgetCostType? _selectedCostType;

  @override
  void initState() {
    super.initState();
    initAddRow();
  }

  @override
  void dispose() {
    _removeOverlay();
    disposeAddRow();
    _qtyController.dispose();
    _qtyFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (widget.isGroup) {
      _removeOverlay();
      return;
    }
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.isEmpty) {
        _removeOverlay();
        return;
      }
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);

    final items = await _catalogService
        .getCatalogItems(widget.workspaceId)
        .first;

    _searchResults = items
        .where(
          (item) =>
              item.name.toLowerCase().contains(query.toLowerCase()) ||
              (item.description?.toLowerCase().contains(query.toLowerCase()) ??
                  false),
        )
        .toList();

    if (!mounted) return;
    _showOverlay();
    setState(() => _isLoading = false);
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final overlayWidth = (viewportWidth - 32).clamp(260.0, _overlayWidth);

        return Positioned(
          width: overlayWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 8),
            followerAnchor: Alignment.topLeft,
            targetAnchor: Alignment.bottomLeft,
            child: TextFieldTapRegion(
              groupId: tapRegionGroup,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(AppRadius.r12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      ..._searchResults.map(
                        (item) => ListTile(
                          dense: true,
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: item.description != null
                              ? Text(
                                  item.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: Text(
                            '\$${item.unitPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onTap: () => _selectCatalogItem(item),
                        ),
                      ),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.add, color: AppColors.info),
                        title: Text(
                          'Create "${nameController.text.trim()}"',
                          style: TextStyle(
                            color: AppColors.info,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Fill in details below',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        onTap: () {
                          _removeOverlay();
                          descriptionFocus.requestFocus();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _selectCatalogItem(CatalogItem item) async {
    _removeOverlay();

    final sortOrder = await _budgetService.getNextSortOrder(
      widget.parentId,
      widget.projectId,
    );
    final now = DateTime.now();

    final newItem = BudgetItem(
      id: '',
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      parentId: widget.parentId,
      hierarchyLevel: widget.hierarchyLevel,
      sortOrder: sortOrder,
      name: item.name,
      description: item.description,
      unit: item.unit,
      unitCost: item.unitCost,
      unitPrice: item.unitPrice,
      markup: item.markup,
      isTaxable: item.isTaxable,
      quantity: 1.0,
      approvedPrice: item.unitPrice,
      projectedCost: item.unitCost,
      itemType: widget.isGroup ? BudgetItemType.group : BudgetItemType.item,
      costType: _selectedCostType,
      createdAt: now,
      updatedAt: now,
      sourceType: widget.sourceType,
      upgradeStatus: widget.sourceType == BudgetItemSource.upgrade
          ? UpgradeStatus.offered
          : null,
    );

    await widget.onSave(newItem);
  }

  Future<void> _trySave() async {
    _removeOverlay();

    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final sortOrder = await _budgetService.getNextSortOrder(
      widget.parentId,
      widget.projectId,
    );
    final now = DateTime.now();

    final description = descriptionController.text.trim();
    final unit = unitController.text.trim();
    final qty = double.tryParse(_qtyController.text.trim()) ?? 1.0;
    final unitCost = double.tryParse(unitCostController.text.trim()) ?? 0.0;
    final unitPrice = double.tryParse(unitPriceController.text.trim()) ?? 0.0;

    final newItem = BudgetItem(
      id: '',
      workspaceId: widget.workspaceId,
      projectId: widget.projectId,
      parentId: widget.parentId,
      hierarchyLevel: widget.hierarchyLevel,
      sortOrder: sortOrder,
      name: name,
      description: description.isNotEmpty ? description : null,
      unit: unit.isNotEmpty ? unit : null,
      quantity: qty,
      unitCost: unitCost,
      unitPrice: unitPrice,
      markup: unitCost > 0
          ? ((unitPrice - unitCost) / unitCost) * 100
          : widget.defaultMarkup,
      isTaxable: true,
      approvedPrice: qty * unitPrice,
      projectedCost: qty * unitCost,
      itemType: widget.isGroup ? BudgetItemType.group : BudgetItemType.item,
      costType: _selectedCostType,
      createdAt: now,
      updatedAt: now,
      sourceType: widget.sourceType,
      upgradeStatus: widget.sourceType == BudgetItemSource.upgrade
          ? UpgradeStatus.offered
          : null,
    );

    await widget.onSave(newItem);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) =>
      handleEscapeKey(event, widget.onCancel);

  @override
  Widget build(BuildContext context) {
    final isItem = !widget.isGroup;
    final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    final colorScheme = Theme.of(context).colorScheme;
    final baseInset = isMobile ? 16.0 : _budgetLeadingInset;
    final nestedInset = isMobile ? 14.0 : 24.0;
    final leadingInset = baseInset + (widget.indentLevel * nestedInset);

    return Focus(
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: TextFieldTapRegion(
        groupId: tapRegionGroup,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Column(
            key: scrollKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary row: name field + cost type
              Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(width: leadingInset),
                    Expanded(child: _buildNameField()),
                    if (isItem && !isMobile) ...[
                      const SizedBox(width: 8),
                      SizedBox(width: 140, child: _buildCostTypeDropdown()),
                    ],
                  ],
                ),
              ),
              // Secondary row: description + numeric fields
              Container(
                padding: EdgeInsets.fromLTRB(10 + leadingInset, 0, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDescriptionField(),
                    if (isItem) ...[
                      const SizedBox(height: 6),
                      if (isMobile) ...[
                        SizedBox(width: 160, child: _buildCostTypeDropdown()),
                        const SizedBox(height: 6),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _qtyController,
                              focusNode: _qtyFocus,
                              style: const TextStyle(fontSize: 13),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(hintText: 'Qty'),
                              onSubmitted: (_) => unitFocus.requestFocus(),
                              onTapOutside: (_) {},
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: unitController,
                              focusNode: unitFocus,
                              style: const TextStyle(fontSize: 13),
                              decoration: _fieldDecoration(hintText: 'Unit'),
                              onSubmitted: (_) => unitCostFocus.requestFocus(),
                              onTapOutside: (_) {},
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: unitCostController,
                              focusNode: unitCostFocus,
                              style: const TextStyle(fontSize: 13),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                hintText: 'Unit cost',
                                prefixText: '\$ ',
                              ),
                              onSubmitted: (_) =>
                                  unitPriceFocus.requestFocus(),
                              onTapOutside: (_) {},
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: unitPriceController,
                              focusNode: unitPriceFocus,
                              style: const TextStyle(fontSize: 13),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                hintText: 'Unit price',
                                prefixText: '\$ ',
                              ),
                              onSubmitted: (_) => _trySave(),
                              onTapOutside: (_) {},
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Bottom row: Add + Cancel buttons
              Container(
                padding: EdgeInsets.fromLTRB(10 + leadingInset, 4, 10, 6),
                child: Row(
                  children: [
                    _buildSaveButton(),
                    const SizedBox(width: 4),
                    _buildCancelButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return TextButton.icon(
      onPressed: _trySave,
      icon: const Icon(Icons.check, size: 14),
      label: Text(widget.isGroup ? 'Add group' : 'Add item'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.info,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildCancelButton() {
    return IconButton(
      onPressed: widget.onCancel,
      icon: const Icon(Icons.close, size: 16),
      color: AppColors.textTertiary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      splashRadius: 14,
      tooltip: 'Cancel',
    );
  }

  Widget _buildNameField() {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: nameController,
        focusNode: nameFocus,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          hintText: widget.isGroup
              ? 'Group name...'
              : 'Item name or search catalog...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.normal,
          ),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 20,
            minHeight: 20,
          ),
        ),
        onChanged: _onSearchChanged,
        onSubmitted: (_) {
          if (!widget.isGroup && _searchResults.isNotEmpty) {
            _selectCatalogItem(_searchResults.first);
          } else {
            descriptionFocus.requestFocus();
          }
        },
        onTapOutside: (_) {},
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: descriptionController,
      focusNode: descriptionFocus,
      style: const TextStyle(fontSize: 12),
      minLines: 1,
      maxLines: 3,
      decoration: _fieldDecoration(hintText: 'Description...'),
      onSubmitted: (_) {
        if (!widget.isGroup) {
          _qtyFocus.requestFocus();
        }
      },
      onTapOutside: (_) {},
    );
  }

  Widget _buildCostTypeDropdown() {
    return _buildFieldShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BudgetCostType>(
          borderRadius: AppRadius.cardRadius,
          value: _selectedCostType,
          hint: Text(
            'Cost Type',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          isExpanded: true,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: AppColors.textTertiary,
          ),
          items: BudgetCostType.values.map((type) {
            return DropdownMenuItem<BudgetCostType>(
              value: type,
              child: Text(
                type.displayLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: type.color,
                ),
              ),
            );
          }).toList(),
          selectedItemBuilder: (context) {
            return BudgetCostType.values.map((type) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  type.displayLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: type.color,
                  ),
                ),
              );
            }).toList();
          },
          onChanged: (type) {
            if (type != null) {
              setState(() => _selectedCostType = type);
            }
          },
        ),
      ),
    );
  }

  Widget _buildFieldShell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: child,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixText: prefixText,
      border: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.xs),
      hintStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      prefixStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}
