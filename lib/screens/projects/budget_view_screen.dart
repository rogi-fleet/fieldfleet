import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/theme.dart';
import '../../models/budget_item.dart';
import '../../models/project.dart';
import '../../models/selection.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/budget_service.dart';
import '../../models/budget_item_labor_summary.dart';
import '../../models/template_category.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/budget_export.dart';
import '../../utils/project_terminology.dart';
import '../../utils/currency_utils.dart';
import '../../utils/hierarchy_flatten.dart';
import '../../utils/hierarchy_utils.dart';
import '../../utils/table_column_visibility.dart';
import '../../utils/table_sort_state.dart';
import '../../utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/common/breadcrumb_bar.dart';
import '../../widgets/catalog_import_dialog.dart';
import '../../widgets/budget_to_catalog_dialog.dart';
import '../../utils/budget_tab_metrics.dart';
import '../../widgets/budget/budget_summary_bar.dart';
import '../../widgets/budget/budget_holdback_view.dart';
import '../../widgets/budget/budget_profit_view.dart';
import '../../widgets/budget/budget_mobile_view.dart';
import '../../widgets/budget/budget_workflow_view.dart';
import '../../widgets/common/async_state_view.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/pay_application.dart';
import '../../services/supabase/pay_application_service.dart';
import '../../models/financial_workflow_state.dart';
import '../../utils/financial_workflow_builder.dart';
import '../../widgets/budget_view_row.dart';
import '../../widgets/table/tree_drop_zone.dart';
import '../../widgets/budget_item_form_popup.dart';
import '../../widgets/budget_inline_add_row.dart';
import '../../widgets/budget_item_tasks_expansion.dart';
import '../../widgets/budget_mass_edit_dialog.dart';
import '../../widgets/ai_takeoff_wizard.dart';
import '../../widgets/budget_document_wizard.dart';
import '../../widgets/table/table_add_item_group_row.dart';
import '../../widgets/table/table_column_schema.dart';
import '../../widgets/table/table_column_picker_button.dart';
import '../../widgets/table/table_controls_bar.dart';
import '../../widgets/table/table_header_cells_builder.dart';
import '../../widgets/table/table_header_row.dart';
import '../../widgets/table/table_summary_footer.dart';
import '../../widgets/table/table_layout_shell.dart';
import '../../widgets/table/table_view_styles.dart';
import '../../widgets/common/view_icon_button.dart';
import '../../widgets/common/view_toolbar.dart';
import '../../widgets/common/zero_items_action_empty_state.dart';
import 'tabs/project_purchase_orders_table_view.dart';
import 'tabs/project_selections_tab.dart';

enum BudgetViewMode {
  workflow,
  estimating,
  purchaseOrders,
  costing,
  invoicing,
  changeOrders,
  selections,
  upgrades,
  holdback,
  profit,
}

enum BudgetPricingInputMode { markup, margin }

class BudgetViewScreen extends StatefulWidget {
  final String projectId;

  /// When [embedded] is true the widget omits its own [Scaffold]/[AppBar],
  /// allowing it to be hosted inside a tab or panel that already provides one.
  /// Action buttons that would normally live in the AppBar are moved into the
  /// shared [TableControlsBar] toolbar instead.
  final bool embedded;

  /// Called when the user confirms the document wizard, passing back the wizard
  /// result so the parent can switch to embedded document creation mode.
  final void Function(BudgetDocumentWizardResult result)? onCreateDocument;

  /// Optional initial view mode for the embedded sub-view dropdown.
  /// Used by deep links such as `?tab=purchase-orders` (legacy) which
  /// now open the Financials tab with the Purchase Orders view selected.
  final BudgetViewMode? initialMode;

  const BudgetViewScreen({
    super.key,
    required this.projectId,
    this.embedded = false,
    this.onCreateDocument,
    this.initialMode,
  });

  @override
  State<BudgetViewScreen> createState() => _BudgetViewScreenState();
}

class _BudgetViewScreenState extends State<BudgetViewScreen> {
  static const List<TableColumnSchema> _estimatingHeaderColumns = [
    TableColumnSchema(id: 'unitCost', label: 'Unit cost', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'unitPrice', label: 'Unit price', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(
      id: 'extendedPrice',
      label: 'Total price',
      defaultWidth: 130,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'profit', label: 'Profit', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(
      id: 'margin',
      label: 'Margin %',
      defaultWidth: 100,
      borderLeft: true,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'markup', label: 'Markup %', defaultWidth: 100, align: TextAlign.right),
    TableColumnSchema(id: 'taxable', label: 'Taxable', defaultWidth: 80),
  ];

  static const List<TableColumnSchema> _costingHeaderColumns = [
    TableColumnSchema(id: 'committed', label: 'Committed', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'actual', label: 'Actual', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'variance', label: 'Variance', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'hoursEst', label: 'Est. hours', defaultWidth: 100, align: TextAlign.right),
    TableColumnSchema(
      id: 'hoursTracked',
      label: 'Tracked hrs',
      defaultWidth: 100,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'laborCost', label: 'Labor cost', defaultWidth: 130, align: TextAlign.right),
  ];

  static const List<TableColumnSchema> _invoicingHeaderColumns = [
    TableColumnSchema(id: 'invoiced', label: 'Invoiced', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'paid', label: 'Collected', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(id: 'remaining', label: 'Remaining', defaultWidth: 130, align: TextAlign.right),
  ];

  static const List<TableColumnSchema> _profitHeaderColumns = [
    TableColumnSchema(
      id: 'actualCost',
      label: 'Actual cost',
      defaultWidth: 130,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'profit', label: 'Profit', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(
      id: 'margin',
      label: 'Margin %',
      defaultWidth: 100,
      borderLeft: true,
      align: TextAlign.right,
    ),
  ];

  static const List<TableColumnSchema> _changeOrdersHeaderColumns = [
    TableColumnSchema(id: 'coNumber', label: 'CO #', defaultWidth: 80),
    TableColumnSchema(id: 'source', label: 'Source', defaultWidth: 100),
    TableColumnSchema(id: 'status', label: 'Status', defaultWidth: 100),
    TableColumnSchema(
      id: 'revenueChange',
      label: 'Revenue Δ',
      defaultWidth: 120,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'costChange', label: 'Cost Δ', defaultWidth: 120, align: TextAlign.right),
    TableColumnSchema(id: 'netChange', label: 'Net Δ', defaultWidth: 120, align: TextAlign.right),
    TableColumnSchema(
      id: 'margin',
      label: 'Margin %',
      defaultWidth: 100,
      borderLeft: true,
      align: TextAlign.right,
    ),
  ];

  static const List<TableColumnSchema> _upgradesHeaderColumns = [
    TableColumnSchema(id: 'isUpgrade', label: 'Upgrade', defaultWidth: 80, align: TextAlign.center),
    TableColumnSchema(id: 'category', label: 'Category', defaultWidth: 120),
    TableColumnSchema(id: 'upgradeStatus', label: 'Status', defaultWidth: 100),
    TableColumnSchema(id: 'price', label: 'Price', defaultWidth: 120, align: TextAlign.right),
    TableColumnSchema(id: 'cost', label: 'Cost', defaultWidth: 120, align: TextAlign.right),
    TableColumnSchema(id: 'profit', label: 'Profit', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(
      id: 'margin',
      label: 'Margin %',
      defaultWidth: 100,
      borderLeft: true,
      align: TextAlign.right,
    ),
    TableColumnSchema(
      id: 'holdbackPct',
      label: 'Holdback %',
      defaultWidth: 100,
      align: TextAlign.right,
    ),
  ];

  static const List<TableColumnSchema> _holdbackHeaderColumns = [
    TableColumnSchema(id: 'approved', label: 'Approved', defaultWidth: 130, align: TextAlign.right),
    TableColumnSchema(
      id: 'holdbackPct',
      label: 'Holdback %',
      defaultWidth: 100,
      align: TextAlign.right,
    ),
    TableColumnSchema(
      id: 'holdbackAmt',
      label: 'Holdback Amt',
      defaultWidth: 130,
      align: TextAlign.right,
    ),
    TableColumnSchema(id: 'released', label: 'Released', defaultWidth: 100),
    TableColumnSchema(
      id: 'collectible',
      label: 'Collectible',
      defaultWidth: 130,
      align: TextAlign.right,
    ),
  ];

  SupabaseBudgetService get _budgetService =>
      ServiceLocator.budgetService as SupabaseBudgetService;
  dynamic get _projectService => ServiceLocator.projectService;
  final _budgetExport = BudgetExport();
  final Set<String> _expandedItems = {};
  bool _allExpanded = true;
  bool _expandInitialized = false;
  static const _expandedPrefsKey = 'budget_expanded';
  final Map<String, double> _actualCosts = {};
  final Map<String, double> _invoicedAmounts = {};
  final Map<String, String> _progressTexts = {};
  final Map<String, BudgetItemDocumentStatus> _documentStatuses = {};
  final Map<String, BudgetItemLaborSummary> _laborSummaries = {};
  final Map<String, String> _changeOrderStatuses = {};
  final Set<String> _taskExpandedItems = {};
  bool _isMetadataLoading = false;
  Project? _project;

  // Workflow view state
  List<GeneratedDocument>? _workflowDocuments;
  bool _workflowDocumentsLoading = false;
  Object? _workflowDocumentsError;
  List<PayApplication> _workflowPayApps = const [];
  final _payAppService = PayApplicationService();

  // Purchase Orders summary, lifted from ProjectPurchaseOrdersTableView so the
  // summary card can render above the shared toolbar (matching the grid views'
  // summary panel placement). Null until the PO streams have loaded.
  ({double committed, double paid, int count})? _poSummary;

  late BudgetViewMode _viewMode =
      widget.initialMode ?? BudgetViewMode.workflow;
  bool _isCardLayout = true;

  // Search state
  String _searchQuery = '';

  // Column visibility state
  TableColumnVisibility _colVis = TableColumnVisibility.empty;
  // Purchase Orders view keeps its own visibility set: its column ids
  // (number/type/title/vendor/...) are unrelated to the budget grid's.
  TableColumnVisibility _poColVis = TableColumnVisibility.empty;
  static const _columnPrefsKey = 'budget_visible_columns';
  static const _poColumnPrefsKey = 'budget_po_visible_columns';
  static const _pricingInputModePrefsKey = 'budget_pricing_input_mode';
  static const _fitToScreenPrefsKey = 'budget_fit_to_screen';
  static const _cardLayoutPrefsKey = 'budget_card_layout';
  static const _showKpiRowPrefsKey = 'budget_show_kpi_row';
  BudgetPricingInputMode _pricingInputMode = BudgetPricingInputMode.markup;
  bool _fitToScreen = false;
  bool _showKpiRow = true;

  // Column sort state
  TableSortState _sortState = const TableSortState();

  // Resizable column widths (overrides; absent = use schema default)
  final Map<String, double> _columnWidths = {};

  void _handleColumnResize(TableColumnResize resize) {
    setState(() {
      _columnWidths[resize.columnId] = resize.width;
    });
  }

  double _colW(String columnId, double defaultWidth) =>
      _columnWidths[columnId] ?? defaultWidth;

  // Column definitions by view mode
  static const _estimatingColumns = [
    'qty',
    'unit',
    'unitCost',
    'unitPrice',
    'extendedPrice',
    'profit',
    'margin',
    'markup',
    'taxable',
  ];
  static const _costingColumns = [
    'qty',
    'unit',
    'committed',
    'actual',
    'variance',
    'hoursEst',
    'hoursTracked',
    'laborCost',
  ];
  static const _invoicingColumns = [
    'qty',
    'unit',
    'invoiced',
    'paid',
    'remaining',
  ];
  static const _profitColumns = [
    'qty',
    'unit',
    'actualCost',
    'profit',
    'margin',
  ];
  static const _changeOrdersColumns = [
    'coNumber',
    'source',
    'status',
    'revenueChange',
    'costChange',
    'netChange',
    'margin',
  ];
  static const _upgradesColumns = [
    'isUpgrade',
    'category',
    'upgradeStatus',
    'price',
    'cost',
    'profit',
    'margin',
    'holdbackPct',
  ];
  static const _holdbackColumns = [
    'approved',
    'holdbackPct',
    'holdbackAmt',
    'released',
    'collectible',
  ];

  static const _columnNames = {
    'qty': 'QTY',
    'unit': 'UNIT',
    'unitCost': 'UNIT COST',
    'unitPrice': 'UNIT PRICE',
    'extendedPrice': 'TOTAL PRICE',
    'profit': 'PROFIT',
    'margin': 'MARGIN %',
    'markup': 'MARKUP %',
    'taxable': 'TAXABLE',
    'committed': 'COMMITTED',
    'actual': 'ACTUAL',
    'variance': 'VARIANCE',
    'hoursEst': 'EST. HOURS',
    'hoursTracked': 'TRACKED HRS',
    'laborCost': 'LABOR COST',
    'invoiced': 'INVOICED',
    'paid': 'COLLECTED',
    'remaining': 'REMAINING',
    'actualCost': 'ACTUAL COST',
    // Change Orders columns
    'coNumber': 'CO #',
    'source': 'SOURCE',
    'revenueChange': 'REVENUE Δ',
    'costChange': 'COST Δ',
    'netChange': 'NET Δ',
    'status': 'STATUS',
    // Upgrades columns
    'isUpgrade': 'UPGRADE',
    'category': 'CATEGORY',
    'upgradeStatus': 'STATUS',
    'price': 'PRICE',
    'cost': 'COST',
    // Holdback columns
    'approved': 'APPROVED',
    'holdbackPct': 'HOLDBACK %',
    'holdbackAmt': 'HOLDBACK AMT',
    'released': 'RELEASED',
    'collectible': 'COLLECTIBLE',
  };

  // Keep leading table geometry aligned across rows, header, add-row and totals.
  static const double _checkboxColumnWidth = 24;
  static const double _afterCheckboxGap = 4;
  static const double _lineItemColumnWidth = 36;
  static const double _afterLineItemGap = 4;
  // Match top-level row name text start (tree chevron placeholder + gaps).
  static const double _nameHeaderInset = 12;
  static const double _tableHorizontalPadding = 10;

  bool get _isNarrowScreen => MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
  bool get _isMobileView => _isNarrowScreen || _isCardLayout;

  void _onBudgetColumnSortTap(String columnId) {
    setState(() => _sortState = _sortState.toggle(columnId));
  }

  Comparator<BudgetItem>? get _budgetSortComparator {
    if (_sortState.column == null) return null;
    final asc = _sortState.ascending;
    return (a, b) {
      int cmp;
      switch (_sortState.column) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case 'id':
          cmp = a.sortOrder.compareTo(b.sortOrder);
          break;
        case 'qty':
          cmp = a.quantity.compareTo(b.quantity);
          break;
        case 'unit':
          cmp = (a.unit ?? '').compareTo(b.unit ?? '');
          break;
        case 'unitCost':
          cmp = a.unitCost.compareTo(b.unitCost);
          break;
        case 'unitPrice':
          cmp = a.unitPrice.compareTo(b.unitPrice);
          break;
        case 'extendedPrice':
          cmp = a.extendedPrice.compareTo(b.extendedPrice);
          break;
        case 'profit':
          cmp = a.projectedProfit.compareTo(b.projectedProfit);
          break;
        case 'margin':
          cmp = a.projectedMargin.compareTo(b.projectedMargin);
          break;
        case 'markup':
          cmp = a.markup.compareTo(b.markup);
          break;
        case 'committed':
          cmp = a.committedCost.compareTo(b.committedCost);
          break;
        case 'actual':
          cmp = a.finalCost.compareTo(b.finalCost);
          break;
        case 'variance':
          final aVar = a.projectedCost - a.finalCost;
          final bVar = b.projectedCost - b.finalCost;
          cmp = aVar.compareTo(bVar);
          break;
        case 'approved':
          cmp = a.approvedPrice.compareTo(b.approvedPrice);
          break;
        case 'holdbackPct':
          cmp = (a.holdbackPercent ?? 0).compareTo(b.holdbackPercent ?? 0);
          break;
        case 'holdbackAmt':
          cmp = a.holdbackAmount.compareTo(b.holdbackAmount);
          break;
        case 'collectible':
          cmp = a.collectibleAmount.compareTo(b.collectibleAmount);
          break;
        case 'price':
          cmp = a.unitPrice.compareTo(b.unitPrice);
          break;
        case 'cost':
          cmp = a.unitCost.compareTo(b.unitCost);
          break;
        default:
          cmp = 0;
      }
      return asc ? cmp : -cmp;
    };
  }

  // Addition state
  String? _addingToParentId;
  int? _addingHierarchyLevel;
  bool _addingAsGroup = false; // Whether we're adding a group or item

  // Selection state
  Set<String> _selectedBudgetItemIds = {};
  List<BudgetItem> _allBudgetItems = [];
  bool _isBudgetItemDragging = false;
  bool _isUngroupDropTargetActive = false;

  // Pre-computed hierarchy maps for O(1) lookups
  Map<String, List<BudgetItem>> _childrenByParentId = {};
  Map<String, BudgetItem> _budgetItemsById = {};
  Map<String, List<BudgetItem>> _descendantsByItemId = {};
  Map<String, List<BudgetItem>> _leafDescendantsByItemId = {};
  Map<String, String> _hierarchicalItemIds = {};

  // Cached future for budget summary to prevent flickering on setState
  Future<BudgetSummary>? _budgetSummaryFuture;
  String? _lastWorkspaceId;
  String? _lastBudgetSummarySignature;
  String? _loadedMetadataKey;
  String? _loadingMetadataKey;

  // Cached streams/futures to prevent recreation on every build
  Future<Project?>? _projectFuture;
  Stream<List<BudgetItem>>? _budgetStream;
  String? _cachedWorkspaceId;

  @override
  void initState() {
    super.initState();
    _loadColumnPreferences();
    if (_viewMode == BudgetViewMode.workflow) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadWorkflowDocuments();
      });
    }
  }

  @override
  void didUpdateWidget(BudgetViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      setState(() {
        _searchQuery = '';
        _selectedBudgetItemIds.clear();
        _expandedItems.clear();
        _taskExpandedItems.clear();
        _addingToParentId = null;
        _addingHierarchyLevel = null;
        _addingAsGroup = false;
        _expandInitialized = false;
        _isBudgetItemDragging = false;
        _isUngroupDropTargetActive = false;
        _allBudgetItems = [];
        _childrenByParentId = {};
        _budgetItemsById = {};
        _descendantsByItemId = {};
        _leafDescendantsByItemId = {};
        _hierarchicalItemIds = {};
        _actualCosts.clear();
        _invoicedAmounts.clear();
        _progressTexts.clear();
        _documentStatuses.clear();
        _laborSummaries.clear();
        _changeOrderStatuses.clear();
        _isMetadataLoading = false;
        _budgetSummaryFuture = null;
        _lastWorkspaceId = null;
        _lastBudgetSummarySignature = null;
        _loadedMetadataKey = null;
        _loadingMetadataKey = null;
        _projectFuture = null;
        _budgetStream = null;
        _cachedWorkspaceId = null;
        _project = null;
        _workflowDocuments = null;
        _workflowPayApps = const [];
        _workflowDocumentsLoading = false;
        _workflowDocumentsError = null;
      });
      if (_viewMode == BudgetViewMode.workflow) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadWorkflowDocuments();
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Currency formatting helpers
  String get _currencyCode => context.read<WorkspaceProvider>().currencyCode;
  String _formatCurrency(double amount) =>
      CurrencyUtils.formatCurrency(amount, _currencyCode);

  /// Modes that render the editable spreadsheet grid (TableLayoutShell).
  /// The shared grid chrome — card/list, expand/collapse, fit-to-screen,
  /// column picker, and the KPI summary panel — only applies to these. The
  /// remaining modes (workflow, purchase orders, selections, holdback, profit)
  /// render their own self-contained widgets, so those controls would be inert.
  bool get _isGridMode {
    switch (_viewMode) {
      case BudgetViewMode.estimating:
      case BudgetViewMode.costing:
      case BudgetViewMode.invoicing:
      case BudgetViewMode.changeOrders:
      case BudgetViewMode.upgrades:
        return true;
      case BudgetViewMode.workflow:
      case BudgetViewMode.purchaseOrders:
      case BudgetViewMode.selections:
      case BudgetViewMode.holdback:
      case BudgetViewMode.profit:
        return false;
    }
  }

  /// Whether the shared toolbar search box can filter the active view. The grid
  /// modes search budget items; the Purchase Orders view filters its own rows.
  /// Other modes have no searchable list, so the box is hidden there.
  bool get _searchAppliesToMode =>
      _isGridMode || _viewMode == BudgetViewMode.purchaseOrders;

  String get _searchHintForMode => _viewMode == BudgetViewMode.purchaseOrders
      ? 'Search purchase orders...'
      : 'Search budget items...';

  /// Starts the create flow for a project purchase order. Routed through the
  /// shared [BudgetDocumentWizard] (pre-filtered to vendor-order templates via
  /// [_defaultCategoryForViewMode]) so creating a PO works exactly like
  /// creating an invoice or change order from the other Financials views. The
  /// PO record is still materialized downstream when the document is finalized.
  void _createPurchaseOrder() {
    final workspaceId = _project?.workspaceId ??
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) {
      // Workspace not resolved yet — fall back to the document create screen.
      context.go(
        '/documents/create?projectId=${Uri.encodeQueryComponent(widget.projectId)}'
        '&prefer_type=request_for_bid',
      );
      return;
    }
    _openDocumentWizard(workspaceId);
  }

  /// Receives the latest Purchase Orders totals from the embedded PO table so
  /// the summary card can be rendered by this screen, above the shared toolbar.
  void _handlePoSummary(double committed, double paid, int count) {
    final existing = _poSummary;
    if (existing != null &&
        existing.committed == committed &&
        existing.paid == paid &&
        existing.count == count) {
      return;
    }
    if (!mounted) return;
    setState(() => _poSummary = (committed: committed, paid: paid, count: count));
  }

  /// Summary panel for the Purchase Orders view, styled to match
  /// [BudgetSummaryPanel] so it sits above the toolbar just like the grid
  /// views' summary.
  Widget _buildPurchaseOrderSummary(
    ({double committed, double paid, int count}) s,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
    final remaining = s.committed - s.paid;

    Widget metric(String label, String value, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    Widget divider() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SizedBox(
            height: 36,
            child: VerticalDivider(
              width: 1,
              thickness: 0.5,
              color: AppColors.cardBorder,
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: metric(
              'Committed',
              _formatCurrency(s.committed),
              AppColors.primary,
            ),
          ),
          divider(),
          Expanded(
            child: metric('Paid', _formatCurrency(s.paid), AppColors.successDark),
          ),
          divider(),
          Expanded(
            child: metric(
              'Remaining',
              _formatCurrency(remaining),
              remaining > 0 ? AppColors.warningDark : AppColors.textSecondary,
            ),
          ),
          divider(),
          Expanded(
            child: metric(
              'Purchase orders',
              '${s.count}',
              AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isNotEmpty) {
        // Auto-expand parents of matching items
        for (final item in _allBudgetItems) {
          if (item.name.toLowerCase().contains(_searchQuery)) {
            _expandAncestors(item);
          }
        }
      }
    });
  }

  void _expandAncestors(BudgetItem item) {
    final ancestors = HierarchyUtils.collectAncestorIds<BudgetItem>(
      item: item,
      itemsById: _budgetItemsById,
      idOf: (i) => i.id,
      parentIdOf: (i) => i.parentId,
    );
    _expandedItems.addAll(ancestors);
  }

  bool _matchesSearch(BudgetItem item) {
    if (_searchQuery.isEmpty) return true;
    if (item.name.toLowerCase().contains(_searchQuery)) return true;
    // Check if any descendant matches
    final descendants = _descendantsByItemId[item.id] ?? [];
    return descendants.any((d) => d.name.toLowerCase().contains(_searchQuery));
  }

  void _expandAll() {
    setState(() {
      for (final item in _allBudgetItems) {
        if (item.itemType == BudgetItemType.group) {
          _expandedItems.add(item.id);
        }
      }
      _allExpanded = true;
    });
    _saveExpandedPreference(true);
  }

  void _collapseAll() {
    setState(() {
      _expandedItems.clear();
      _allExpanded = false;
    });
    _saveExpandedPreference(false);
  }

  Future<void> _saveExpandedPreference(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedPrefsKey, expanded);
  }

  Future<void> _saveFitToScreenPreference(bool fit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fitToScreenPrefsKey, fit);
  }

