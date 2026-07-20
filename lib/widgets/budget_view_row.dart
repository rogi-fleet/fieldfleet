import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/budget_item.dart';
import '../theme/theme.dart';
import '../providers/workspace_provider.dart';
import '../services/supabase/budget_service.dart' show BudgetItemDocumentStatus;
import '../models/budget_item_labor_summary.dart';
import '../utils/currency_utils.dart';
import '../utils/pricing_math.dart';
import 'budget_document_status_indicator.dart';
import 'table/composition_badges.dart';
import 'table/conditional_value_text.dart';
import 'table/cost_type_dot.dart';
import 'table/editable_field_registry.dart';
import 'table/hover_action_row.dart';
import 'table/inline_checkbox_cell.dart';
import 'table/inline_edit_cell.dart';
import 'table/table_text_cell.dart';
import 'table/tree_line_painter.dart';
import 'table/tree_drop_zone.dart';
import 'table/tree_row_container.dart';
import 'table/tree_row_chevron.dart';
import 'table/tree_row_add_button.dart';
import 'table/tree_row_drop_wrapper.dart';
import 'table/inline_row_edit_mixin.dart';
import '../screens/projects/budget_view_screen.dart';
import '../utils/text_selection_utils.dart';

/// A dedicated row widget for the budget view with inline editing.
/// Modeled after UnifiedGanttRow for consistent UX.
class BudgetViewRow extends StatefulWidget {
  final BudgetItem item;
  final String lineItemId;
  final List<BudgetItem> allItems;
  final bool hasChildren;
  final BudgetViewMode viewMode;
  final double lineItemColumnWidth;
  final int indentLevel;
  final bool isExpanded;
  final bool isSelected;

  /// Visual position among leaf items (used for alternating row colors).
  /// Groups should pass 0 — they use their own background.
  final int visualIndex;
  final List<bool> treeGuides;
  final bool isLastChild;
  final String searchQuery;
  final double actualCost;
  final double invoicedAmount;
  final String progressText;
  final BudgetItemDocumentStatus? documentStatus;
  final VoidCallback? onDocumentStatusTap;
  final BudgetItemLaborSummary? laborSummary;
  final String? changeOrderStatusText;
  final BudgetPricingInputMode pricingInputMode;
  final bool isTasksExpanded;
  final VoidCallback? onTasksExpandToggle;
  final Set<String> visibleColumns;
  final Map<String, double> columnWidths;
  final VoidCallback? onExpandToggle;
  final Function(BudgetItem, bool)? onSelectionChanged;
  final Function(BudgetItem)? onItemChanged;
  final Function(String? parentId, int hierarchyLevel, {required bool isGroup})?
  onAddItem;
  final Function(BudgetItem)? onEditItem;
  final Function(BudgetItem)? onDeleteItem;
  final Function(BudgetItem)? onUngroupItem;
  final Function(BudgetItem)? onDuplicateItem;
  final Function(BudgetItem)? onGroupItem;
  final Function(BudgetItem)? onSaveAsTemplate;
  final Function(BudgetItem)? onSaveToCatalog;
  final Function(BudgetItem, String?)? onItemParentChanged;
  final void Function(BudgetItem dragged, BudgetItem target, DropZone zone)?
  onItemDropped;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  const BudgetViewRow({
    super.key,
    required this.item,
    required this.lineItemId,
    required this.allItems,
    this.hasChildren = false,
    required this.viewMode,
    this.lineItemColumnWidth = 36,
    required this.indentLevel,
    required this.isExpanded,
    required this.isSelected,
    this.visualIndex = 0,
    this.treeGuides = const [],
    this.isLastChild = true,
    this.searchQuery = '',
    this.actualCost = 0.0,
    this.invoicedAmount = 0.0,
    this.progressText = '',
    this.documentStatus,
    this.onDocumentStatusTap,
    this.laborSummary,
    this.changeOrderStatusText,
    this.pricingInputMode = BudgetPricingInputMode.markup,
    this.isTasksExpanded = false,
    this.onTasksExpandToggle,
    this.visibleColumns = const {},
    this.columnWidths = const {},
    this.onExpandToggle,
    this.onSelectionChanged,
    this.onItemChanged,
    this.onAddItem,
    this.onEditItem,
    this.onDeleteItem,
    this.onUngroupItem,
    this.onDuplicateItem,
    this.onGroupItem,
    this.onSaveAsTemplate,
    this.onSaveToCatalog,
    this.onItemParentChanged,
    this.onItemDropped,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onDragStarted,
    this.onDragEnded,
  });

  @override
  State<BudgetViewRow> createState() => _BudgetViewRowState();
}

