/// Flat table view of all Purchase Orders (Materials, Subcontracts, Rentals)
/// for a project. Renders inside the Financials tab so it shares the same
/// chrome (header row, body rows, summary footer) as the Budget / Bills /
/// Invoices views.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/subcontract.dart';
import '../../../models/vendor.dart';
import '../../../models/work_order.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/currency_utils.dart';
import '../../../utils/table_sort_state.dart';
import '../../../widgets/common/item_card.dart';
import '../../../widgets/common/metric_chip.dart';
import '../../../widgets/common/status_chip.dart';
import '../../../widgets/common/zero_items_action_empty_state.dart';
import '../../../widgets/table/table_column_schema.dart';
import '../../../widgets/table/table_header_cells_builder.dart';
import '../../../widgets/table/table_header_row.dart';
import '../../../widgets/table/table_layout_shell.dart';
import '../../../widgets/table/table_summary_footer.dart';
import '../../../widgets/table/table_view_styles.dart';
import 'project_subcontracts_tab.dart';
import 'project_work_orders_tab.dart';

enum _PoKind { materials, subcontract, rental }

extension on _PoKind {
  String get label => switch (this) {
        _PoKind.materials => 'Materials',
        _PoKind.subcontract => 'Subcontract',
        _PoKind.rental => 'Rental',
      };

  IconData get icon => switch (this) {
        _PoKind.materials => Icons.inventory_2_outlined,
        _PoKind.subcontract => Icons.handshake_outlined,
        _PoKind.rental => Icons.local_shipping_outlined,
      };

  Color get color => switch (this) {
        _PoKind.materials => const Color(0xFF3B82F6),
        _PoKind.subcontract => const Color(0xFF8B5CF6),
        _PoKind.rental => const Color(0xFF14B8A6),
      };
}

enum _Filter { all, materials, subcontracts, rentals }

class _PoRow {
  final _PoKind kind;
  final String id;
  final String number;
  final String title;
  final String? vendorId;
  final int itemCount;
  final double committed;
  final double paid;
  final DateTime? date;
  final String statusLabel;
  final Color statusColor;
  final WorkOrder? workOrder;
  final Subcontract? subcontract;

  const _PoRow({
    required this.kind,
    required this.id,
    required this.number,
    required this.title,
    required this.vendorId,
    required this.itemCount,
    required this.committed,
    required this.paid,
    required this.date,
    required this.statusLabel,
    required this.statusColor,
    this.workOrder,
    this.subcontract,
  });

  double get remaining => committed - paid;

  factory _PoRow.fromWorkOrder(WorkOrder w) {
    final kind = w.kind == 'rental' ? _PoKind.rental : _PoKind.materials;
    return _PoRow(
      kind: kind,
      id: w.id,
      number: w.number,
      title: w.title,
      vendorId: w.vendorId,
      itemCount: w.items.length,
      committed: w.totalAmount,
      paid: w.paidToDate,
      date: w.scheduledStart ?? w.createdAt,
      statusLabel: w.status.label,
      statusColor: w.status.color,
      workOrder: w,
    );
  }

  factory _PoRow.fromSubcontract(Subcontract s) {
    return _PoRow(
      kind: _PoKind.subcontract,
      id: s.id,
      number: s.number,
      title: s.title,
      vendorId: s.vendorId,
      itemCount: s.items.length,
      committed: s.contractAmount,
      paid: s.paidToDate,
      date: s.startDate ?? s.sentAt ?? s.createdAt,
      statusLabel: s.status.label,
      statusColor: s.status.color,
      subcontract: s,
    );
  }
}

class ProjectPurchaseOrdersTableView extends StatefulWidget {
  final Project project;

  /// Workspace currency code (ISO 4217). Used so the PO table formats money
  /// the same way as the rest of the Financials tab instead of hardcoding USD.
  final String currencyCode;

