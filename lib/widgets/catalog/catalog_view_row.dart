import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/catalog_item.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../table/hover_action_row.dart';
import '../table/inline_checkbox_cell.dart';
import '../table/inline_edit_cell.dart';
import '../table/table_text_cell.dart';
import '../table/tree_drop_zone.dart';
import '../table/tree_line_painter.dart';
import '../table/tree_row_chevron.dart';
import '../table/tree_row_add_button.dart';
import '../table/tree_row_container.dart';
import '../table/inline_row_edit_mixin.dart';
import '../table/tree_row_drop_wrapper.dart';
import '../../utils/text_selection_utils.dart';

/// A dedicated row widget for the catalog view with inline editing.
/// Reuses the shared tree row primitives from the budget/task tables.
class CatalogViewRow extends StatefulWidget {
  final CatalogItem item;
  final List<CatalogItem> allItems;
  final Map<String, CatalogItem> itemsById;
  final bool hasChildren;
  final int indentLevel;
  final bool isExpanded;
  final bool isSelected;
  final List<bool> treeGuides;
  final bool isLastChild;
  final String searchQuery;
  final Set<String> visibleColumns;
  final Map<String, double> columnWidths;
  final VoidCallback? onExpandToggle;
  final Function(CatalogItem, bool)? onSelectionChanged;
  final Function(CatalogItem)? onItemChanged;
  final Function(String? parentId, int hierarchyLevel, {required bool isGroup})?
  onAddItem;
  final Function(CatalogItem)? onEditItem;
  final Function(CatalogItem)? onDuplicateItem;
  final Function(CatalogItem)? onDeleteItem;
  final Function(CatalogItem, String?)? onItemParentChanged;
  final void Function(CatalogItem dragged, CatalogItem target, DropZone zone)?
  onItemDropped;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const CatalogViewRow({
    super.key,
    required this.item,
    required this.allItems,
    required this.itemsById,
    this.hasChildren = false,
    required this.indentLevel,
    required this.isExpanded,
    required this.isSelected,
    this.treeGuides = const [],
    this.isLastChild = true,
    this.searchQuery = '',
    this.visibleColumns = const {},
    this.columnWidths = const {},
    this.onExpandToggle,
    this.onSelectionChanged,
    this.onItemChanged,
    this.onAddItem,
    this.onEditItem,
    this.onDuplicateItem,
    this.onDeleteItem,
    this.onItemParentChanged,
    this.onItemDropped,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<CatalogViewRow> createState() => _CatalogViewRowState();
}

class _CatalogViewRowState extends State<CatalogViewRow>
    with InlineRowEditMixin {
  double _colW(String id, double defaultWidth) =>
      widget.columnWidths[id] ?? defaultWidth;

  static const double _dropInsertionGap = 44;
  static const double _rowVerticalGap = 0;
  static const List<Color> _groupAccentColors = [
    Color(0xFF4A90A4),
    Color(0xFFE8973A),
    Color(0xFF4CAF50),
  ];

  bool _isEditingName = false;
  bool _isEditingDescription = false;
  bool _isEditingUnit = false;
  bool _isEditingUnitCost = false;
  bool _isEditingUnitPrice = false;
  bool _isEditingMarkup = false;
  bool _isEditingMargin = false;
  bool _isCustomUnitMode = false;
  late TextEditingController marginController;
  DropZone _dropZone = DropZone.none;

  static const List<String> _standardUnits = [
    'ea',
    'hr',
    'day',
    'sqft',
    'sqm',
    'lnft',
    'cuft',
    'gal',
    'lb',
    'kg',
    'ton',
    'lot',
    'LS',
  ];

  // nameController, descriptionController, unitController, unitCostController,
  // unitPriceController, markupController provided by InlineRowEditMixin.

  bool get _canHaveChildren => widget.item.itemType == CatalogItemType.group;
  int get _descendantLeafCount {
    return widget.allItems
        .where((item) => _isDescendantOf(widget.item, item))
        .where((item) => item.itemType == CatalogItemType.item)
        .length;
  }

  bool get _hasRowBadges => _buildBadges().isNotEmpty;

  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);
  String get _currencySymbol => CurrencyUtils.getSymbol(_currencyCode);

  bool _isColumnVisible(String columnId) =>
      widget.visibleColumns.isEmpty || widget.visibleColumns.contains(columnId);

  @override
  void initState() {
    super.initState();
    initRowControllers(
      name: widget.item.name,
      description: widget.item.description ?? '',
      unit: widget.item.unit ?? '',
      unitCost: widget.item.unitCost,
      unitPrice: widget.item.unitPrice,
      markup: widget.item.markup,
    );
    marginController =
        TextEditingController(text: widget.item.margin.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(CatalogViewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.name != oldWidget.item.name && !_isEditingName) {
      nameController.text = widget.item.name;
    }
    if (widget.item.description != oldWidget.item.description &&
        !_isEditingDescription) {
      descriptionController.text = widget.item.description ?? '';
    }
    if (widget.item.unit != oldWidget.item.unit && !_isEditingUnit) {
      unitController.text = widget.item.unit ?? '';
    }
    if (widget.item.unitCost != oldWidget.item.unitCost &&
        !_isEditingUnitCost) {
      unitCostController.text = widget.item.unitCost.toStringAsFixed(2);
    }
    if (widget.item.unitPrice != oldWidget.item.unitPrice &&
        !_isEditingUnitPrice) {
      unitPriceController.text = widget.item.unitPrice.toStringAsFixed(2);
    }
    if (widget.item.markup != oldWidget.item.markup && !_isEditingMarkup) {
      markupController.text = widget.item.markup.toStringAsFixed(2);
    }
    if (widget.item.margin != oldWidget.item.margin && !_isEditingMargin) {
      marginController.text = widget.item.margin.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    marginController.dispose();
    disposeRowControllers();
    super.dispose();
  }

  bool _isDescendantOf(CatalogItem parent, CatalogItem potentialDescendant) {
    var currentParentId = potentialDescendant.parentId;
    var iterations = 0;
    while (currentParentId != null && iterations < 100) {
      iterations++;
      if (currentParentId == parent.id) return true;
      currentParentId = widget.itemsById[currentParentId]?.parentId;
    }
    return false;
  }

  DropZone _resolveDropZone(Offset globalOffset) {
    return computeDropZone(
      context,
      globalOffset,
      depth: widget.indentLevel,
      hasParent: widget.item.parentId != null,
      hasVisibleChildren: widget.hasChildren && widget.isExpanded,
    );
  }

  bool _canAcceptDrop(CatalogItem draggedItem, DropZone zone) {
    if (zone == DropZone.none) return false;
    if (draggedItem.id == widget.item.id) return false;
    if (_isDescendantOf(draggedItem, widget.item)) return false;
    if (zone == DropZone.child && !_canHaveChildren) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.item.itemType == CatalogItemType.group;
    final colorScheme = Theme.of(context).colorScheme;
    final hasDescription =
        widget.item.description != null &&
        widget.item.description!.trim().isNotEmpty;
    final useAutoRowHeight =
        hasDescription || _isEditingDescription || _hasRowBadges;

    Widget rowContent = HoverActionRow(
      builder: (isHovered) {
        Color rowColor = Colors.white;
        if (_dropZone == DropZone.child) {
          rowColor = AppColors.info.withValues(alpha: 0.14);
        } else if (_dropZone == DropZone.unparent) {
          rowColor = AppColors.warning.withValues(alpha: 0.10);
        } else if (isHovered) {
          rowColor = AppColors.background;
        } else if (widget.isSelected) {
          rowColor = colorScheme.primary.withValues(alpha: 0.10);
        } else if (isGroup && widget.indentLevel == 0) {
          rowColor = AppColors.background;
        }

        final accentColor = isGroup
            ? _groupAccentColors[widget.indentLevel.clamp(
                0,
                _groupAccentColors.length - 1,
              )]
            : null;

        final leftBorder =
            isGroup && widget.indentLevel == 0 && accentColor != null
            ? BorderSide(color: accentColor, width: 3)
            : BorderSide.none;
        final topBorder = _dropZone == DropZone.above
            ? const BorderSide(color: AppColors.info, width: 2)
            : BorderSide.none;
        final rightBorder = BorderSide(
          color: AppColors.cardBorder,
          width: 1,
        );
        final bottomBorder = _dropZone == DropZone.below
            ? const BorderSide(color: AppColors.info, width: 2)
            : BorderSide(
                color: AppColors.cardBorder,
                width: 1,
              );

        return TreeRowDropWrapper(
          dropZone: _dropZone,
          insertionGap: _dropInsertionGap,
          verticalGap: _rowVerticalGap,
          child: TreeRowContainer(
            color: rowColor,
            leftBorder: leftBorder,
            rightBorder: rightBorder,
            topBorder: topBorder,
            bottomBorder: bottomBorder,
            height: useAutoRowHeight ? null : 48,
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: useAutoRowHeight ? 8 : 0,
            ),
            child: Row(
              crossAxisAlignment: useAutoRowHeight
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  child: InlineCheckboxCell(
                    value: widget.isSelected,
                    onChanged: (value) =>
                        widget.onSelectionChanged?.call(widget.item, value),
                    enabled: widget.onSelectionChanged != null,
                  ),
                ),
                const SizedBox(width: 4),
                _buildNameColumn(isGroup, isHovered),
                if (!isGroup) ...[
                  if (_isColumnVisible('unit')) _buildUnitDropdown(),
                  if (_isColumnVisible('unitCost'))
                    _buildEditablePriceColumn(
                      width: _colW('unitCost', 120),
                      controller: unitCostController,
                      value: _formatCurrency(widget.item.unitCost),
                      onSave: _saveUnitCostEdit,
                      onCancel: _cancelUnitCostEdit,
                      isEditing: _isEditingUnitCost,
                      enterEdit: _enterUnitCostEditMode,
                    ),
                  if (_isColumnVisible('unitPrice'))
                    _buildEditablePriceColumn(
                      width: _colW('unitPrice', 120),
                      controller: unitPriceController,
                      value: _formatCurrency(widget.item.unitPrice),
                      onSave: _saveUnitPriceEdit,
                      onCancel: _cancelUnitPriceEdit,
                      isEditing: _isEditingUnitPrice,
                      enterEdit: _enterUnitPriceEditMode,
                    ),
                  if (_isColumnVisible('markup'))
                    _buildEditablePercentageColumn(
                      width: _colW('markup', 100),
                      controller: markupController,
                      value: widget.item.formattedMarkup,
                      onSave: _saveMarkupEdit,
                      onCancel: _cancelMarkupEdit,
                      isEditing: _isEditingMarkup,
                      enterEdit: _enterMarkupEditMode,
                    ),
                  if (_isColumnVisible('margin'))
                    _buildEditablePercentageColumn(
                      width: _colW('margin', 100),
                      controller: marginController,
                      value: widget.item.formattedMargin,
                      onSave: _saveMarginEdit,
                      onCancel: _cancelMarginEdit,
                      isEditing: _isEditingMargin,
                      enterEdit: _enterMarginEditMode,
                    ),
                  if (_isColumnVisible('taxable')) _buildTaxableColumn(),
                  if (_isColumnVisible('sku'))
                    _buildReadOnlyColumn(widget.item.sku,
                        width: _colW('sku', 140)),
                  if (_isColumnVisible('category'))
                    _buildReadOnlyColumn(widget.item.category,
                        width: _colW('category', 160)),
                ] else ...[
                  if (_isColumnVisible('unit'))
                    _buildDashColumn(_colW('unit', 80)),
                  if (_isColumnVisible('unitCost'))
                    _buildDashColumn(_colW('unitCost', 120)),
                  if (_isColumnVisible('unitPrice'))
                    _buildDashColumn(_colW('unitPrice', 120)),
                  if (_isColumnVisible('markup'))
                    _buildDashColumn(_colW('markup', 100)),
                  if (_isColumnVisible('margin'))
                    _buildDashColumn(_colW('margin', 100)),
                  if (_isColumnVisible('taxable'))
                    _buildDashColumn(_colW('taxable', 80)),
                  if (_isColumnVisible('sku'))
                    _buildDashColumn(_colW('sku', 140)),
                  if (_isColumnVisible('category'))
                    _buildDashColumn(_colW('category', 160)),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (widget.onItemDropped == null) {
      return RepaintBoundary(child: rowContent);
    }

    final dragFeedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 340,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.info, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator, size: 18, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.item.name.isEmpty ? 'Untitled group' : widget.item.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: DragTarget<CatalogItem>(
        onWillAcceptWithDetails: (details) {
          final zone = _resolveDropZone(details.offset);
          return _canAcceptDrop(details.data, zone);
        },
        onMove: (details) {
          final nextZone = _resolveDropZone(details.offset);
          final acceptedZone = _canAcceptDrop(details.data, nextZone)
              ? nextZone
              : DropZone.none;
          if (acceptedZone != _dropZone) {
            setState(() => _dropZone = acceptedZone);
          }
        },
        onLeave: (_) {
          if (_dropZone != DropZone.none) {
            setState(() => _dropZone = DropZone.none);
          }
        },
        onAcceptWithDetails: (details) {
          final zone = _dropZone == DropZone.none
              ? _resolveDropZone(details.offset)
              : _dropZone;
          setState(() => _dropZone = DropZone.none);
          if (_canAcceptDrop(details.data, zone)) {
            widget.onItemDropped?.call(details.data, widget.item, zone);
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isMobile = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android);
          if (isMobile) {
            return LongPressDraggable<CatalogItem>(
              data: widget.item,
              feedback: dragFeedback,
              childWhenDragging: Opacity(opacity: 0.35, child: rowContent),
              hapticFeedbackOnStart: true,
              child: rowContent,
            );
          }
          return Draggable<CatalogItem>(
            data: widget.item,
            feedback: dragFeedback,
            childWhenDragging: Opacity(opacity: 0.35, child: rowContent),
            child: rowContent,
          );
        },
      ),
    );
  }

  Widget _buildNameColumn(bool isGroup, bool isHovered) {
    final hasDescription =
        widget.item.description != null && widget.item.description!.isNotEmpty;
    final showActions = isHovered && !_isEditingName && !_isEditingDescription;

    return Expanded(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...buildTreeGuides(
              depth: widget.indentLevel,
              treeGuides: widget.treeGuides,
              isLastChild: widget.isLastChild,
              colorScheme: Theme.of(context).colorScheme,
              cellHeight: null,
            ),
            ...buildTreeChevron(
              hasChildren: widget.hasChildren,
              isExpanded: widget.isExpanded,
              depth: widget.indentLevel,
              onToggle: widget.onExpandToggle,
            ),
            if (_canHaveChildren && widget.onAddItem != null)
              _buildAddChildButton()
            else
              const SizedBox(width: 4),
            const SizedBox(width: 4),
            Flexible(
              child: _isEditingName
                  ? _buildNameEditField()
                  : Row(
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildNameDisplay(isGroup),
                              if (hasDescription ||
                                  _isEditingDescription ||
                                  (isHovered && !_isEditingName))
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: _isEditingDescription
                                      ? _buildDescriptionEditField()
                                      : MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: _enterDescriptionEditMode,
                                            child: hasDescription
                                                ? Text(
                                                    widget.item.description!,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors
                                                          .textTertiary,
                                                      height: 1.3,
                                                    ),
                                                    softWrap: true,
                                                  )
                                                : Text(
                                                    '+ Add description',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors
                                                          .textTertiary
                                                          .withValues(
                                                            alpha: 0.5,
                                                          ),
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ),
                        if (showActions) ...[
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              onPressed: () =>
                                  widget.onEditItem?.call(widget.item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: 'Edit details',
                              color: AppColors.textSecondary,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: _buildMoreMenu(isGroup),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenu(bool isGroup) {
    final childLevel = widget.item.hierarchyLevel + 1;
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AppColors.textTertiary,
      ),
      padding: EdgeInsets.zero,
      iconSize: 18,
      offset: const Offset(0, 32),
      itemBuilder: (_) => [
        if (widget.onMoveDown != null)
          PopupMenuItem(
            value: 'move_down',
            enabled: widget.canMoveDown,
            child: Row(
              children: [
                Icon(
                  Icons.arrow_downward,
                  size: 16,
                  color: widget.canMoveDown ? null : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Move down',
                  style: widget.canMoveDown
                      ? null
                      : TextStyle(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        if (widget.onMoveDown != null &&
            (isGroup || widget.onDeleteItem != null))
          const PopupMenuDivider(),
        if (widget.onDuplicateItem != null)
          const PopupMenuItem(
            value: 'duplicate',
            child: Row(
              children: [
                Icon(Icons.copy_outlined, size: 16),
                SizedBox(width: 8),
                Text('Duplicate'),
              ],
            ),
          ),
        if (isGroup && widget.onAddItem != null) ...[
          const PopupMenuItem(
            value: 'add_item',
            child: Row(
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 8),
                Text('Add Item'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'add_group',
            child: Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 16),
                SizedBox(width: 8),
                Text('Add Group'),
              ],
            ),
          ),
        ],
        if (widget.onDeleteItem != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        ],
      ],
      onSelected: (value) {
        switch (value) {
          case 'move_down':
            widget.onMoveDown?.call();
          case 'duplicate':
            widget.onDuplicateItem?.call(widget.item);
          case 'add_item':
            if (!widget.isExpanded && widget.onExpandToggle != null) {
              widget.onExpandToggle!();
            }
            widget.onAddItem?.call(widget.item.id, childLevel, isGroup: false);
          case 'add_group':
            if (!widget.isExpanded && widget.onExpandToggle != null) {
              widget.onExpandToggle!();
            }
            widget.onAddItem?.call(widget.item.id, childLevel, isGroup: true);
          case 'delete':
            widget.onDeleteItem?.call(widget.item);
        }
      },
    );
  }

  Widget _buildAddChildButton() {
    final childLevel = widget.item.hierarchyLevel + 1;

    return TreeRowAddButton(
      isExpanded: widget.isExpanded,
      onEnsureExpanded: widget.onExpandToggle,
      onAddItem: () =>
          widget.onAddItem?.call(widget.item.id, childLevel, isGroup: false),
      onAddGroup: () =>
          widget.onAddItem?.call(widget.item.id, childLevel, isGroup: true),
    );
  }

  Widget _buildNameDisplay(bool isGroup) {
    final rawName = widget.item.name.trim();
    final name = rawName.isEmpty && isGroup
        ? 'Untitled group'
        : widget.item.name;
    final effectiveName = name.trim().isEmpty ? 'Untitled item' : name;
    final style = TextStyle(
      fontWeight: isGroup ? FontWeight.w700 : FontWeight.normal,
      fontSize: isGroup ? 15 : 14,
      fontStyle: rawName.isEmpty ? FontStyle.italic : FontStyle.normal,
      color: rawName.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
    );

    Widget label;
    if (widget.searchQuery.isNotEmpty &&
        effectiveName.toLowerCase().contains(widget.searchQuery)) {
      final lower = effectiveName.toLowerCase();
      final start = lower.indexOf(widget.searchQuery);
      final end = start + widget.searchQuery.length;
      label = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: effectiveName.substring(0, start)),
            TextSpan(
              text: effectiveName.substring(start, end),
              style: TextStyle(
                backgroundColor: Colors.yellow.shade200,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: effectiveName.substring(end)),
          ],
          style: style,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      label = Text(
        effectiveName,
        style: style,
        overflow: TextOverflow.ellipsis,
      );
    }

    final badges = _buildBadges();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: _enterNameEditMode, child: label),
        ),
        if (badges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: badges),
          ),
      ],
    );
  }

  List<Widget> _buildBadges() {
    final badges = <Widget>[];
    final isGroup = widget.item.itemType == CatalogItemType.group;

    if (isGroup) {
      final label = _descendantLeafCount == 0
          ? 'Empty group'
          : '$_descendantLeafCount item${_descendantLeafCount == 1 ? '' : 's'}';
      badges.add(
        _CatalogBadge(
          label: label,
          backgroundColor: AppColors.info.withValues(alpha: 0.12),
          foregroundColor: AppColors.infoDark,
        ),
      );
    }

    return badges;
  }

  Widget _buildNameEditField() {
    return InlineEditCell(
      value: widget.item.name,
      onSave: (_) => _saveNameEdit(),
      onCancel: _cancelNameEdit,
      required: true,
      controller: nameController,
      isEditing: true,
      editBorderColor: AppColors.info,
      editStyle: TextStyle(
        fontWeight: widget.item.hierarchyLevel == 0
            ? FontWeight.w700
            : FontWeight.normal,
        fontSize: widget.item.hierarchyLevel == 0 ? 15 : 14,
      ),
      onEditStateChanged: (isEditing) {
        if (!isEditing && _isEditingName) {
          setState(() => _isEditingName = false);
        }
      },
    );
  }

  Widget _buildDescriptionEditField() {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final isSelectAllShortcut =
            event.logicalKey == LogicalKeyboardKey.keyA &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed);
        if (isSelectAllShortcut) {
          selectAllText(descriptionController);
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelDescriptionEdit();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.infoDark, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
        child: TextField(
          controller: descriptionController,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 12, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Add a description...',
            hintStyle: TextStyle(color: AppColors.textTertiary),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTapOutside: (_) => _saveDescriptionEdit(),
        ),
      ),
    );
  }

  Widget _buildEditablePriceColumn({
    required double width,
    required TextEditingController controller,
    required String value,
    required VoidCallback onSave,
    required VoidCallback onCancel,
    required bool isEditing,
    required VoidCallback enterEdit,
  }) {
    return SizedBox(
      width: width,
      child: InlineEditCell(
        value: value,
        onSave: (_) => onSave(),
        onCancel: onCancel,
        cellType: InlineEditCellType.currency,
        currencySymbol: _currencySymbol,
        controller: controller,
        isEditing: isEditing,
        onEnterEdit: enterEdit,
        editBorderColor: AppColors.info,
      ),
    );
  }

  Widget _buildEditablePercentageColumn({
    required double width,
    required TextEditingController controller,
    required String value,
    required VoidCallback onSave,
    required VoidCallback onCancel,
    required bool isEditing,
    required VoidCallback enterEdit,
  }) {
    return SizedBox(
      width: width,
      child: InlineEditCell(
        value: value,
        onSave: (_) => onSave(),
        onCancel: onCancel,
        cellType: InlineEditCellType.percentage,
        controller: controller,
        isEditing: isEditing,
        onEnterEdit: enterEdit,
        editBorderColor: AppColors.info,
      ),
    );
  }

  Widget _buildUnitDropdown() {
    final unitWidth = _colW('unit', 80);
    final currentUnit = widget.item.unit ?? '';

    if (_isEditingUnit || _isCustomUnitMode) {
      return SizedBox(
        width: unitWidth,
        child: InlineEditFrame(
          borderColor: AppColors.info,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          child: TextField(
            controller: unitController,
            autofocus: true,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'Unit',
            ),
            onSubmitted: (_) => _saveUnitEdit(),
            onTapOutside: (_) => _cancelUnitEdit(),
          ),
        ),
      );
    }

    return SizedBox(
      width: unitWidth,
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == '_custom_') {
            setState(() {
              _isCustomUnitMode = true;
              _isEditingUnit = true;
              unitController.text = currentUnit;
              selectAllText(unitController);
            });
          } else if (value != currentUnit) {
            widget.onItemChanged?.call(
              widget.item.copyWith(
                unit: value.isEmpty ? null : value,
                updatedAt: DateTime.now(),
              ),
            );
          }
        },
        tooltip: 'Select unit',
        offset: const Offset(0, 36),
        itemBuilder: (context) => [
          ..._standardUnits.map(
            (unit) => PopupMenuItem<String>(
              value: unit,
              child: Row(
                children: [
                  if (unit == currentUnit)
                    Icon(Icons.check, size: 16, color: AppColors.info)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(unit),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: '_custom_',
            child: Row(
              children: [
                Icon(Icons.edit, size: 16, color: AppColors.textTertiary),
                SizedBox(width: 8),
                Text('Custom...'),
              ],
            ),
          ),
        ],
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  currentUnit.isEmpty ? '-' : currentUnit,
                  style: TextStyle(
                    color: currentUnit.isEmpty
                        ? AppColors.textTertiary
                        : AppColors.infoDark,
                    decoration: currentUnit.isEmpty
                        ? TextDecoration.none
                        : TextDecoration.underline,
                    decorationColor: AppColors.infoDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: AppColors.infoDark),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildTaxableColumn() {
    return SizedBox(
      width: _colW('taxable', 80),
      child: InlineCheckboxCell(
        value: widget.item.isTaxable,
        onChanged: _toggleTaxable,
      ),
    );
  }

  Widget _buildReadOnlyColumn(String? value, {required double width}) {
    return TableTextCell(
      width: width,
      text: value,
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
    );
  }

  Widget _buildDashColumn(double width) {
    return TableTextCell(width: width);
  }

  void _enterNameEditMode() {
    setState(() {
      _isEditingName = true;
      nameController.text = widget.item.name;
      selectAllText(nameController);
    });
  }

  void _saveNameEdit() {
    final trimmedValue = nameController.text.trim();
    if (trimmedValue != widget.item.name) {
      widget.onItemChanged?.call(
        widget.item.copyWith(name: trimmedValue, updatedAt: DateTime.now()),
      );
    }
    setState(() => _isEditingName = false);
  }

  void _cancelNameEdit() {
    setState(() {
      _isEditingName = false;
      nameController.text = widget.item.name;
    });
  }

  void _enterDescriptionEditMode() {
    setState(() {
      _isEditingDescription = true;
      descriptionController.text = widget.item.description ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      descriptionController.selection = TextSelection.collapsed(
        offset: descriptionController.text.length,
      );
    });
  }

  void _saveDescriptionEdit() {
    if (!_isEditingDescription) return;
    final trimmed = descriptionController.text.trim();
    final current = widget.item.description?.trim() ?? '';
    if (trimmed != current) {
      widget.onItemChanged?.call(
        widget.item.copyWith(
          description: trimmed.isEmpty ? null : trimmed,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingDescription = false);
  }

  void _cancelDescriptionEdit() {
    setState(() {
      _isEditingDescription = false;
      descriptionController.text = widget.item.description ?? '';
    });
  }

  void _saveUnitEdit() {
    final value = unitController.text.trim();
    if (value != (widget.item.unit ?? '')) {
      widget.onItemChanged?.call(
        widget.item.copyWith(
          unit: value.isEmpty ? null : value,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() {
      _isEditingUnit = false;
      _isCustomUnitMode = false;
    });
  }

  void _cancelUnitEdit() {
    setState(() {
      _isEditingUnit = false;
      _isCustomUnitMode = false;
    });
  }

  void _enterUnitCostEditMode() {
    setState(() {
      _isEditingUnitCost = true;
      unitCostController.text = widget.item.unitCost.toStringAsFixed(2);
      selectAllText(unitCostController);
    });
  }

  void _saveUnitCostEdit() {
    final value = double.tryParse(unitCostController.text);
    if (value != null && value >= 0 && value != widget.item.unitCost) {
      final newUnitPrice = CatalogItem.calculatePriceFromMarkup(
        value,
        widget.item.markup,
      );
      final newMargin = CatalogItem.calculateMargin(value, newUnitPrice);
      widget.onItemChanged?.call(
        widget.item.copyWith(
          unitCost: value,
          unitPrice: newUnitPrice,
          margin: newMargin,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingUnitCost = false);
  }

  void _cancelUnitCostEdit() => setState(() => _isEditingUnitCost = false);

  void _enterUnitPriceEditMode() {
    setState(() {
      _isEditingUnitPrice = true;
      unitPriceController.text = widget.item.unitPrice.toStringAsFixed(2);
      selectAllText(unitPriceController);
    });
  }

  void _saveUnitPriceEdit() {
    final value = double.tryParse(unitPriceController.text);
    if (value != null && value >= 0 && value != widget.item.unitPrice) {
      final newMarkup = CatalogItem.calculateMarkup(
        widget.item.unitCost,
        value,
      );
      final newMargin = CatalogItem.calculateMargin(
        widget.item.unitCost,
        value,
      );
      widget.onItemChanged?.call(
        widget.item.copyWith(
          unitPrice: value,
          markup: newMarkup,
          margin: newMargin,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingUnitPrice = false);
  }

  void _cancelUnitPriceEdit() => setState(() => _isEditingUnitPrice = false);

  void _enterMarkupEditMode() {
    setState(() {
      _isEditingMarkup = true;
      markupController.text = widget.item.markup.toStringAsFixed(2);
      selectAllText(markupController);
    });
  }

  void _saveMarkupEdit() {
    final value = double.tryParse(markupController.text);
    if (value != null && value >= -100 && value != widget.item.markup) {
      final newUnitPrice = CatalogItem.calculatePriceFromMarkup(
        widget.item.unitCost,
        value,
      );
      final newMargin = CatalogItem.calculateMargin(
        widget.item.unitCost,
        newUnitPrice,
      );
      widget.onItemChanged?.call(
        widget.item.copyWith(
          markup: value,
          unitPrice: newUnitPrice,
          margin: newMargin,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingMarkup = false);
  }

  void _cancelMarkupEdit() => setState(() => _isEditingMarkup = false);

  void _enterMarginEditMode() {
    setState(() {
      _isEditingMargin = true;
      marginController.text = widget.item.margin.toStringAsFixed(2);
      selectAllText(marginController);
    });
  }

  void _saveMarginEdit() {
    final value = double.tryParse(marginController.text);
    if (value != null && value < 100 && value != widget.item.margin) {
      final newUnitPrice = CatalogItem.calculatePriceFromMargin(
        widget.item.unitCost,
        value,
      );
      final newMarkup = CatalogItem.calculateMarkup(
        widget.item.unitCost,
        newUnitPrice,
      );
      widget.onItemChanged?.call(
        widget.item.copyWith(
          margin: value,
          unitPrice: newUnitPrice,
          markup: newMarkup,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingMargin = false);
  }

  void _cancelMarginEdit() => setState(() => _isEditingMargin = false);

  void _toggleTaxable(bool value) {
    widget.onItemChanged?.call(
      widget.item.copyWith(isTaxable: value, updatedAt: DateTime.now()),
    );
  }
}

class _CatalogBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _CatalogBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
