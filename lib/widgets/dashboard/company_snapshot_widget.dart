import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/asset.dart';
import '../../models/customer.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/inventory/inventory_item.dart';
import '../../models/inventory/inventory_supplier.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/vehicle.dart';
import '../../models/vendor.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Company-wide snapshot. Pulls one frame of data from every module and
/// renders an interactive dashboard with KPIs, charts and drill-through
/// navigation to each source module.
class CompanySnapshotWidget extends StatefulWidget {
  final String workspaceId;
  const CompanySnapshotWidget({super.key, required this.workspaceId});

  @override
  State<CompanySnapshotWidget> createState() => _CompanySnapshotWidgetState();
}

class _CompanySnapshotWidgetState extends State<CompanySnapshotWidget> {
  late Future<_Snapshot> _future;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CompanySnapshotWidget old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) _future = _load();
  }

  Future<_Snapshot> _load() async {
    final wsId = widget.workspaceId;

    Future<T> safe<T>(Future<T> Function() f, T fallback) async {
      try { return await f().timeout(const Duration(seconds: 12)); }
      catch (_) { return fallback; }
    }
    Future<List<T>> lst<T>(Stream<List<T>> Function() s) =>
      safe(() => s().first, <T>[]);

    final r = await Future.wait<dynamic>([
      lst<Project>(() =>
        ServiceLocator.projectService.getProjects(wsId)
          as Stream<List<Project>>),
      lst<Task>(() =>
        ServiceLocator.taskService.getAllWorkspaceTasks(wsId)
          as Stream<List<Task>>),
      lst<Customer>(() =>
        ServiceLocator.customerService.getCustomers(wsId)
          as Stream<List<Customer>>),
      lst<Vendor>(() =>
        ServiceLocator.vendorService.getVendors(wsId)
          as Stream<List<Vendor>>),
      lst<dynamic>(() =>
        ServiceLocator.workspaceMemberService.getWorkspaceMembers(wsId)
          as Stream<List<dynamic>>),
      // Single financial source: workspace-wide `generated_documents`. We
      // split by document type below so AR / AP / Expenses all read from the
      // same record set the Financials view lists.
      lst<GeneratedDocument>(() =>
        ServiceLocator.documentService.getDocuments(wsId)
          as Stream<List<GeneratedDocument>>),
      lst<InventoryItem>(() =>
        ServiceLocator.inventoryItemServiceFor(wsId).watchItems()),
      lst<InventorySupplier>(() =>
        ServiceLocator.inventorySupplierServiceFor(wsId).watchSuppliers()),
      lst<Asset>(() =>
        ServiceLocator.assetServiceFor(wsId).getAssets()),
      lst<Vehicle>(() =>
        ServiceLocator.vehicleServiceFor(wsId).getVehicles()),
    ]);

    _loadedAt = DateTime.now();
    final allDocs = r[5] as List<GeneratedDocument>;
    return _Snapshot(
      projects:        r[0]  as List<Project>,
      tasks:           r[1]  as List<Task>,
      customers:       r[2]  as List<Customer>,
      vendors:         r[3]  as List<Vendor>,
      members:         r[4]  as List<dynamic>,
      invoiceDocs: allDocs
          .where((d) => _Snapshot.invoiceTypes.contains(d.documentType))
          .toList(),
      billDocs: allDocs
          .where((d) => _Snapshot.billTypes.contains(d.documentType))
          .toList(),
      expenseDocs:
          allDocs.where((d) => d.documentType == DocumentType.expense).toList(),
      inventoryItems:  r[6] as List<InventoryItem>,
      suppliers:       r[7] as List<InventorySupplier>,
      // Purchase orders are documents-first: derive them from the documents
      // already streamed above rather than a separate inventory PO source.
      purchaseOrders: allDocs
          .where((d) => d.documentType == DocumentType.purchaseOrder)
          .toList(),
      assets:          r[8] as List<Asset>,
      vehicles:        r[9] as List<Vehicle>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Snapshot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || snap.data == null) {
          return _ErrorState(onRetry: _refresh);
        }
        return _SnapshotView(
          data: snap.data!,
          loadedAt: _loadedAt,
          onRefresh: _refresh,
        );
      },
    );
  }
}

// ============================================================================
// Data
// ============================================================================

class _Snapshot {
  /// Customer-side invoice document types — these drive A/R + invoiced totals.
  static const invoiceTypes = <DocumentType>{
    DocumentType.invoice,
    DocumentType.progressInvoice,
    DocumentType.aiaPayApp,
    DocumentType.deposit,
    DocumentType.credit,
    DocumentType.refund,
  };