  Future<void> _saveCardLayoutPreference(bool isCard) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cardLayoutPrefsKey, isCard);
  }

  Future<void> _saveKpiRowPreference(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showKpiRowPrefsKey, show);
  }

  Future<void> _loadColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedColumns = prefs.getStringList(_columnPrefsKey);
    final savedPricingInputMode = prefs.getString(_pricingInputModePrefsKey);
    final savedExpanded = prefs.getBool(_expandedPrefsKey);
    final savedFit = prefs.getBool(_fitToScreenPrefsKey);
    final savedCardLayout = prefs.getBool(_cardLayoutPrefsKey);
    if (savedExpanded != null) {
      _allExpanded = savedExpanded;
    }
    if (savedFit != null) {
      _fitToScreen = savedFit;
    }
    if (savedCardLayout != null) {
      _isCardLayout = savedCardLayout;
    }
    final savedShowKpi = prefs.getBool(_showKpiRowPrefsKey);
    if (savedShowKpi != null) {
      _showKpiRow = savedShowKpi;
    }
    final savedPoColumns = prefs.getStringList(_poColumnPrefsKey);
    _poColVis = TableColumnVisibility(
      savedPoColumns ?? ProjectPurchaseOrdersTableView.columnIds,
    );

    var resolvedPricingMode = BudgetPricingInputMode.markup;
    if (savedPricingInputMode != null) {
      resolvedPricingMode = BudgetPricingInputMode.values.firstWhere(
        (mode) => mode.name == savedPricingInputMode,
        orElse: () => BudgetPricingInputMode.markup,
      );
    }

    if (savedColumns != null) {
      setState(() {
        _colVis = TableColumnVisibility(savedColumns);
        _pricingInputMode = resolvedPricingMode;
      });
    } else {
      // Default: all columns visible
      setState(() {
        _colVis = TableColumnVisibility([
          ..._estimatingColumns,
          ..._costingColumns,
          ..._invoicingColumns,
          ..._profitColumns,
          ..._changeOrdersColumns,
          ..._upgradesColumns,
          ..._holdbackColumns,
        ]);
        _pricingInputMode = resolvedPricingMode;
      });
    }
  }

  Future<void> _saveColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_columnPrefsKey, _colVis.toList());
  }

  void _toggleColumn(String columnId) {
    setState(() => _colVis = _colVis.toggle(columnId));
    _saveColumnPreferences();
  }

  void _togglePoColumn(String columnId) {
    setState(() => _poColVis = _poColVis.toggle(columnId));
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setStringList(_poColumnPrefsKey, _poColVis.toList()),
    );
  }

  List<String> _getColumnsForCurrentMode() {
    switch (_viewMode) {
      case BudgetViewMode.workflow:
        return const []; // Workflow has no table columns
      case BudgetViewMode.purchaseOrders:
        return const []; // Purchase Orders renders its own widget
      case BudgetViewMode.estimating:
        return _estimatingColumns;
      case BudgetViewMode.costing:
        return _costingColumns;
      case BudgetViewMode.invoicing:
        return _invoicingColumns;
      case BudgetViewMode.profit:
        return _profitColumns;
      case BudgetViewMode.changeOrders:
        return _changeOrdersColumns;
      case BudgetViewMode.selections:
        return const []; // Selections renders its own widget
      case BudgetViewMode.upgrades:
        return _upgradesColumns;
      case BudgetViewMode.holdback:
        return _holdbackColumns;
    }
  }

  bool _isColumnVisible(String columnId) => _colVis.isVisible(columnId);

  void _refreshBudgetSummary(String workspaceId) {
    _budgetSummaryFuture = _budgetService.calculateBudgetSummary(
      widget.projectId,
      workspaceId,
    );
    _lastWorkspaceId = workspaceId;
  }

  /// Pre-compute hierarchy relationships for O(1) lookups
  void _buildHierarchyMaps(List<BudgetItem> items) {
    _budgetItemsById = {for (final item in items) item.id: item};
    _childrenByParentId = HierarchyUtils.buildChildrenMap<BudgetItem>(
      items,
      idOf: (item) => item.id,
      parentIdOf: (item) => item.parentId,
      rootKey: '',
      sort: (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );

    // Pre-compute all descendants for each item
    _descendantsByItemId = {};
    _leafDescendantsByItemId = {};
    for (final item in items) {
      final descendants = HierarchyUtils.collectDescendants<BudgetItem>(
        item.id,
        _childrenByParentId,
        idOf: (i) => i.id,
      );
      _descendantsByItemId[item.id] = descendants;
      _leafDescendantsByItemId[item.id] = descendants
          .where((d) => d.itemType == BudgetItemType.item)
          .toList();
    }
  }

  String _buildItemsSignature(List<BudgetItem> items) {
    if (items.isEmpty) return '';
    final parts =
        items
            .map(
              (item) => '${item.id}:${item.updatedAt.millisecondsSinceEpoch}',
            )
            .toList()
          ..sort();
    return parts.join('|');
  }

  String _buildMetadataKey(
    String projectId,
    String workspaceId,
    List<BudgetItem> items,
  ) {
    final signature = _buildItemsSignature(items);
    if (signature.isEmpty) return '';
    return '$projectId|$workspaceId|$signature';
  }

  bool _matchesDirectModeFilter(BudgetItem item) {
    switch (_viewMode) {
      case BudgetViewMode.changeOrders:
        return item.sourceType == BudgetItemSource.changeOrder;
      case BudgetViewMode.holdback:
        return item.hasHoldback;
      // Upgrades now mirrors the Budget view (all items visible) so the user
      // can toggle each line on/off as an upgrade via the checkbox column.
      case BudgetViewMode.upgrades:
      case BudgetViewMode.selections:
      case BudgetViewMode.workflow:
      case BudgetViewMode.estimating:
      case BudgetViewMode.purchaseOrders:
      case BudgetViewMode.costing:
      case BudgetViewMode.invoicing:
      case BudgetViewMode.profit:
        return true;
    }
  }

  /// Source type to assign to newly-created budget items based on the
  /// active view mode. Items added from the Change Orders / Upgrades tabs
  /// are tagged accordingly so they appear in those filtered views.
  BudgetItemSource _sourceTypeForCurrentMode() {
    switch (_viewMode) {
      case BudgetViewMode.changeOrders:
        return BudgetItemSource.changeOrder;
      case BudgetViewMode.upgrades:
        return BudgetItemSource.upgrade;
      default:
        return BudgetItemSource.base;
    }
  }

  List<BudgetItem> _itemsForCurrentMode(List<BudgetItem> allItems) {
    if (_viewMode == BudgetViewMode.selections ||
        _viewMode == BudgetViewMode.purchaseOrders) {
      return const [];
    }
    if (_viewMode == BudgetViewMode.workflow ||
        _viewMode == BudgetViewMode.estimating ||
        _viewMode == BudgetViewMode.costing ||
        _viewMode == BudgetViewMode.invoicing ||
        _viewMode == BudgetViewMode.profit) {
      return allItems;
    }

    final includedIds = <String>{};
    for (final item in allItems) {
      if (!_matchesDirectModeFilter(item)) continue;
      includedIds.add(item.id);
      if (item.itemType == BudgetItemType.group) {
        includedIds.addAll(
          (_descendantsByItemId[item.id] ?? const <BudgetItem>[]).map(
            (descendant) => descendant.id,
          ),
        );
      }
    }

    return allItems.where((item) => includedIds.contains(item.id)).toList();
  }

  void _buildHierarchicalItemIds(List<BudgetItem> topLevelItems) {
    _hierarchicalItemIds = {};
    _assignHierarchicalIds(topLevelItems, '');
  }

  void _assignHierarchicalIds(List<BudgetItem> siblings, String prefix) {
    for (int i = 0; i < siblings.length; i++) {
      final item = siblings[i];
      final itemNumber = prefix.isEmpty ? '${i + 1}' : '$prefix.${i + 1}';
      _hierarchicalItemIds[item.id] = itemNumber;
      final children = _childrenByParentId[item.id] ?? const <BudgetItem>[];
      if (children.isNotEmpty) {
        _assignHierarchicalIds(children, itemNumber);
      }
    }
  }

  void _initializeStreams(String workspaceId) {
    _projectFuture ??= _projectService.getProject(widget.projectId);
    if (_budgetStream == null || _cachedWorkspaceId != workspaceId) {
      _budgetStream = _budgetService.getBudgetItems(
        widget.projectId,
        workspaceId: workspaceId,
      );
      _cachedWorkspaceId = workspaceId;
    }
  }

  Future<void> _loadWorkflowDocuments() async {
    if (_workflowDocuments != null || _workflowDocumentsLoading) return;
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null) return;
    final projectId = widget.projectId;
    setState(() {
      _workflowDocumentsLoading = true;
      _workflowDocumentsError = null;
    });
    try {
      final documentService = ServiceLocator.documentService;
      final List<GeneratedDocument> docs = await documentService
          .getDocumentsOnce(workspaceId, projectId: projectId);
      // Also fetch pay-app headers so the AIA Pay App workflow node
      // shows live status. Failure here is non-fatal — the node falls
      // back to "Not Started".
      List<PayApplication> payApps = const [];
      try {
        payApps = await _payAppService.listForProject(projectId);
      } catch (_) {
        payApps = const [];
      }
      if (mounted && widget.projectId == projectId) {
        setState(() {
          _workflowDocuments = docs;
          _workflowPayApps = payApps;
          _workflowDocumentsLoading = false;
        });
      }
    } catch (e) {
      // Record the failure instead of silently clearing the flag: the build
      // method only auto-schedules a load while there is no error, so a
      // persistent failure shows the error state once rather than looping
      // spinner -> one-frame content flash -> spinner forever.
      if (mounted && widget.projectId == projectId) {
        setState(() {
          _workflowDocumentsLoading = false;
          _workflowDocumentsError = e;
        });
      }
    }
  }

  /// Workflow canvas wrapped in the shared async chrome (spinner / error +
  /// retry). "Documents not yet requested" counts as loading so the canvas
  /// never paints a frame of empty data before the post-frame load runs.
  Widget _buildWorkflowContent(
    List<BudgetItem> displayedItems, {
    required bool compact,
  }) {
    return AsyncStateView(
      isLoading:
          _workflowDocumentsLoading ||
          (_workflowDocuments == null && _workflowDocumentsError == null),
      error: _workflowDocumentsError,
      errorAction: 'load financial documents',
      onRetry: _loadWorkflowDocuments,
      builder: (context) => BudgetWorkflowView(
        state: FinancialWorkflowBuilder.build(
          documents: _workflowDocuments ?? [],
          budgetItems: displayedItems,
          holdbackBreakdown: BudgetTabMetrics.holdbackBreakdown(
            allItems: displayedItems,
            invoicedAmounts: _invoicedAmounts,
            invoices: _workflowDocuments ?? const [],
          ),
          formatCurrency: _formatCurrency,
          actualCosts: _actualCosts,
          payApplications: _workflowPayApps,
        ),
        projectName: _project?.name ?? 'Job',
        formatCurrency: _formatCurrency,
        compact: compact,
        onNodeTap: _handleWorkflowNodeTap,
        onBandTap: (mode) => setState(() => _viewMode = mode),
      ),
    );
  }

  void _handleWorkflowNodeTap(WorkflowNode node) {
    if (node.blockedReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(node.blockedReason!)),
      );
      return;
    }

    if (node.documentId != null) {
      context.push('/documents/${node.documentId}');
      return;
    }

    switch (node.id) {
      case 'create_budget_items':
      case 'scope_confirmed':
        setState(() => _viewMode = BudgetViewMode.estimating);
        return;
      case 'work_authorization':
        _startCreateForType(DocumentType.workAuthServices);
        return;
      case 'track_costs':
        _startCreateForType(DocumentType.bill);
        return;
      case 'create_estimate':
        _startCreateForType(DocumentType.quotation);
        return;
      case 'committed_budget':
        _startCreateForType(DocumentType.purchaseOrder);
        return;
      case 'collect_deposit':
        _startCreateForType(DocumentType.deposit);
        return;
      case 'cost_variance':
        setState(() => _viewMode = BudgetViewMode.costing);
        return;
      case 'change_order':
        setState(() => _viewMode = BudgetViewMode.changeOrders);
        return;
      case 'add_to_invoice':
        _startInvoiceFromApprovedChangeOrders();
        return;
      case 'customer_upgrade':
        setState(() => _viewMode = BudgetViewMode.upgrades);
        return;
      case 'bill_separately':
        _startInvoiceFromAcceptedUpgrades();
        return;
      case 'send_invoice':
        _startCreateForType(DocumentType.invoice);
        return;
      case 'progress_invoice':
        _startCreateForType(DocumentType.progressInvoice);
        return;
      case 'final_invoice':
        _startCreateForType(DocumentType.invoice);
        return;
      case 'receive_payment':
      case 'outstanding_balance':
        setState(() => _viewMode = BudgetViewMode.invoicing);
        return;
      case 'aia_pay_app':
        context.go('/projects/${widget.projectId}/pay-applications');
        return;
      case 'release_holdback':
        context.go('/projects/${widget.projectId}/holdback-releases');
        return;
      case 'holdback_withheld':
        setState(() => _viewMode = BudgetViewMode.holdback);
        return;
      case 'credit_note':
        _startCreateForType(DocumentType.credit);
        return;
      case 'refund_adjustment':
        _startCreateForType(DocumentType.refund);
        return;
    }
  }

  /// Start creating a new document of [type] for this project, pre-loading the
  /// workspace default template for that type when one exists. Used by the
  /// workflow's action nodes (e.g. "Add Bill / Expense") so a click takes the
  /// user straight into the relevant create form instead of a blank wizard.
  Future<void> _startCreateForType(DocumentType type) async {
    final workspaceId = _project?.workspaceId;
    if (workspaceId == null) {
      context.push('/documents/create?projectId=${widget.projectId}');
      return;
    }
    try {
      final template = await ServiceLocator.documentTemplateService
          .getDefaultTemplate(workspaceId, type);
      if (!mounted) return;
      final query = StringBuffer('projectId=${widget.projectId}');
      if (template != null) {
        query.write('&templateId=${template.id}');
      }
      context.push('/documents/create?$query');
      if (template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No default ${type.displayName} template found. Pick one to continue.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      context.push('/documents/create?projectId=${widget.projectId}');
    }
  }

  /// Add to Invoice — collect approved change-order line items that aren't
  /// already invoiced and deep-link into the document create screen with the
  /// invoice template and the budget items pre-selected. Previously this
  /// just switched the budget view mode and did nothing actionable.
  Future<void> _startInvoiceFromApprovedChangeOrders() async {
    final approvedCoIds = (_workflowDocuments ?? <GeneratedDocument>[])
        .where((d) =>
            d.documentType == DocumentType.changeOrder &&
            (d.status == DocumentStatus.approved ||
                d.status == DocumentStatus.signed))
        .map((d) => d.id)
        .toSet();

    final coItems = _allBudgetItems
        .where((b) =>
            b.itemType == BudgetItemType.item &&
            b.sourceType == BudgetItemSource.changeOrder &&
            b.changeOrderId != null &&
            approvedCoIds.contains(b.changeOrderId))
        .toList();

    if (coItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No approved change-order line items to add to an invoice yet.',
          ),
        ),
      );
      return;
    }

    final selectedIds = coItems.map((b) => b.id).toList();
    final amounts = <String, double>{
      for (final b in coItems) b.id: b.approvedPrice,
    };

    // Preselect the workspace's default invoice template so the user lands
    // on the right doc type — otherwise the document picker defaults to
    // Vendor Bill, which is wrong for "Add to Invoice".
    final workspaceId = _project?.workspaceId;
    String? templateId;
    if (workspaceId != null) {
      try {
        final template = await ServiceLocator.documentTemplateService
            .getDefaultTemplate(workspaceId, DocumentType.invoice);
        templateId = template?.id;
      } catch (_) {
        // Best-effort — fall through without a template if the lookup fails.
      }
    }
    if (!mounted) return;

    final query = StringBuffer('projectId=${widget.projectId}');
    if (templateId != null) {
      query.write('&templateId=$templateId');
    }

    context.push(
      '/documents/create?$query',
      extra: <String, dynamic>{
        'selectedBudgetItemIds': selectedIds,
        'budgetItemAmounts': amounts,
      },
    );
  }

  /// Bill accepted customer upgrades on a fresh invoice. Mirrors the
  /// change-order flow: gather accepted upgrade budget items, preselect the
  /// workspace's default invoice template, and push the create-document
  /// screen with those items pre-selected.
  Future<void> _startInvoiceFromAcceptedUpgrades() async {
    final acceptedUpgrades = _allBudgetItems
        .where((b) =>
            b.itemType == BudgetItemType.item &&
            b.sourceType == BudgetItemSource.upgrade &&
            b.upgradeStatus == UpgradeStatus.accepted)
        .toList();

    if (acceptedUpgrades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mark a customer upgrade as accepted before adding it to an invoice.',
          ),
        ),
      );
      return;
    }

    final selectedIds = acceptedUpgrades.map((b) => b.id).toList();
    final amounts = <String, double>{
      for (final b in acceptedUpgrades) b.id: b.approvedPrice,
    };

    final workspaceId = _project?.workspaceId;
    String? templateId;
    if (workspaceId != null) {
      try {
        final template = await ServiceLocator.documentTemplateService
            .getDefaultTemplate(workspaceId, DocumentType.invoice);
        templateId = template?.id;
      } catch (_) {}
    }
    if (!mounted) return;

    final query = StringBuffer('projectId=${widget.projectId}');
    if (templateId != null) {
      query.write('&templateId=$templateId');
    }

    context.push(
      '/documents/create?$query',
      extra: <String, dynamic>{
        'selectedBudgetItemIds': selectedIds,
        'budgetItemAmounts': amounts,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      const errorMsg = 'Error: No workspace found';
      debugPrint(errorMsg);
      if (widget.embedded) {
        return const Center(child: SelectableText(errorMsg));
      }
      return const Scaffold(body: Center(child: SelectableText(errorMsg)));
    }

    // Initialize cached streams/futures
    _initializeStreams(workspaceId);
    if ((_viewMode == BudgetViewMode.workflow ||
            _viewMode == BudgetViewMode.holdback) &&
        _workflowDocuments == null &&
        !_workflowDocumentsLoading &&
        _workflowDocumentsError == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadWorkflowDocuments();
      });
    }

    final body = FutureBuilder<Project?>(
      future: _projectFuture,
      builder: (context, projectSnapshot) {
        if (projectSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (projectSnapshot.hasError) {
          final errorMsg = UserFacingError.uiMessage(
            projectSnapshot.error,
            action: 'load this project',
          );
          debugPrint(errorMsg);
          return Center(child: SelectableText(errorMsg));
        }

        final project = projectSnapshot.data;
        if (project == null) {
          return Center(child: Text('$singular not found'));
        }
        _project = project;

        return StreamBuilder<List<BudgetItem>>(
          stream: _budgetStream,
          builder: (context, budgetSnapshot) {
            if (budgetSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (budgetSnapshot.hasError) {
              final errorMsg = UserFacingError.uiMessage(
                budgetSnapshot.error,
                action: 'load budget items',
              );
              debugPrint(errorMsg);
              return Center(child: SelectableText(errorMsg));
            }

            final budgetItems = budgetSnapshot.data ?? [];
            _allBudgetItems = budgetItems;

            // Always rebuild hierarchy maps when stream emits new data
            // (items may have moved even if count stays the same)
            _buildHierarchyMaps(budgetItems);

            final budgetSummarySignature = _buildItemsSignature(budgetItems);
            final metadataKey = _buildMetadataKey(
              widget.projectId,
              workspaceId,
              budgetItems,
            );

            // Auto-expand on first load if preference is set
            if (!_expandInitialized && budgetItems.isNotEmpty) {
              _expandInitialized = true;
              if (_allExpanded) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _expandAll();
                });
              }
            }

            // Refresh budget summary and metadata if workspace changed, first load, or items changed
            // Always show the table structure (even when empty) so users can add items
            if (budgetItems.isNotEmpty &&
                (_budgetSummaryFuture == null ||
                    _lastWorkspaceId != workspaceId ||
                    _lastBudgetSummarySignature != budgetSummarySignature)) {
              _lastBudgetSummarySignature = budgetSummarySignature;
              _refreshBudgetSummary(workspaceId);
            }

            if (budgetItems.isNotEmpty &&
                metadataKey.isNotEmpty &&
                metadataKey != _loadedMetadataKey &&
                metadataKey != _loadingMetadataKey) {
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _loadProjectMetadata(
                    widget.projectId,
                    workspaceId,
                    metadataKey: metadataKey,
                  );
                }
              });
            }

            return Column(
              children: [
                // Only show the generic budget summary panel on the editable
                // grid modes. Workflow, Purchase Orders and Selections bring
                // their own header chrome, while Profit and Holdback render
                // their own breakdown views — showing this panel above those
                // would duplicate the summary.
                if (budgetItems.isNotEmpty && _isGridMode)
                  FutureBuilder<BudgetSummary>(
                    future: _budgetSummaryFuture,
                    builder: (context, summarySnapshot) {
                      if (summarySnapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          child: Text(
                            UserFacingError.uiMessage(
                              summarySnapshot.error,
                              action: 'load budget summary',
                            ),
                            style: const TextStyle(color: AppColors.error),
                          ),
                        );
                      }
                      if (!summarySnapshot.hasData) {
                        // Show loading placeholder to prevent layout shift
                        return _buildSummaryPlaceholder();
                      }
                      final sm = BudgetTabMetrics.summaryMetrics(
                        summarySnapshot.data!,
                        budgetItems,
                      );
                      final displayedForKpi = _itemsForCurrentMode(budgetItems);
                      final viewKpis = _showKpiRow && displayedForKpi.isNotEmpty
                          ? BudgetTabMetrics.kpisForMode(
                              mode: _viewMode,
                              // KPI builders filter to the subset they need
                              // (base vs CO, holdback items, etc.), so they must
                              // see ALL items — not just the current mode's
                              // filtered rows. Otherwise modes like Change Orders
                              // lose their base contract ("Original contract"
                              // shows $0) and Holdback under-counts invoiced.
                              allItems: budgetItems,
                              actualCosts: _actualCosts,
                              invoicedAmounts: _invoicedAmounts,
                              formatCurrency: _formatCurrency,
                              changeOrderStatuses: _changeOrderStatuses,
                            )
                          : <TabKpi>[];
                      return Column(
                        children: [
                          BudgetSummaryPanel(
                            metrics: sm,
                            formatCurrency: _formatCurrency,
                            hasApprovedEstimate:
                                project.status.isEstimateApproved,
                            viewKpis: viewKpis,
                          ),
                          if (_viewMode != BudgetViewMode.upgrades)
                            _SelectionsBudgetCard(
                              projectId: widget.projectId,
                              formatCurrency: _formatCurrency,
                            ),
                        ],
                      );
                    },
                  ),

                // Purchase Orders summary — rendered here (above the toolbar)
                // so it mirrors the grid views' summary-panel placement, and
                // gated on the same toolbar toggle as the grid KPI cards.
                // Totals are lifted from the embedded PO table via
                // _handlePoSummary.
                if (_viewMode == BudgetViewMode.purchaseOrders &&
                    _poSummary != null &&
                    _showKpiRow)
                  _buildPurchaseOrderSummary(_poSummary!),

                // Budget Table
                Expanded(child: _buildBudgetTable(budgetItems, workspaceId)),
              ],
            );
          },
        );
      },
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text('$singular Budget'),
        actions: _buildAppBarActions(workspaceId),
      ),
      body: Column(
        children: [
          BreadcrumbBar(
            items: [
              BreadcrumbItem(
                label: projectTerminology,
                onTap: () => context.go('/projects'),
              ),
              BreadcrumbItem(
                label: _project?.name ?? singular,
                onTap: () => context.go('/projects/${widget.projectId}'),
              ),
              const BreadcrumbItem(label: 'Budget'),
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions(String workspaceId) {
    final hasSelection = _selectedBudgetItemIds.isNotEmpty;
    final docLabel = _toolbarDocLabel(_viewMode);
    return [
      FilledButton.tonalIcon(
        onPressed: () => showAiTakeoffWizard(
          context,
          projectId: widget.projectId,
          workspaceId: workspaceId,
          project: _project,
          onComplete: () => _refreshBudgetSummary(workspaceId),
        ),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('AI Takeoff'),
        style: FilledButton.styleFrom(
          foregroundColor: AppColors.secondaryDark,
          backgroundColor: AppColors.secondarySurface,
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.download_outlined),
        onPressed: () => _showImportCatalogDialog(workspaceId),
        tooltip: 'Import from Catalog',
      ),
      IconButton(
        icon: const Icon(Icons.upload_outlined),
        onPressed: () => _showExportDialog(workspaceId),
        tooltip: 'Export Budget',
      ),
      IconButton(
        icon: const Icon(Icons.copy_all),
        onPressed: () => _showExportToCatalogDialog(workspaceId),
        tooltip: 'Copy to Catalog',
      ),
      if (docLabel != null)
        _buildCreateDocButton(
          label: docLabel,
          onPressed: () => _openDocumentWizard(
            workspaceId,
            preSelectedIds: hasSelection ? _selectedBudgetItemIds : null,
          ),
        ),
      if (hasSelection) ...[
        const SizedBox(width: 8),
        _buildSelectionActionsMenu(
          groupable: _selectionMetrics().groupable,
        ),
      ],
    ];
  }

  /// Computes selection metrics used by both the selection bar and toolbar.
  ({int ungroupable, bool groupable, int invoiceable, int descendants})
  _selectionMetrics() {
    final selectedRootItems = _getSelectedRootItems();
    final ungroupable = selectedRootItems
        .where((item) => item.parentId != null)
        .length;

    // Groupable: 2+ root items that all share the same parent
    final groupable =
        selectedRootItems.length >= 2 &&
        selectedRootItems.map((i) => i.parentId).toSet().length == 1;

    final leafItemsFromSelection = <BudgetItem>{};
    for (final itemId in _selectedBudgetItemIds) {
      final item = _allBudgetItems.firstWhereOrNull((i) => i.id == itemId);
      if (item == null) continue;
      if (item.itemType == BudgetItemType.item) {
        leafItemsFromSelection.add(item);
      } else {
        leafItemsFromSelection.addAll(_leafDescendantsByItemId[item.id] ?? []);
      }
    }
    final invoiceable = leafItemsFromSelection.length;

    final descendants = _selectedBudgetItemIds
        .map((id) => _descendantsByItemId[id]?.length ?? 0)
        .fold(0, (a, b) => a + b);

    return (
      ungroupable: ungroupable,
      groupable: groupable,
      invoiceable: invoiceable,
      descendants: descendants,
    );
  }

  List<PopupMenuEntry<String>> _selectionActionMenuItems(bool groupable) {
    return [
      PopupMenuItem(
        value: 'group',
        enabled: groupable,
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: groupable ? null : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              'Group',
              style: groupable
                  ? null
                  : TextStyle(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
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
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'edit_selected',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 16, color: AppColors.infoDark),
            SizedBox(width: 8),
            Text(
              'Edit Selected',
              style: TextStyle(color: AppColors.infoDark),
            ),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'delete_selected',
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: AppColors.errorDark),
            SizedBox(width: 8),
            Text(
              'Delete Selected',
              style: TextStyle(color: AppColors.errorDark),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSelectionActionsMenu({
    required bool groupable,
    Offset menuOffset = const Offset(0, 32),
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      offset: menuOffset,
      itemBuilder: (_) => _selectionActionMenuItems(groupable),
      onSelected: _handleSelectionAction,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Actions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectionActions(ButtonStyle style) {
    final m = _selectionMetrics();
    return [
      if (m.ungroupable > 0)
        TextButton.icon(
          onPressed: _handleUngroupSelection,
          icon: const Icon(Icons.format_indent_decrease, size: 18),
          label: const Text('Ungroup'),
          style: style,
        ),
      _buildSelectionActionsMenu(
        groupable: m.groupable,
        menuOffset: const Offset(0, -4),
      ),
    ];
  }

  void _handleSelectionAction(String value) {
    switch (value) {
      case 'group':
        _handleGroupSelection();
      case 'save_catalog':
        _handleSaveSelectionToCatalog();
      case 'save_template':
        _handleSaveSelectionAsTemplate();
      case 'edit_selected':
        _handleMassEdit();
      case 'delete_selected':
        _handleMassDelete();
    }
  }

  Widget _buildInlineSelectionBar() {
    final m = _selectionMetrics();
    final count = _selectedBudgetItemIds.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          if (m.descendants > 0) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.account_tree_outlined,
              size: 13,
              color: AppColors.infoDark,
            ),
            const SizedBox(width: 2),
            Text(
              '+${m.descendants}',
              style: TextStyle(
                color: AppColors.infoDark,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (m.invoiceable > 0) ...[
            const SizedBox(width: 6),
            Text(
              '(${m.invoiceable} invoiceable)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear selection',
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 52, // Match the height of the compact summary card
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildBudgetTable(List<BudgetItem> allItems, String workspaceId) {
    final displayedItems = _itemsForCurrentMode(allItems);
    final topLevelItems = displayedItems.where((item) {
      final parentId = item.parentId;
      return parentId == null ||
          !displayedItems.any((candidate) => candidate.id == parentId);
    }).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _buildHierarchicalItemIds(topLevelItems);

    // Purchase Orders is handled by the mobile view (purchaseOrdersContent)
    // and the desktop Stack branch below — both keep the shared toolbar/
    // dropdown chrome, so there is intentionally no early return here.

    if (_isMobileView) {
      return BudgetMobileView(
        displayedItems: displayedItems,
        workspaceId: workspaceId,
        viewMode: _viewMode,
        formatCurrency: _formatCurrency,
        expandedItems: _expandedItems,
        selectedItemIds: _selectedBudgetItemIds,
        childrenByParentId: _childrenByParentId,
        leafDescendantsByItemId: _leafDescendantsByItemId,
        hierarchicalItemIds: _hierarchicalItemIds,
        actualCosts: _actualCosts,
        invoicedAmounts: _invoicedAmounts,
        changeOrderStatuses: _changeOrderStatuses,
        searchQuery: _searchQuery,
        sortComparator: _budgetSortComparator,
        addingToParentId: _addingToParentId,
        addingHierarchyLevel: _addingHierarchyLevel,
        controlsBar: _buildMobileBudgetControls(workspaceId),
        profitBreakdown: _viewMode == BudgetViewMode.profit
            ? BudgetTabMetrics.profitBreakdown(
                allItems: displayedItems,
                actualCosts: _actualCosts,
                invoicedAmounts: _invoicedAmounts,
                formatCurrency: _formatCurrency,
                changeOrderStatuses: _changeOrderStatuses,
              )
            : null,
        holdbackBreakdown: _viewMode == BudgetViewMode.holdback
            ? BudgetTabMetrics.holdbackBreakdown(
                // Use the full item set (matches the desktop holdback view),
                // not the holdback-filtered rows, so "Total invoiced" counts
                // every billed line, not just holdback-tagged ones.
                allItems: allItems,
                invoicedAmounts: _invoicedAmounts,
                invoices: _workflowDocuments ?? const [],
              )
            : null,
        workflowContent: _viewMode == BudgetViewMode.workflow
            ? _buildWorkflowContent(displayedItems, compact: true)
            : null,
        purchaseOrdersContent:
            _viewMode == BudgetViewMode.purchaseOrders && _project != null
                ? ProjectPurchaseOrdersTableView(
                    project: _project!,
                    currencyCode: _currencyCode,
                    searchQuery: _searchQuery,
                    onCreatePurchaseOrder: _createPurchaseOrder,
                    onSummary: _handlePoSummary,
                    fitToScreen: _fitToScreen,
                    isColumnVisible: _poColVis.isVisible,
                    // The mobile/card path always renders cards, matching how
                    // the budget grid modes force cards here; the flat table
                    // is the desktop "List" layout below.
                    cardLayout: true,
                  )
                : null,
        selectionsContent:
            _viewMode == BudgetViewMode.selections && _project != null
                ? Column(
                    children: [
                      _SelectionsBudgetCard(
                        projectId: widget.projectId,
                        formatCurrency: _formatCurrency,
                      ),
                      Expanded(
                        child: ProjectSelectionsTab(project: _project!),
                      ),
                    ],
                  )
                : null,
        onToggleExpansion: (id) {
          setState(() {
            if (_expandedItems.contains(id)) {
              _expandedItems.remove(id);
            } else {
              _expandedItems.add(id);
            }
          });
        },
        onSelectionChanged: (item, selected) =>
            _handleBudgetItemSelectionChanged(item, selected),
        onEdit: _handleEditItem,
        onDelete: _handleDeleteItem,
        onDuplicate: _handleDuplicateItem,
        onGroup: _handleGroupItem,
        onUngroup: _handleUngroupGroup,
        onAdd: _handleAddItem,
        onSaveAsTemplate: _handleSaveAsTemplate,
        onMove: _moveItemWithinSiblings,
        onItemChanged: _handleItemChanged,
        onSearchChanged: _onSearchChanged,
        buildInlineAddRow:
            ({
              required String workspaceId,
              required String? parentId,
              required int hierarchyLevel,
              required int indentLevel,
            }) => _buildInlineBudgetAddRow(
              workspaceId: workspaceId,
              parentId: parentId,
              hierarchyLevel: hierarchyLevel,
              indentLevel: indentLevel,
            ),
        isLastVisibleRowInParentSubtree:
            (entries, {required rowIndex, required parentId}) =>
                _isLastVisibleRowInParentSubtree(
                  entries,
                  rowIndex: rowIndex,
                  parentId: parentId,
                ),
        isItemVisibleInSearch: _isItemVisibleInSearch,
        hasApprovedEstimate: _project?.status.isEstimateApproved ?? false,
        emptyStateContent: _emptyStateContentForMode(),
      );
    }

    // Build hierarchy tree - use pre-computed map for top-level items
    final flattenedRows = _buildFlattenedBudgetRows(
      displayedItems,
      workspaceId,
    );
    final minTableWidth = _fitToScreen
        ? 0.0
        : (_viewMode == BudgetViewMode.profit ? 1200.0 : 1600.0);

    return Stack(
      children: [
        Column(
          children: [
            ViewToolbar(
              searchHint: _searchHintForMode,
              searchQuery: _searchQuery,
              onSearch: _onSearchChanged,
              showSearch: _searchAppliesToMode,
              centerSlot: _buildViewModeToggle(),
              quickToggles: _buildQuickToggles(workspaceId),
            ),
            if (_viewMode == BudgetViewMode.workflow)
              Flexible(
                child: SingleChildScrollView(
                  child: _buildWorkflowContent(displayedItems, compact: false),
                ),
              )
            else if (_viewMode == BudgetViewMode.purchaseOrders)
              Expanded(
                child: _project == null
                    ? const SizedBox.shrink()
                    : ProjectPurchaseOrdersTableView(
                        project: _project!,
                        currencyCode: _currencyCode,
                        searchQuery: _searchQuery,
                        onCreatePurchaseOrder: _createPurchaseOrder,
                        onSummary: _handlePoSummary,
                        fitToScreen: _fitToScreen,
                        isColumnVisible: _poColVis.isVisible,
                      ),
              )
            else if (_viewMode == BudgetViewMode.holdback)
              // Holdback view always renders so it can show invoice-level
              // retainage even when no budget items are tagged with holdback.
              // The empty-state branch below would otherwise hide it.
              Flexible(
                child: SingleChildScrollView(
                  child: BudgetHoldbackView(
                    breakdown: BudgetTabMetrics.holdbackBreakdown(
                      allItems: _allBudgetItems,
                      invoicedAmounts: _invoicedAmounts,
                      invoices: _workflowDocuments ?? const [],
                    ),
                    formatCurrency: _formatCurrency,
                    projectId: widget.projectId,
                  ),
                ),
              )
            else if (displayedItems.isEmpty && _addingHierarchyLevel == null)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final es = _emptyStateContentForMode();
                    return ZeroItemsActionEmptyState(
                      icon: es.icon,
                      title: es.title,
                      subtitle: es.subtitle,
                      ctaLabel: es.ctaLabel,
                      hintText: 'Use Add Item or Add Group to get started',
                      onTap: () => _handleAddItem(null, 0, isGroup: false),
                      secondaryAction: TextButton.icon(
                        onPressed: () => _handleAddItem(null, 0, isGroup: true),
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 16,
                        ),
                        label: const Text('Add Group'),
                      ),
                    );
                  },
                ),
              )
            else if (_viewMode == BudgetViewMode.profit)
              Flexible(
                child: SingleChildScrollView(
                  child: BudgetProfitView(
                    breakdown: BudgetTabMetrics.profitBreakdown(
                      allItems: displayedItems,
                      actualCosts: _actualCosts,
                      invoicedAmounts: _invoicedAmounts,
                      formatCurrency: _formatCurrency,
                      changeOrderStatuses: _changeOrderStatuses,
                    ),
                    formatCurrency: _formatCurrency,
                  ),
                ),
              )
            else if (_viewMode == BudgetViewMode.selections)
              Expanded(
                child: _project == null
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _SelectionsBudgetCard(
                            projectId: widget.projectId,
                            formatCurrency: _formatCurrency,
                          ),
                          Expanded(
                            child: ProjectSelectionsTab(project: _project!),
                          ),
                        ],
                      ),
              )
            else
              Expanded(
                // Spreadsheet-style typography for the whole budget grid:
                // tabular figures so columns of numbers line up, slightly
                // smaller default font, and a tighter line-height to match
                // the new 32px row chrome.
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  child: TableLayoutShell(
                    minTableWidth: minTableWidth,
                    footer: _buildSummaryFooter(displayedItems),
                    header: _buildTableHeader(displayedItems),
                    body: ListView.builder(
                      itemCount: flattenedRows.length,
                      itemBuilder: (context, index) => flattenedRows[index],
                    ),
                    showHeaderDivider: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Desktop toolbar quick-toggles, scoped to the active view mode so inert
  /// controls (column picker, expand/collapse, etc.) don't appear on views
  /// that render their own widget rather than the editable grid.
  List<Widget> _buildQuickToggles(String workspaceId) {
    if (_viewMode == BudgetViewMode.purchaseOrders) {
      // Same control order as the grid views below; expand/collapse is
      // omitted because the flat PO list has no hierarchy for it to act on.
      return [
        _buildCardListViewToggle(),
        _buildFitToScreenToggle(),
        _buildKpiRowToggle(),
        _buildPoColumnPicker(),
        if (widget.embedded)
          _buildCreateDocButton(
            label: 'New Purchase Order',
            onPressed: _createPurchaseOrder,
          ),
      ];
    }
    if (!_isGridMode) return const []; // workflow, profit, holdback, selections
    return [
      _buildCardListViewToggle(),
      _buildExpandCollapseToggle(),
      _buildFitToScreenToggle(),
      _buildKpiRowToggle(),
      _buildColumnPicker(),
      if (widget.embedded) ...[
        _buildAiTakeoffToggle(workspaceId),
        ..._buildBudgetActionButtons(workspaceId),
      ],
      if (_selectedBudgetItemIds.isNotEmpty) _buildInlineSelectionBar(),
    ];
  }

  /// Mobile toolbar quick-toggles, mirroring [_buildQuickToggles] but using the
  /// compact icon-button action set.
  List<Widget> _buildMobileQuickToggles(String workspaceId) {
    if (_viewMode == BudgetViewMode.purchaseOrders) {
      // Mirror the grid views' toolbar: a prominent labelled create button on
      // roomy layouts, collapsing to a compact icon only on phone widths.
      return _isNarrowScreen
          ? [
              if (widget.embedded)
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: _createPurchaseOrder,
                  tooltip: 'New Purchase Order',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              _buildKpiRowToggle(),
            ]
          : [
              _buildCardListViewToggle(),
              _buildFitToScreenToggle(),
              _buildKpiRowToggle(),
              _buildPoColumnPicker(),
              if (widget.embedded)
                _buildCreateDocButton(
                  label: 'New Purchase Order',
                  onPressed: _createPurchaseOrder,
                ),
            ];
    }
    if (!_isGridMode) return const []; // workflow, profit, holdback, selections
    return _isNarrowScreen
        ? [
            if (widget.embedded) ..._buildMobileActionIcons(workspaceId),
            _buildKpiRowToggle(),
          ]
        : [
            _buildCardListViewToggle(),
            _buildExpandCollapseToggle(),
            _buildFitToScreenToggle(),
            _buildKpiRowToggle(),
            _buildColumnPicker(),
            if (widget.embedded) ...[
              _buildAiTakeoffToggle(workspaceId),
              ..._buildBudgetActionButtons(workspaceId),
            ],
            if (_selectedBudgetItemIds.isNotEmpty) _buildInlineSelectionBar(),
          ];
  }

  Widget _buildMobileBudgetControls(String workspaceId) {
    final hasSelection = _isNarrowScreen && _selectedBudgetItemIds.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewToolbar(
          searchHint: _searchHintForMode,
          searchQuery: _searchQuery,
          onSearch: _onSearchChanged,
          showSearch: _searchAppliesToMode,
          centerSlot: _buildViewModeToggle(),
          quickToggles: _buildMobileQuickToggles(workspaceId),
        ),
        if (hasSelection) _buildMobileSelectionBar(workspaceId),
      ],
    );
  }

  Widget _buildMobileSelectionBar(String workspaceId) {
    final m = _selectionMetrics();
    final count = _selectedBudgetItemIds.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          if (m.descendants > 0) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.account_tree_outlined,
              size: 13,
              color: AppColors.infoDark,
            ),
            const SizedBox(width: 2),
            Text(
              '+${m.descendants}',
              style: TextStyle(
                color: AppColors.infoDark,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          _buildSelectionActionsMenu(groupable: m.groupable),
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              onPressed: _clearSelection,
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Clear selection',
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMobileActionIcons(String workspaceId) {
    final chrome = ChromeColors.of(context);
    const constraints = BoxConstraints(minWidth: 32, minHeight: 32);
    final docLabel = _toolbarDocLabel(_viewMode);
    final hasSelection = _selectedBudgetItemIds.isNotEmpty;
    return [
      IconButton(
        icon: const Icon(
          Icons.auto_awesome,
          size: 18,
          color: AppColors.secondaryDark,
        ),
        onPressed: () => showAiTakeoffWizard(
          context,
          projectId: widget.projectId,
          workspaceId: workspaceId,
          project: _project,
          onComplete: () => _refreshBudgetSummary(workspaceId),
        ),
        tooltip: 'AI Takeoff',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
      IconButton(
        icon: Icon(Icons.download_outlined, size: 18, color: chrome.text),
        onPressed: () => _showImportCatalogDialog(workspaceId),
        tooltip: 'Import from Catalog',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
      IconButton(
        icon: Icon(Icons.file_upload_outlined, size: 18, color: chrome.text),
        onPressed: () => _showExportDialog(workspaceId),
        tooltip: 'Export Budget',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: constraints,
      ),
      if (docLabel != null)
        IconButton(
          icon: Icon(Icons.description_outlined, size: 18, color: chrome.text),
          onPressed: () => _openDocumentWizard(
            workspaceId,
            preSelectedIds: hasSelection ? _selectedBudgetItemIds : null,
          ),
          tooltip: docLabel,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: constraints,
        ),
    ];
  }

  ({IconData icon, String title, String subtitle, String ctaLabel})
  _emptyStateContentForMode() {
    switch (_viewMode) {
      case BudgetViewMode.estimating:
        return (
          icon: Icons.calculate_outlined,
          title: 'No estimate items yet',
          subtitle:
              'Add line items and groups to build your project estimate with costs, pricing, and margins.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.costing:
        return (
          icon: Icons.attach_money,
          title: 'No cost items yet',
          subtitle:
              'Start by adding estimate items, then track actual costs against your budget here.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.invoicing:
        return (
          icon: Icons.receipt_long_outlined,
          title: 'No invoiceable items yet',
          subtitle:
              'Add budget items with pricing to track invoicing progress and payment status.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.changeOrders:
        return (
          icon: Icons.swap_horiz,
          title: 'No change orders yet',
          subtitle:
              'Change orders capture scope changes after the original estimate is approved.',
          ctaLabel: 'Add Change Order',
        );
      case BudgetViewMode.upgrades:
        return (
          icon: Icons.upgrade,
          title: 'No upgrades yet',
          subtitle:
              'Upgrades track optional enhancements or selections chosen by the customer.',
          ctaLabel: 'Add Upgrade',
        );
      case BudgetViewMode.holdback:
        return (
          icon: Icons.lock_outline,
          title: 'No holdback items yet',
          subtitle:
              'Mark budget items with holdback amounts to track retained funds and releases.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.profit:
        return (
          icon: Icons.trending_up,
          title: 'No profit data yet',
          subtitle:
              'Add estimate items with costs and pricing to see your profit breakdown here.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.purchaseOrders:
        return (
          icon: Icons.shopping_cart_outlined,
          title: 'No purchase orders yet',
          subtitle:
              'Create purchase orders to commit costs with vendors for this project.',
          ctaLabel: 'Create Purchase Order',
        );
      case BudgetViewMode.workflow:
        return (
          icon: Icons.account_tree_outlined,
          title: 'Workflow',
          subtitle:
              'The workflow canvas shows the financial lifecycle of this job.',
          ctaLabel: 'Add Item',
        );
      case BudgetViewMode.selections:
        return (
          icon: Icons.checklist_outlined,
          title: 'Selections & Allowances',
          subtitle:
              'Track client decisions and how they affect the budget.',
          ctaLabel: 'New Selection',
        );
    }
  }

  static const _viewModeLabels = <BudgetViewMode, String>{
    BudgetViewMode.workflow: 'Workflow',
    BudgetViewMode.estimating: 'Budget',
    BudgetViewMode.purchaseOrders: 'Purchase Orders',
    BudgetViewMode.costing: 'Bills/Expenses',
    BudgetViewMode.invoicing: 'Invoices',
    BudgetViewMode.profit: 'Profit',
    BudgetViewMode.changeOrders: 'Change Orders',
    BudgetViewMode.selections: 'Selections',
    BudgetViewMode.upgrades: 'Upgrades',
    BudgetViewMode.holdback: 'Holdback',
  };

  static const _viewModeIcons = <BudgetViewMode, IconData>{
    BudgetViewMode.workflow: Icons.account_tree_outlined,
    BudgetViewMode.estimating: Icons.calculate_outlined,
    BudgetViewMode.purchaseOrders: Icons.shopping_cart_outlined,
    BudgetViewMode.costing: Icons.attach_money,
    BudgetViewMode.invoicing: Icons.receipt_long_outlined,
    BudgetViewMode.profit: Icons.trending_up,
    BudgetViewMode.changeOrders: Icons.swap_horiz,
    BudgetViewMode.selections: Icons.checklist_outlined,
    BudgetViewMode.upgrades: Icons.upgrade,
    BudgetViewMode.holdback: Icons.lock_outline,
  };

  Widget _buildViewModeToggle() {
    return PopupMenuButton<BudgetViewMode>(
      onSelected: (mode) {
        setState(() {
          _viewMode = mode;
          // Drop any stale query when moving to a view that can't search,
          // so it doesn't silently filter the grid when the user returns.
          if (!_searchAppliesToMode) _searchQuery = '';
        });
        if (mode == BudgetViewMode.workflow) {
          _loadWorkflowDocuments();
        }
      },
      tooltip: 'Budget view',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 180),
      color: AppColors.sidebarSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.sidebarSelected,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _viewModeIcons[_viewMode] ?? Icons.view_module_outlined,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              _viewModeLabels[_viewMode] ?? 'Budget',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
          ],
        ),
      ),
      itemBuilder: (context) => [
        // Workflow view mode — rendered separately above the divider
        _buildViewModeMenuItem(BudgetViewMode.workflow),
        const PopupMenuDivider(),
        for (final mode in BudgetViewMode.values)
          if (mode != BudgetViewMode.workflow) ...[
            if (mode == BudgetViewMode.profit) const PopupMenuDivider(),
            _buildViewModeMenuItem(mode),
          ],
      ],
    );
  }

  Widget _buildCreateDocButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<BudgetViewMode> _buildViewModeMenuItem(BudgetViewMode mode) {
    final isSelected = mode == _viewMode;
    return PopupMenuItem<BudgetViewMode>(
      value: mode,
      height: 40,
      padding: EdgeInsets.zero,
      mouseCursor: SystemMouseCursors.click,
      child: _ViewModeMenuItemContent(
        icon: _viewModeIcons[mode] ?? Icons.view_module_outlined,
        label: _viewModeLabels[mode] ?? mode.name,
        isSelected: isSelected,
      ),
    );
  }

  Widget _buildExpandCollapseToggle() {
    final chrome = ChromeColors.of(context);
    final hasExpanded = _expandedItems.isNotEmpty;
    return IconButton(
      icon: Icon(
        hasExpanded ? Icons.unfold_less : Icons.unfold_more,
        size: 20,
        color: chrome.text,
      ),
      onPressed: hasExpanded ? _collapseAll : _expandAll,
      tooltip: hasExpanded ? 'Collapse all' : 'Expand all',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildFitToScreenToggle() {
    final chrome = ChromeColors.of(context);
    return IconButton(
      icon: Icon(
        _fitToScreen ? Icons.open_in_full : Icons.close_fullscreen,
        size: 18,
        color: _fitToScreen ? chrome.text : AppColors.secondary,
      ),
      onPressed: () {
        final newFit = !_fitToScreen;
        setState(() => _fitToScreen = newFit);
        _saveFitToScreenPreference(newFit);
      },
      tooltip: _fitToScreen ? 'Expand table (scrollable)' : 'Fit to screen',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildKpiRowToggle() {
    return ViewIconButton(
      icon: Icons.dashboard_outlined,
      tooltip: _showKpiRow ? 'Hide summary cards' : 'Show summary cards',
      isSelected: _showKpiRow,
      onTap: () {
        final newShow = !_showKpiRow;
        setState(() => _showKpiRow = newShow);
        _saveKpiRowPreference(newShow);
      },
    );
  }

  Widget _buildCardListViewToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ViewIconButton(
          icon: Icons.grid_view,
          tooltip: 'Cards',
          isSelected: _isCardLayout,
          onTap: () {
            setState(() => _isCardLayout = true);
            _saveCardLayoutPreference(true);
          },
        ),
        ViewIconButton(
          icon: Icons.table_rows,
          tooltip: 'List',
          isSelected: !_isCardLayout,
          onTap: () {
            setState(() => _isCardLayout = false);
            _saveCardLayoutPreference(false);
          },
        ),
      ],
    );
  }

  Widget _buildAiTakeoffToggle(String workspaceId) {
    return IconButton(
      icon: const Icon(
        Icons.auto_awesome,
        size: 18,
        color: AppColors.secondaryDark,
      ),
      onPressed: () => showAiTakeoffWizard(
        context,
        projectId: widget.projectId,
        workspaceId: workspaceId,
        project: _project,
        onComplete: () => _refreshBudgetSummary(workspaceId),
      ),
      tooltip: 'AI Takeoff',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  List<Widget> _buildBudgetActionButtons(String workspaceId) {
    final chrome = ChromeColors.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: chrome.text,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minimumSize: Size.zero,
      textStyle: const TextStyle(fontSize: 13),
    );
    final hasSelection = _selectedBudgetItemIds.isNotEmpty;
    final docLabel = _toolbarDocLabel(_viewMode);
    return [
      TextButton.icon(
        onPressed: () => _showImportCatalogDialog(workspaceId),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Import'),
        style: style,
      ),
      TextButton.icon(
        onPressed: () => _showExportDialog(workspaceId),
        icon: const Icon(Icons.file_upload_outlined, size: 18),
        label: const Text('Export'),
        style: style,
      ),
      if (docLabel != null)
        _buildCreateDocButton(
          label: docLabel,
          onPressed: () => _openDocumentWizard(
            workspaceId,
            preSelectedIds: hasSelection ? _selectedBudgetItemIds : null,
          ),
        ),
      if (hasSelection) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: chrome.text.withValues(alpha: 0.2),
            ),
          ),
        ),
        ..._buildSelectionActions(style),
      ],
    ];
  }

  Widget _buildColumnPicker() {
    final columns = _getColumnsForCurrentMode();
    return TableDefaultColumnPickerButton(
      columnIds: columns,
      isColumnVisible: _isColumnVisible,
      onToggleColumn: _toggleColumn,
      columnNames: _columnNames,
    );
  }

  Widget _buildPoColumnPicker() {
    return TableColumnPickerButton(
      columnIds: ProjectPurchaseOrdersTableView.columnIds,
      isColumnVisible: _poColVis.isVisible,
      onToggleColumn: _togglePoColumn,
      columnLabel: ProjectPurchaseOrdersTableView.columnLabel,
      badgeBackgroundColor: AppColors.infoLight,
      badgeTextColor: AppColors.infoDark,
    );
  }

  Widget _buildAddRow() {
    return DragTarget<BudgetItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        setState(() => _isUngroupDropTargetActive = false);
        _handleItemParentChanged(details.data, null);
      },
      onMove: (_) {
        if (!_isUngroupDropTargetActive) {
          setState(() => _isUngroupDropTargetActive = true);
        }
      },
      onLeave: (_) {
        if (_isUngroupDropTargetActive) {
          setState(() => _isUngroupDropTargetActive = false);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: _isUngroupDropTargetActive
              ? BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  border: Border(
                    top: BorderSide(color: AppColors.info, width: 2),
                  ),
                )
              : null,
          child: TableAddItemGroupRow(
            leadingSpacing:
                _checkboxColumnWidth +
                _afterCheckboxGap +
                _lineItemColumnWidth +
                _afterLineItemGap,
            padding: const EdgeInsets.symmetric(
              horizontal: _tableHorizontalPadding,
              vertical: AppSpacing.md,
            ),
            borderSide: BorderSide(
              color: _isUngroupDropTargetActive
                  ? AppColors.info
                  : AppColors.cardBorder,
            ),
            onAddItem: () => _handleAddItem(null, 0, isGroup: false),
            onAddGroup: () => _handleAddItem(null, 0, isGroup: true),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(List<BudgetItem> displayedItems) {
    final isAllSelected =
        displayedItems.isNotEmpty &&
        displayedItems.every(
          (item) => _selectedBudgetItemIds.contains(item.id),
        );
    final isSomeSelected =
        displayedItems.any(
          (item) => _selectedBudgetItemIds.contains(item.id),
        ) &&
        !isAllSelected;

    final headerStyle =
        TableViewStyles.headerLabelStyle(context) ??
        const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AppColors.textSecondary,
        );

    return TableHeaderRow(
      excelStyle: true,
      padding: const EdgeInsets.symmetric(horizontal: _tableHorizontalPadding),
      children: [
        // Select all checkbox
        SizedBox(
          width: _checkboxColumnWidth,
          child: Center(
            child: Checkbox(
              value: isAllSelected,
              tristate: isSomeSelected,
              onChanged: (val) => _selectAll(val ?? false, displayedItems),
            ),
          ),
        ),
        const SizedBox(width: _afterCheckboxGap),
        SizedBox(
          width: _lineItemColumnWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: _BudgetSortableLabel(
              label: 'Id',
              textStyle: headerStyle,
              textAlign: TextAlign.right,
              isSorted: _sortState.column == 'id',
              ascending: _sortState.column == 'id' ? _sortState.ascending : true,
              onTap: () => _onBudgetColumnSortTap('id'),
            ),
          ),
        ),
        const SizedBox(width: _afterLineItemGap),
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: _nameHeaderInset),
              _BudgetSortableLabel(
                label: 'Name',
                textStyle: headerStyle,
                isSorted: _sortState.column == 'name',
                ascending: _sortState.column == 'name' ? _sortState.ascending : true,
                onTap: () => _onBudgetColumnSortTap('name'),
              ),
            ],
          ),
        ),
        ..._buildVisibleHeaderCells(headerStyle),
        SizedBox(
          width: 80,
          child: Text(
            'Status',
            style: headerStyle,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildVisibleHeaderCells(TextStyle headerStyle) {
    final columns = <TableColumnSchema>[
      const TableColumnSchema(
        id: 'qty',
        label: 'Qty',
        defaultWidth: 80,
        borderLeft: true,
        align: TextAlign.right,
      ),
      const TableColumnSchema(
        id: 'unit',
        label: 'Unit',
        defaultWidth: 80,
        align: TextAlign.right,
      ),
      ..._modeHeaderColumns(_viewMode),
    ];

    return buildTableHeaderCells(
      context: context,
      columns: columns,
      widths: {
        for (final column in columns)
          column.id: _columnWidths[column.id] ?? column.defaultWidth,
      },
      isVisible: (column) => _isColumnVisible(column.id),
      onColumnResize: _handleColumnResize,
      textStyle: headerStyle,
      showHoverAffordances: true,
      onSortTap: (column) => _onBudgetColumnSortTap(column.id),
      sortedColumnId: _sortState.column,
      sortAscending: _sortState.ascending,
    );
  }

  List<TableColumnSchema> _modeHeaderColumns(BudgetViewMode mode) {
    switch (mode) {
      case BudgetViewMode.workflow:
        return const []; // Workflow has no table header
      case BudgetViewMode.purchaseOrders:
        return const []; // Purchase Orders renders its own widget
      case BudgetViewMode.estimating:
        return _estimatingHeaderColumns;
      case BudgetViewMode.costing:
        return _costingHeaderColumns;
      case BudgetViewMode.invoicing:
        return _invoicingHeaderColumns;
      case BudgetViewMode.profit:
        return _profitHeaderColumns;
      case BudgetViewMode.changeOrders:
        return _changeOrdersHeaderColumns;
      case BudgetViewMode.upgrades:
        return _upgradesHeaderColumns;
      case BudgetViewMode.holdback:
        return _holdbackHeaderColumns;
      case BudgetViewMode.selections:
        return const [];
    }
  }

  Widget _buildSummaryFooter(List<BudgetItem> allItems) {
    final colorScheme = Theme.of(context).colorScheme;
    // Calculate totals from leaf items only (not groups to avoid double-counting)
    final leafItems = allItems.where((i) => i.itemType == BudgetItemType.item);

    // Check if all items have the same unit (for meaningful QTY total)
    final units = leafItems
        .map((i) => i.unit)
        .where((u) => u != null && u.isNotEmpty)
        .toSet();
    final hasUniformUnit = units.length == 1;
    final totalQty = hasUniformUnit
        ? leafItems.fold(0.0, (sum, i) => sum + i.quantity)
        : 0.0;
    final uniformUnit = hasUniformUnit ? units.first : null;

    // Calculate totals.
    // "Total price" sums the live extended price (qty × unitPrice) shown in
    // each row so the footer matches the column visually. "Approved" total
    // is also tracked separately for invoicing/holdback math that needs the
    // frozen contract amount.
    final totalApproved = leafItems.fold(
      0.0,
      (sum, i) => sum + i.approvedPrice,
    );
    final totalExtendedPrice = leafItems.fold(
      0.0,
      (sum, i) => sum + i.extendedPrice,
    );
    final totalProjectedCost = leafItems.fold(
      0.0,
      (sum, i) => sum + i.projectedCost,
    );
    // Profit is the spread between what we're billing and what we're spending
    // — keep it derived from the same two totals shown in the footer so
    // Profit + Cost = Total price in the bar (no rounding drift).
    final totalProfit = totalExtendedPrice - totalProjectedCost;
    // Weighted per-unit averages for the unit-cost / unit-price totals.
    // Only meaningful when every line shares the same unit and there is at
    // least some quantity to divide by.
    final weightedUnitCost = (hasUniformUnit && totalQty > 0)
        ? totalProjectedCost / totalQty
        : null;
    final weightedUnitPrice = (hasUniformUnit && totalQty > 0)
        ? totalExtendedPrice / totalQty
        : null;
    // Blended markup % across all leaf items (profit over cost).
    final overallMarkup = totalProjectedCost > 0
        ? (totalProfit / totalProjectedCost) * 100
        : 0.0;
    final totalCommitted = leafItems.fold(
      0.0,
      (sum, i) => sum + i.committedCost,
    );
    final totalActual = leafItems.fold(
      0.0,
      (sum, i) => sum + (_actualCosts[i.id] ?? 0.0),
    );
    final totalVariance = totalProjectedCost - totalActual;
    final totalInvoiced = leafItems.fold(
      0.0,
      (sum, i) => sum + (_invoicedAmounts[i.id] ?? 0.0),
    );
    final totalPaid = leafItems.fold(0.0, (sum, i) {
      final status = _documentStatuses[i.id];
      return sum + (status?.paidAmount ?? 0.0);
    });
    final totalRemaining = totalApproved - totalInvoiced;
    final totalHoldbackAmount = leafItems.fold<double>(
      0.0,
      (sum, i) => sum + i.holdbackAmount,
    );
    final totalCollectible = leafItems.fold<double>(
      0.0,
      (sum, i) => sum + i.collectibleAmount,
    );
    final topLevelBudgetItemIds = _allBudgetItems
        .where((item) => item.parentId == null)
        .map((item) => item.id)
        .toSet();
    final topLevelLaborSummaries = _laborSummaries.values.where(
      (summary) => topLevelBudgetItemIds.contains(summary.budgetItemId),
    );
    final totalEstHours = topLevelLaborSummaries.fold<double>(
      0.0,
      (sum, summary) => sum + summary.estimatedHours,
    );
    final totalTrackedHours = topLevelLaborSummaries.fold<double>(
      0.0,
      (sum, summary) => sum + summary.trackedHours,
    );
    final totalLaborCost = topLevelLaborSummaries.fold<double>(
      0.0,
      (sum, summary) => sum + summary.laborCost,
    );

    // Calculate overall margin against the same Total price the footer shows.
    final overallMargin = totalExtendedPrice > 0
        ? (totalProfit / totalExtendedPrice) * 100
        : 0.0;

    return TableSummaryFooter(
      padding: const EdgeInsets.symmetric(horizontal: _tableHorizontalPadding),
      children: [
        // Checkbox column space
        const SizedBox(width: _checkboxColumnWidth),
        const SizedBox(width: _afterCheckboxGap),
        // ID column space
        const SizedBox(width: _lineItemColumnWidth),
        const SizedBox(width: _afterLineItemGap),
        // Name column - TOTALS label
        const TableSummaryLabel(text: 'TOTALS', inset: _nameHeaderInset),
        // 8px spacer to match the header's borderLeft handle on Qty
        if (_isColumnVisible('qty')) const SizedBox(width: 8),
        // QTY
        if (_isColumnVisible('qty'))
          TableSummaryCell(
            width: _colW('qty', 80),
            text: hasUniformUnit ? totalQty.toStringAsFixed(1) : null,
            isBold: true,
            textAlign: TextAlign.right,
          ),
        // UNIT
        if (_isColumnVisible('unit'))
          TableSummaryCell(
            width: _colW('unit', 80),
            text: uniformUnit,
            textAlign: TextAlign.right,
            color: colorScheme.onSurfaceVariant,
          ),
        ..._buildModeTotalsCells(
          colorScheme: colorScheme,
          totalExtendedPrice: totalExtendedPrice,
          totalProfit: totalProfit,
          totalCommitted: totalCommitted,
          totalActual: totalActual,
          totalVariance: totalVariance,
          totalEstHours: totalEstHours,
          totalTrackedHours: totalTrackedHours,
          totalLaborCost: totalLaborCost,
          totalInvoiced: totalInvoiced,
          totalPaid: totalPaid,
          totalRemaining: totalRemaining,
          totalApproved: totalApproved,
          totalProjectedCost: totalProjectedCost,
          totalHoldbackAmount: totalHoldbackAmount,
          totalCollectible: totalCollectible,
          overallMargin: overallMargin,
          overallMarkup: overallMarkup,
          weightedUnitCost: weightedUnitCost,
          weightedUnitPrice: weightedUnitPrice,
        ),

        // STATUS - not meaningful for totals
        Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: TableSummaryCell(
            width: 80,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildModeTotalsCells({
    required ColorScheme colorScheme,
    required double totalExtendedPrice,
    required double totalProfit,
    required double totalApproved,
    required double totalProjectedCost,
    required double totalCommitted,
    required double totalActual,
    required double totalVariance,
    required double totalEstHours,
    required double totalTrackedHours,
    required double totalLaborCost,
    required double totalInvoiced,
    required double totalPaid,
    required double totalRemaining,
    required double totalHoldbackAmount,
    required double totalCollectible,
    required double overallMargin,
    required double overallMarkup,
    required double? weightedUnitCost,
    required double? weightedUnitPrice,
  }) {
    switch (_viewMode) {
      case BudgetViewMode.workflow:
        return const []; // Workflow has no table footer
      case BudgetViewMode.purchaseOrders:
        return const []; // Purchase Orders renders its own widget
      case BudgetViewMode.estimating:
        return [
          // Weighted per-unit cost/price are only shown when every line uses
          // the same unit; otherwise summing per-unit values would be
          // misleading, so we fall back to the "-" placeholder.
          if (weightedUnitCost != null)
            _buildVisibleTotalsCurrencyCell(
              columnId: 'unitCost',
              width: _colW('unitCost', 130),
              value: weightedUnitCost,
            )
          else
            _buildVisibleTotalsPlaceholderCell(
              columnId: 'unitCost',
              width: _colW('unitCost', 130),
              colorScheme: colorScheme,
              textAlign: TextAlign.right,
            ),
          if (weightedUnitPrice != null)
            _buildVisibleTotalsCurrencyCell(
              columnId: 'unitPrice',
              width: _colW('unitPrice', 130),
              value: weightedUnitPrice,
            )
          else
            _buildVisibleTotalsPlaceholderCell(
              columnId: 'unitPrice',
              width: _colW('unitPrice', 130),
              colorScheme: colorScheme,
              textAlign: TextAlign.right,
            ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'extendedPrice',
            width: _colW('extendedPrice', 130),
            value: totalExtendedPrice,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'profit',
            width: _colW('profit', 130),
            value: totalProfit,
            color: totalProfit >= 0 ? AppColors.success : AppColors.error,
          ),
          _buildVisibleTotalsPercentCell(
            columnId: 'margin',
            width: _colW('margin', 100),
            value: overallMargin,
            color: overallMargin >= 0 ? AppColors.success : AppColors.error,
            borderLeft: true,
          ),
          _buildVisibleTotalsPercentCell(
            columnId: 'markup',
            width: _colW('markup', 100),
            value: overallMarkup,
            color: overallMarkup >= 0 ? AppColors.success : AppColors.error,
          ),
          // Taxable is a per-row boolean; an aggregate has no meaning.
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'taxable',
            width: _colW('taxable', 80),
            colorScheme: colorScheme,
          ),
        ];
      case BudgetViewMode.costing:
        return [
          _buildVisibleTotalsCurrencyCell(
            columnId: 'committed',
            width: _colW('committed', 130),
            value: totalCommitted,
            color: AppColors.infoDark,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'actual',
            width: _colW('actual', 130),
            value: totalActual,
            color: AppColors.messageAccent,
          ),
          _buildVisibleTotalsVarianceCell(
            columnId: 'variance',
            width: _colW('variance', 130),
            value: totalVariance,
          ),
          _buildVisibleTotalsHoursCell(
            columnId: 'hoursEst',
            width: _colW('hoursEst', 100),
            hours: totalEstHours,
          ),
          _buildVisibleTotalsHoursCell(
            columnId: 'hoursTracked',
            width: _colW('hoursTracked', 100),
            hours: totalTrackedHours,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'laborCost',
            width: _colW('laborCost', 130),
            value: totalLaborCost,
            color: AppColors.warningDark,
          ),
        ];
      case BudgetViewMode.invoicing:
        return [
          _buildVisibleTotalsCurrencyCell(
            columnId: 'invoiced',
            width: _colW('invoiced', 130),
            value: totalInvoiced,
            color: AppColors.messageAccent,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'paid',
            width: _colW('paid', 130),
            value: totalPaid,
            color: AppColors.successDark,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'remaining',
            width: _colW('remaining', 130),
            value: totalRemaining.clamp(0, double.infinity).toDouble(),
            color: totalRemaining > 0
                ? AppColors.warningDark
                : AppColors.textTertiary,
          ),
        ];
      case BudgetViewMode.profit:
        return [
          _buildVisibleTotalsCurrencyCell(
            columnId: 'actualCost',
            width: _colW('actualCost', 130),
            value: totalActual,
            color: AppColors.messageAccent,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'profit',
            width: _colW('profit', 130),
            value: totalProfit,
            color: totalProfit >= 0 ? AppColors.success : AppColors.error,
          ),
          _buildVisibleTotalsPercentCell(
            columnId: 'margin',
            width: _colW('margin', 100),
            value: overallMargin,
            color: overallMargin >= 0 ? AppColors.success : AppColors.error,
            borderLeft: true,
          ),
        ];
      case BudgetViewMode.changeOrders:
        return [
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'coNumber',
            width: _colW('coNumber', 80),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'source',
            width: _colW('source', 100),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'status',
            width: _colW('status', 100),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'revenueChange',
            width: _colW('revenueChange', 120),
            value: totalApproved,
            color: AppColors.successDark,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'costChange',
            width: _colW('costChange', 120),
            value: totalProjectedCost,
            color: AppColors.errorDark,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'netChange',
            width: _colW('netChange', 120),
            value: totalProfit,
            color: totalProfit >= 0 ? AppColors.success : AppColors.error,
          ),
          _buildVisibleTotalsPercentCell(
            columnId: 'margin',
            width: _colW('margin', 100),
            value: overallMargin,
            color: overallMargin >= 0 ? AppColors.success : AppColors.error,
            borderLeft: true,
          ),
        ];
      case BudgetViewMode.upgrades:
        return [
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'isUpgrade',
            width: _colW('isUpgrade', 80),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'category',
            width: _colW('category', 120),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'upgradeStatus',
            width: _colW('upgradeStatus', 100),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'price',
            width: _colW('price', 120),
            value: totalApproved,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'cost',
            width: _colW('cost', 120),
            value: totalProjectedCost,
            color: AppColors.errorDark,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'profit',
            width: _colW('profit', 130),
            value: totalProfit,
            color: totalProfit >= 0 ? AppColors.success : AppColors.error,
          ),
          _buildVisibleTotalsPercentCell(
            columnId: 'margin',
            width: _colW('margin', 100),
            value: overallMargin,
            color: overallMargin >= 0 ? AppColors.success : AppColors.error,
            borderLeft: true,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'holdbackPct',
            width: _colW('holdbackPct', 100),
            colorScheme: colorScheme,
            textAlign: TextAlign.right,
          ),
        ];
      case BudgetViewMode.holdback:
        return [
          _buildVisibleTotalsCurrencyCell(
            columnId: 'approved',
            width: _colW('approved', 130),
            value: totalApproved,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'holdbackPct',
            width: _colW('holdbackPct', 100),
            colorScheme: colorScheme,
            textAlign: TextAlign.right,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'holdbackAmt',
            width: _colW('holdbackAmt', 130),
            value: totalHoldbackAmount,
            color: AppColors.warningDark,
          ),
          _buildVisibleTotalsPlaceholderCell(
            columnId: 'released',
            width: _colW('released', 100),
            colorScheme: colorScheme,
          ),
          _buildVisibleTotalsCurrencyCell(
            columnId: 'collectible',
            width: _colW('collectible', 130),
            value: totalCollectible,
            color: AppColors.successDark,
          ),
        ];
      case BudgetViewMode.selections:
        return const [];
    }
  }

  Widget _buildVisibleTotalsPlaceholderCell({
    required String columnId,
    required double width,
    required ColorScheme colorScheme,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (!_isColumnVisible(columnId)) return const SizedBox.shrink();
    return TableSummaryCell(
      width: width,
      color: colorScheme.onSurfaceVariant,
      textAlign: textAlign,
    );
  }

  Widget _buildVisibleTotalsCurrencyCell({
    required String columnId,
    required double width,
    required double value,
    Color? color,
  }) {
    if (!_isColumnVisible(columnId)) return const SizedBox.shrink();
    return TableSummaryCell(
      width: width,
      text: _formatCurrency(value),
      isBold: true,
      color: color,
      textAlign: TextAlign.right,
    );
  }

  Widget _buildVisibleTotalsPercentCell({
    required String columnId,
    required double width,
    required double value,
    required Color color,
    bool borderLeft = false,
  }) {
    if (!_isColumnVisible(columnId)) return const SizedBox.shrink();
    Widget cell = TableSummaryCell(
      width: width,
      text: '${value.toStringAsFixed(1)}%',
      color: color,
      textAlign: TextAlign.right,
    );
    if (borderLeft) {
      cell = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: cell,
      );
    }
    return cell;
  }

  Widget _buildVisibleTotalsHoursCell({
    required String columnId,
    required double width,
    required double hours,
  }) {
    if (!_isColumnVisible(columnId)) return const SizedBox.shrink();
    return TableSummaryCell(
      width: width,
      text: '${hours.toStringAsFixed(1)}h',
      isBold: true,
      textAlign: TextAlign.right,
    );
  }

  Widget _buildVisibleTotalsVarianceCell({
    required String columnId,
    required double width,
    required double value,
  }) {
    if (!_isColumnVisible(columnId)) return const SizedBox.shrink();
    final isPositive = value >= 0;
    final color = isPositive ? AppColors.success : AppColors.error;
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            _formatCurrency(value.abs()),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFlattenedBudgetRows(
    List<BudgetItem> allItems,
    String workspaceId,
  ) {
    final entries = flattenHierarchy<BudgetItem>(
      items: allItems,
      idOf: (item) => item.id,
      parentIdOf: (item) => item.parentId,
      isExpandedOf: (item) => _expandedItems.contains(item.id),
      sortSiblings:
          _budgetSortComparator ?? (a, b) => a.sortOrder.compareTo(b.sortOrder),
    );

    final visibleEntries = entries
        .where((entry) => _isItemVisibleInSearch(entry.item))
        .toList(growable: false);

    final rows = <Widget>[];
    int itemIndex = 0; // tracks leaf items only, for alternating row colors
    for (var i = 0; i < visibleEntries.length; i++) {
      final entry = visibleEntries[i];
      final item = entry.item;
      final siblings =
          _childrenByParentId[item.parentId ?? ''] ?? const <BudgetItem>[];
      final siblingIndex = siblings.indexWhere(
        (sibling) => sibling.id == item.id,
      );
      final canMoveUp = siblingIndex > 0;
      final canMoveDown =
          siblingIndex >= 0 && siblingIndex < siblings.length - 1;
      final isExpanded = _expandedItems.contains(item.id);
      final isGroup = item.itemType == BudgetItemType.group;
      final currentItemIndex = isGroup ? 0 : itemIndex;
      if (!isGroup) itemIndex++;

      rows.add(
        KeyedSubtree(
          key: ValueKey('budget-item-${item.id}'),
          child: BudgetViewRow(
            key: ValueKey('budget-row-${item.id}'),
            item: item,
            lineItemId: _hierarchicalItemIds[item.id] ?? '',
            lineItemColumnWidth: _lineItemColumnWidth,
            allItems: _allBudgetItems,
            hasChildren: entry.hasChildren,
            visualIndex: currentItemIndex,
            viewMode: _viewMode,
            indentLevel: entry.depth,
            isExpanded: isExpanded,
            isSelected: _selectedBudgetItemIds.contains(item.id),
            treeGuides: entry.treeGuides,
            isLastChild: entry.isLastChild,
            searchQuery: _searchQuery,
            actualCost: _actualCosts[item.id] ?? 0.0,
            invoicedAmount: _invoicedAmounts[item.id] ?? 0.0,
            progressText: _progressTexts[item.id] ?? '',
            documentStatus: _documentStatuses[item.id],
            onDocumentStatusTap:
                (_documentStatuses[item.id]?.documentIds.isNotEmpty ?? false)
                ? () => _navigateToDocuments(_documentStatuses[item.id]!)
                : null,
            laborSummary: _laborSummaries[item.id],
            changeOrderStatusText: item.changeOrderId != null
                ? _changeOrderStatuses[item.changeOrderId!]
                : null,
            pricingInputMode: _pricingInputMode,
            isTasksExpanded: _taskExpandedItems.contains(item.id),
            onTasksExpandToggle: (_laborSummaries[item.id]?.taskCount ?? 0) > 0
                ? () => _toggleTaskPanel(item.id)
                : null,
            visibleColumns: _colVis.toSet(),
            columnWidths: _columnWidths,
            onExpandToggle: entry.hasChildren
                ? () => _toggleBudgetItemExpansion(item.id)
                : null,
            onSelectionChanged: _handleBudgetItemSelectionChanged,
            onItemChanged: _handleItemChanged,
            onAddItem: _handleAddItem,
            onEditItem: _handleEditItem,
            onDeleteItem: _handleDeleteItem,
            onUngroupItem: _handleUngroupGroup,
            onDuplicateItem: _handleDuplicateItem,
            onGroupItem: !isGroup ? _handleGroupItem : null,
            onSaveAsTemplate: _handleSaveAsTemplate,
            onSaveToCatalog: _handleSaveToCatalog,
            onItemParentChanged: _handleItemParentChanged,
            onItemDropped: _handleItemDropped,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: canMoveUp
                ? () => _moveItemWithinSiblings(item, -1)
                : null,
            onMoveDown: canMoveDown
                ? () => _moveItemWithinSiblings(item, 1)
                : null,
            onDragStarted: _onBudgetItemDragStarted,
            onDragEnded: _onBudgetItemDragEnded,
          ),
        ),
      );

      if (_taskExpandedItems.contains(item.id)) {
        rows.add(
          BudgetItemTasksExpansion(
            key: ValueKey('tasks-${item.id}'),
            budgetItemId: item.id,
            projectId: widget.projectId,
            workspaceId: item.workspaceId,
          ),
        );
      }

      if (_addingToParentId != null &&
          _addingHierarchyLevel != null &&
          _isLastVisibleRowInParentSubtree(
            visibleEntries,
            rowIndex: i,
            parentId: _addingToParentId!,
          )) {
        rows.add(
          _buildInlineBudgetAddRow(
            workspaceId: item.workspaceId,
            parentId: _addingToParentId!,
            hierarchyLevel: _addingHierarchyLevel!,
            indentLevel: (entry.depth + 1).clamp(0, 4),
          ),
        );
      }
    }

    if (_addingToParentId == null && _addingHierarchyLevel == 0) {
      rows.add(
        KeyedSubtree(
          key: const ValueKey('inline-add-row'),
          child: _buildInlineBudgetAddRow(
            workspaceId: workspaceId,
            parentId: null,
            hierarchyLevel: 0,
            indentLevel: 0,
          ),
        ),
      );
    }

    rows.add(
      KeyedSubtree(key: const ValueKey('add-row'), child: _buildAddRow()),
    );
    return rows;
  }

  bool _isItemVisibleInSearch(BudgetItem item) {
    if (!_matchesSearch(item)) return false;
    var parentId = item.parentId;
    var iterations = 0;
    while (parentId != null && iterations < 100) {
      iterations++;
      final parent = _budgetItemsById[parentId];
      if (parent == null) break;
      if (!_matchesSearch(parent)) return false;
      parentId = parent.parentId;
    }
    return true;
  }

  bool _isLastVisibleRowInParentSubtree(
    List<HierarchyFlatEntry<BudgetItem>> entries, {
    required int rowIndex,
    required String parentId,
  }) {
    final current = entries[rowIndex].item;
    if (!_isSelfOrDescendantOf(current, parentId)) return false;
    if (rowIndex >= entries.length - 1) return true;
    final next = entries[rowIndex + 1].item;
    return !_isSelfOrDescendantOf(next, parentId);
  }

  bool _isSelfOrDescendantOf(BudgetItem item, String ancestorId) {
    if (item.id == ancestorId) return true;
    var parentId = item.parentId;
    var iterations = 0;
    while (parentId != null && iterations < 100) {
      iterations++;
      if (parentId == ancestorId) return true;
      parentId = _budgetItemsById[parentId]?.parentId;
    }
    return false;
  }

  void _toggleTaskPanel(String itemId) {
    setState(() {
      if (_taskExpandedItems.contains(itemId)) {
        _taskExpandedItems.remove(itemId);
      } else {
        _taskExpandedItems.add(itemId);
      }
    });
  }

  void _toggleBudgetItemExpansion(String itemId) {
    setState(() {
      if (_expandedItems.contains(itemId)) {
        _expandedItems.remove(itemId);
      } else {
        _expandedItems.add(itemId);
      }
    });
  }

  Widget _buildInlineBudgetAddRow({
    required String workspaceId,
    required String? parentId,
    required int hierarchyLevel,
    required int indentLevel,
  }) {
    return BudgetInlineAddRow(
      projectId: widget.projectId,
      workspaceId: workspaceId,
      parentId: parentId,
      hierarchyLevel: hierarchyLevel,
      indentLevel: indentLevel,
      isGroup: _addingAsGroup,
      defaultMarkup: _project?.materialMarkupPercent ?? 20.0,
      sourceType: _sourceTypeForCurrentMode(),
      onCancel: () => setState(() {
        _addingToParentId = null;
        _addingHierarchyLevel = null;
      }),
      onSave: (newItem) async {
        try {
          await _budgetService.createBudgetItem(newItem);
          setState(() {
            _addingToParentId = null;
            _addingHierarchyLevel = null;
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: SelectableText(
                UserFacingError.uiMessage(e, action: 'add budget item'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
    );
  }

  // Selection methods

  void _handleBudgetItemSelectionChanged(BudgetItem item, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedBudgetItemIds.add(item.id);
        // Select all descendants using pre-computed map
        final descendants = _descendantsByItemId[item.id] ?? [];
        _selectedBudgetItemIds.addAll(descendants.map((i) => i.id));
      } else {
        _selectedBudgetItemIds.remove(item.id);
        // Deselect all descendants using pre-computed map
        final descendants = _descendantsByItemId[item.id] ?? [];
        _selectedBudgetItemIds.removeAll(descendants.map((i) => i.id).toSet());
      }
    });
  }

  List<BudgetItem> _getSelectedRootItems() {
    final selectedItems = _allBudgetItems
        .where((item) => _selectedBudgetItemIds.contains(item.id))
        .toList();
    return selectedItems.where((item) {
      var parentId = item.parentId;
      while (parentId != null) {
        if (_selectedBudgetItemIds.contains(parentId)) {
          return false;
        }
        parentId = _budgetItemsById[parentId]?.parentId;
      }
      return true;
    }).toList();
  }

  int _sortIndexForParent(String? parentId, String itemId) {
    final siblings =
        _childrenByParentId[parentId ?? ''] ?? const <BudgetItem>[];
    final index = siblings.indexWhere((item) => item.id == itemId);
    return index >= 0 ? index : siblings.length;
  }

  Future<void> _handleUngroupSelection() async {
    final selectedRootItems = _getSelectedRootItems();
    final itemsToUngroup =
        selectedRootItems.where((item) => item.parentId != null).toList()
          ..sort((a, b) {
            final aParent = _budgetItemsById[a.parentId!];
            final bParent = _budgetItemsById[b.parentId!];
            final parentCompare = _sortIndexForParent(
              aParent?.parentId,
              a.parentId!,
            ).compareTo(_sortIndexForParent(bParent?.parentId, b.parentId!));
            if (parentCompare != 0) return parentCompare;
            return a.sortOrder.compareTo(b.sortOrder);
          });

    if (itemsToUngroup.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only grouped items can be ungrouped')),
        );
      }
      return;
    }

    final groupedByParent = <String, List<BudgetItem>>{};
    for (final item in itemsToUngroup) {
      groupedByParent
          .putIfAbsent(item.parentId!, () => <BudgetItem>[])
          .add(item);
    }

    final siblingOrderCache = <String?, List<String>>{};
    List<String> getSiblingOrder(String? parentId) {
      return siblingOrderCache.putIfAbsent(
        parentId,
        () => List<String>.from(
          (_childrenByParentId[parentId ?? ''] ?? const <BudgetItem>[]).map(
            (item) => item.id,
          ),
        ),
      );
    }

    try {
      for (final entry in groupedByParent.entries) {
        final currentParentId = entry.key;
        final currentParent = _budgetItemsById[currentParentId];
        if (currentParent == null) continue;

        final targetParentId = currentParent.parentId;
        final targetOrder = getSiblingOrder(targetParentId);
        final currentParentIndex = targetOrder.indexOf(currentParentId);
        final insertIndex = currentParentIndex >= 0
            ? currentParentIndex + 1
            : targetOrder.length;
        final childIds = entry.value.map((item) => item.id).toList();
        targetOrder.insertAll(insertIndex, childIds);

        var newSortOrder = insertIndex;
        for (final item in entry.value) {
          await _budgetService.moveItem(item.id, targetParentId, newSortOrder);
          newSortOrder++;
        }

        final oldParentOrder = getSiblingOrder(currentParentId)
          ..removeWhere(childIds.contains);
        await _budgetService.reorderItems(currentParentId, oldParentOrder);
        await _budgetService.reorderItems(targetParentId, targetOrder);
      }

      if (!mounted) return;
      setState(() {
        _selectedBudgetItemIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ungrouped ${itemsToUngroup.length} item${itemsToUngroup.length == 1 ? '' : 's'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'ungroup items')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleGroupSelection() async {
    final selectedRootItems = _getSelectedRootItems();
    if (selectedRootItems.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select at least 2 items to group together'),
          ),
        );
      }
      return;
    }

    // All selected root items must share the same parent
    final parentIds = selectedRootItems.map((i) => i.parentId).toSet();
    if (parentIds.length > 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selected items must be at the same level to group together',
            ),
          ),
        );
      }
      return;
    }

    final commonParentId = parentIds.first;
    final firstItem = selectedRootItems.first;

    try {
      final nextSortOrder = await _budgetService.getNextSortOrder(
        commonParentId,
        firstItem.projectId,
      );
      final now = DateTime.now();
      final group = firstItem.copyWith(
        id: '',
        name: 'New Group',
        itemType: BudgetItemType.group,
        sortOrder: nextSortOrder,
        quantity: 0,
        unitCost: 0,
        unitPrice: 0,
        approvedPrice: 0,
        projectedCost: 0,
        committedCost: 0,
        finalCost: 0,
        description: null,
        isComplete: false,
        completedDate: null,
        createdAt: now,
        updatedAt: now,
      );

      final groupId = await _budgetService.createBudgetItem(group);

      // Move selected items into the new group, preserving relative order
      final sortedItems = List<BudgetItem>.from(selectedRootItems)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (var i = 0; i < sortedItems.length; i++) {
        await _budgetService.moveItem(sortedItems[i].id, groupId, i);
      }

      if (!mounted) return;
      setState(() {
        _expandedItems.add(groupId);
        _selectedBudgetItemIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grouped ${sortedItems.length} items into "New Group"'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'group items')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleSaveSelectionToCatalog() async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final selectedRootItems = _getSelectedRootItems();
    if (selectedRootItems.isEmpty) return;

    // Collect all items including descendants
    final itemsToSave = <BudgetItem>[];
    for (final item in selectedRootItems) {
      itemsToSave.add(item);
      if (item.itemType == BudgetItemType.group) {
        itemsToSave.addAll(_getAllDescendants(item));
      }
    }

    final leafCount = itemsToSave
        .where((i) => i.itemType == BudgetItemType.item)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save to Catalog'),
        content: Text(
          'Add $leafCount item${leafCount == 1 ? '' : 's'} to your workspace catalog?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final catalogService = ServiceLocator.catalogService;
      await catalogService.copyBudgetItemsToCatalog(
        budgetItems: itemsToSave,
        workspaceId: workspaceId,
      );

      if (mounted) {
        setState(() => _selectedBudgetItemIds.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$leafCount item${leafCount == 1 ? '' : 's'} saved to catalog',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving to catalog'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSaveSelectionAsTemplate() async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;
    if (workspaceId == null || userId == null) return;

    final selectedRootItems = _getSelectedRootItems();
    if (selectedRootItems.isEmpty) return;

    final itemsToTemplate = <BudgetItem>[];
    for (final item in selectedRootItems) {
      itemsToTemplate.add(item);
      if (item.itemType == BudgetItemType.group) {
        itemsToTemplate.addAll(_getAllDescendants(item));
      }
    }

    final nameController = TextEditingController(
      text: selectedRootItems.length == 1
          ? selectedRootItems.first.name
          : 'New Template',
    );
    final descController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Template Name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final templateService = ServiceLocator.budgetTemplateService;
      await templateService.createTemplateFromItems(
        items: itemsToTemplate,
        workspaceId: workspaceId,
        name: nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
        createdBy: userId,
      );

      if (mounted) {
        setState(() => _selectedBudgetItemIds.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "${nameController.text.trim()}" saved'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving template'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleUngroupGroup(BudgetItem group) async {
    final directChildren = List<BudgetItem>.from(
      _childrenByParentId[group.id] ?? const <BudgetItem>[],
    )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (group.itemType != BudgetItemType.group || directChildren.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This group has no items to ungroup')),
        );
      }
      return;
    }

    final targetParentId = group.parentId;
    final targetOrder = List<String>.from(
      (_childrenByParentId[targetParentId ?? ''] ?? const <BudgetItem>[]).map(
        (item) => item.id,
      ),
    );
    final groupIndex = targetOrder.indexOf(group.id);
    if (groupIndex >= 0) {
      targetOrder
        ..removeAt(groupIndex)
        ..insertAll(groupIndex, directChildren.map((child) => child.id));
    } else {
      targetOrder.addAll(directChildren.map((child) => child.id));
    }

    try {
      final insertionIndex = groupIndex >= 0
          ? groupIndex
          : targetOrder.length - directChildren.length;
      var newSortOrder = insertionIndex;
      for (final child in directChildren) {
        await _budgetService.moveItem(child.id, targetParentId, newSortOrder);
        newSortOrder++;
      }
      await _budgetService.deleteBudgetItem(group.id);
      await _budgetService.reorderItems(targetParentId, targetOrder);

      if (!mounted) return;
      setState(() {
        _selectedBudgetItemIds.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ungrouped "${group.name}"')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'ungroup group')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Get all descendants of an item (uses pre-computed map for O(1) lookup)
  List<BudgetItem> _getAllDescendants(BudgetItem item) {
    return _descendantsByItemId[item.id] ?? [];
  }

  void _selectAll(bool select, List<BudgetItem> items) {
    setState(() {
      if (select) {
        _selectedBudgetItemIds = items.map((i) => i.id).toSet();
      } else {
        _selectedBudgetItemIds.clear();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedBudgetItemIds.clear();
    });
  }

  void _removeDeletedItemsFromView(
    Set<String> deletedIds, {
    required String workspaceId,
  }) {
    _allBudgetItems = _allBudgetItems
        .where((item) => !deletedIds.contains(item.id))
        .toList();
    _buildHierarchyMaps(_allBudgetItems);
    _selectedBudgetItemIds.removeAll(deletedIds);
    _budgetStream = _budgetService.getBudgetItems(
      widget.projectId,
      workspaceId: workspaceId,
    );
    _cachedWorkspaceId = workspaceId;
    _refreshBudgetSummary(workspaceId);
  }

  void _handleMassEdit() {
    final selectedItems = _allBudgetItems
        .where((item) => _selectedBudgetItemIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    showBudgetMassEditDialog(
      context,
      items: selectedItems,
      onItemsUpdated: (updatedItems) async {
        try {
          await _budgetService.updateBudgetItems(updatedItems);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Updated ${updatedItems.length} item${updatedItems.length > 1 ? 's' : ''}',
                ),
              ),
            );
          }
          _clearSelection();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'updating items'),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      },
      onDelete: _handleMassDelete,
    );
  }

  Future<void> _handleMassDelete() async {
    final workspaceId = _cachedWorkspaceId;
    if (workspaceId == null) return;

    final selectedItems = _allBudgetItems
        .where((item) => _selectedBudgetItemIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    // Collect all IDs that would be deleted (selected + descendants)
    final idsToDelete = <String>[];
    for (final item in selectedItems) {
      idsToDelete.add(item.id);
      idsToDelete.addAll(_getAllDescendants(item).map((d) => d.id));
    }

    // Check for linked documents
    final linkedDocs = await _budgetService.getLinkedDocumentsForBudgetItems(
      idsToDelete,
    );
    if (!mounted) return;
    if (linkedDocs.isNotEmpty) {
      _showLinkedDocumentsBlockDialog(linkedDocs);
      return;
    }

    // Count groups and items separately
    final groupCount = selectedItems
        .where((i) => i.itemType == BudgetItemType.group)
        .length;

    // Count total descendants that will also be deleted
    int descendantCount = 0;
    for (final item in selectedItems) {
      descendantCount += _getAllDescendants(item).length;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Items'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete ${selectedItems.length} item${selectedItems.length > 1 ? 's' : ''}?',
            ),
            if (groupCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$groupCount group${groupCount > 1 ? 's' : ''} selected',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if (descendantCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'This will also delete $descendantCount child item${descendantCount > 1 ? 's' : ''}.',
                style: TextStyle(
                  color: AppColors.errorDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deletedIds = idsToDelete.toSet();
      try {
        await _budgetService.deleteBudgetItems(
          selectedItems.map((i) => i.id).toList(),
        );
        if (mounted) {
          setState(() {
            _removeDeletedItemsFromView(deletedIds, workspaceId: workspaceId);
          });
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Deleted ${selectedItems.length} item${selectedItems.length > 1 ? 's' : ''}',
                ),
              ),
            );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting items'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _openDocumentWizard(
    String workspaceId, {
    Set<String>? preSelectedIds,
  }) async {
    // Collect leaf item IDs from any pre-selected items (traverse hierarchy)
    Set<String>? resolvedIds;
    if (preSelectedIds != null && preSelectedIds.isNotEmpty) {
      final leafIds = <String>{};
      for (final itemId in preSelectedIds) {
        final item = _allBudgetItems.firstWhereOrNull((i) => i.id == itemId);
        if (item == null) continue;
        if (item.itemType == BudgetItemType.item) {
          leafIds.add(item.id);
        } else {
          leafIds.addAll(
            (_leafDescendantsByItemId[item.id] ?? []).map((i) => i.id),
          );
        }
      }
      if (leafIds.isNotEmpty) {
        resolvedIds = leafIds;
      }
    }

    await BudgetDocumentWizard.show(
      context,
      projectId: widget.projectId,
      workspaceId: workspaceId,
      budgetItems: _allBudgetItems,
      preSelectedItemIds: resolvedIds,
      defaultCategory: _defaultCategoryForViewMode(_viewMode),
      onCreateDocument: widget.onCreateDocument,
    );

    if (!mounted) return;
    final metadataKey = _buildMetadataKey(
      widget.projectId,
      workspaceId,
      _allBudgetItems,
    );
    if (metadataKey.isNotEmpty) {
      await _loadProjectMetadata(
        widget.projectId,
        workspaceId,
        metadataKey: metadataKey,
        force: true,
      );
    }
  }

  /// Returns the document-creation label for the toolbar button in each view mode.
  /// Returns null for modes that don't support document creation (profit).
  static String? _toolbarDocLabel(BudgetViewMode mode) {
    switch (mode) {
      case BudgetViewMode.estimating:
        return 'Create Document';
      case BudgetViewMode.costing:
        return 'Record Bill';
      case BudgetViewMode.invoicing:
        return 'Create Invoice';
      case BudgetViewMode.changeOrders:
        return 'New Change Order';
      case BudgetViewMode.purchaseOrders:
        return 'New Purchase Order';
      case BudgetViewMode.upgrades:
        return 'Offer Upgrade';
      case BudgetViewMode.holdback:
        return 'Create Document';
      case BudgetViewMode.profit:
      case BudgetViewMode.workflow:
      case BudgetViewMode.selections:
        return null;
    }
  }

  static TemplateCategory? _defaultCategoryForViewMode(BudgetViewMode mode) {
    switch (mode) {
      case BudgetViewMode.estimating:
        // Estimating is the general document-creation entry point: let the user
        // create any document type (estimate, PO, invoice, etc.), not just
        // customer-order templates. Show all categories by returning null.
        return null;
      case BudgetViewMode.changeOrders:
      case BudgetViewMode.upgrades:
        return TemplateCategory.customerOrder;
      case BudgetViewMode.invoicing:
      case BudgetViewMode.holdback:
        return TemplateCategory.customerInvoice;
      case BudgetViewMode.costing:
      case BudgetViewMode.purchaseOrders:
        return TemplateCategory.vendorOrder;
      case BudgetViewMode.profit:
      case BudgetViewMode.workflow:
      case BudgetViewMode.selections:
        return null; // No default – show all categories
    }
  }

  // Item change handler

  Future<void> _handleItemChanged(BudgetItem updatedItem) async {
    try {
      await _budgetService.updateBudgetItem(updatedItem);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _moveItemWithinSiblings(BudgetItem item, int direction) async {
    final siblings = List<BudgetItem>.from(
      _childrenByParentId[item.parentId ?? ''] ?? const <BudgetItem>[],
    );
    if (siblings.length < 2) return;

    final currentIndex = siblings.indexWhere((s) => s.id == item.id);
    if (currentIndex < 0) return;

    final targetIndex = currentIndex + direction;
    if (targetIndex < 0 || targetIndex >= siblings.length) return;

    final movedItem = siblings.removeAt(currentIndex);
    siblings.insert(targetIndex, movedItem);

    try {
      await _budgetService.reorderItems(
        item.parentId,
        siblings.map((s) => s.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'reordering item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Navigate to documents linked to a budget item
  void _navigateToDocuments(BudgetItemDocumentStatus status) {
    if (status.documentIds.isEmpty) return;
    context.push('/documents/${status.documentIds.first}');
  }

  // Item edit handler

  void _handleEditItem(BudgetItem item) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) return;

    showBudgetItemFormPopup(
      context,
      projectId: widget.projectId,
      workspaceId: workspaceId,
      parentId: item.parentId,
      hierarchyLevel: item.hierarchyLevel,
      existingItem: item,
    );
  }

  Future<void> _handleDeleteItem(BudgetItem item) async {
    final isGroup = item.itemType == BudgetItemType.group;
    final hasChildren = _allBudgetItems.any((i) => i.parentId == item.id);

    // Collect all item IDs that would be deleted (item + descendants)
    final idsToDelete = <String>[item.id];
    if (hasChildren) {
      idsToDelete.addAll(_getAllDescendants(item).map((d) => d.id));
    }

    // Check for linked documents
    final linkedDocs = await _budgetService.getLinkedDocumentsForBudgetItems(
      idsToDelete,
    );
    if (!mounted) return;
    if (linkedDocs.isNotEmpty) {
      _showLinkedDocumentsBlockDialog(linkedDocs);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isGroup ? 'Group' : 'Item'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${item.name}"?'),
            if (hasChildren) ...[
              const SizedBox(height: 8),
              Text(
                'This will also delete all child items.',
                style: TextStyle(
                  color: AppColors.errorDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _budgetService.deleteBudgetItem(item.id);
        if (mounted) {
          final workspaceId = context
              .read<AuthProvider>()
              .appUser
              ?.currentWorkspaceId;
          if (workspaceId != null) {
            setState(() {
              _removeDeletedItemsFromView(
                idsToDelete.toSet(),
                workspaceId: workspaceId,
              );
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${isGroup ? 'Group' : 'Item'} "${item.name}" deleted',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(UserFacingError.uiMessage(e, action: 'deleting')),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleDuplicateItem(BudgetItem item) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    try {
      final nextSortOrder = await _budgetService.getNextSortOrder(
        item.parentId,
        item.projectId,
      );
      final now = DateTime.now();
      final duplicate = item.copyWith(
        id: '', // Will be assigned by Firestore/Supabase
        name: '${item.name} (Copy)',
        sortOrder: nextSortOrder,
        isComplete: false,
        completedDate: null,
        finalCost: 0,
        committedCost: 0,
        createdAt: now,
        updatedAt: now,
      );
      await _budgetService.createBudgetItem(duplicate);

      // If duplicating a group, also duplicate its children
      if (item.itemType == BudgetItemType.group) {
        final newParentId = _allBudgetItems
            .lastWhere(
              (i) => i.name == duplicate.name && i.parentId == item.parentId,
            )
            .id;
        final children = _childrenByParentId[item.id] ?? [];
        for (final child in children) {
          final childDuplicate = child.copyWith(
            id: '',
            parentId: newParentId,
            name: child.name,
            isComplete: false,
            completedDate: null,
            finalCost: 0,
            committedCost: 0,
            createdAt: now,
            updatedAt: now,
          );
          await _budgetService.createBudgetItem(childDuplicate);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${item.name}" duplicated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'duplicating')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleGroupItem(BudgetItem item) async {
    try {
      final nextSortOrder = await _budgetService.getNextSortOrder(
        item.parentId,
        item.projectId,
      );
      final now = DateTime.now();
      final group = item.copyWith(
        id: '',
        name: 'New Group',
        itemType: BudgetItemType.group,
        sortOrder: nextSortOrder,
        quantity: 0,
        unitCost: 0,
        unitPrice: 0,
        approvedPrice: 0,
        projectedCost: 0,
        committedCost: 0,
        finalCost: 0,
        description: null,
        isComplete: false,
        completedDate: null,
        createdAt: now,
        updatedAt: now,
      );
      final groupId = await _budgetService.createBudgetItem(group);

      await _budgetService.moveItem(item.id, groupId, 0);
      if (!mounted) return;
      setState(() => _expandedItems.add(groupId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${item.name}" wrapped in a new group')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'grouping item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSaveAsTemplate(BudgetItem item) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;
    if (workspaceId == null || userId == null) return;

    final nameController = TextEditingController(text: item.name);
    final descController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Template Name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final templateService = ServiceLocator.budgetTemplateService;
      // Collect items to template: the item itself + descendants if group
      final itemsToTemplate = <BudgetItem>[item];
      if (item.itemType == BudgetItemType.group) {
        itemsToTemplate.addAll(_getAllDescendants(item));
      }

      await templateService.createTemplateFromItems(
        items: itemsToTemplate,
        workspaceId: workspaceId,
        name: nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
        createdBy: userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "${nameController.text.trim()}" saved'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving template'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSaveToCatalog(BudgetItem item) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    final itemsToSave = <BudgetItem>[item];
    if (item.itemType == BudgetItemType.group) {
      itemsToSave.addAll(_getAllDescendants(item));
    }

    final itemCount = itemsToSave
        .where((i) => i.itemType == BudgetItemType.item)
        .length;
    final label = item.itemType == BudgetItemType.group
        ? '"${item.name}" ($itemCount items)'
        : '"${item.name}"';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save to Catalog'),
        content: Text('Add $label to your workspace catalog?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final catalogService = ServiceLocator.catalogService;
      await catalogService.copyBudgetItemsToCatalog(
        budgetItems: itemsToSave,
        workspaceId: workspaceId,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label saved to catalog')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving to catalog'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showLinkedDocumentsBlockDialog(
    Map<String, List<Map<String, String>>> linkedDocs,
  ) {
    // Deduplicate documents across all items
    final uniqueDocs = <String, Map<String, String>>{};
    for (final docs in linkedDocs.values) {
      for (final doc in docs) {
        uniqueDocs[doc['id']!] = doc;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot Delete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              uniqueDocs.length == 1
                  ? 'This item is linked to a document. Please delete the document first.'
                  : 'These items are linked to ${uniqueDocs.length} documents. Please delete the documents first.',
            ),
            const SizedBox(height: 12),
            ...uniqueDocs.values.map(
              (doc) => InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  this.context.push('/documents/${doc['id']}');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          doc['template_name']!,
                          style: TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleItemParentChanged(
    BudgetItem item,
    String? newParentId,
  ) async {
    try {
      final newSortOrder = await _budgetService.getNextSortOrder(
        newParentId,
        item.projectId,
      );
      await _budgetService.moveItem(item.id, newParentId, newSortOrder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved "${item.name}" successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'moving item')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleItemDropped(
    BudgetItem dragged,
    BudgetItem target,
    DropZone zone,
  ) async {
    switch (zone) {
      case DropZone.child:
        // Re-parent dragged item under target
        await _handleItemParentChanged(dragged, target.id);
      case DropZone.above:
      case DropZone.below:
        // Move dragged to same parent as target, positioned above/below
        final targetParentId = target.parentId;
        final siblings = List<BudgetItem>.from(
          _childrenByParentId[targetParentId ?? ''] ?? const <BudgetItem>[],
        );
        // Remove dragged from siblings if already there
        siblings.removeWhere((s) => s.id == dragged.id);
        final targetIndex = siblings.indexWhere((s) => s.id == target.id);
        if (targetIndex < 0) {
          // Fallback: just re-parent to end
          await _handleItemParentChanged(dragged, targetParentId);
          return;
        }
        final insertIndex = zone == DropZone.above
            ? targetIndex
            : targetIndex + 1;
        siblings.insert(insertIndex, dragged);
        try {
          // First move to correct parent if needed
          if (dragged.parentId != targetParentId) {
            await _budgetService.moveItem(
              dragged.id,
              targetParentId,
              insertIndex,
            );
          }
          // Then reorder all siblings
          await _budgetService.reorderItems(
            targetParentId,
            siblings.map((s) => s.id).toList(),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  UserFacingError.uiMessage(e, action: 'moving item'),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      case DropZone.unparent:
        // Move to root (remove parent)
        await _handleItemParentChanged(dragged, null);
      case DropZone.none:
        break;
    }
  }

  void _onBudgetItemDragStarted() {
    if (!_isBudgetItemDragging) {
      setState(() => _isBudgetItemDragging = true);
    }
  }

  void _onBudgetItemDragEnded() {
    if (_isBudgetItemDragging || _isUngroupDropTargetActive) {
      setState(() {
        _isBudgetItemDragging = false;
        _isUngroupDropTargetActive = false;
      });
    }
  }

  // Item creation handler

  void _handleAddItem(
    String? parentId,
    int hierarchyLevel, {
    required bool isGroup,
  }) {
    if (kDebugMode) {
      debugPrint(
        '_handleAddItem: parentId=$parentId, hierarchyLevel=$hierarchyLevel, isGroup=$isGroup',
      );
    }
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      if (kDebugMode) {
        debugPrint('_handleAddItem: workspaceId is null, returning');
      }
      return;
    }

    // In card view the inline add row is docked at the top of the list,
    // so clicking Add Item/Group at the bottom appears to do nothing.
    // Open the popup instead — it's visible regardless of scroll position.
    if (_isMobileView) {
      showBudgetItemFormPopup(
        context,
        projectId: widget.projectId,
        workspaceId: workspaceId,
        parentId: parentId,
        hierarchyLevel: hierarchyLevel,
        isGroup: isGroup,
        sourceType: _sourceTypeForCurrentMode(),
      );
      return;
    }

    // Expand the parent if adding a child
    if (parentId != null) {
      setState(() {
        _expandedItems.add(parentId);
        _addingToParentId = parentId;
        _addingHierarchyLevel = hierarchyLevel;
        _addingAsGroup = isGroup;
      });
    } else {
      setState(() {
        _addingToParentId = null;
        _addingHierarchyLevel = 0;
        _addingAsGroup = isGroup;
      });
    }
  }

  Future<void> _loadProjectMetadata(
    String projectId,
    String workspaceId, {
    required String metadataKey,
    bool force = false,
  }) async {
    if (!force &&
        (_loadedMetadataKey == metadataKey ||
            _loadingMetadataKey == metadataKey)) {
      return;
    }
    if (_isMetadataLoading && !force) {
      return;
    }

    _isMetadataLoading = true;
    _loadingMetadataKey = metadataKey;

    if (mounted) {
      setState(() {});
    }

    try {
      final results = await Future.wait<dynamic>([
        _budgetService.getActualCostsForProject(projectId, workspaceId),
        _budgetService.getDocumentStatusForProject(projectId, workspaceId),
        _budgetService.getProgressTextsForProject(projectId, workspaceId),
        _projectService.getProject(projectId) as Future<Project?>,
        ServiceLocator.budgetTaskLinkService.getLaborSummaryForProject(
          projectId,
          workspaceId,
        ),
        _budgetService.getChangeOrderStatusesForProject(projectId, workspaceId),
      ]);

      if (mounted &&
          widget.projectId == projectId &&
          _loadingMetadataKey == metadataKey) {
        setState(() {
          final costs = results[0] as Map<String, double>;
          final docStatuses =
              results[1] as Map<String, BudgetItemDocumentStatus>;
          final progressTexts = results[2] as Map<String, String>;
          _project = results[3] as Project?;
          final laborSummaries =
              results[4] as Map<String, BudgetItemLaborSummary>;
          final changeOrderStatuses = results[5] as Map<String, String>;

          _actualCosts
            ..clear()
            ..addAll(costs);
          _documentStatuses
            ..clear()
            ..addAll(docStatuses);
          _progressTexts
            ..clear()
            ..addAll(progressTexts);
          _laborSummaries
            ..clear()
            ..addAll(laborSummaries);
          _changeOrderStatuses
            ..clear()
            ..addAll(changeOrderStatuses);
          _invoicedAmounts.clear();

          // Roll up labor summaries to parent groups
          _rollUpLaborSummaries();

          // Also update invoiced amounts from doc statuses for convenience
          docStatuses.forEach((id, status) {
            _invoicedAmounts[id] = status.invoicedAmount;
          });

          _loadedMetadataKey = metadataKey;
          _loadingMetadataKey = null;
          _isMetadataLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading project metadata: $e');
      if (mounted &&
          widget.projectId == projectId &&
          _loadingMetadataKey == metadataKey) {
        setState(() {
          _loadingMetadataKey = null;
          _isMetadataLoading = false;
        });
      }
    }
  }

  /// Roll up labor summaries from leaf items to parent groups
  void _rollUpLaborSummaries() {
    final maxLevel = _allBudgetItems.fold<int>(
      0,
      (max, item) => item.hierarchyLevel > max ? item.hierarchyLevel : max,
    );
    for (int level = maxLevel; level > 0; level--) {
      final parentItems = _allBudgetItems
          .where((i) => i.hierarchyLevel == level - 1)
          .toList();
      for (final parent in parentItems) {
        final children = _allBudgetItems
            .where((i) => i.parentId == parent.id)
            .toList();
        if (children.isEmpty) continue;

        var rolled = BudgetItemLaborSummary(budgetItemId: parent.id);
        for (final child in children) {
          final childSummary = _laborSummaries[child.id];
          if (childSummary != null) {
            rolled = rolled + childSummary;
          }
        }
        if (rolled.taskCount > 0) {
          _laborSummaries[parent.id] = rolled;
        }
      }
    }
  }

  Future<void> _exportToCSV() async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      const errorMsg = 'Error: No workspace found';
      debugPrint(errorMsg);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: SelectableText(errorMsg),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final project = await _projectService.getProject(widget.projectId);
      if (project == null) {
        throw Exception('Project not found');
      }

      await _budgetExport.exportBudgetToCSV(
        projectId: widget.projectId,
        workspaceId: workspaceId,
        project: project,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Budget exported to CSV')));
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = UserFacingError.uiMessage(e, action: 'export budget');
        debugPrint(errorMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(errorMsg),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showImportCatalogDialog(String workspaceId) async {
    await showCatalogImportDialog(
      context,
      projectId: widget.projectId,
      workspaceId: workspaceId,
    );
  }

  Future<void> _showExportToCatalogDialog(String workspaceId) async {
    await showBudgetToCatalogDialog(
      context,
      projectId: widget.projectId,
      workspaceId: workspaceId,
    );
  }

  Future<void> _showExportDialog(String workspaceId) async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose export format:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Standard CSV'),
              subtitle: const Text('Full budget with all details'),
              onTap: () => Navigator.pop(context, 'standard'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Standard PDF'),
              subtitle: const Text('Printable budget report'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('QuickBooks'),
              subtitle: const Text('Products/Services + Estimate format'),
              onTap: () => Navigator.pop(context, 'quickbooks'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;

    if (format == 'standard') {
      await _exportToCSV();
    } else if (format == 'pdf') {
      await _exportToPDF(workspaceId);
    } else if (format == 'quickbooks') {
      await _exportToQuickBooks(workspaceId);
    }
  }

  Future<void> _exportToPDF(String workspaceId) async {
    final currencyCode = _currencyCode;

    try {
      final project = await _projectService.getProject(widget.projectId);
      if (project == null) {
        throw Exception('Project not found');
      }

      await _budgetExport.exportBudgetToPDF(
        projectId: widget.projectId,
        workspaceId: workspaceId,
        project: project,
        currencyCode: currencyCode,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Budget exported to PDF')));
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = UserFacingError.uiMessage(e, action: 'export budget');
        debugPrint(errorMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(errorMsg),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _exportToQuickBooks(String workspaceId) async {
    try {
      final project = await _projectService.getProject(widget.projectId);
      if (project == null) {
        throw Exception('Project not found');
      }

      final truncatedCount = await _budgetExport.exportBudgetToQuickBooks(
        projectId: widget.projectId,
        workspaceId: workspaceId,
        project: project,
      );

      if (mounted) {
        if (truncatedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Budget exported. Note: $truncatedCount product name${truncatedCount > 1 ? 's were' : ' was'} truncated to fit QBO\'s 100-character limit.',
              ),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget exported to QuickBooks format'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = UserFacingError.uiMessage(e, action: 'export budget');
        debugPrint(errorMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(errorMsg),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Inline sortable label for budget table header columns (Name, Id).
class _BudgetSortableLabel extends StatefulWidget {
  final String label;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  const _BudgetSortableLabel({
    required this.label,
    this.textStyle,
    this.textAlign = TextAlign.left,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  @override
  State<_BudgetSortableLabel> createState() => _BudgetSortableLabelState();
}

class _BudgetSortableLabelState extends State<_BudgetSortableLabel> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final sortIcon = widget.isSorted
        ? (widget.ascending ? Icons.arrow_upward : Icons.arrow_downward)
        : Icons.unfold_more;
    final showIcon = widget.isSorted || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlign,
              style: widget.isSorted
                  ? widget.textStyle?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : widget.textStyle,
            ),
            if (showIcon) ...[
              const SizedBox(width: 2),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: widget.isSorted ? 1.0 : 0.5,
                child: Icon(
                  sortIcon,
                  size: 14,
                  color: widget.isSorted
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewModeMenuItemContent extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;

  const _ViewModeMenuItemContent({
    required this.icon,
    required this.label,
    required this.isSelected,
  });

  @override
  State<_ViewModeMenuItemContent> createState() =>
      _ViewModeMenuItemContentState();
}

class _ViewModeMenuItemContentState extends State<_ViewModeMenuItemContent> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        height: 40,
        color: _hovering
            ? AppColors.sidebarHover.withValues(alpha: 0.6)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: widget.isSelected
                  ? AppColors.secondary
                  : AppColors.sidebarText,
            ),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                color: widget.isSelected
                    ? Colors.white
                    : AppColors.sidebarText,
              ),
            ),
            const Spacer(),
            if (widget.isSelected)
              const Icon(Icons.check, size: 18, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}

/// Compact rollup card showing how selections & allowances affect the budget.
/// Lives directly under the BudgetSummaryPanel on the Financials tab.
class _SelectionsBudgetCard extends StatefulWidget {
  final String projectId;
  final String Function(double) formatCurrency;
  const _SelectionsBudgetCard({
    required this.projectId,
    required this.formatCurrency,
  });
  @override
  State<_SelectionsBudgetCard> createState() => _SelectionsBudgetCardState();
}

class _SelectionsBudgetCardState extends State<_SelectionsBudgetCard> {
  late Stream<SelectionSummary> _stream;

  Stream<SelectionSummary> _makeStream(String projectId) {
    final svc = ServiceLocator.selectionService;
    return svc.watchByProject(projectId).map(svc.summarise);
  }

  @override
  void initState() {
    super.initState();
    _stream = _makeStream(widget.projectId);
  }

  @override
  void didUpdateWidget(covariant _SelectionsBudgetCard old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) {
      _stream = _makeStream(widget.projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SelectionSummary>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final s = snap.data!;
        if (s.countTotal == 0) return const SizedBox.shrink();
        final variance = s.approvedVariance;
        final varianceColor = variance > 0
            ? AppColors.error
            : (variance < 0 ? AppColors.success : AppColors.textSecondary);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.checklist_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text('Selections',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              _cell('Total Allowance',
                  widget.formatCurrency(s.totalAllowance)),
              const SizedBox(width: 24),
              _cell('Approved', widget.formatCurrency(s.totalSelected),
                  color: AppColors.success),
              const SizedBox(width: 24),
              _cell('Pending', widget.formatCurrency(s.pendingAllowance),
                  color: AppColors.warning),
              const SizedBox(width: 24),
              _cell('Variance', widget.formatCurrency(variance),
                  color: varianceColor),
              const Spacer(),
              Text(
                '${s.countAwaitingClient} awaiting · '
                '${s.countApproved} approved',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}
