import 'package:flutter/material.dart';

import '../../models/catalog_item.dart';
import '../../theme/theme.dart';
import '../table/inline_add_row_mixin.dart';

class CatalogInlineAddRow extends StatefulWidget {
  final String workspaceId;
  final String? parentId;
  final int hierarchyLevel;
  final int indentLevel;
  final bool isGroup;
  final VoidCallback onCancel;
  final Future<void> Function(CatalogItem) onSave;

  const CatalogInlineAddRow({
    super.key,
    required this.workspaceId,
    this.parentId,
    required this.hierarchyLevel,
    required this.indentLevel,
    required this.isGroup,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<CatalogInlineAddRow> createState() => _CatalogInlineAddRowState();
}

class _CatalogInlineAddRowState extends State<CatalogInlineAddRow>
    with InlineAddRowMixin {
  static const double _catalogLeadingInset = 28;

  @override
  void initState() {
    super.initState();
    initAddRow();
  }

  @override
  void dispose() {
    disposeAddRow();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) =>
      handleEscapeKey(event, widget.onCancel);

  Future<void> _trySave() async {
    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final description = descriptionController.text.trim();
    final unit = unitController.text.trim();
    final unitCost = double.tryParse(unitCostController.text.trim()) ?? 0.0;
    final unitPrice = double.tryParse(unitPriceController.text.trim()) ?? 0.0;
    final now = DateTime.now();

    final newItem = CatalogItem(
      id: '',
      workspaceId: widget.workspaceId,
      name: name,
      description: description.isNotEmpty ? description : null,
      unit: unit.isNotEmpty ? unit : null,
      unitCost: unitCost,
      unitPrice: unitPrice,
      markup: CatalogItem.calculateMarkup(unitCost, unitPrice),
      margin: CatalogItem.calculateMargin(unitCost, unitPrice),
      createdAt: now,
      updatedAt: now,
      parentId: widget.parentId,
      hierarchyLevel: widget.hierarchyLevel,
      itemType: widget.isGroup ? CatalogItemType.group : CatalogItemType.item,
    );

    await widget.onSave(newItem);
  }

  @override
  Widget build(BuildContext context) {
    final isItem = !widget.isGroup;
    final colorScheme = Theme.of(context).colorScheme;
    final leadingInset = _catalogLeadingInset + (widget.indentLevel * 24.0);

    return Focus(
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: TextFieldTapRegion(
        groupId: tapRegionGroup,
        onTapOutside: (_) => widget.onCancel(),
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
              // Primary row: name field
              Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(width: leadingInset),
                    Expanded(child: _buildNameField()),
                  ],
                ),
              ),
              // Secondary row: description + numeric fields
              Container(
                padding: EdgeInsets.fromLTRB(
                  10 + leadingInset,
                  0,
                  10,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDescriptionField(),
                    if (isItem) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: unitController,
                              focusNode: unitFocus,
                              style: const TextStyle(fontSize: 13),
                              decoration: _fieldDecoration(
                                hintText: 'Unit',
                              ),
                              onSubmitted: (_) =>
                                  unitCostFocus.requestFocus(),
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
                padding: EdgeInsets.fromLTRB(
                  10 + leadingInset,
                  4,
                  10,
                  6,
                ),
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
    return TextField(
      controller: nameController,
      focusNode: nameFocus,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        hintText: widget.isGroup ? 'Group name...' : 'Item name...',
        hintStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.normal,
        ),
      ),
      onSubmitted: (_) => descriptionFocus.requestFocus(),
      onTapOutside: (_) {},
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: descriptionController,
      focusNode: descriptionFocus,
      style: const TextStyle(fontSize: 12),
      minLines: 1,
      maxLines: 3,
      decoration: _fieldDecoration(
        hintText: 'Description...',
      ),
      onSubmitted: (_) {
        if (!widget.isGroup) {
          unitFocus.requestFocus();
        }
      },
      onTapOutside: (_) {},
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