  /// Credits/refunds reduce what the customer owes — fold with this instead
  /// of raw totalAmount so A/R and invoiced totals net credit notes rather
  /// than inflating by them.
  static double signedAmount(GeneratedDocument d) =>
      (d.documentType == DocumentType.credit ||
              d.documentType == DocumentType.refund)
          ? -d.totalAmount
          : d.totalAmount;

  /// Vendor-side bill document types — these drive A/P + open-bill counts.
  /// Expenses live on their own bucket since they're already-paid receipts
  /// rather than a bill we owe (see [expenseDocs]).
  static const billTypes = <DocumentType>{
    DocumentType.bill,
    DocumentType.vendorCredit,
    DocumentType.vendorRefund,
  };

  final List<Project> projects;
  final List<Task> tasks;
  final List<Customer> customers;
  final List<Vendor> vendors;
  final List<dynamic> members;

  /// Invoice / bill / expense documents from `generated_documents`. Same
  /// records the project Financials view reads from, so the home snapshot
  /// can't disagree with the rest of the app about what's been billed.
  final List<GeneratedDocument> invoiceDocs;
  final List<GeneratedDocument> billDocs;
  final List<GeneratedDocument> expenseDocs;

  final List<InventoryItem> inventoryItems;
  final List<InventorySupplier> suppliers;
  final List<GeneratedDocument> purchaseOrders;
  final List<Asset> assets;
  final List<Vehicle> vehicles;

  _Snapshot({
    required this.projects, required this.tasks, required this.customers,
    required this.vendors, required this.members,
    required this.invoiceDocs, required this.billDocs, required this.expenseDocs,
    required this.inventoryItems, required this.suppliers,
    required this.purchaseOrders, required this.assets, required this.vehicles,
  });

  /// A document is "billed out" when its status indicates it's been sent
  /// to / accepted by the counterparty. Matches
  /// `SupabaseBudgetService.calculateInvoicedAmount` — keep the two in sync
  /// so the home snapshot and the per-project rollups count the same money
  /// the same way.
  static bool isBilled(GeneratedDocument d) {
    switch (d.status) {
      case DocumentStatus.sent:
      case DocumentStatus.viewed:
      case DocumentStatus.signed:
      case DocumentStatus.approved:
      case DocumentStatus.applied:
      case DocumentStatus.pending:
      case DocumentStatus.responded:
      case DocumentStatus.changesRequested:
        return true;
      case DocumentStatus.denied:
      case DocumentStatus.withdrawn:
      case DocumentStatus.notSelected:
      case DocumentStatus.draft:
        return false;
    }
  }

  /// A document is "paid / closed" once its `paid_date` is stamped. The
  /// budget service uses the same predicate.
  static bool isPaid(GeneratedDocument d) => d.paidDate != null;
}

// ============================================================================
// View
// ============================================================================


// ============================================================================
// View — Databox-style executive dashboard
// ============================================================================

const _kRadius     = 12.0;
const _kPad        = 22.0;
const _kBorder     = Color(0xFFE5E7EB);
const _kCardBg     = Colors.white;
const _kPageBg     = Color(0xFFF7F8FA);
const _kLabel      = Color(0xFF6B7280);
const _kSubLabel   = Color(0xFF9CA3AF);
const _kAxis       = Color(0xFF9CA3AF);
const _kGrid       = Color(0xFFEEF0F3);
const _kInk        = Color(0xFF111827);
const _kInkSoft    = Color(0xFF374151);
const _kBlue       = Color(0xFF2F80ED);
const _kBlueSoft   = Color(0xFF6FA8F5);
const _kTeal       = Color(0xFF14B8A6);
const _kPositive   = AppColors.success;
const _kWarn       = AppColors.warning;
const _kDanger     = AppColors.error;
const _kPurple     = Color(0xFF8B5CF6);
const _kSlate      = Color(0xFF94A3B8);

class _SnapshotView extends StatelessWidget {
  final _Snapshot data;
  final DateTime? loadedAt;
  final VoidCallback onRefresh;