  /// Free-text query from the shared Financials toolbar. Filters rows by
  /// number, title and vendor so the global search box is not inert here.
  final String searchQuery;

  /// Invoked by the "New Purchase Order" action and the empty-state CTA.
  final VoidCallback? onCreatePurchaseOrder;

  /// Reports project-level PO totals (committed, paid, count) whenever the
  /// underlying streams change, so the host can render a summary card above its
  /// shared toolbar — keeping the figures in sync with this table's footer.
  final void Function(double committed, double paid, int count)? onSummary;

  /// When true the table shrinks to the viewport instead of scrolling
  /// horizontally — driven by the shared toolbar's fit-to-screen toggle so the
  /// PO view honors the same preference as the budget grids.
  final bool fitToScreen;

  /// Column visibility predicate, driven by the shared toolbar's column
  /// picker. Null shows every column.
  final bool Function(String columnId)? isColumnVisible;

  /// When true, renders POs as shrink-wrapped cards (same visual language as
  /// the budget item cards in BudgetMobileView) instead of the flat table —
  /// driven by the shared card/list toggle so this view honors the same
  /// layout preference as the budget grids.
  final bool cardLayout;

  const ProjectPurchaseOrdersTableView({
    super.key,
    required this.project,
    this.currencyCode = 'USD',
    this.searchQuery = '',
    this.onCreatePurchaseOrder,
    this.onSummary,
    this.fitToScreen = false,
    this.isColumnVisible,
    this.cardLayout = false,
  });

  /// Column ids/labels exposed so the host's shared toolbar can render the
  /// same column picker the budget grids use.
  static List<String> get columnIds =>
      [for (final c in _ProjectPurchaseOrdersTableViewState._columns) c.id];

  static String columnLabel(String columnId) =>
      _ProjectPurchaseOrdersTableViewState._columns
          .firstWhere((c) => c.id == columnId)
          .label ??
      columnId;

  @override
  State<ProjectPurchaseOrdersTableView> createState() =>
      _ProjectPurchaseOrdersTableViewState();
}