class _BudgetViewRowState extends State<BudgetViewRow>
    with InlineRowEditMixin {
  static const double _dropInsertionGap = 36;
  static const double _rowVerticalGap = 0;

  double _colW(String id, double defaultWidth) =>
      widget.columnWidths[id] ?? defaultWidth;
  bool _isHovered = false;
  DropZone _dropZone = DropZone.none;
  bool _isEditingName = false;
  bool _isEditingDescription = false;
  bool _isEditingQty = false;
  bool _isEditingUnit = false;
  bool _isEditingUnitCost = false;
  bool _isEditingUnitPrice = false;
  bool _isEditingProfit = false;
  bool _isEditingMargin = false;
  bool _isEditingMarkup = false;
  bool _isCustomUnitMode = false; // For custom unit text entry

  // Snapshot of the item taken before the first field in an edit session is
  // opened. Escape from any field reverts to this, undoing Tab-saved changes.
  BudgetItem? _editSnapshot;

  bool get _isAnyFieldEditing =>
      _isEditingName ||
      _isEditingQty ||
      _isEditingUnitCost ||
      _isEditingUnitPrice ||
      _isEditingProfit ||
      _isEditingMargin ||
      _isEditingMarkup;

  void _revertToSnapshot() {
    final snap = _editSnapshot;
    _editSnapshot = null;
    if (snap != null && snap.updatedAt != widget.item.updatedAt) {
      widget.onItemChanged?.call(snap);
    }
  }

  // Standard construction units
  static const List<String> _standardUnits = [
    'ea', // each
    'hr', // hour
    'day', // day
    'sqft', // square feet
    'sqm', // square meter
    'lnft', // linear feet
    'cuft', // cubic feet
    'gal', // gallon
    'lb', // pound
    'kg', // kilogram
    'ton', // ton
    'lot', // lot/lump sum
    'LS', // lump sum
  ];

  // nameController, descriptionController, unitController, unitCostController,
  // unitPriceController, markupController provided by InlineRowEditMixin.

  // Budget-specific controllers:
  late TextEditingController _qtyController;
  late TextEditingController _approvedPriceController;
  late TextEditingController _projectedCostController;
  late TextEditingController _profitController;
  late TextEditingController _marginController;

  // Focus nodes for keyboard navigation
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _unitCostFocus = FocusNode();
  final FocusNode _unitPriceFocus = FocusNode();
  final FocusNode _markupFocus = FocusNode();

  // Ordered list of editable fields for Tab navigation
  EditableFieldRegistry get _fieldRegistry => EditableFieldRegistry([
    EditableFieldEntry(
      id: 'name',
      isEditing: () => _isEditingName,
      enter: _enterNameEditMode,
      save: _saveNameEdit,
      cancel: _cancelNameEdit,
    ),
    EditableFieldEntry(
      id: 'qty',
      isEditing: () => _isEditingQty,
      enter: _enterQtyEditMode,
      save: _saveQtyEdit,
      cancel: _cancelQtyEdit,
    ),
    EditableFieldEntry(
      id: 'unitCost',
      isEditing: () => _isEditingUnitCost,
      enter: _enterUnitCostEditMode,
      save: _saveUnitCostEdit,
      cancel: _cancelUnitCostEdit,
    ),
    EditableFieldEntry(
      id: 'unitPrice',
      isEditing: () => _isEditingUnitPrice,
      enter: _enterUnitPriceEditMode,
      save: _saveUnitPriceEdit,
      cancel: _cancelUnitPriceEdit,
    ),
    EditableFieldEntry(
      id: 'profit',
      isEditing: () => _isEditingProfit,
      enter: _enterProfitEditMode,
      save: _saveProfitEdit,
      cancel: _cancelProfitEdit,
    ),
    EditableFieldEntry(
      id: 'margin',
      isEditing: () => _isEditingMargin,
      enter: _enterMarginEditMode,
      save: _saveMarginEdit,
      cancel: _cancelMarginEdit,
    ),
    EditableFieldEntry(
      id: 'markup',
      isEditing: () => _isEditingMarkup,
      enter: _enterMarkupEditMode,
      save: _saveMarkupEdit,
      cancel: _cancelMarkupEdit,
    ),
  ]);

  void _selectAllText(TextEditingController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      selectAllText(controller);
    });
  }

  void _handleFieldKeyEvent(KeyEvent event, String fieldId) {
    _fieldRegistry.handleKeyEvent(event, fieldId);
  }

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
      markupFormat: (v) => v.toStringAsFixed(1),
    );
    _qtyController = TextEditingController(
      text: widget.item.quantity.toString(),
    );
    _approvedPriceController = TextEditingController(
      text: widget.item.approvedPrice.toStringAsFixed(2),
    );
    _projectedCostController = TextEditingController(
      text: widget.item.projectedCost.toStringAsFixed(2),
    );
    _profitController = TextEditingController(
      text: widget.item.projectedProfit.toStringAsFixed(2),
    );
    _marginController = TextEditingController(
      text: widget.item.projectedMargin.toStringAsFixed(1),
    );
    _marginController.addListener(_handlePricingFieldTextChanged);
    markupController.addListener(_handlePricingFieldTextChanged);
  }

  @override
  void didUpdateWidget(BudgetViewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers if item changed externally
    if (widget.item.name != oldWidget.item.name && !_isEditingName) {
      nameController.text = widget.item.name;
    }
    if (widget.item.description != oldWidget.item.description &&
        !_isEditingDescription) {
      descriptionController.text = widget.item.description ?? '';
    }
    if (widget.item.quantity != oldWidget.item.quantity && !_isEditingQty) {
      _qtyController.text = widget.item.quantity.toString();
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
      markupController.text = widget.item.markup.toStringAsFixed(1);
    }
    if ((widget.item.unitCost != oldWidget.item.unitCost ||
            widget.item.unitPrice != oldWidget.item.unitPrice) &&
        !_isEditingMargin) {
      _marginController.text = widget.item.projectedMargin.toStringAsFixed(1);
    }
    if ((widget.item.approvedPrice != oldWidget.item.approvedPrice ||
            widget.item.projectedCost != oldWidget.item.projectedCost) &&
        !_isEditingProfit) {
      _profitController.text = widget.item.projectedProfit.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    disposeRowControllers();
    _qtyController.dispose();
    _approvedPriceController.dispose();
    _projectedCostController.dispose();
    _profitController.dispose();
    _marginController.dispose();
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    _qtyFocus.dispose();
    _unitCostFocus.dispose();
    _unitPriceFocus.dispose();
    _markupFocus.dispose();
    super.dispose();
  }

  void _handlePricingFieldTextChanged() {
    if (!mounted) return;
    if (_isEditingMarkup || _isEditingMargin) {
      setState(() {});
    }
  }

  bool get _hasChildren => widget.hasChildren;
  // Groups can contain children (groups or items)
  bool get _canHaveChildren => widget.item.itemType == BudgetItemType.group;

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);
  String get _currencySymbol => CurrencyUtils.getSymbol(_currencyCode);

  // Column visibility helper
  bool _isColumnVisible(String columnId) =>
      widget.visibleColumns.isEmpty || widget.visibleColumns.contains(columnId);

  // Helper to check if an item is a descendant of another (prevents circular drops)
  bool _isDescendantOf(BudgetItem parent, BudgetItem potentialDescendant) {
    int iterations = 0;
    String? currentParentId = potentialDescendant.parentId;
    while (currentParentId != null) {
      iterations++;
      if (iterations > 100) break; // Safety limit
      if (currentParentId == parent.id) return true;
      final parentItem = widget.allItems.firstWhere(
        (i) => i.id == currentParentId,
        orElse: () => widget.item,
      );
      if (parentItem.id != currentParentId) break;
      currentParentId = parentItem.parentId;
    }
    return false;
  }

  // Group accent colors by hierarchy level
  static final _groupAccentColors = [
    Colors.indigo,
    AppColors.financialAccent,
    AppColors.warning,
  ];

  void _showContextMenu(BuildContext context, Offset position) {
    final isGroup = widget.item.itemType == BudgetItemType.group;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (widget.onEditItem != null)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined, size: 18),
              title: Text('Edit'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onDuplicateItem != null)
          const PopupMenuItem(
            value: 'duplicate',
            child: ListTile(
              leading: Icon(Icons.copy_outlined, size: 18),
              title: Text('Duplicate'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (!isGroup && widget.onGroupItem != null)
          const PopupMenuItem(
            value: 'group',
            child: ListTile(
              leading: Icon(Icons.folder_outlined, size: 18),
              title: Text('Group'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onSaveAsTemplate != null)
          const PopupMenuItem(
            value: 'save_template',
            child: ListTile(
              leading: Icon(Icons.save_outlined, size: 18),
              title: Text('Save as Template'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onSaveToCatalog != null)
          const PopupMenuItem(
            value: 'save_catalog',
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined, size: 18),
              title: Text('Save to Catalog'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (isGroup && widget.onUngroupItem != null)
          const PopupMenuItem(
            value: 'ungroup',
            child: ListTile(
              leading: Icon(Icons.format_indent_decrease, size: 18),
              title: Text('Ungroup'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onDeleteItem != null)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.error,
              ),
              title: const Text('Delete'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          widget.onEditItem?.call(widget.item);
        case 'duplicate':
          widget.onDuplicateItem?.call(widget.item);
        case 'group':
          widget.onGroupItem?.call(widget.item);
        case 'save_template':
          widget.onSaveAsTemplate?.call(widget.item);
        case 'save_catalog':
          widget.onSaveToCatalog?.call(widget.item);
        case 'ungroup':
          widget.onUngroupItem?.call(widget.item);
        case 'delete':
          widget.onDeleteItem?.call(widget.item);
      }
    });
  }

  Widget _buildMoreMenu(bool isGroup) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert,
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
        if (widget.onMoveDown != null)
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
        if (!isGroup && widget.onGroupItem != null)
          const PopupMenuItem(
            value: 'group',
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16),
                SizedBox(width: 8),
                Text('Group'),
              ],
            ),
          ),
        if (isGroup && widget.onUngroupItem != null)
          const PopupMenuItem(
            value: 'ungroup',
            child: Row(
              children: [
                Icon(Icons.format_indent_decrease, size: 16),
                SizedBox(width: 8),
                Text('Ungroup'),
              ],
            ),
          ),
        if (widget.onSaveAsTemplate != null)
          const PopupMenuItem(
            value: 'save_template',
            child: Row(
              children: [
                Icon(Icons.save_outlined, size: 16),
                SizedBox(width: 8),
                Text('Save as Template'),
              ],
            ),
          ),
        if (widget.onSaveToCatalog != null)
          const PopupMenuItem(
            value: 'save_catalog',
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 16),
                SizedBox(width: 8),
                Text('Save to Catalog'),
              ],
            ),
          ),
        if (widget.item.sourceType == BudgetItemSource.upgrade &&
            !isGroup &&
            widget.onItemChanged != null) ...[
          const PopupMenuDivider(),
          if (widget.item.upgradeStatus != UpgradeStatus.accepted)
            const PopupMenuItem(
              value: 'upgrade_accept',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16),
                  SizedBox(width: 8),
                  Text('Mark as Accepted'),
                ],
              ),
            ),
          if (widget.item.upgradeStatus != UpgradeStatus.declined)
            const PopupMenuItem(
              value: 'upgrade_decline',
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, size: 16),
                  SizedBox(width: 8),
                  Text('Mark as Declined'),
                ],
              ),
            ),
          if (widget.item.upgradeStatus != UpgradeStatus.offered)
            const PopupMenuItem(
              value: 'upgrade_reset',
              child: Row(
                children: [
                  Icon(Icons.undo, size: 16),
                  SizedBox(width: 8),
                  Text('Reset to Offered'),
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
          case 'group':
            widget.onGroupItem?.call(widget.item);
          case 'save_template':
            widget.onSaveAsTemplate?.call(widget.item);
          case 'save_catalog':
            widget.onSaveToCatalog?.call(widget.item);
          case 'ungroup':
            widget.onUngroupItem?.call(widget.item);
          case 'upgrade_accept':
            widget.onItemChanged?.call(
              widget.item.copyWith(
                upgradeStatus: UpgradeStatus.accepted,
                updatedAt: DateTime.now(),
              ),
            );
          case 'upgrade_decline':
            widget.onItemChanged?.call(
              widget.item.copyWith(
                upgradeStatus: UpgradeStatus.declined,
                updatedAt: DateTime.now(),
              ),
            );
          case 'upgrade_reset':
            widget.onItemChanged?.call(
              widget.item.copyWith(
                upgradeStatus: UpgradeStatus.offered,
                updatedAt: DateTime.now(),
              ),
            );
          case 'delete':
            widget.onDeleteItem?.call(widget.item);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.item.itemType == BudgetItemType.group;
    final colorScheme = Theme.of(context).colorScheme;
    final hasVisibleDescription =
        (widget.item.description?.trim().isNotEmpty ?? false) &&
        widget.viewMode != BudgetViewMode.invoicing;
    final useAutoRowHeight = _isEditingDescription || hasVisibleDescription;

    // Step 1: base color (alternating for items, fixed for groups)
    Color rowColor;
    if (isGroup && widget.indentLevel == 0) {
      rowColor = AppColors.background;
    } else if (!isGroup && widget.visualIndex.isOdd) {
      rowColor = AppColors.surfaceAlt;
    } else {
      rowColor = Colors.white;
    }

    // Step 2: overlay interactive state on top of base
    if (_dropZone == DropZone.child) {
      rowColor = AppColors.info.withValues(alpha: 0.15);
    } else if (_dropZone == DropZone.unparent) {
      rowColor = AppColors.warning.withValues(alpha: 0.10);
    } else if (widget.isSelected && _isHovered) {
      rowColor = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.12),
        rowColor,
      );
    } else if (widget.isSelected) {
      rowColor = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.08),
        rowColor,
      );
    } else if (_isHovered) {
      rowColor = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.04),
        rowColor,
      );
    }

    // Group accent color
    final accentColor = isGroup
        ? _groupAccentColors[widget.indentLevel.clamp(
            0,
            _groupAccentColors.length - 1,
          )]
        : null;

    // Border based on drop zone (matching TaskRow style)
    BorderSide leftBorder;
    if (isGroup && widget.indentLevel == 0 && accentColor != null) {
      leftBorder = BorderSide(color: accentColor, width: 3);
    } else {
      leftBorder = BorderSide.none;
    }

    BorderSide topBorder = BorderSide.none;
    if (_dropZone == DropZone.above) {
      topBorder = BorderSide(color: AppColors.info, width: 2);
    }

    // Spreadsheet-style: stronger, fully-opaque hairline borders so cells
    // read as a continuous grid instead of soft cards.
    const gridBorderColor = Color(0xFFD7DBE0);
    BorderSide rightBorder = const BorderSide(
      color: gridBorderColor,
      width: 1,
    );

    BorderSide bottomBorder;
    if (_dropZone == DropZone.below) {
      bottomBorder = BorderSide(color: AppColors.info, width: 2);
    } else {
      bottomBorder = const BorderSide(
        color: gridBorderColor,
        width: 1,
      );
    }

    // Build the row content
    Widget rowContent = GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: HoverActionRow(
        onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
        builder: (isHovered) {
          final guides = buildTreeGuides(
            depth: widget.indentLevel,
            treeGuides: widget.treeGuides,
            isLastChild: widget.isLastChild,
            colorScheme: Theme.of(context).colorScheme,
            cellHeight: null,
          );
          // checkbox(24) + gap(4) + lineItemId + gap(4) + container padding(10)
          final guideLeftOffset = 24.0 + 4.0 + widget.lineItemColumnWidth + 4.0 + 10.0;
          final guideWidth = guides.length * 24.0;

          return Stack(
          clipBehavior: Clip.none,
          children: [
            TreeRowDropWrapper(
              dropZone: _dropZone,
              insertionGap: _dropInsertionGap,
              verticalGap: _rowVerticalGap,
              child: TreeRowContainer(
                color: rowColor,
                leftBorder: leftBorder,
                rightBorder: rightBorder,
                topBorder: topBorder,
                bottomBorder: bottomBorder,
                // Spreadsheet-density rows: 36px standard (just enough for
                // compact checkboxes and inline edit controls), expands only
                // when an inline description is showing/editing.
                height: useAutoRowHeight ? null : 36,
                minHeight: 36,
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: useAutoRowHeight ? 6 : 0,
                ),
                child: Row(
                  crossAxisAlignment: useAutoRowHeight
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    // Selection checkbox
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onSelectionChanged?.call(
                          widget.item,
                          !widget.isSelected,
                        ),
                        activeColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Hierarchical line item ID (auto-sized, small trailing gap)
                    SizedBox(
                      width: widget.lineItemColumnWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          widget.lineItemId,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Name column with hierarchy (Expanded)
                    _buildNameColumn(isGroup, isHovered),

                    // 8px spacer to match the header's borderLeft handle on Qty
                    if (_isColumnVisible('qty'))
                      const SizedBox(width: 8),

                    // Common Columns: QTY and UNIT
                    // Items show unit-level data, groups aggregate children and show "-"
                    if (!isGroup) ...[
                      if (_isColumnVisible('qty'))
                        SizedBox(
                          width: _colW('qty', 80),
                          child: InlineEditCell(
                            value: widget.item.quantity.toString(),
                            onSave: (_) => _saveQtyEdit(),
                            onCancel: _cancelQtyEdit,
                            cellType: InlineEditCellType.number,
                            controller: _qtyController,
                            isEditing: _isEditingQty,
                            onEnterEdit: _enterQtyEditMode,
                            onKeyEvent: (e) => _handleFieldKeyEvent(e, 'qty'),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      if (_isColumnVisible('unit')) _buildUnitDropdown(),
                    ] else ...[
                      // Groups show dash placeholders for QTY/UNIT
                      if (_isColumnVisible('qty'))
                        SizedBox(
                          width: _colW('qty', 80),
                          child: Text(
                            '-',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppColors.textTertiary),
                          ),
                        ),
                      if (_isColumnVisible('unit'))
                        SizedBox(
                          width: _colW('unit', 80),
                          child: Text(
                            '-',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppColors.textTertiary),
                          ),
                        ),
                    ],

                    if (widget.viewMode == BudgetViewMode.estimating) ...[
                      // Items show unit costs, groups show dashes
                      if (!isGroup) ...[
                        if (_isColumnVisible('unitCost'))
                          SizedBox(
                            width: _colW('unitCost', 130),
                            child: InlineEditCell(
                              value: _formatCurrency(widget.item.unitCost),
                              onSave: (_) => _saveUnitCostEdit(),
                              onCancel: _cancelUnitCostEdit,
                              cellType: InlineEditCellType.currency,
                              currencySymbol: _currencySymbol,
                              controller: unitCostController,
                              isEditing: _isEditingUnitCost,
                              onEnterEdit: _enterUnitCostEditMode,
                              onKeyEvent: (e) =>
                                  _handleFieldKeyEvent(e, 'unitCost'),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_isColumnVisible('unitPrice'))
                          SizedBox(
                            width: _colW('unitPrice', 130),
                            child: InlineEditCell(
                              value: _formatCurrency(widget.item.unitPrice),
                              onSave: (_) => _saveUnitPriceEdit(),
                              onCancel: _cancelUnitPriceEdit,
                              cellType: InlineEditCellType.currency,
                              currencySymbol: _currencySymbol,
                              controller: unitPriceController,
                              isEditing: _isEditingUnitPrice,
                              onEnterEdit: _enterUnitPriceEditMode,
                              onKeyEvent: (e) =>
                                  _handleFieldKeyEvent(e, 'unitPrice'),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_isColumnVisible('extendedPrice'))
                          _buildExtendedPriceCell(
                            width: _colW('extendedPrice', 130),
                          ),
                        if (_isColumnVisible('profit'))
                          _buildProfitColumn(editable: true),
                        if (_isColumnVisible('margin'))
                          SizedBox(
                            width: _colW('margin', 100),
                            child: InlineEditCell(
                              value: widget.item.formattedProjectedMargin,
                              onSave: (_) => _saveMarginEdit(),
                              onCancel: _cancelMarginEdit,
                              cellType: InlineEditCellType.percentage,
                              liveEquivalentText: _marginInputEquivalentText,
                              controller: _marginController,
                              isEditing: _isEditingMargin,
                              onEnterEdit: _enterMarginEditMode,
                              onKeyEvent: (e) =>
                                  _handleFieldKeyEvent(e, 'margin'),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_isColumnVisible('markup'))
                          SizedBox(
                            width: _colW('markup', 100),
                            child: InlineEditCell(
                              value: widget.item.formattedMarkup,
                              onSave: (_) => _saveMarkupEdit(),
                              onCancel: _cancelMarkupEdit,
                              cellType: InlineEditCellType.percentage,
                              liveEquivalentText: _markupInputEquivalentText,
                              controller: markupController,
                              isEditing: _isEditingMarkup,
                              onEnterEdit: _enterMarkupEditMode,
                              onKeyEvent: (e) =>
                                  _handleFieldKeyEvent(e, 'markup'),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        if (_isColumnVisible('taxable')) _buildTaxableColumn(),
                      ] else ...[
                        // Groups show aggregated subtotals from child items
                        if (_isColumnVisible('unitCost'))
                          _buildReadOnlyColumn(
                            width: _colW('unitCost', 130),
                            value: _formatCurrency(widget.item.projectedCost),
                            color: AppColors.textSecondary,
                            isBold: true,
                            textAlign: TextAlign.right,
                          ),
                        if (_isColumnVisible('unitPrice'))
                          _buildReadOnlyColumn(
                            width: _colW('unitPrice', 130),
                            value: _formatCurrency(widget.item.approvedPrice),
                            color: AppColors.textSecondary,
                            isBold: true,
                            textAlign: TextAlign.right,
                          ),
                        if (_isColumnVisible('extendedPrice'))
                          _buildReadOnlyColumn(
                            width: _colW('extendedPrice', 130),
                            value: _formatCurrency(widget.item.approvedPrice),
                            isBold: true,
                            textAlign: TextAlign.right,
                          ),
                        if (_isColumnVisible('profit')) _buildProfitColumn(),
                        if (_isColumnVisible('margin')) _buildMarginColumn(isBold: true),
                        if (_isColumnVisible('markup'))
                          SizedBox(
                            width: _colW('markup', 100),
                            child: Text(
                              '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ),
                        if (_isColumnVisible('taxable'))
                          SizedBox(
                            width: _colW('taxable', 80),
                            child: Text(
                              '—',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ),
                      ],
                    ],

                    if (widget.viewMode == BudgetViewMode.costing) ...[
                      if (_isColumnVisible('committed'))
                        _buildReadOnlyColumn(
                          width: _colW('committed', 130),
                          value: _formatCurrency(widget.item.committedCost),
                          color: AppColors.infoDark,
                          isBold: isGroup,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('actual')) _buildActualCostColumn(),
                      if (_isColumnVisible('variance')) _buildVarianceColumn(),
                      if (_isColumnVisible('hoursEst'))
                        _buildReadOnlyColumn(
                          width: _colW('hoursEst', 100),
                          value:
                              widget.laborSummary != null &&
                                  widget.laborSummary!.estimatedHours > 0
                              ? '${widget.laborSummary!.estimatedHours.toStringAsFixed(1)}h'
                              : '-',
                          isBold: isGroup,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('hoursTracked'))
                        _buildLaborHoursTrackedColumn(),
                      if (_isColumnVisible('laborCost'))
                        _buildLaborCostColumn(),
                    ],

                    if (widget.viewMode == BudgetViewMode.invoicing) ...[
                      if (_isColumnVisible('invoiced'))
                        _buildReadOnlyColumn(
                          width: _colW('invoiced', 130),
                          value: _formatCurrency(widget.invoicedAmount),
                          color: AppColors.messageAccentDark,
                          isBold: isGroup,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('paid'))
                        _buildReadOnlyColumn(
                          width: _colW('paid', 130),
                          value: _formatCurrency(
                            widget.documentStatus?.paidAmount ?? 0.0,
                          ),
                          color: AppColors.successDark,
                          isBold: isGroup,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('remaining'))
                        _buildRemainingInvoicedColumn(),
                    ],

                    if (widget.viewMode == BudgetViewMode.profit) ...[
                      if (_isColumnVisible('actualCost'))
                        _buildReadOnlyColumn(
                          width: _colW('actualCost', 130),
                          value: _formatCurrency(widget.actualCost),
                          color: AppColors.messageAccentDark,
                          isBold: isGroup,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('profit')) _buildProfitColumn(),
                      if (_isColumnVisible('margin')) _buildMarginColumn(isBold: isGroup),
                    ],

                    // Change Orders view - shows source type, CO number, revenue/cost deltas
                    if (widget.viewMode == BudgetViewMode.changeOrders) ...[
                      if (_isColumnVisible('coNumber'))
                        _buildReadOnlyColumn(
                          width: _colW('coNumber', 80),
                          value:
                              widget.item.changeOrderId?.substring(0, 8) ?? '-',
                        ),
                      if (_isColumnVisible('source')) _buildSourceTypeBadge(),
                      if (_isColumnVisible('status'))
                        _buildReadOnlyColumn(
                          width: _colW('status', 100),
                          value: widget.changeOrderStatusText ?? '-',
                        ),
                      if (_isColumnVisible('revenueChange'))
                        _buildReadOnlyColumn(
                          width: _colW('revenueChange', 120),
                          value: widget.item.sourceType != BudgetItemSource.base
                              ? _formatCurrency(widget.item.approvedPrice)
                              : '-',
                          color: AppColors.successDark,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('costChange'))
                        _buildReadOnlyColumn(
                          width: _colW('costChange', 120),
                          value: widget.item.sourceType != BudgetItemSource.base
                              ? _formatCurrency(widget.item.projectedCost)
                              : '-',
                          color: AppColors.errorDark,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('netChange'))
                        _buildReadOnlyColumn(
                          width: _colW('netChange', 120),
                          value: widget.item.sourceType != BudgetItemSource.base
                              ? _formatCurrency(widget.item.projectedProfit)
                              : '-',
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('margin')) _buildMarginColumn(isBold: isGroup),
                    ],

                    // Upgrades view - shows upgrade status, pricing, holdback
                    if (widget.viewMode == BudgetViewMode.upgrades) ...[
                      if (_isColumnVisible('isUpgrade'))
                        SizedBox(
                          width: _colW('isUpgrade', 80),
                          child: widget.item.itemType == BudgetItemType.group
                              ? const SizedBox.shrink()
                              : InlineCheckboxCell(
                                  value: widget.item.sourceType ==
                                      BudgetItemSource.upgrade,
                                  onChanged: (checked) {
                                    final updated = widget.item.copyWith(
                                      sourceType: checked
                                          ? BudgetItemSource.upgrade
                                          : BudgetItemSource.base,
                                      upgradeStatus: checked
                                          ? (widget.item.upgradeStatus ??
                                              UpgradeStatus.offered)
                                          : null,
                                    );
                                    widget.onItemChanged?.call(updated);
                                  },
                                ),
                        ),
                      if (_isColumnVisible('category'))
                        _buildReadOnlyColumn(
                          width: _colW('category', 120),
                          value: widget.item.categoryId ?? '-',
                        ),
                      if (_isColumnVisible('upgradeStatus'))
                        _buildUpgradeStatusBadge(),
                      if (_isColumnVisible('price'))
                        _buildReadOnlyColumn(
                          width: _colW('price', 120),
                          value: _formatCurrency(widget.item.approvedPrice),
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('cost'))
                        _buildReadOnlyColumn(
                          width: _colW('cost', 120),
                          value: _formatCurrency(widget.item.projectedCost),
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('profit')) _buildProfitColumn(),
                      if (_isColumnVisible('margin')) _buildMarginColumn(isBold: isGroup),
                      if (_isColumnVisible('holdbackPct'))
                        _buildReadOnlyColumn(
                          width: _colW('holdbackPct', 100),
                          value: widget.item.holdbackPercent != null
                              ? '${widget.item.holdbackPercent!.toStringAsFixed(1)}%'
                              : '-',
                          textAlign: TextAlign.right,
                        ),
                    ],

                    // Holdback view - shows holdback amounts and release status
                    if (widget.viewMode == BudgetViewMode.holdback) ...[
                      if (_isColumnVisible('approved'))
                        _buildReadOnlyColumn(
                          width: _colW('approved', 130),
                          value: _formatCurrency(widget.item.approvedPrice),
                          isBold: true,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('holdbackPct'))
                        _buildReadOnlyColumn(
                          width: _colW('holdbackPct', 100),
                          value: widget.item.holdbackPercent != null
                              ? '${widget.item.holdbackPercent!.toStringAsFixed(1)}%'
                              : '-',
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('holdbackAmt'))
                        _buildReadOnlyColumn(
                          width: _colW('holdbackAmt', 130),
                          value: _formatCurrency(widget.item.holdbackAmount),
                          color: AppColors.warningDark,
                          textAlign: TextAlign.right,
                        ),
                      if (_isColumnVisible('released'))
                        _buildHoldbackReleasedBadge(),
                      if (_isColumnVisible('collectible'))
                        _buildReadOnlyColumn(
                          width: _colW('collectible', 130),
                          value: _formatCurrency(widget.item.collectibleAmount),
                          color: AppColors.successDark,
                          textAlign: TextAlign.right,
                        ),
                    ],

                    // Always show Status at the end
                    _buildStatusColumn(),
                  ],
                ),
              ),
            ),
            // Drop zone visual indicators (matching TaskRow)
            if (_dropZone == DropZone.above || _dropZone == DropZone.below)
              Positioned(
                left: 8,
                right: 8,
                top: _dropZone == DropZone.above ? 0 : null,
                bottom: _dropZone == DropZone.below ? 0 : null,
                child: IgnorePointer(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.info,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.info.withValues(alpha: 0.25),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_dropZone == DropZone.child)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.info.withValues(alpha: 0.28),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Make child',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          // Tree guide lines as overlay — extends beyond row bounds
          if (guides.isNotEmpty)
            Positioned(
              left: guideLeftOffset,
              top: 0,
              bottom: -6,
              width: guideWidth,
              child: IgnorePointer(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: guides,
                ),
              ),
            ),
          ],
        );
        },
      ),
    );

    // If drag is not enabled, just return the row content
    if (widget.onItemParentChanged == null) {
      return RepaintBoundary(child: rowContent);
    }

    // Wrap with DragTarget for 4-zone drop (matching TaskRow)
    final rowWithDropTarget = DragTarget<BudgetItem>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        if (dragged.id == widget.item.id) return false;
        if (_isDescendantOf(dragged, widget.item)) return false;
        return true;
      },
      onAcceptWithDetails: (details) {
        final zone = _dropZone;
        setState(() => _dropZone = DropZone.none);
        widget.onItemDropped?.call(details.data, widget.item, zone);
      },
      onMove: (details) {
        var zone = computeDropZone(
          context,
          details.offset,
          depth: widget.indentLevel,
          hasParent: widget.item.parentId != null,
          hasVisibleChildren: widget.hasChildren && widget.isExpanded,
        );
        final childMoveAllowed =
            _canHaveChildren && widget.item.hierarchyLevel < 2;
        if (zone == DropZone.child && !childMoveAllowed) {
          zone = DropZone.none;
        }
        // For group rows, the whole row is a child drop target — no need to
        // hit the narrow middle zone. Matches task group header behavior.
        if (childMoveAllowed &&
            (zone == DropZone.above || zone == DropZone.below)) {
          zone = DropZone.child;
        }
        if (zone != _dropZone) setState(() => _dropZone = zone);
      },
      onLeave: (_) {
        if (_dropZone != DropZone.none) {
          setState(() => _dropZone = DropZone.none);
        }
      },
      builder: (context, candidateData, rejectedData) => rowContent,
    );

    // Build drag feedback widget (shown while dragging)
    final dragFeedback = Opacity(
      opacity: 0.55,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 300,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.info, width: 2),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, size: 16, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    onDragStarted() {
      if (_isHovered || _dropZone != DropZone.none) {
        setState(() {
          _isHovered = false;
          _dropZone = DropZone.none;
        });
      }
      widget.onDragStarted?.call();
    }

    onDragEnd(_) {
      if (_isHovered || _dropZone != DropZone.none) {
        setState(() {
          _isHovered = false;
          _dropZone = DropZone.none;
        });
      }
      widget.onDragEnded?.call();
    }

    final whenDragging = IgnorePointer(
      child: Opacity(opacity: 0.16, child: rowWithDropTarget),
    );

    if (isMobile) {
      return RepaintBoundary(
        child: LongPressDraggable<BudgetItem>(
          data: widget.item,
          onDragStarted: onDragStarted,
          onDragEnd: onDragEnd,
          feedback: dragFeedback,
          childWhenDragging: whenDragging,
          hapticFeedbackOnStart: true,
          child: rowWithDropTarget,
        ),
      );
    }
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<BudgetItem>(
          data: widget.item,
          onDragStarted: onDragStarted,
          onDragEnd: onDragEnd,
          feedback: dragFeedback,
          childWhenDragging: whenDragging,
          child: rowWithDropTarget,
        ),
      ),
    );
  }

  Widget _buildActualCostColumn() {
    final progress = widget.item.projectedCost > 0
        ? (widget.actualCost / widget.item.projectedCost)
        : 0.0;
    final color = progress > 1.0 ? AppColors.error : AppColors.messageAccent;

    return SizedBox(
      width: _colW('actual', 130),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatCurrency(widget.actualCost),
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
          if (!_hasChildren) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitDropdown() {
    final currentUnit = widget.item.unit ?? '';

    // If in custom mode or editing, show the text field
    if (_isEditingUnit || _isCustomUnitMode) {
      return SizedBox(
        width: _colW('unit', 80),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.infoDark, width: 2),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          child: TextField(
            controller: unitController,
            autofocus: true,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'Unit',
            ),
            onSubmitted: (_) => _saveUnitEdit(),
            onTapOutside: (_) => _saveUnitEdit(),
          ),
        ),
      );
    }

    // Show dropdown for standard units + custom option
    return SizedBox(
      width: _colW('unit', 80),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == '_custom_') {
            // Enter custom mode
            setState(() {
              _isCustomUnitMode = true;
              _isEditingUnit = true;
              unitController.text = currentUnit;
              selectAllText(unitController);
            });
          } else {
            // Save the selected standard unit
            if (value != currentUnit) {
              widget.onItemChanged?.call(
                widget.item.copyWith(
                  unit: value.isEmpty ? null : value,
                  updatedAt: DateTime.now(),
                ),
              );
            }
          }
        },
        tooltip: 'Select unit',
        offset: const Offset(0, 36),
        itemBuilder: (context) => [
          // Standard units
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
          // Custom option
          PopupMenuItem<String>(
            value: '_custom_',
            child: Row(
              children: [
                Icon(Icons.edit, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                const Text('Custom...'),
              ],
            ),
          ),
        ],
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.xs)),
            // Right-aligned to match the Unit header and keep the column
            // visually consistent with the other numeric columns. The dropdown
            // caret stays at the far right, and the value hugs it.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    currentUnit.isEmpty ? '-' : currentUnit,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.infoDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: AppColors.infoDark,
                ),
              ],
            ),
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

  Widget _buildNameColumn(bool isGroup, bool isHovered) {
    final hasDescription =
        widget.item.description != null && widget.item.description!.isNotEmpty;
    final showDescription =
        hasDescription && widget.viewMode != BudgetViewMode.invoicing;
    final showActions = isHovered && !_isEditingName && !_isEditingDescription;

    return Expanded(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reserve space for tree guides (painted via Positioned overlay)
            SizedBox(width: widget.indentLevel * 24.0),
            // Expand/collapse icon
            ...buildTreeChevron(
              hasChildren: _hasChildren,
              isExpanded: widget.isExpanded,
              depth: widget.indentLevel,
              onToggle: widget.onExpandToggle,
            ),
            // Add child button (for Groups)
            if (_canHaveChildren && widget.onAddItem != null)
              _buildAddChildButton()
            else
              const SizedBox(width: 4),
            const SizedBox(width: 4),
            // Name + description stacked, with inline actions on hover
            Flexible(
              child: _isEditingName
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: _buildNameEditField(),
                    )
                  : Row(
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildNameDisplay(isGroup),
                              if (showDescription ||
                                  _isEditingDescription ||
                                  (isHovered &&
                                      widget.viewMode !=
                                          BudgetViewMode.invoicing &&
                                      !_isEditingName))
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: _isEditingDescription
                                      ? _buildDescriptionEditField()
                                      : MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: _enterDescriptionEditMode,
                                            child: showDescription
                                                ? Tooltip(
                                                    message: widget
                                                        .item
                                                        .description!,
                                                    preferBelow: true,
                                                    waitDuration:
                                                        const Duration(
                                                          milliseconds: 500,
                                                        ),
                                                    child: Text(
                                                      widget.item.description!,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors
                                                            .textTertiary,
                                                        height: 1.3,
                                                      ),
                                                      softWrap: true,
                                                    ),
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
                          SizedBox(width: 28, child: _buildMoreMenu(isGroup)),
                        ],
                      ],
                    ),
            ),
            // Tasks toggle icon
            if (widget.onTasksExpandToggle != null) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  widget.isTasksExpanded
                      ? Icons.assignment_turned_in
                      : Icons.assignment_outlined,
                  size: 16,
                  color: widget.isTasksExpanded
                      ? AppColors.info
                      : AppColors.textTertiary,
                ),
                onPressed: widget.onTasksExpandToggle,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: '${widget.laborSummary?.taskCount ?? 0} linked tasks',
                visualDensity: VisualDensity.compact,
              ),
            ],
            // Progress badge for parents
            if (_hasChildren && widget.progressText.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Text(
                  widget.progressText,
                  style: TextStyle(fontSize: 12, color: AppColors.infoDark),
                ),
              ),
            // Drop here badge for groups when dragging over them
            if (isGroup && _dropZone == DropZone.child) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Text(
                  'Drop here',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            // Cost type composition badges for groups
            if (isGroup && _hasChildren) _buildCostTypeBadges(),
            // Completion icon for leaf items
            if (!_hasChildren && widget.item.isComplete)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.success,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostTypeBadges() {
    // Collect direct child leaf items of this group
    final childItems = widget.allItems.where(
      (i) => i.parentId == widget.item.id && i.itemType == BudgetItemType.item,
    );
    if (childItems.isEmpty) return const SizedBox.shrink();

    // Check if any child has a costType set
    final hasAnyCostType = childItems.any((i) => i.costType != null);
    if (!hasAnyCostType) return const SizedBox.shrink();

    final counts = <BudgetCostType, int>{};
    for (final item in childItems) {
      if (item.costType != null) {
        counts[item.costType!] = (counts[item.costType!] ?? 0) + 1;
      }
    }

    final badges = BudgetCostType.values
        .where((type) => (counts[type] ?? 0) > 0)
        .map(
          (type) => CompositionBadge(
            label: type.displayLabel,
            count: counts[type]!,
            total: childItems.length,
            color: type.color,
          ),
        )
        .toList();

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: CompositionBadges(badges: badges),
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
    final name = widget.item.name;
    final query = widget.searchQuery;

    // Show placeholder for empty-name groups to avoid blank grey rows
    if (name.trim().isEmpty && isGroup) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _enterNameEditMode,
          child: Text(
            'Untitled group',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    Widget nameWidget;
    if (query.isNotEmpty && name.toLowerCase().contains(query)) {
      // Build highlighted text
      final lowerName = name.toLowerCase();
      final matchStart = lowerName.indexOf(query);
      final matchEnd = matchStart + query.length;
      nameWidget = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: name.substring(0, matchStart)),
            TextSpan(
              text: name.substring(matchStart, matchEnd),
              style: TextStyle(
                backgroundColor: Colors.yellow.shade200,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: name.substring(matchEnd)),
          ],
          style: TextStyle(
            fontWeight: isGroup ? FontWeight.bold : FontWeight.normal,
            fontSize: isGroup ? 15 : 14,
            color: isGroup ? Colors.black : AppColors.textPrimary,
          ),
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      nameWidget = Text(
        name,
        style: TextStyle(
          fontWeight: isGroup ? FontWeight.bold : FontWeight.normal,
          fontSize: isGroup ? 15 : 14,
          color: isGroup ? Colors.black : AppColors.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final isLaborOverBudget = widget.laborSummary?.isOverBudget ?? false;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _enterNameEditMode,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isGroup && widget.item.costType != null) ...[
              CostTypeDot(
                color: widget.item.costType!.color,
                tooltip: widget.item.costType!.displayLabel,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(child: nameWidget),
            if (isLaborOverBudget) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Labor hours exceed estimate',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNameEditField() {
    final isGroup = widget.item.itemType == BudgetItemType.group;

    return Focus(
      onKeyEvent: (_, event) {
        if (_fieldRegistry.handleKeyEvent(event, 'name')) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InlineEditCell(
        value: widget.item.name,
        onSave: (_) => _saveNameEdit(),
        onCancel: _cancelNameEdit,
        cellType: InlineEditCellType.text,
        required: true,
        controller: nameController,
        focusNode: _nameFocus,
        isEditing: true,
        editBorderColor: AppColors.info,
        onEditStateChanged: (isEditing) {
          if (!isEditing && _isEditingName) {
            setState(() => _isEditingName = false);
          }
        },
        onKeyEvent: (event) => _handleFieldKeyEvent(event, 'name'),
        displayStyle: TextStyle(
          fontSize: isGroup ? 15 : 14,
          fontWeight: isGroup ? FontWeight.bold : FontWeight.normal,
          color: isGroup ? Colors.black : AppColors.textPrimary,
        ),
      ),
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
      child: InlineEditFrame(
        borderColor: AppColors.infoDark,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
        child: TextField(
          controller: descriptionController,
          focusNode: _descriptionFocus,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 12, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Add a description...',
            hintStyle: TextStyle(color: AppColors.textTertiary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTapOutside: (_) => _saveDescriptionEdit(),
        ),
      ),
    );
  }

  Widget _buildReadOnlyColumn({
    required double width,
    required String value,
    bool isBold = false,
    Color? color,
    TextAlign textAlign = TextAlign.left,
  }) {
    return TableTextCell(
      width: width,
      text: value,
      isBold: isBold,
      color: color,
      textAlign: textAlign,
    );
  }

  /// Extended price cell for approved items: shows the current extended
  /// price with a small indicator when it diverges from the frozen approved
  /// total. Tooltip surfaces the variance for quick reconciliation.
  Widget _buildExtendedPriceCell({required double width}) {
    final item = widget.item;
    final current = item.extendedPrice;
    final valueText = _formatCurrency(current);

    if (!item.isApproved) {
      return TableTextCell(width: width, text: valueText, textAlign: TextAlign.right);
    }

    final variance = item.approvedPriceVariance;
    final hasVariance = variance.abs() > 0.005;
    final iconColor = hasVariance
        ? AppColors.warningDark
        : AppColors.textTertiary;
    final icon = hasVariance ? Icons.warning_amber_rounded : Icons.lock_outline;
    final tooltip = hasVariance
        ? 'Approved: ${_formatCurrency(item.approvedPrice)}  •  '
              'Variance: ${variance >= 0 ? '+' : '-'}'
              '${_formatCurrency(variance.abs())}'
        : 'Locked — contracted at ${_formatCurrency(item.approvedPrice)}';

    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              valueText,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: hasVariance ? AppColors.warningDark : null,
                fontWeight: hasVariance ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: tooltip,
            child: Icon(icon, size: 14, color: iconColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitColumn({bool editable = false}) {
    final profit = widget.item.projectedProfit;
    if (editable) {
      return SizedBox(
        width: _colW('profit', 130),
        child: InlineEditCell(
          value: _formatCurrency(profit),
          onSave: (_) => _saveProfitEdit(),
          onCancel: _cancelProfitEdit,
          cellType: InlineEditCellType.currency,
          currencySymbol: _currencySymbol,
          controller: _profitController,
          isEditing: _isEditingProfit,
          onEnterEdit: _enterProfitEditMode,
          onKeyEvent: (e) => _handleFieldKeyEvent(e, 'profit'),
          textAlign: TextAlign.right,
        ),
      );
    }
    return SizedBox(
      width: _colW('profit', 130),
      child: ConditionalValueText(
        value: profit,
        displayText: _formatCurrency(profit),
        style: const TextStyle(fontWeight: FontWeight.w600),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildMarginColumn({bool isBold = false}) {
    final margin = widget.item.projectedMargin;
    return Container(
      width: _colW('margin', 100),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: ConditionalValueText(
        value: margin,
        displayText: widget.item.formattedProjectedMargin,
        textAlign: TextAlign.right,
        style: isBold ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
    );
  }

  /// Build a badge showing the source type (Base, CO, Upgrade)
  Widget _buildSourceTypeBadge() {
    final sourceType = widget.item.sourceType;
    Color badgeColor;
    String label;

    switch (sourceType) {
      case BudgetItemSource.base:
        badgeColor = AppColors.textTertiary;
        label = 'Base';
        break;
      case BudgetItemSource.changeOrder:
        badgeColor = AppColors.info;
        label = 'CO';
        break;
      case BudgetItemSource.upgrade:
        badgeColor = AppColors.messageAccent;
        label = 'Upgrade';
        break;
    }

    return SizedBox(
      width: _colW('source', 100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: badgeColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Build a badge showing the upgrade status
  Widget _buildUpgradeStatusBadge() {
    final status = widget.item.upgradeStatus;
    if (status == null) {
      return SizedBox(
        width: _colW('upgradeStatus', 100),
        child: Text('-', style: TextStyle(color: AppColors.textTertiary)),
      );
    }

    Color badgeColor;
    String label;

    switch (status) {
      case UpgradeStatus.offered:
        badgeColor = AppColors.warning;
        label = 'Offered';
        break;
      case UpgradeStatus.accepted:
        badgeColor = AppColors.success;
        label = 'Accepted';
        break;
      case UpgradeStatus.declined:
        badgeColor = AppColors.error;
        label = 'Declined';
        break;
    }

    return SizedBox(
      width: _colW('upgradeStatus', 100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: badgeColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Build a badge showing holdback release status
  Widget _buildHoldbackReleasedBadge() {
    final released = widget.item.holdbackReleased;
    final hasHoldback = widget.item.hasHoldback;

    if (!hasHoldback) {
      return SizedBox(
        width: _colW('released', 100),
        child: Text('-', style: TextStyle(color: AppColors.textTertiary)),
      );
    }

    return SizedBox(
      width: _colW('released', 100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: released
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: Border.all(
            color: released
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.warning.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              released ? Icons.lock_open : Icons.lock_clock,
              size: 14,
              color: released ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: 4),
            Text(
              released ? 'Released' : 'Held',
              style: TextStyle(
                color: released ? AppColors.success : AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVarianceColumn() {
    final variance = widget.item.projectedProfitVariance(widget.actualCost);
    final color = variance >= 0 ? AppColors.success : AppColors.error;

    return SizedBox(
      width: _colW('variance', 130),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            variance >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            _formatCurrency(variance.abs()),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildLaborHoursTrackedColumn() {
    final summary = widget.laborSummary;
    if (summary == null || summary.trackedHours == 0) {
      return _buildReadOnlyColumn(width: _colW('hoursTracked', 100), value: '-', textAlign: TextAlign.right);
    }

    final utilization = summary.hoursUtilization;
    final color = utilization > 100
        ? AppColors.error
        : utilization > 80
        ? AppColors.warning
        : AppColors.success;

    return SizedBox(
      width: _colW('hoursTracked', 100),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (summary.isOverBudget)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber,
                size: 14,
                color: AppColors.error,
              ),
            ),
          Text(
            '${summary.trackedHours.toStringAsFixed(1)}h',
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildLaborCostColumn() {
    final summary = widget.laborSummary;
    if (summary == null || summary.laborCost == 0) {
      return _buildReadOnlyColumn(width: _colW('laborCost', 130), value: '-', textAlign: TextAlign.right);
    }

    return _buildReadOnlyColumn(
      width: _colW('laborCost', 130),
      value: _formatCurrency(summary.laborCost),
      color: AppColors.warningDark,
      textAlign: TextAlign.right,
    );
  }

  Widget _buildStatusColumn() {
    return SizedBox(
      width: 80,
      child: Center(
        child: widget.documentStatus != null
            ? BudgetDocumentStatusIndicator(
                status: widget.documentStatus!,
                compact: true,
                onTap: widget.onDocumentStatusTap,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildRemainingInvoicedColumn() {
    final remainingByTotal = widget.item.approvedPrice - widget.invoicedAmount;
    final isOverInvoiced = remainingByTotal < 0;
    final color = isOverInvoiced
        ? AppColors.errorDark
        : remainingByTotal > 0
        ? AppColors.warningDark
        : AppColors.textTertiary;

    return Tooltip(
      message: isOverInvoiced
          ? 'Over-invoiced by ${_formatCurrency(-remainingByTotal)}'
          : '',
      child: SizedBox(
        width: _colW('remaining', 130),
        child: Text(
          _formatCurrency(remainingByTotal.abs()),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w500,
            decoration: isOverInvoiced ? TextDecoration.underline : null,
            decorationColor: AppColors.errorDark,
          ),
        ),
      ),
    );
  }

  // Edit mode methods

  void _enterNameEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingName = true;
      nameController.text = widget.item.name;
      selectAllText(nameController);
    });
  }

  void _saveNameEdit() {
    final trimmedValue = nameController.text.trim();
    if (trimmedValue.isNotEmpty && trimmedValue != widget.item.name) {
      widget.onItemChanged?.call(
        widget.item.copyWith(name: trimmedValue, updatedAt: DateTime.now()),
      );
    }
    setState(() => _isEditingName = false);
  }

  void _cancelNameEdit() {
    _revertToSnapshot();
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
      _descriptionFocus.requestFocus();
      final controller = descriptionController;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
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

  void _enterQtyEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingQty = true;
      _qtyController.text = widget.item.quantity.toString();
    });
    _selectAllText(_qtyController);
  }

  void _saveQtyEdit() {
    final value = double.tryParse(_qtyController.text);
    if (value != null && value > 0 && value != widget.item.quantity) {
      final newProjectedCost = value * widget.item.unitCost;
      // Once approved, the contracted total is frozen — variance shows in the
      // row via currentExtendedPrice vs. approvedPrice.
      final updated = widget.item.copyWith(
        quantity: value,
        projectedCost: newProjectedCost,
        approvedPrice: widget.item.isApproved
            ? widget.item.approvedPrice
            : value * widget.item.unitPrice,
        updatedAt: DateTime.now(),
      );
      widget.onItemChanged?.call(updated);
    }
    setState(() => _isEditingQty = false);
  }

  void _cancelQtyEdit() {
    _revertToSnapshot();
    setState(() => _isEditingQty = false);
  }

  void _saveUnitEdit() {
    final value = unitController.text.trim();
    if (value != widget.item.unit) {
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

  void _enterUnitCostEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingUnitCost = true;
      unitCostController.text = widget.item.unitCost.toStringAsFixed(2);
    });
    _selectAllText(unitCostController);
  }

  void _saveUnitCostEdit() {
    final value = double.tryParse(unitCostController.text);
    if (value != null && value >= 0 && value != widget.item.unitCost) {
      final newUnitPrice = PricingMath.priceFromMarkup(value, widget.item.markup);
      // When cost becomes 0, price also becomes 0 — reset markup so it doesn't
      // show a phantom percentage on an item with no financial value.
      final newMarkup = value == 0 ? 0.0 : widget.item.markup;
      widget.onItemChanged?.call(
        widget.item.copyWith(
          unitCost: value,
          projectedCost: widget.item.quantity * value,
          unitPrice: newUnitPrice,
          markup: newMarkup,
          approvedPrice: widget.item.isApproved
              ? widget.item.approvedPrice
              : widget.item.quantity * newUnitPrice,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingUnitCost = false);
  }

  void _cancelUnitCostEdit() {
    _revertToSnapshot();
    setState(() => _isEditingUnitCost = false);
  }

  void _enterUnitPriceEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingUnitPrice = true;
      unitPriceController.text = widget.item.unitPrice.toStringAsFixed(2);
    });
    _selectAllText(unitPriceController);
  }

  void _saveUnitPriceEdit() {
    final value = double.tryParse(unitPriceController.text);
    if (value != null && value >= 0 && value != widget.item.unitPrice) {
      final newMarkup = widget.item.unitCost > 0
          ? ((value - widget.item.unitCost) / widget.item.unitCost) * 100
          : 0.0;
      widget.onItemChanged?.call(
        widget.item.copyWith(
          unitPrice: value,
          approvedPrice: widget.item.isApproved
              ? widget.item.approvedPrice
              : widget.item.quantity * value,
          markup: newMarkup,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingUnitPrice = false);
  }

  void _cancelUnitPriceEdit() {
    _revertToSnapshot();
    setState(() => _isEditingUnitPrice = false);
  }

  void _enterProfitEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingProfit = true;
      _profitController.text = widget.item.projectedProfit.toStringAsFixed(2);
    });
    _selectAllText(_profitController);
  }

  void _saveProfitEdit() {
    final value = double.tryParse(_profitController.text);
    // Profit is derived from approvedPrice - projectedCost; once approved,
    // approvedPrice is locked so profit can't be edited directly.
    if (widget.item.isApproved) {
      setState(() => _isEditingProfit = false);
      return;
    }
    if (value != null && value != widget.item.projectedProfit) {
      final rawApprovedPrice = widget.item.projectedCost + value;
      final newApprovedPrice = rawApprovedPrice < 0 ? 0.0 : rawApprovedPrice;
      final newUnitPrice = widget.item.quantity > 0
          ? newApprovedPrice / widget.item.quantity
          : widget.item.unitPrice;
      final newMarkup = widget.item.unitCost > 0
          ? ((newUnitPrice - widget.item.unitCost) / widget.item.unitCost) * 100
          : 0.0;

      widget.onItemChanged?.call(
        widget.item.copyWith(
          unitPrice: newUnitPrice,
          approvedPrice: newApprovedPrice,
          markup: newMarkup,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingProfit = false);
  }

  void _cancelProfitEdit() {
    _revertToSnapshot();
    setState(() {
      _isEditingProfit = false;
      _profitController.text = widget.item.projectedProfit.toStringAsFixed(2);
    });
  }

  void _enterMarkupEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingMargin = false;
      _isEditingMarkup = true;
      markupController.text = widget.item.markup.toStringAsFixed(1);
    });
    _selectAllText(markupController);
  }

  void _saveMarkupEdit() {
    final value = double.tryParse(markupController.text);
    if (value != null && value >= -100 && value != widget.item.markup) {
      final newUnitPrice = widget.item.unitCost * (1 + value / 100);
      widget.onItemChanged?.call(
        widget.item.copyWith(
          markup: value,
          unitPrice: newUnitPrice,
          approvedPrice: widget.item.isApproved
              ? widget.item.approvedPrice
              : widget.item.quantity * newUnitPrice,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingMarkup = false);
  }

  void _cancelMarkupEdit() {
    _revertToSnapshot();
    setState(() {
      _isEditingMarkup = false;
      markupController.text = widget.item.markup.toStringAsFixed(1);
    });
  }

  void _enterMarginEditMode() {
    if (!_isAnyFieldEditing) _editSnapshot = widget.item;
    setState(() {
      _isEditingMarkup = false;
      _isEditingMargin = true;
      _marginController.text = widget.item.projectedMargin.toStringAsFixed(1);
    });
    _selectAllText(_marginController);
  }

  void _saveMarginEdit() {
    final value = double.tryParse(_marginController.text);
    if (value != null &&
        value > -100 &&
        value < 100 &&
        value != widget.item.projectedMargin) {
      final denominator = 1 - value / 100;
      final newUnitPrice = denominator == 0
          ? widget.item.unitCost
          : widget.item.unitCost / denominator;
      final newMarkup = PricingMath.markupFromMargin(value);

      widget.onItemChanged?.call(
        widget.item.copyWith(
          markup: newMarkup,
          unitPrice: newUnitPrice,
          approvedPrice: widget.item.isApproved
              ? widget.item.approvedPrice
              : widget.item.quantity * newUnitPrice,
          updatedAt: DateTime.now(),
        ),
      );
    }
    setState(() => _isEditingMargin = false);
  }

  void _cancelMarginEdit() {
    _revertToSnapshot();
    setState(() {
      _isEditingMargin = false;
      _marginController.text = widget.item.projectedMargin.toStringAsFixed(1);
    });
  }

  String get _markupInputEquivalentText {
    final markup = double.tryParse(markupController.text);
    if (markup == null) return 'Margin --';
    return 'Margin ${PricingMath.marginFromMarkup(markup).toStringAsFixed(1)}%';
  }

  String get _marginInputEquivalentText {
    final margin = double.tryParse(_marginController.text);
    if (margin == null) return 'Markup --';
    return 'Markup ${PricingMath.markupFromMargin(margin).toStringAsFixed(1)}%';
  }

  void _toggleTaxable(bool value) {
    widget.onItemChanged?.call(
      widget.item.copyWith(isTaxable: value, updatedAt: DateTime.now()),
    );
  }
}