  const _SnapshotView({
    required this.data,
    required this.loadedAt,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final compact = NumberFormat.compactCurrency(symbol: r'$', decimalDigits: 1);
    final now = DateTime.now();

    // ── Aggregations ───────────────────────────────────────────────────
    final projects = data.projects;
    int pBy(ProjectStatus s) => projects.where((p) => p.status == s).length;
    final pipelineValue = projects
        .where((p) =>
            p.status != ProjectStatus.complete &&
            p.status != ProjectStatus.lost &&
            p.status != ProjectStatus.canceled)
        .fold<double>(0, (a, p) => a + (p.estimatedBudget ?? 0));
    final wonValue = projects
        .where((p) =>
            p.status == ProjectStatus.awarded ||
            p.status == ProjectStatus.active ||
            p.status == ProjectStatus.complete)
        .fold<double>(0, (a, p) => a + (p.estimatedBudget ?? 0));
    final lostCount = pBy(ProjectStatus.lost) + pBy(ProjectStatus.canceled);
    final wonCount = pBy(ProjectStatus.awarded) +
        pBy(ProjectStatus.active) +
        pBy(ProjectStatus.complete);
    final winRate = (wonCount + lostCount) == 0
        ? 0
        : ((wonCount / (wonCount + lostCount)) * 100).round();

    final tasks = data.tasks;
    final tDone = tasks.where((t) => t.isComplete).length;
    final tProg = tasks.where((t) => t.status == 'working_on_it').length;
    final tStuck = tasks.where((t) => t.status == 'stuck').length;
    // Route through the model so "overdue" means the due DAY has passed
    // (date-only tasks aren't overdue all day on their due date).
    final tOver = tasks.where((t) => t.isOverdue()).length;
    final compPct = tasks.isEmpty ? 0 : ((tDone / tasks.length) * 100).round();

    final invoices = data.invoiceDocs;
    final bills = data.billDocs;

    // A/R / A/P use the same `paid_date IS NULL` convention as
    // SupabaseBudgetService. Documents don't track a partial-payment
    // balance here, so a partially-paid invoice still shows its full
    // total until `paid_date` is stamped.
    final outAR = invoices
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .fold<double>(0, (a, d) => a + _Snapshot.signedAmount(d));
    final ovdAR = invoices
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .where((d) => d.dueDate != null && d.dueDate!.isBefore(now))
        .fold<double>(0, (a, d) => a + _Snapshot.signedAmount(d));
    final outAP = bills
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .fold<double>(0, (a, d) => a + d.totalAmount);

    // 6-month cash-flow series, sourced from documents' `paid_date`:
    // "money in / out" is approximated by the moment an invoice / bill /
    // expense document gets paid.
    final months = <DateTime>[
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];
    double sumPaidIn(
      Iterable<GeneratedDocument> docs,
      DateTime s,
      DateTime e,
    ) {
      return docs
          .where((d) =>
              d.paidDate != null &&
              !d.paidDate!.isBefore(s) &&
              d.paidDate!.isBefore(e))
          .fold<double>(0, (a, d) => a + d.totalAmount);
    }

    final cashSeries = <_MonthBar>[];
    for (var i = 0; i < months.length; i++) {
      final s = months[i];
      final e = i == months.length - 1
          ? DateTime(now.year, now.month + 1, 1)
          : months[i + 1];
      cashSeries.add(_MonthBar(
        DateFormat('MMM').format(s),
        // Money in: invoice docs whose customer paid in this month.
        sumPaidIn(invoices, s, e),
        // Money out: vendor bills + expense receipts paid in this month.
        sumPaidIn(bills, s, e) + sumPaidIn(data.expenseDocs, s, e),
      ));
    }

    final items = data.inventoryItems;
    final invValue =
        items.fold<double>(0, (a, i) => a + (i.onHandQty * i.unitCost));
    final lowStock = items.where((i) => i.isBelowReorderPoint).length;

    final assets = data.assets;
    int aBy(String s) => assets.where((a) => a.status == s).length;

    // ── Extras for module sections ────────────────────────────────────
    final activeBacklog = projects
        .where((p) => p.status == ProjectStatus.active)
        .fold<double>(0, (a, p) => a + (p.estimatedBudget ?? 0));

    final tToday = tasks.where((t) => t.isDueToday()).length;
    final tHigh = tasks.where((t) => t.priority == 'high').length;
    final tMed = tasks.where((t) => t.priority == 'medium').length;
    final tLow = tasks.where((t) => t.priority == 'low').length;

    // "Total invoiced" = every customer invoice that's been billed out,
    // regardless of paid state — matches what shows up in the project
    // financials' invoiced rollup.
    final invoiced = invoices
        .where(_Snapshot.isBilled)
        .fold<double>(0, (a, d) => a + _Snapshot.signedAmount(d));
    final ovdAP = bills
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .where((d) => d.dueDate != null && d.dueDate!.isBefore(now))
        .fold<double>(0, (a, d) => a + d.totalAmount);
    final expensesTotal =
        data.expenseDocs.fold<double>(0, (a, d) => a + d.totalAmount);
    final openInvoices = invoices
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .length;
    final openBills = bills
        .where(_Snapshot.isBilled)
        .where((d) => !_Snapshot.isPaid(d))
        .length;

    final openPOs = data.purchaseOrders
        .where((po) =>
            po.status != DocumentStatus.withdrawn &&
            po.status != DocumentStatus.denied &&
            po.fulfillment != PoFulfillment.received)
        .length;

    final vehicles = data.vehicles;
    int vBy(String s) => vehicles.where((v) => v.status == s).length;

    // Top inventory categories by on-hand value
    final catTotals = <String, double>{};
    for (final it in items) {
      final key = (it.category.isEmpty) ? 'Uncategorized' : it.category;
      catTotals[key] =
          (catTotals[key] ?? 0) + (it.onHandQty * it.unitCost);
    }
    final topCatsSorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCats = topCatsSorted.take(5).toList();

    // ── Render ─────────────────────────────────────────────────────────
    return Container(
      color: _kPageBg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        // 4-column grid below 1100, 12-col above
        final wide = w >= 1100;
        final med = w >= 720;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(loadedAt: loadedAt, onRefresh: onRefresh),
            const SizedBox(height: 20),

            // ───────────────────────────────────────────────────────────
            //   Sales & Pipeline — funnel donut + 6 unique KPIs
            // ───────────────────────────────────────────────────────────
            _ModuleSection(
              icon: Icons.business_center_outlined,
              title: 'Sales & Pipeline',
              subtitle: 'Project funnel, deal value and conversion',
              accent: _kBlue,
              onOpen: () => _go(context, '/projects'),
              wide: wide, med: med,
              chart: _DonutCard(
                label: 'PROJECT FUNNEL',
                slices: [
                  _Slice('Lead', pBy(ProjectStatus.lead), _kSlate),
                  _Slice('Bidding', pBy(ProjectStatus.bidding), _kBlueSoft),
                  _Slice('Proposal', pBy(ProjectStatus.proposalSent), _kPurple),
                  _Slice('Awarded', pBy(ProjectStatus.awarded), _kPositive),
                  _Slice('Active', pBy(ProjectStatus.active), _kBlue),
                  _Slice('On hold', pBy(ProjectStatus.onHold), _kWarn),
                  _Slice('Complete', pBy(ProjectStatus.complete), _kTeal),
                  _Slice('Lost', lostCount, _kDanger),
                ],
                centerValue: '${projects.length}',
                centerLabel: 'projects',
                onTap: () => _go(context, '/projects'),
              ),
              tiles: [
                _StatTile(label: 'WIN RATE', value: '$winRate%',
                  sub: '$wonCount won · $lostCount lost',
                  accent: _kPositive, onTap: () => _go(context, '/projects')),
                _StatTile(label: 'PIPELINE VALUE',
                  value: compact.format(pipelineValue),
                  sub: '${projects.length} projects',
                  accent: _kBlue, onTap: () => _go(context, '/projects')),
                _StatTile(label: 'WON VALUE',
                  value: compact.format(wonValue),
                  sub: '$wonCount deals',
                  accent: _kPositive, onTap: () => _go(context, '/projects')),
                _StatTile(label: 'AVG WON DEAL',
                  value: compact.format(wonCount > 0 ? wonValue / wonCount : 0),
                  sub: '$wonCount won deals',
                  accent: _kPositive,
                  onTap: () => _go(context, '/projects')),
                _StatTile(label: 'ACTIVE BACKLOG',
                  value: compact.format(activeBacklog),
                  sub: '${pBy(ProjectStatus.active)} active',
                  accent: _kBlue, onTap: () => _go(context, '/projects')),
                _StatTile(label: 'CUSTOMERS',
                  value: '${data.customers.length}',
                  accent: _kTeal, onTap: () => _go(context, '/customers')),
              ],
            ),
            const SizedBox(height: 28),

            // ───────────────────────────────────────────────────────────
            //   Operations & Tasks — status donut + 6 unique KPIs
            // ───────────────────────────────────────────────────────────
            _ModuleSection(
              icon: Icons.checklist_outlined,
              title: 'Operations & Tasks',
              subtitle: 'Workload, throughput and what is overdue',
              accent: _kBlue,
              onOpen: () => _go(context, '/tasks'),
              wide: wide, med: med,
              chart: _DonutCard(
                label: 'TASKS BY STATUS',
                slices: [
                  _Slice('Done', tDone, _kPositive),
                  _Slice('In progress', tProg, _kBlue),
                  _Slice('Stuck', tStuck, _kDanger),
                  _Slice('Not started',
                      (tasks.length - tDone - tProg - tStuck)
                          .clamp(0, 1 << 30),
                      _kSlate),
                ],
                centerValue: '$compPct%',
                centerLabel: 'complete',
                onTap: () => _go(context, '/tasks'),
              ),
              tiles: [
                _StatTile(label: 'TOTAL TASKS', value: '${tasks.length}',
                  accent: _kBlue, onTap: () => _go(context, '/tasks')),
                _StatTile(label: 'DUE TODAY', value: '$tToday',
                  accent: tToday > 0 ? _kWarn : _kSlate,
                  onTap: () => _go(context, '/tasks')),
                _StatTile(label: 'OVERDUE', value: '$tOver',
                  accent: tOver > 0 ? _kDanger : _kPositive,
                  onTap: () => _go(context, '/tasks')),
                _StatTile(label: 'HIGH PRIORITY', value: '$tHigh',
                  accent: _kDanger, onTap: () => _go(context, '/tasks')),
                _StatTile(label: 'MEDIUM PRIORITY', value: '$tMed',
                  accent: _kWarn, onTap: () => _go(context, '/tasks')),
                _StatTile(label: 'LOW PRIORITY', value: '$tLow',
                  accent: _kPositive, onTap: () => _go(context, '/tasks')),
              ],
            ),
            const SizedBox(height: 28),

            // ───────────────────────────────────────────────────────────
            //   Finance — cash flow + 6 unique KPIs
            // ───────────────────────────────────────────────────────────
            _ModuleSection(
              icon: Icons.account_balance_outlined,
              title: 'Finance',
              subtitle: 'Cash, AR, AP and what we owe vs what is owed',
              accent: _kPositive,
              onOpen: () => _go(context, '/financials'),
              wide: wide, med: med,
              chart: _CashFlowCard(
                label: 'CASH FLOW · LAST 6 MONTHS',
                series: cashSeries,
                money: compact,
                onTap: () => _go(context, '/financials'),
              ),
              tiles: [
                _StatTile(label: 'A/R OUTSTANDING',
                  value: compact.format(outAR),
                  sub: ovdAR > 0
                      ? '${compact.format(ovdAR)} overdue' : 'all current',
                  accent: ovdAR > 0 ? _kDanger : _kPositive,
                  onTap: () => _go(context, '/financials')),
                _StatTile(label: 'A/P OUTSTANDING',
                  value: compact.format(outAP),
                  sub: ovdAP > 0
                      ? '${compact.format(ovdAP)} overdue' : 'all current',
                  accent: ovdAP > 0 ? _kDanger : _kWarn,
                  onTap: () => _go(context, '/financials')),
                _StatTile(label: 'TOTAL INVOICED',
                  value: compact.format(invoiced),
                  sub: '$openInvoices open',
                  accent: _kBlue,
                  onTap: () => _go(context, '/financials')),
                _StatTile(label: 'EXPENSES LOGGED',
                  value: compact.format(expensesTotal),
                  accent: _kPurple,
                  onTap: () => _go(context, '/financials')),
                _StatTile(label: 'OPEN BILLS', value: '$openBills',
                  accent: _kBlue,
                  onTap: () => _go(context, '/financials')),
                _StatTile(label: 'OPEN INVOICES', value: '$openInvoices',
                  accent: _kTeal,
                  onTap: () => _go(context, '/financials')),
              ],
            ),
            const SizedBox(height: 28),

            // ───────────────────────────────────────────────────────────
            //   Inventory & Procurement — top categories + 5 unique KPIs
            // ───────────────────────────────────────────────────────────
            _ModuleSection(
              icon: Icons.inventory_2_outlined,
              title: 'Inventory & Procurement',
              subtitle: 'Stock value, reorder alerts and POs',
              accent: _kBlue,
              onOpen: () => _go(context, '/inventory'),
              wide: wide, med: med,
              chart: _HBarCard(
                label: 'TOP CATEGORIES BY VALUE',
                items: topCats.isEmpty
                    ? [_HBar('No items yet', 0, _kSlate)]
                    : [
                        for (var i = 0; i < topCats.length; i++)
                          _HBar(
                            topCats[i].key,
                            topCats[i].value.round(),
                            [_kBlue, _kTeal, _kPurple, _kWarn, _kSlate][i % 5],
                          ),
                      ],
                onTap: () => _go(context, '/inventory'),
              ),
              tiles: [
                _StatTile(label: 'INVENTORY ITEMS', value: '${items.length}',
                  accent: _kBlue, onTap: () => _go(context, '/inventory')),
                _StatTile(label: 'INVENTORY VALUE',
                  value: compact.format(invValue),
                  accent: _kTeal, onTap: () => _go(context, '/inventory')),
                _StatTile(label: 'BELOW REORDER', value: '$lowStock',
                  accent: lowStock > 0 ? _kDanger : _kPositive,
                  onTap: () => _go(context, '/inventory')),
                _StatTile(label: 'OPEN POs', value: '$openPOs',
                  accent: openPOs > 0 ? _kWarn : _kSlate,
                  onTap: () => _go(context, '/inventory')),
                _StatTile(label: 'SUPPLIERS',
                  value: '${data.suppliers.length}',
                  accent: _kSlate, onTap: () => _go(context, '/inventory')),
                _StatTile(label: 'VENDORS',
                  value: '${data.vendors.length}',
                  accent: _kSlate, onTap: () => _go(context, '/vendors')),
              ],
            ),
            const SizedBox(height: 28),

            // ───────────────────────────────────────────────────────────
            //   Assets & Fleet — availability donut + 6 unique KPIs
            // ───────────────────────────────────────────────────────────
            _ModuleSection(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Equipment & Fleet',
              subtitle: 'Equipment availability and vehicles',
              accent: _kPurple,
              onOpen: () => _go(context, '/equipment'),
              wide: wide, med: med,
              chart: _DonutCard(
                label: 'ASSET AVAILABILITY',
                slices: [
                  _Slice('Available', aBy('available'), _kPositive),
                  _Slice('Assigned', aBy('assigned'), _kBlue),
                  _Slice('Maintenance', aBy('maintenance'), _kWarn),
                  _Slice('Retired', aBy('retired'), _kSlate),
                ],
                centerValue: '${assets.length}',
                centerLabel: 'assets',
                onTap: () => _go(context, '/equipment'),
              ),
              tiles: [
                _StatTile(label: 'ASSET UTILIZATION',
                  value: assets.isEmpty
                      ? '—'
                      : '${((aBy('assigned') / assets.length) * 100).round()}%',
                  sub: '${aBy('assigned')} of ${assets.length} in use',
                  accent: _kBlue, onTap: () => _go(context, '/equipment')),
                _StatTile(label: 'FLEET ACTIVE',
                  value: vehicles.isEmpty
                      ? '—'
                      : '${((vBy('active') / vehicles.length) * 100).round()}%',
                  sub: '${vBy('active')} of ${vehicles.length} on the road',
                  accent: _kPositive,
                  onTap: () => _go(context, '/vehicles')),
                _StatTile(label: 'VEHICLES', value: '${vehicles.length}',
                  accent: _kPurple, onTap: () => _go(context, '/vehicles')),
                _StatTile(label: 'IN SERVICE', value: '${vBy('active')}',
                  accent: _kPositive, onTap: () => _go(context, '/vehicles')),
                _StatTile(label: 'IN MAINTENANCE',
                  value: '${vBy('maintenance')}',
                  accent: _kWarn, onTap: () => _go(context, '/vehicles')),
                _StatTile(label: 'OUT OF SERVICE',
                  value: '${vBy('out_of_service')}',
                  accent: _kDanger, onTap: () => _go(context, '/vehicles')),
              ],
            ),
          ],
        );
      }),
    );
  }

  static void _go(BuildContext c, String r) => c.go(r);
}