class _ProjectPurchaseOrdersTableViewState
    extends State<ProjectPurchaseOrdersTableView> {
  StreamSubscription<List<WorkOrder>>? _matSub;
  StreamSubscription<List<WorkOrder>>? _rentSub;
  StreamSubscription<List<Subcontract>>? _subSub;
  StreamSubscription<List<Vendor>>? _vendorSub;
  String? _subscribedProjectId;

  List<WorkOrder> _materials = const [];
  List<WorkOrder> _rentals = const [];
  List<Subcontract> _subcontracts = const [];
  Map<String, Vendor> _vendorsById = const {};

  bool _matLoaded = false;
  bool _rentLoaded = false;
  bool _subLoaded = false;
  Object? _error;

  _Filter _filter = _Filter.all;

  // Header sort + resizable column overrides, mirroring the budget grids'
  // interactions (3-state sort, drag-to-resize). Unsorted falls back to the
  // default newest-first date order.
  TableSortState _sortState = const TableSortState();
  final Map<String, double> _columnWidths = {};

  // Match the rest of the Financials tab: workspace currency symbol with two
  // decimal places (CurrencyUtils.formatCurrency uses the same formatting).
  late final NumberFormat _currency = NumberFormat.currency(
    symbol: CurrencyUtils.getSymbol(widget.currencyCode),
    decimalDigits: 2,
  );
  final _dateFmt = DateFormat.MMMd();

  @override
  void initState() {
    super.initState();
    _subscribePoStreams();
  }

  @override
  void didUpdateWidget(covariant ProjectPurchaseOrdersTableView old) {
    super.didUpdateWidget(old);
    if (old.project.id != widget.project.id) {
      _subscribePoStreams();
    }
  }

  /// Reports project-level totals to the host so it can render the summary
  /// card above its toolbar. Computed from every PO (ignores the chip/search
  /// filter) so the figure stays stable as the user filters.
  void _notifySummary() {
    final cb = widget.onSummary;
    if (cb == null) return;
    double committed = 0, paid = 0;
    var count = 0;
    for (final w in _materials) {
      committed += w.totalAmount;
      paid += w.paidToDate;
      count++;
    }
    for (final w in _rentals) {
      committed += w.totalAmount;
      paid += w.paidToDate;
      count++;
    }
    for (final s in _subcontracts) {
      committed += s.contractAmount;
      paid += s.paidToDate;
      count++;
    }
    cb(committed, paid, count);
  }

  void _subscribePoStreams() {
    final pid = widget.project.id;
    if (_subscribedProjectId == pid) return;
    _matSub?.cancel();
    _rentSub?.cancel();
    _subSub?.cancel();
    _materials = const [];
    _rentals = const [];
    _subcontracts = const [];
    _matLoaded = false;
    _rentLoaded = false;
    _subLoaded = false;
    _error = null;
    _subscribedProjectId = pid;
    _matSub = ServiceLocator.workOrderService
        .watchByProject(pid, kind: 'materials')
        .listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _materials = rows;
          _matLoaded = true;
        });
        _notifySummary();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = e);
      },
    );
    _rentSub = ServiceLocator.workOrderService
        .watchByProject(pid, kind: 'rental')
        .listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _rentals = rows;
          _rentLoaded = true;
        });
        _notifySummary();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = e);
      },
    );
    _subSub = ServiceLocator.subcontractService.watchByProject(pid).listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _subcontracts = rows;
          _subLoaded = true;
        });
        _notifySummary();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = e);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vendorSub != null) return;
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final stream = ServiceLocator.vendorService.getVendors(workspaceId)
        as Stream<List<Vendor>>;
    _vendorSub = stream.listen(
      (vendors) {
        if (!mounted) return;
        setState(() => _vendorsById = {for (final v in vendors) v.id: v});
      },
      onError: (_) {
        // Vendor lookups are non-critical; fall back to em-dash in the row.
      },
    );
  }

  @override
  void dispose() {
    _matSub?.cancel();
    _rentSub?.cancel();
    _subSub?.cancel();
    _vendorSub?.cancel();
    super.dispose();
  }

  String _vendorName(_PoRow r) =>
      (r.vendorId == null ? null : _vendorsById[r.vendorId]?.displayName) ?? '';

  List<_PoRow> _buildRows() {
    var rows = <_PoRow>[
      if (_filter == _Filter.all || _filter == _Filter.materials)
        ..._materials.map(_PoRow.fromWorkOrder),
      if (_filter == _Filter.all || _filter == _Filter.subcontracts)
        ..._subcontracts.map(_PoRow.fromSubcontract),
      if (_filter == _Filter.all || _filter == _Filter.rentals)
        ..._rentals.map(_PoRow.fromWorkOrder),
    ];
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((r) {
        return r.number.toLowerCase().contains(query) ||
            r.title.toLowerCase().contains(query) ||
            _vendorName(r).toLowerCase().contains(query);
      }).toList();
    }
    rows.sort(_rowComparator);
    return rows;
  }

  int _rowComparator(_PoRow a, _PoRow b) {
    int byDateDesc() {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    }

    final column = _sortState.column;
    if (column == null) return byDateDesc();
    int cmp;
    switch (column) {
      case 'number':
        cmp = a.number.toLowerCase().compareTo(b.number.toLowerCase());
        break;
      case 'type':
        cmp = a.kind.label.compareTo(b.kind.label);
        break;
      case 'title':
        cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        break;
      case 'vendor':
        cmp = _vendorName(a)
            .toLowerCase()
            .compareTo(_vendorName(b).toLowerCase());
        break;
      case 'date':
        cmp = (a.date ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.date ?? DateTime.fromMillisecondsSinceEpoch(0));
        break;
      case 'items':
        cmp = a.itemCount.compareTo(b.itemCount);
        break;
      case 'committed':
        cmp = a.committed.compareTo(b.committed);
        break;
      case 'paid':
        cmp = a.paid.compareTo(b.paid);
        break;
      case 'remaining':
        cmp = a.remaining.compareTo(b.remaining);
        break;
      case 'status':
        cmp = a.statusLabel.compareTo(b.statusLabel);
        break;
      default:
        cmp = 0;
    }
    if (cmp == 0) return byDateDesc();
    return _sortState.ascending ? cmp : -cmp;
  }

  static const _columns = <TableColumnSchema>[
    TableColumnSchema(id: 'number', label: '#', defaultWidth: 100),
    TableColumnSchema(id: 'type', label: 'Type', defaultWidth: 130),
    TableColumnSchema(id: 'title', label: 'Title', defaultWidth: 280),
    TableColumnSchema(id: 'vendor', label: 'Vendor', defaultWidth: 200),
    TableColumnSchema(id: 'date', label: 'Date', defaultWidth: 100),
    TableColumnSchema(
        id: 'items', label: 'Items', defaultWidth: 70, align: TextAlign.right),
    TableColumnSchema(
        id: 'committed',
        label: 'Committed',
        defaultWidth: 120,
        align: TextAlign.right,
        borderLeft: true),
    TableColumnSchema(
        id: 'paid', label: 'Paid', defaultWidth: 110, align: TextAlign.right),
    TableColumnSchema(
        id: 'remaining',
        label: 'Remaining',
        defaultWidth: 120,
        align: TextAlign.right),
    TableColumnSchema(id: 'status', label: 'Status', defaultWidth: 130),
  ];

  Map<String, double> get _widths => {
        for (final c in _columns)
          c.id: _columnWidths[c.id] ?? c.defaultWidth,
      };

  bool _isVisible(String columnId) =>
      widget.isColumnVisible?.call(columnId) ?? true;

  /// Min table width when not fitting to screen: visible columns + row padding.
  double get _minTableWidth {
    if (widget.fitToScreen) return 0;
    var w = 20.0; // horizontal row padding
    for (final c in _columns) {
      if (_isVisible(c.id)) w += _widths[c.id]!;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _matLoaded && _rentLoaded && _subLoaded;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Failed to load purchase orders: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (!loaded) {
      // Card layout embeds in the host's outer ListView (unbounded height),
      // so the spinner needs its own bounded box there.
      return widget.cardLayout
          ? const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            )
          : const Center(child: CircularProgressIndicator());
    }

    final rows = _buildRows();
    if (widget.cardLayout) {
      return _buildCardLayout(rows);
    }
    final totalCommitted = rows.fold<double>(0, (s, r) => s + r.committed);
    final totalPaid = rows.fold<double>(0, (s, r) => s + r.paid);
    final totalRemaining = totalCommitted - totalPaid;
    final totalItems = rows.fold<int>(0, (s, r) => s + r.itemCount);

    return DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.2,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      child: TableLayoutShell(
        minTableWidth: _minTableWidth,
        topControls: _buildFilterStrip(rows.length),
        header: _buildHeader(),
        body: rows.isEmpty
            ? _buildEmptyState(
                filteredBySearch: widget.searchQuery.trim().isNotEmpty,
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => _buildRow(rows[index]),
              ),
        footer: _buildFooter(
          count: rows.length,
          totalItems: totalItems,
          totalCommitted: totalCommitted,
          totalPaid: totalPaid,
          totalRemaining: totalRemaining,
        ),
      ),
    );
  }

  Widget _buildFilterStrip(int visibleCount) {
    final counts = {
      _Filter.all:
          _materials.length + _subcontracts.length + _rentals.length,
      _Filter.materials: _materials.length,
      _Filter.subcontracts: _subcontracts.length,
      _Filter.rentals: _rentals.length,
    };
    Widget chip(_Filter f, String label) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label  ${counts[f] ?? 0}'),
          selected: selected,
          onSelected: (_) => setState(() => _filter = f),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          chip(_Filter.all, 'All'),
          chip(_Filter.materials, 'Materials'),
          chip(_Filter.subcontracts, 'Subcontracts'),
          chip(_Filter.rentals, 'Rentals'),
          const Spacer(),
          Text(
            '$visibleCount showing',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Card layout: filter chips followed by shrink-wrapped PO cards, so the
  /// whole thing scrolls with the host's outer ListView exactly like the
  /// budget item cards do.
  Widget _buildCardLayout(List<_PoRow> rows) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterStrip(rows.length),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          SizedBox(
            height: 420,
            child: _buildEmptyState(
              filteredBySearch: widget.searchQuery.trim().isNotEmpty,
            ),
          )
        else
          for (final row in rows) _buildCard(row),
      ],
    );
  }

  /// Single PO card, mirroring BudgetMobileView's budget item cards: white
  /// rounded card, bold title with chips on the right, caption subtitle line,
  /// and an equal-width row of MetricChips.
  Widget _buildCard(_PoRow row) {
    final colorScheme = Theme.of(context).colorScheme;
    final vendor = _vendorName(row);
    final subtitleParts = <String>[
      row.number,
      if (vendor.isNotEmpty) vendor,
      if (row.date != null) _dateFmt.format(row.date!),
      '${row.itemCount} item${row.itemCount == 1 ? '' : 's'}',
    ];
    return ItemCard(
      onTap: () => _openDetail(row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.title.isEmpty ? '(untitled)' : row.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _typeBadge(row.kind),
              const SizedBox(width: 6),
              _statusPill(row.statusLabel, row.statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitleParts.join('  ·  '),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MetricChip(
                  label: 'Committed',
                  value: _currency.format(row.committed),
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricChip(
                  label: 'Paid',
                  value: _currency.format(row.paid),
                  color: AppColors.successDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricChip(
                  label: 'Remaining',
                  value: _currency.format(row.remaining),
                  color: row.remaining > 0 ? AppColors.warningDark : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final headerStyle = TableViewStyles.headerLabelStyle(context) ??
        const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AppColors.textSecondary,
        );
    final cells = buildTableHeaderCells(
      context: context,
      columns: _columns,
      widths: _widths,
      isVisible: (c) => _isVisible(c.id),
      onColumnResize: (resize) =>
          setState(() => _columnWidths[resize.columnId] = resize.width),
      onSortTap: (c) => setState(() => _sortState = _sortState.toggle(c.id)),
      sortedColumnId: _sortState.column,
      sortAscending: _sortState.ascending,
      textStyle: headerStyle,
    );
    return TableHeaderRow(
      excelStyle: true,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: cells,
    );
  }

  Widget _buildRow(_PoRow row) {
    final colorScheme = Theme.of(context).colorScheme;
    final vendor = row.vendorId == null ? null : _vendorsById[row.vendorId];
    final vendorName = vendor?.displayName ?? '—';
    final dateText = row.date == null ? '—' : _dateFmt.format(row.date!);

    Widget cell(String id) {
      final width = _widths[id]!;
      switch (id) {
        case 'number':
          return SizedBox(
            width: width,
            child: Text(
              row.number,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        case 'type':
          return SizedBox(width: width, child: _typeBadge(row.kind));
        case 'title':
          return SizedBox(
            width: width,
            child: Text(
              row.title.isEmpty ? '(untitled)' : row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        case 'vendor':
          return SizedBox(
            width: width,
            child: Text(
              vendorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        case 'date':
          return SizedBox(
            width: width,
            child: Text(
              dateText,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        case 'items':
          return SizedBox(
            width: width,
            child: Text(row.itemCount.toString(), textAlign: TextAlign.right),
          );
        case 'committed':
          return Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.only(left: 8),
            child: SizedBox(
              width: width,
              child: Text(
                _currency.format(row.committed),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          );
        case 'paid':
          return SizedBox(
            width: width,
            child: Text(
              _currency.format(row.paid),
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.successDark),
            ),
          );
        case 'remaining':
          return SizedBox(
            width: width,
            child: Text(
              _currency.format(row.remaining),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: row.remaining > 0
                    ? AppColors.warningDark
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          );
        case 'status':
          return SizedBox(
            width: width,
            child: _statusPill(row.statusLabel, row.statusColor),
          );
        default:
          return SizedBox(width: width);
      }
    }

    return InkWell(
      onTap: () => _openDetail(row),
      child: Container(
        // Spreadsheet-density chrome matching the budget grids: 36px rows
        // with the same fully-opaque hairline divider (see BudgetViewRow).
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFD7DBE0), width: 1),
          ),
        ),
        child: Row(
          children: [
            for (final c in _columns)
              if (_isVisible(c.id)) cell(c.id),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(_PoKind kind) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: 13, color: kind.color),
          const SizedBox(width: 4),
          Text(
            kind.label,
            style: TextStyle(
              color: kind.color,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    // Canonical pill; Align stops it stretching to the cell width.
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusChip(label: label, color: color, size: StatusChipSize.compact),
    );
  }

  Widget _buildFooter({
    required int count,
    required int totalItems,
    required double totalCommitted,
    required double totalPaid,
    required double totalRemaining,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // The totals label spans whichever of the leading text columns are
    // visible, keeping the numeric cells aligned under their headers.
    var labelWidth = 0.0;
    for (final id in const ['number', 'type', 'title', 'vendor', 'date']) {
      if (_isVisible(id)) labelWidth += _widths[id]!;
    }
    return TableSummaryFooter(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            'TOTALS  ($count)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: colorScheme.primary,
            ),
          ),
        ),
        if (_isVisible('items'))
          TableSummaryCell(
            width: _widths['items']!,
            text: totalItems.toString(),
            isBold: true,
          ),
        if (_isVisible('committed'))
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.only(left: 8),
            child: TableSummaryCell(
              width: _widths['committed']!,
              text: _currency.format(totalCommitted),
              isBold: true,
            ),
          ),
        if (_isVisible('paid'))
          TableSummaryCell(
            width: _widths['paid']!,
            text: _currency.format(totalPaid),
            color: AppColors.successDark,
            isBold: true,
          ),
        if (_isVisible('remaining'))
          TableSummaryCell(
            width: _widths['remaining']!,
            text: _currency.format(totalRemaining),
            color: totalRemaining > 0
                ? AppColors.warningDark
                : colorScheme.onSurfaceVariant,
            isBold: true,
          ),
        if (_isVisible('status')) SizedBox(width: _widths['status']!),
      ],
    );
  }

  Widget _buildEmptyState({bool filteredBySearch = false}) {
    if (filteredBySearch) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text(
                'No matching purchase orders',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different search term or clear the search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    // Same animated empty state as the budget grid views (copy mirrors
    // _emptyStateContentForMode in BudgetViewScreen).
    return ZeroItemsActionEmptyState(
      icon: Icons.shopping_cart_outlined,
      title: 'No purchase orders yet',
      subtitle:
          'Materials, subcontracts and rentals issued to vendors will appear here.',
      ctaLabel: 'Create Purchase Order',
      onTap: widget.onCreatePurchaseOrder,
    );
  }

  Future<void> _openDetail(_PoRow row) async {
    if (row.workOrder != null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (_, controller) => WorkOrderDetailSheet(
            workOrder: row.workOrder!,
            scrollController: controller,
            currency: _currency,
          ),
        ),
      );
    } else if (row.subcontract != null) {
      final vendor = _vendorsById[row.subcontract!.vendorId];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (_, controller) => SubcontractDetailSheet(
            subcontract: row.subcontract!,
            vendor: vendor,
            scrollController: controller,
            currency: _currency,
          ),
        ),
      );
    }
  }
}