// ----------------------------------------------------------------------------
// Small reusable layout helpers
// ----------------------------------------------------------------------------

class _MonthBar {
  final String label;
  final double received;
  final double paid;
  _MonthBar(this.label, this.received, this.paid);
}

class _Slice {
  final String label;
  final num value;
  final Color color;
  _Slice(this.label, this.value, this.color);
}

class _HBar {
  final String label;
  final num value;
  final Color color;
  _HBar(this.label, this.value, this.color);
}

class _Header extends StatelessWidget {
  final DateTime? loadedAt;
  final VoidCallback onRefresh;
  const _Header({required this.loadedAt, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final t = loadedAt == null
        ? '—'
        : DateFormat('MMM d, yyyy · h:mm a').format(loadedAt!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Company snapshot',
            style: TextStyle(
                color: _kInk,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: const Text('Live',
              style: TextStyle(
                  color: _kBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
        ),
        const Spacer(),
        Text('Updated $t',
            style: const TextStyle(color: _kLabel, fontSize: 12)),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18, color: _kLabel),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: const BorderSide(color: _kBorder),
            ),
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Simple responsive grid that lays out children equally in [cols] columns.
class _Grid extends StatelessWidget {
  final int cols;
  final double gap;
  final List<Widget> children;
  const _Grid({required this.cols, required this.gap, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final row = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0) row.add(SizedBox(width: gap));
        if (i + j < children.length) {
          row.add(Expanded(child: children[i + j]));
        } else {
          row.add(const Expanded(child: SizedBox.shrink()));
        }
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: row),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

// ----------------------------------------------------------------------------
// Card primitives
// ----------------------------------------------------------------------------

class _Card extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const _Card({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(_kPad),
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
                color: _hover && widget.onTap != null
                    ? _kBlueSoft
                    : _kBorder,
                width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                    alpha: _hover && widget.onTap != null ? 0.06 : 0.025),
                blurRadius: _hover ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _CardHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _kLabel,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Stat tile (label + big number + sub)
// ----------------------------------------------------------------------------

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color accent;
  final VoidCallback? onTap;
  const _StatTile({
    required this.label,
    required this.value,
    this.sub,
    this.accent = _kBlue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kLabel,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                )),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _kSubLabel,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Donut card
// ----------------------------------------------------------------------------

class _DonutCard extends StatelessWidget {
  final String label;
  final List<_Slice> slices;
  final String centerValue;
  final String centerLabel;
  final VoidCallback? onTap;
  const _DonutCard({
    required this.label,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, s) => a + s.value.toDouble());
    final visible = slices.where((s) => s.value > 0).toList();
    return _Card(
      onTap: onTap,
      child: SizedBox(
        height: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(label: label),
            const SizedBox(height: 8),
            Expanded(
              child: total == 0
                  ? const Center(
                      child: Text('No data yet',
                          style:
                              TextStyle(color: _kSubLabel, fontSize: 12)))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PieChart(PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 38,
                                startDegreeOffset: -90,
                                sections: [
                                  for (final s in visible)
                                    PieChartSectionData(
                                      value: s.value.toDouble(),
                                      color: s.color,
                                      radius: 22,
                                      showTitle: false,
                                    ),
                                ],
                              )),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(centerValue,
                                      style: const TextStyle(
                                          color: _kInk,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3)),
                                  Text(centerLabel,
                                      style: const TextStyle(
                                          color: _kSubLabel,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500)),

                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final s in slices)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: s.color,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(s.label,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: _kInkSoft,
                                                  fontSize: 11.5,
                                                  fontWeight:
                                                      FontWeight.w500)),
                                        ),
                                        Text('${s.value}',
                                            style: const TextStyle(
                                                color: _kInk,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700)),
                                      ],
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
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Cash flow card (grouped vertical bars over months)
// ----------------------------------------------------------------------------

class _CashFlowCard extends StatelessWidget {
  final String label;
  final List<_MonthBar> series;
  final NumberFormat money;
  final VoidCallback? onTap;
  const _CashFlowCard({
    required this.label,
    required this.series,
    required this.money,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = series.fold<double>(
        0, (a, s) => math.max(a, math.max(s.received, s.paid)));
    return _Card(
      onTap: onTap,
      child: SizedBox(
        height: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              label: label,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _LegendDot(color: _kPositive, text: 'Received'),
                const SizedBox(width: 10),
                _LegendDot(color: _kWarn, text: 'Paid'),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: maxV == 0
                  ? const Center(
                      child: Text('No payments yet',
                          style:
                              TextStyle(color: _kSubLabel, fontSize: 12)))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _niceMax(maxV),
                        barTouchData: BarTouchData(enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => _kInk,
                            tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            getTooltipItem: (group, gIdx, rod, rIdx) {
                              final m = series[group.x.toInt()];
                              final isReceived = rIdx == 0;
                              return BarTooltipItem(
                                '${m.label}\n${isReceived ? "Received" : "Paid"}: ${money.format(rod.toY)}',
                                const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500),
                              );
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _niceMax(maxV) / 4,
                          getDrawingHorizontalLine: (_) => const FlLine(
                              color: _kGrid, strokeWidth: 1, dashArray: [3, 3]),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              interval: _niceMax(maxV) / 4,
                              getTitlesWidget: (v, _) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(money.format(v),
                                    style: const TextStyle(
                                        color: _kAxis, fontSize: 10)),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= series.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(series[i].label,
                                      style: const TextStyle(
                                          color: _kAxis, fontSize: 10.5)),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < series.length; i++)
                            BarChartGroupData(
                              x: i,
                              barsSpace: 4,
                              barRods: [
                                BarChartRodData(
                                  toY: series[i].received,
                                  color: _kPositive,
                                  width: 8,
                                  borderRadius:
                                      BorderRadius.circular(3),
                                ),
                                BarChartRodData(
                                  toY: series[i].paid,
                                  color: _kWarn,
                                  width: 8,
                                  borderRadius:
                                      BorderRadius.circular(3),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: _kLabel, fontSize: 11, fontWeight: FontWeight.w500)),
      ]);
}

double _niceMax(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, v.toString().split('.').first.length - 1).toDouble();
  return ((v / mag).ceilToDouble()) * mag;
}

// ----------------------------------------------------------------------------
// Area / line card
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// Horizontal-bar card (e.g. invoice statuses)
// ----------------------------------------------------------------------------

class _HBarCard extends StatelessWidget {
  final String label;
  final List<_HBar> items;
  final VoidCallback? onTap;
  const _HBarCard({required this.label, required this.items, this.onTap});

  @override
  Widget build(BuildContext context) {
    final maxV = items.fold<double>(0, (a, b) => math.max(a, b.value.toDouble()));
    final total = items.fold<double>(0, (a, b) => a + b.value.toDouble());
    return _Card(
      onTap: onTap,
      child: SizedBox(
        height: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(label: label),
            const SizedBox(height: 6),
            Text('${total.toInt()}',
                style: const TextStyle(
                    color: _kInk,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            const SizedBox(height: 8),
            Expanded(
              child: maxV == 0
                  ? const Center(
                      child: Text('No data yet',
                          style:
                              TextStyle(color: _kSubLabel, fontSize: 12)))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final b in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(b.label,
                                        style: const TextStyle(
                                            color: _kInkSoft,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                  Text('${b.value}',
                                      style: const TextStyle(
                                          color: _kInk,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  child: Stack(children: [
                                    Container(
                                      height: 8,
                                      color: const Color(0xFFF1F3F6),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: maxV == 0
                                          ? 0
                                          : (b.value.toDouble() / maxV)
                                              .clamp(0.04, 1.0),
                                      child: Container(
                                        height: 8,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              b.color.withValues(alpha: 0.85),
                                              b.color,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ]),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Bottom chip bar (small footer summary)
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Module section: header (icon + title + subtitle + Open ›) + KPI tile grid
// ----------------------------------------------------------------------------

class _ModuleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onOpen;
  final bool wide;
  final bool med;
  final Widget? chart;
  final List<Widget> tiles;

  const _ModuleSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onOpen,
    required this.wide,
    required this.med,
    this.chart,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    final tileGrid = _Grid(
      cols: wide ? 3 : (med ? 3 : 2),
      gap: 12,
      children: tiles,
    );

    Widget body;
    if (chart == null) {
      body = _Grid(cols: wide ? 6 : (med ? 3 : 2), gap: 12, children: tiles);
    } else if (wide) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SizedBox(height: 240, child: chart!),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 7, child: tileGrid),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 240, child: chart!),
          const SizedBox(height: 12),
          tileGrid,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModuleSectionHeader(
          icon: icon,
          title: title,
          subtitle: subtitle,
          accent: accent,
          onOpen: onOpen,
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

class _ModuleSectionHeader extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onOpen;

  const _ModuleSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onOpen,
  });

  @override
  State<_ModuleSectionHeader> createState() => _ModuleSectionHeaderState();
}

class _ModuleSectionHeaderState extends State<_ModuleSectionHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(widget.icon, size: 20, color: widget.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            color: _kInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 1),
                    Text(widget.subtitle,
                        style: const TextStyle(
                            color: _kSubLabel,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
                decoration: BoxDecoration(
                  color: _hover
                      ? widget.accent.withValues(alpha: 0.10)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: _hover ? widget.accent : _kBorder, width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Open',
                      style: TextStyle(
                          color: _hover ? widget.accent : _kInkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward,
                      size: 14, color: _hover ? widget.accent : _kInkSoft),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Error state
// ----------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 32, color: _kDanger),
          const SizedBox(height: 8),
          const Text("Couldn't load the snapshot",
              style: TextStyle(
                  color: _kInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
