/// Internal board for selections & allowances on a project.
///
/// Renders 5 status columns (Pending, Awaiting Client, Approved, Declined,
/// Cancelled). Each card shows the selection name, allowance, and the
/// currently-selected option/amount. Tapping a card opens an editor sheet
/// to manage options, change status, or pick the winning option internally.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_header.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/budget_item.dart';
import '../../../models/catalog_item.dart';
import '../../../models/project.dart';
import '../../../models/selection.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/user_facing_error.dart';

/// Status icon (not color-only) so the board is legible to colourblind users.
IconData selectionStatusIcon(SelectionStatus status) {
  switch (status) {
    case SelectionStatus.approved:
      return Icons.check_circle;
    case SelectionStatus.declined:
      return Icons.cancel;
    case SelectionStatus.awaitingClient:
      return Icons.schedule;
    case SelectionStatus.cancelled:
      return Icons.block;
    case SelectionStatus.pending:
      return Icons.more_horiz;
  }
}

class ProjectSelectionsTab extends StatefulWidget {
  final Project project;
  const ProjectSelectionsTab({super.key, required this.project});

  @override
  State<ProjectSelectionsTab> createState() => _ProjectSelectionsTabState();
}

class _ProjectSelectionsTabState extends State<ProjectSelectionsTab> {
  late final Stream<List<Selection>> _stream =
      ServiceLocator.selectionService.watchByProject(widget.project.id);

  final _currency =
      NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.MMMd();

  bool _groupByArea = false; // false = status kanban, true = area-grouped
  Map<String, int> _messageCounts = const {};

  @override
  void initState() {
    super.initState();
    _loadMessageCounts();
  }

  Future<void> _loadMessageCounts() async {
    try {
      final counts = await ServiceLocator.selectionService
          .commentCountsByProject(widget.project.id);
      if (mounted) setState(() => _messageCounts = counts);
    } catch (_) {/* badges are best-effort */}
  }

  static const _columns = <SelectionStatus>[
    SelectionStatus.pending,
    SelectionStatus.awaitingClient,
    SelectionStatus.approved,
    SelectionStatus.declined,
    SelectionStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSelection,
        icon: const Icon(Icons.add),
        label: const Text('New selection'),
      ),
      body: StreamBuilder<List<Selection>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(UserFacingError.uiMessage(snap.error,
                  action: 'load selections')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final selections = snap.data!;
          final summary =
              ServiceLocator.selectionService.summarise(selections);

          return Column(
            children: [
              _SummaryStrip(summary: summary, currency: _currency),
              _BoardToolbar(
                groupByArea: _groupByArea,
                onToggleGroup: (v) => setState(() => _groupByArea = v),
                onSummary: () => _openSummary(selections),
                onSend: selections.any((s) =>
                        s.status == SelectionStatus.pending &&
                        s.options.isNotEmpty)
                    ? () => _openBulkSend(selections)
                    : null,
                onImport: () => _importFromBudget(selections),
                onTemplates: () => _openTemplates(selections),
              ),
              const Divider(height: 1),
              Expanded(child: _buildBoard(selections)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<Selection> all) {
    if (_groupByArea) return _buildAreaBoard(all);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in _columns)
            _Column(
              status: status,
              items: all.where((s) => s.status == status).toList(),
              currency: _currency,
              dateFmt: _dateFmt,
              messageCounts: _messageCounts,
              onTap: _openEditor,
            ),
        ],
      ),
    );
  }

  /// Area-grouped view (JobTread default): selections grouped by Area, sorted
  /// with un-areaed items under "General".
  Widget _buildAreaBoard(List<Selection> all) {
    final byArea = <String, List<Selection>>{};
    for (final s in all) {
      final area = (s.location ?? '').trim().isEmpty
          ? 'General'
          : s.location!.trim();
      byArea.putIfAbsent(area, () => []).add(s);
    }
    final areas = byArea.keys.toList()
      ..sort((a, b) => a == 'General'
          ? -1
          : b == 'General'
              ? 1
              : a.compareTo(b));
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final area in areas) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(area,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          for (final s in byArea[area]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Card(
                selection: s,
                currency: _currency,
                dateFmt: _dateFmt,
                messageCount: _messageCounts[s.id] ?? 0,
                onTap: () => _openEditor(s),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _openSummary(List<Selection> selections) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SelectionsSummaryDialog(
        projectId: widget.project.id,
        selections: selections,
        currency: _currency,
      ),
    );
  }

  Future<void> _openBulkSend(List<Selection> selections) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SendSelectionsDialog(
        selections: selections
            .where((s) =>
                s.status == SelectionStatus.pending && s.options.isNotEmpty)
            .toList(),
        currency: _currency,
      ),
    );
  }

  Future<void> _createSelection() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final result = await showFormPopup<_CreateSelectionResult>(
      context,
      icon: Icons.checklist_rtl,
      title: 'Create New Selection',
      width: 480,
      fitContent: false,
      builder: (ctx, scrollController) => _CreateSelectionContent(
        projectId: widget.project.id,
        workspaceId: workspaceId,
        scrollController: scrollController,
      ),
    );
    if (result == null) return;
    final svc = ServiceLocator.selectionService;
    try {
      final selection = await svc.create(
        workspaceId: workspaceId,
        projectId: widget.project.id,
        name: result.name,
        category: result.category,
        location: result.location,
        description: result.description,
        allowanceAmount: result.allowance,
        dueDate: result.dueDate,
        budgetItemId: result.budgetItemId,
        excludeFromBudget: result.excludeFromBudget,
        showAmountDifferences: result.showAmountDifferences,
        allowMultipleSelections: result.allowMultipleSelections,
      );
      // Persist any options built inline so the selection lands ready-to-use.
      for (var i = 0; i < result.options.length; i++) {
        final o = result.options[i];
        await svc.addOption(
          selectionId: selection.id,
          workspaceId: workspaceId,
          name: o.name,
          description: o.description,
          vendor: o.vendor,
          sku: o.sku,
          unitCost: o.unitCost,
          quantity: o.quantity,
          imageUrls: o.imageUrls,
          sortOrder: i,
        );
        if (o.saveToCatalog) {
          try {
            await ServiceLocator.catalogService.createCatalogItem(CatalogItem(
              id: '',
              workspaceId: workspaceId,
              name: o.name,
              description: o.description,
              unitCost: o.unitCost,
              unitPrice: o.unitCost,
              markup: 0,
              margin: 0,
              imageUrl: o.imageUrls.isNotEmpty ? o.imageUrls.first : null,
              sku: o.sku,
              category: result.category,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          } catch (_) {/* catalog save is best-effort */}
        }
      }
      // "Create & send": move straight to the client once options exist.
      if (result.sendToClient && result.options.isNotEmpty) {
        await svc.sendToClient(selection.id);
      }
      if (mounted && result.options.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.sendToClient
                ? 'Selection created and sent to client.'
                : 'Selection created with ${result.options.length} option(s).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(UserFacingError.uiMessage(e,
                  action: 'create selection'))),
        );
      }
    }
  }

  Future<void> _openEditor(Selection s) async {
    // Match the create popup: centered dialog on desktop, bottom sheet on
    // mobile. The editor widget itself adapts its own chrome to suit.
    final isWide = MediaQuery.of(context).size.width >= AppBreakpoints.mobile;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (_) => _SelectionEditorSheet(selection: s, currency: _currency),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _SelectionEditorSheet(selection: s, currency: _currency),
      );
    }
    // Refresh message badges after the user may have read/replied.
    _loadMessageCounts();
  }

  /// Reusable selection-sheet templates: save the current sheet, or apply a
  /// saved one (JobTread "selection sheet templates").
  Future<void> _openTemplates(List<Selection> current) async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final svc = ServiceLocator.selectionService;
    final messenger = ScaffoldMessenger.of(context);

    final action = await showDialog<({String kind, Map<String, dynamic>? tpl})>(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: svc.listTemplates(workspaceId),
        builder: (ctx, snap) {
          final templates = snap.data ?? const [];
          return AlertDialog(
            clipBehavior: Clip.antiAlias,
            titlePadding: EdgeInsets.zero,
            title: FormPopupHeader(
              icon: Icons.bookmark_outline,
              title: 'Selection Templates',
              onClose: () => Navigator.of(ctx).pop(),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.save_outlined),
                    title: const Text('Save current sheet as template'),
                    subtitle: Text('${current.length} selection(s)'),
                    onTap: () =>
                        Navigator.pop(ctx, (kind: 'save', tpl: null)),
                  ),
                  const Divider(),
                  if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: Center(
                          child: SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  else if (templates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('No templates yet.',
                          style: TextStyle(color: AppColors.textTertiary)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in templates)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.dashboard_customize_outlined),
                              title: Text(t['name']?.toString() ?? 'Template'),
                              subtitle: Text(
                                  '${(t['payload'] as List?)?.length ?? 0} selection(s)'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.error),
                                onPressed: () async {
                                  await svc.deleteTemplate(t['id'] as String);
                                  if (ctx.mounted) Navigator.pop(ctx, null);
                                },
                              ),
                              onTap: () =>
                                  Navigator.pop(ctx, (kind: 'apply', tpl: t)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
    if (action == null || !mounted) return;

    if (action.kind == 'save') {
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Template name'),
          content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. Standard Kitchen')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                child: const Text('Save')),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      final payload = [
        for (final s in current)
          {
            'name': s.name,
            'category': s.category,
            'location': s.location,
            'allowance_amount': s.allowanceAmount,
            'description': s.description,
            'options': [
              for (final o in s.options)
                {
                  'name': o.name,
                  'vendor': o.vendor,
                  'sku': o.sku,
                  'unit_cost': o.unitCost,
                  'quantity': o.quantity,
                }
            ],
          }
      ];
      await svc.saveTemplate(
          workspaceId: workspaceId, name: name, payload: payload);
      messenger.showSnackBar(SnackBar(content: Text('Saved template "$name".')));
    } else if (action.kind == 'apply' && action.tpl != null) {
      final payload = (action.tpl!['payload'] as List?) ?? const [];
      var created = 0;
      for (final raw in payload) {
        final e = Map<String, dynamic>.from(raw as Map);
        try {
          final sel = await svc.create(
            workspaceId: workspaceId,
            projectId: widget.project.id,
            name: e['name']?.toString() ?? 'Selection',
            category: e['category']?.toString(),
            location: e['location']?.toString(),
            description: e['description']?.toString(),
            allowanceAmount: (e['allowance_amount'] as num?)?.toDouble() ?? 0,
          );
          for (final oraw in (e['options'] as List? ?? const [])) {
            final o = Map<String, dynamic>.from(oraw as Map);
            await svc.addOption(
              selectionId: sel.id,
              workspaceId: workspaceId,
              name: o['name']?.toString() ?? 'Option',
              vendor: o['vendor']?.toString(),
              sku: o['sku']?.toString(),
              unitCost: (o['unit_cost'] as num?)?.toDouble() ?? 0,
              quantity: (o['quantity'] as num?)?.toDouble() ?? 1,
            );
          }
          created++;
        } catch (_) {/* keep going */}
      }
      messenger.showSnackBar(
          SnackBar(content: Text('Applied template — created $created selection(s).')));
    }
  }

  /// Mass-create selections from the project's allowance budget lines that
  /// don't already have one (JobTread "import from budget group").
  Future<void> _importFromBudget(List<Selection> existing) async {
    final messenger = ScaffoldMessenger.of(context);
    final items = await ServiceLocator.budgetService
        .getBudgetItems(widget.project.id)
        .first;
    final linked =
        existing.map((s) => s.budgetItemId).whereType<String>().toSet();
    final candidates = items
        .where((b) =>
            b.itemType == BudgetItemType.item &&
            b.isAllowance &&
            !linked.contains(b.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;
    if (candidates.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'No unlinked allowance lines. Mark a budget line as an allowance, '
            'or all allowances already have a selection.'),
      ));
      return;
    }

    final chosen = await showDialog<List<BudgetItem>>(
      context: context,
      builder: (_) =>
          _ImportSelectionsDialog(candidates: candidates, currency: _currency),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    var created = 0;
    for (final b in chosen) {
      final amount =
          b.approvedPrice > 0 ? b.approvedPrice : b.unitPrice * b.quantity;
      try {
        await ServiceLocator.selectionService.create(
          workspaceId: workspaceId,
          projectId: widget.project.id,
          name: b.name.replaceAll(RegExp(r'\s*\(allowance\)\s*$', caseSensitive: false), ''),
          allowanceAmount: amount,
          budgetItemId: b.id,
        );
        created++;
      } catch (_) {/* keep going; report total at end */}
    }
    if (mounted) {
      messenger.showSnackBar(SnackBar(
          content: Text('Created $created selection${created == 1 ? '' : 's'} '
              'from allowances.')));
    }
  }
}

// ───────────────────────────────────── Summary strip ─────────────────────────

class _SummaryStrip extends StatelessWidget {
  final SelectionSummary summary;
  final NumberFormat currency;
  const _SummaryStrip({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      color: AppColors.surface,
      child: Row(
        children: [
          _kpi('Total Allowance', currency.format(summary.totalAllowance)),
          const SizedBox(width: 24),
          _kpi('Approved', currency.format(summary.totalSelected),
              color: SelectionStatus.approved.color),
          const SizedBox(width: 24),
          _kpi('Pending', currency.format(summary.pendingAllowance),
              color: SelectionStatus.awaitingClient.color),
          const SizedBox(width: 24),
          _kpi(
            'Variance',
            currency.format(summary.approvedVariance),
            color: summary.approvedVariance > 0
                ? AppColors.error
                : AppColors.success,
          ),
          const Spacer(),
          Text(
            '${summary.countAwaitingClient} awaiting · '
            '${summary.countApproved} approved · '
            '${summary.countDeclined} declined',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}

// ───────────────────────────────────── Column ───────────────────────────────

class _Column extends StatelessWidget {
  final SelectionStatus status;
  final List<Selection> items;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final ValueChanged<Selection> onTap;
  final Map<String, int> messageCounts;

  const _Column({
    required this.status,
    required this.items,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
    this.messageCounts = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            decoration: BoxDecoration(
              color: status.color.withOpacity(0.10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(selectionStatusIcon(status), size: 14, color: status.color),
                const SizedBox(width: 8),
                Text(status.label,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${items.length}',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 600),
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.base),
                    child: Text(
                      'Nothing here yet.',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _Card(
                      selection: items[i],
                      currency: currency,
                      dateFmt: dateFmt,
                      messageCount: messageCounts[items[i].id] ?? 0,
                      onTap: () => onTap(items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Selection selection;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final int messageCount;

  const _Card({
    required this.selection,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
    this.messageCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final variance = selection.variance;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(selection.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (selection.options.any((o) => o.isClientSuggested))
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: 'Client suggested an option',
                      child: Icon(Icons.lightbulb,
                          size: 15, color: AppColors.warning),
                    ),
                  ),
                if (messageCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.forum,
                          size: 13, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text('$messageCount',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ]),
                  ),
              ],
            ),
            if ((selection.category ?? '').isNotEmpty ||
                (selection.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [selection.category, selection.location]
                    .where((v) => v != null && v.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _chip('Allow', currency.format(selection.allowanceAmount)),
                if (selection.status == SelectionStatus.approved) ...[
                  const SizedBox(width: 6),
                  _chip(
                    'Selected',
                    currency.format(selection.selectedAmount),
                    bg: variance > 0
                        ? AppColors.error.withOpacity(0.10)
                        : AppColors.success.withOpacity(0.10),
                    fg: variance > 0 ? AppColors.error : AppColors.success,
                  ),
                ] else if (selection.options.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  // Pre-approval preview: do any offered options exceed the
                  // allowance? Lets the builder catch overage risk before send.
                  Builder(builder: (_) {
                    final costs = selection.options
                        .map((o) => o.totalCost)
                        .toList()
                      ..sort();
                    final lo = costs.first;
                    final hi = costs.last;
                    final couldOver = hi > selection.allowanceAmount &&
                        selection.allowanceAmount > 0;
                    final value = lo == hi
                        ? currency.format(lo)
                        : '${currency.format(lo)}–${currency.format(hi)}';
                    final chip = _chip(
                      'Options',
                      value,
                      bg: couldOver
                          ? AppColors.error.withOpacity(0.08)
                          : null,
                      fg: couldOver ? AppColors.error : null,
                    );
                    if (!couldOver) return chip;
                    return Tooltip(
                      message:
                          'Some options exceed the ${currency.format(selection.allowanceAmount)} allowance — the client will see an overage.',
                      child: chip,
                    );
                  }),
                ],
                const Spacer(),
                if (selection.dueDate != null)
                  Builder(builder: (_) {
                    // Overdue only matters while the client still owes a
                    // decision (pending / awaiting). Decided selections show
                    // the date plainly.
                    final undecided =
                        selection.status == SelectionStatus.pending ||
                            selection.status == SelectionStatus.awaitingClient;
                    final due = DateTime(selection.dueDate!.year,
                        selection.dueDate!.month, selection.dueDate!.day);
                    final today = DateTime.now();
                    final overdue = undecided &&
                        due.isBefore(DateTime(today.year, today.month, today.day));
                    if (!overdue) {
                      return Text('Due ${dateFmt.format(selection.dueDate!)}',
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 11));
                    }
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          size: 12, color: AppColors.error),
                      const SizedBox(width: 2),
                      Text('Overdue ${dateFmt.format(selection.dueDate!)}',
                          style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ]);
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text('$label $value',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg ?? AppColors.textSecondary)),
    );
  }
}

// ───────────────────────────────────── Create dialog ────────────────────────

class _CreateSelectionResult {
  final String name;
  final String? category;
  final String? location; // surfaced as "Area" in the UI
  final String? description;
  final double allowance;
  final DateTime? dueDate;
  final String? budgetItemId;
  final bool excludeFromBudget;
  final bool showAmountDifferences;
  final bool allowMultipleSelections;

  /// Options the user built right in the create flow (single-step create).
  /// Empty in edit mode — existing selections manage options in the editor.
  final List<_OptionDraft> options;

  /// True when the user picked "Create & send": send to the client straight
  /// after creating, so a ready selection is one action, not three.
  final bool sendToClient;
  _CreateSelectionResult({
    required this.name,
    this.category,
    this.location,
    this.description,
    this.allowance = 0,
    this.dueDate,
    this.budgetItemId,
    this.excludeFromBudget = false,
    this.showAmountDifferences = true,
    this.allowMultipleSelections = false,
    this.options = const [],
    this.sendToClient = false,
  });
}

/// JobTread-style selection form: Name, Area, Allowance (linked to a budget
/// line), Description, Due date, and the three behaviour toggles.
class _CreateSelectionContent extends StatefulWidget {
  final String projectId;
  final String workspaceId; // needed to build options (photo uploads) inline
  final Selection? initial; // when set, the dialog edits instead of creates
  final ScrollController? scrollController;
  const _CreateSelectionContent(
      {required this.projectId,
      required this.workspaceId,
      this.initial,
      this.scrollController});
  @override
  State<_CreateSelectionContent> createState() =>
      _CreateSelectionContentState();
}

class _CreateSelectionContentState extends State<_CreateSelectionContent> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _area = TextEditingController();
  final _allowance = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _due;

  String? _allowanceLineId; // id of the budget line linked as the allowance
  bool _excludeFromBudget = false;
  bool _showAmountDifferences = true;
  bool _allowMultiple = false;

  /// Options assembled inline so a new selection can be created complete — no
  /// second trip to the editor sheet just to add choices. Create-mode only.
  final List<_OptionDraft> _options = [];

  bool get _isEdit => widget.initial != null;

  /// True once the selection has actually been submitted — guards the
  /// dispose-time cleanup so submitting doesn't delete the photos we just
  /// handed off in the result.
  bool _created = false;

  Future<void> _addOptionDraft() async {
    final draft = await showFormPopup<_OptionDraft>(
      context,
      icon: Icons.add_circle_outline,
      title: 'Create New Option',
      width: 420,
      fitContent: false,
      builder: (ctx, scrollController) => _OptionContent(
        workspaceId: widget.workspaceId,
        scrollController: scrollController,
      ),
    );
    if (draft != null) setState(() => _options.add(draft));
  }

  /// Best-effort removal of abandoned draft photos from the bucket.
  Future<void> _deleteBlobs(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await Supabase.instance.client.storage
          .from('project-images')
          .remove(paths);
    } catch (_) {/* best-effort cleanup */}
  }

  void _removeOptionAt(int i) {
    // Drop the draft's just-uploaded photos so removing it doesn't orphan blobs.
    _deleteBlobs(_options[i].imagePaths);
    setState(() => _options.removeAt(i));
  }


  /// Amber heads-up when at least one option's total exceeds the allowance, so
  /// the builder sees overage risk before sending — the client will too.
  Widget _buildOverageHint() {
    final allowance = double.tryParse(_allowance.text.trim()) ?? 0;
    if (allowance <= 0 || _options.isEmpty) return const SizedBox.shrink();
    final anyOver = _options.any((o) => o.totalCost > allowance);
    if (!anyOver) return const SizedBox.shrink();
    final money = NumberFormat.simpleCurrency(decimalDigits: 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Some options exceed the ${money.format(allowance)} allowance — '
              'the client will see an overage and a change order is added on '
              'approval.',
              style: const TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  /// Pops the dialog with the assembled form. [send] requests "Create & send".
  void _submit({bool send = false}) {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    _created = true; // hand the draft photos off to the result; don't clean up
    Navigator.of(context).pop(_CreateSelectionResult(
      name: name,
      category: clean(_category),
      location: clean(_area),
      description: clean(_desc),
      allowance: double.tryParse(_allowance.text.trim()) ?? 0,
      dueDate: _due,
      budgetItemId: _excludeFromBudget ? null : _allowanceLineId,
      excludeFromBudget: _excludeFromBudget,
      showAmountDifferences: _showAmountDifferences,
      allowMultipleSelections: _allowMultiple,
      options: List.unmodifiable(_options),
      sendToClient: send,
    ));
  }

  @override
  void initState() {
    super.initState();
    // Keep the per-option over/under-allowance badges live as the allowance is
    // typed (create mode only — edit mode manages options elsewhere).
    if (widget.initial == null) {
      _allowance.addListener(() {
        if (mounted) setState(() {});
      });
    }
    final s = widget.initial;
    if (s != null) {
      _name.text = s.name;
      _category.text = s.category ?? '';
      _area.text = s.location ?? '';
      _allowance.text =
          s.allowanceAmount == 0 ? '' : s.allowanceAmount.toStringAsFixed(0);
      _desc.text = s.description ?? '';
      _due = s.dueDate;
      _allowanceLineId = s.budgetItemId;
      _excludeFromBudget = s.excludeFromBudget;
      _showAmountDifferences = s.showAmountDifferences;
      _allowMultiple = s.allowMultipleSelections;
    }
  }

  @override
  void dispose() {
    // Dismissed without creating: drop every draft's uploaded photos so a
    // cancelled create never leaves orphaned blobs. (Submitting sets
    // [_created], handing the photos off to the result instead.)
    if (!_created && !_isEdit) {
      _deleteBlobs(_options.expand((o) => o.imagePaths).toList());
    }
    _name.dispose();
    _category.dispose();
    _area.dispose();
    _allowance.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _onAllowanceLine(BudgetItem? item) {
    setState(() {
      _allowanceLineId = item?.id;
      // Seed the allowance amount from the budget line's approved/estimated
      // value so the two stay coherent (the user can still override).
      if (item != null) {
        final seed =
            item.approvedPrice > 0 ? item.approvedPrice : item.unitPrice;
        if (seed > 0) _allowance.text = seed.toStringAsFixed(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name (e.g. "Kitchen cabinets")',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _area,
                      decoration: const InputDecoration(
                          labelText: 'Area (e.g. "Kitchen")'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _category,
                      decoration:
                          const InputDecoration(labelText: 'Category'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Allowance: link to a project budget line. This is what makes
              // approval roll the chosen cost into the budget.
              StreamBuilder<List<BudgetItem>>(
                stream: ServiceLocator.budgetService
                    .getBudgetItems(widget.projectId),
                builder: (context, snap) {
                  final lines = (snap.data ?? const <BudgetItem>[])
                      .where((b) => b.itemType == BudgetItemType.item)
                      .toList()
                    ..sort((a, b) => a.name.compareTo(b.name));
                  // Allowance lines (designated for selections) come first so
                  // the picker reflects its purpose; everything else is grouped
                  // under "Other budget lines".
                  final allowanceLines =
                      lines.where((b) => b.isAllowance).toList();
                  final otherLines =
                      lines.where((b) => !b.isAllowance).toList();
                  final money = NumberFormat.simpleCurrency(decimalDigits: 0);
                  String amountFor(BudgetItem b) => money.format(
                      b.approvedPrice > 0 ? b.approvedPrice : b.unitPrice * b.quantity);
                  // Re-resolve the selected value against the current list so a
                  // stream re-emit (new instances) can't desync the dropdown.
                  BudgetItem? selectedValue;
                  for (final b in lines) {
                    if (b.id == _allowanceLineId) selectedValue = b;
                  }
                  DropdownMenuItem<BudgetItem> lineItem(BudgetItem b,
                      {required bool allowance}) {
                    return DropdownMenuItem(
                      value: b,
                      child: Row(
                        children: [
                          if (allowance)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.savings_outlined,
                                  size: 16, color: AppColors.success),
                            ),
                          Expanded(
                            child: Text(b.name,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(amountFor(b),
                              style: const TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12)),
                        ],
                      ),
                    );
                  }
                  return DropdownButtonFormField<BudgetItem>(
                    isExpanded: true,
                    value: selectedValue,
                    decoration: const InputDecoration(
                        labelText: 'Allowance — link a budget line'),
                    hint: const Text('Select an allowance…'),
                    items: [
                      const DropdownMenuItem<BudgetItem>(
                        value: null,
                        child: Text('No budget link'),
                      ),
                      if (allowanceLines.isNotEmpty)
                        const DropdownMenuItem<BudgetItem>(
                          enabled: false,
                          child: Text('ALLOWANCES',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary)),
                        ),
                      ...allowanceLines.map((b) => lineItem(b, allowance: true)),
                      if (otherLines.isNotEmpty)
                        const DropdownMenuItem<BudgetItem>(
                          enabled: false,
                          child: Text('OTHER BUDGET LINES',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary)),
                        ),
                      ...otherLines.map((b) => lineItem(b, allowance: false)),
                    ],
                    onChanged: _onAllowanceLine,
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _allowance,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Allowance amount',
                          prefixText: '\$',
                          hintText: '0'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: _due ?? DateTime.now(),
                        );
                        if (picked != null) setState(() => _due = picked);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Due date (optional)',
                          suffixIcon: _due == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  tooltip: 'Clear due date',
                                  onPressed: () => setState(() => _due = null),
                                ),
                        ),
                        child: Text(
                          _due == null
                              ? 'Pick a date'
                              : DateFormat.yMMMd().format(_due!),
                          style: _due == null
                              ? const TextStyle(
                                  color: AppColors.textTertiary)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: 'Description / instructions for the client',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 4),
              // NOTE: "Allow multiple selections" is intentionally not exposed —
              // multi-option pick isn't implemented yet (selected_option_id is
              // singular). Hidden rather than shown as a no-op toggle.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _showAmountDifferences,
                onChanged: (v) => setState(() => _showAmountDifferences = v),
                title: const Text('Show amount differences',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Show over/under-allowance amounts to the client',
                    style: TextStyle(fontSize: 11)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _excludeFromBudget,
                onChanged: (v) => setState(() => _excludeFromBudget = v),
                title: const Text('Exclude from budget',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Write-in choice; approval won\'t touch the budget',
                    style: TextStyle(fontSize: 11)),
              ),
              // Inline options — build the whole selection in one step. Existing
              // selections edit their options in the editor sheet instead.
              if (!_isEdit) ...[
                const Divider(height: 28),
                Row(
                  children: [
                    const Text('Options',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('(${_options.length})',
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 13)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addOptionDraft,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add option'),
                    ),
                  ],
                ),
                if (_options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                        'Add the choices your client picks from. You can also '
                        'add more later.',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  ),
                for (var i = 0; i < _options.length; i++)
                  _OptionDraftRow(
                    draft: _options[i],
                    allowance: double.tryParse(_allowance.text.trim()) ?? 0,
                    showDelta: _showAmountDifferences,
                    onRemove: () => _removeOptionAt(i),
                  ),
                _buildOverageHint(),
                ],
              ],
            ),
          ),
        ),
        FormPopupFooter(
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: _isEdit
              ? _submit
              : (_options.isEmpty ? _submit : () => _submit(send: true)),
          submitLabel: _isEdit
              ? 'Save'
              : (_options.isEmpty ? 'Create' : 'Create & send'),
          submitIcon: (!_isEdit && _options.isNotEmpty) ? Icons.send : null,
          secondary: (!_isEdit && _options.isNotEmpty)
              ? OutlinedButton(
                  onPressed: _submit, child: const Text('Create'))
              : null,
        ),
      ],
    );
  }
}

// ───────────────────────────────────── Editor sheet ─────────────────────────

class _SelectionEditorSheet extends StatefulWidget {
  final Selection selection;
  final NumberFormat currency;
  const _SelectionEditorSheet(
      {required this.selection, required this.currency});

  @override
  State<_SelectionEditorSheet> createState() => _SelectionEditorSheetState();
}

class _SelectionEditorSheetState extends State<_SelectionEditorSheet> {
  late Selection _current = widget.selection;
  late final _service = ServiceLocator.selectionService;

  List<SelectionComment> _comments = const [];
  bool _commentsLoaded = false;
  List<SelectionSignature> _signatures = const [];
  final TextEditingController _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _loadSignatures();
  }

  Future<void> _loadSignatures() async {
    try {
      final list = await _service.listSignatures(_current.id);
      if (mounted) setState(() => _signatures = list);
    } catch (_) {/* ignore */}
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await _service.listComments(_current.id);
      if (mounted) setState(() {
        _comments = list;
        _commentsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _commentsLoaded = true);
    }
  }

  Future<void> _sendComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final user = context.read<AuthProvider>().appUser;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : (user?.email ?? 'Team');
    try {
      await _service.addComment(
        selectionId: _current.id,
        workspaceId: _current.workspaceId,
        body: body,
        authorName: name,
      );
      _commentCtrl.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'send message'))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    final list = await _service.listByProject(_current.projectId);
    final updated = list.firstWhere(
      (s) => s.id == _current.id,
      orElse: () => _current,
    );
    if (mounted) setState(() => _current = updated);
    _loadComments();
    _loadSignatures();
  }

  /// The option to approve when the user picks "Approved" from the status
  /// menu: the already-selected option, or the only option if there's just
  /// one. Returns null when it's ambiguous (multiple options, none picked) —
  /// the caller then asks the user to tap a specific option card.
  /// Approve a selection to [opt], but first confirm when the action has a
  /// consequence the user should see: changing an already-approved choice, or
  /// picking an option over the allowance (which spins up a change order).
  Future<void> _pickOption(Selection s, SelectionOption opt) async {
    // Re-tapping the option that's already approved is a no-op — don't re-run
    // approval or re-prompt the overage confirmation.
    if (s.status == SelectionStatus.approved &&
        s.selectedOptionId == opt.id) {
      return;
    }
    final overAllowance =
        s.allowanceAmount > 0 && opt.totalCost > s.allowanceAmount;
    final isChange = s.status == SelectionStatus.approved &&
        s.selectedOptionId != null &&
        s.selectedOptionId != opt.id;
    if (overAllowance || isChange) {
      final over = opt.totalCost - s.allowanceAmount;
      final msg = <String>[
        if (isChange)
          'This replaces the currently approved choice and updates the budget.',
        if (overAllowance)
          '${widget.currency.format(over)} over the ${widget.currency.format(s.allowanceAmount)} allowance — a change order will be added for the difference.',
      ].join('\n\n');
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Approve "${opt.name}"?'),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Approve')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _service.approveInternally(
        selectionId: s.id, option: opt, actorName: 'Team');
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approved "${opt.name}".')));
    }
  }

  /// Edit a selection's core details (name, area, category, allowance link,
  /// amount, due date, description, toggles) after creation — reuses the create
  /// form in edit mode. Previously these were uneditable once created.
  Future<void> _editSelectionDetails(Selection s) async {
    final result = await showFormPopup<_CreateSelectionResult>(
      context,
      icon: Icons.edit,
      title: 'Edit Selection',
      width: 480,
      fitContent: false,
      builder: (ctx, scrollController) => _CreateSelectionContent(
        projectId: s.projectId,
        workspaceId: s.workspaceId,
        initial: s,
        scrollController: scrollController,
      ),
    );
    if (result == null) return;
    final allowanceChanged = result.allowance != s.allowanceAmount;
    final linkChanged = result.budgetItemId != s.budgetItemId;
    await _service.update(_current.id, {
      'name': result.name,
      'category': result.category,
      'location': result.location,
      'description': result.description,
      'allowance_amount': result.allowance,
      'due_date': result.dueDate?.toIso8601String(),
      'budget_item_id': result.budgetItemId,
      'exclude_from_budget': result.excludeFromBudget,
      'show_amount_differences': result.showAmountDifferences,
    });
    await _refresh();
    // Keep the budget coherent if an approved selection's allowance/link moved.
    if (_current.status == SelectionStatus.approved &&
        _current.selectedOptionId != null &&
        (allowanceChanged || linkChanged)) {
      SelectionOption? opt;
      for (final o in _current.options) {
        if (o.id == _current.selectedOptionId) opt = o;
      }
      if (opt != null) {
        await _service.approveInternally(
            selectionId: _current.id, option: opt, actorName: 'Team');
        await _refresh();
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selection updated.')));
    }
  }

  SelectionOption? _optionForApproval(Selection s) {
    if (s.options.isEmpty) return null;
    if (s.selectedOptionId != null) {
      for (final o in s.options) {
        if (o.id == s.selectedOptionId) return o;
      }
    }
    if (s.options.length == 1) return s.options.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _current;
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= AppBreakpoints.mobile;
    final scheme = Theme.of(context).colorScheme;
    final header = FormPopupHeader(
      dense: !isWide,
      borderRadius:
          isWide ? null : const BorderRadius.vertical(top: Radius.circular(20)),
      icon: Icons.checklist_rtl,
      title: s.name,
      onClose: () => Navigator.of(context).pop(),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      tooltip: 'Edit details',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editSelectionDetails(s),
                    ),
                    PopupMenuButton<SelectionStatus>(
                      icon: Row(
                        children: [
                          Icon(selectionStatusIcon(s.status),
                              size: 14, color: s.status.color),
                          const SizedBox(width: 6),
                          Text(s.status.label),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                      onSelected: (st) async {
                        // Approving must record WHICH option was chosen and
                        // apply it to the linked allowance budget line. A bare
                        // status update would leave the selection "approved"
                        // with no option, $0 selected, and the budget untouched
                        // — so route approval through the atomic RPC instead.
                        if (st == SelectionStatus.approved) {
                          final opt = _optionForApproval(s);
                          if (opt == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Tap the option you want to approve.'),
                                ),
                              );
                            }
                            return;
                          }
                          await _pickOption(s, opt);
                          return;
                        } else {
                          await _service.setStatus(s.id, st);
                        }
                        await _refresh();
                      },
                      itemBuilder: (_) => [
                        for (final st in SelectionStatus.values)
                          PopupMenuItem(value: st, child: Text(st.label)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if ((s.category ?? '').isNotEmpty)
                      Chip(label: Text(s.category!)),
                    if ((s.location ?? '').isNotEmpty)
                      Chip(label: Text(s.location!)),
                    if (s.dueDate != null)
                      Chip(
                          label: Text(
                              'Due ${DateFormat.yMMMd().format(s.dueDate!)}')),
                    ActionChip(
                        avatar: const Icon(Icons.edit, size: 14),
                        tooltip: 'Adjust allowance (reallocate budget)',
                        onPressed: _editAllowance,
                        label: Text(
                            'Allowance ${widget.currency.format(s.allowanceAmount)}')),
                    if (s.status == SelectionStatus.approved)
                      Chip(
                          backgroundColor:
                              SelectionStatus.approved.color.withOpacity(0.10),
                          label: Text(
                              'Selected ${widget.currency.format(s.selectedAmount)}')),
                  ],
                ),
                if ((s.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(s.description!),
                ],
                const Divider(height: 32),
                Row(
                  children: [
                    const Text('Options',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Add option',
                      onSelected: (v) async {
                        if (v == 'new') {
                          await _addOption(s);
                        } else if (v == 'budget') {
                          await _addOptionFromBudget(s);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'new', child: Text('New option')),
                        PopupMenuItem(
                            value: 'budget',
                            child: Text('From budget line…')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: 4),
                          Text('Add option'),
                        ]),
                      ),
                    ),
                  ],
                ),
                if (s.options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
                    child: Text('No options yet. Add one to send to client.',
                        style: TextStyle(color: AppColors.textTertiary)),
                  ),
                if (s.options.isNotEmpty)
                  LayoutBuilder(builder: (context, c) {
                    // Responsive card grid: 1 col on phones, 2 on wider.
                    final cols = c.maxWidth >= 520 ? 2 : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: cols == 1 ? 2.6 : 1.5,
                      children: [
                        for (final opt in s.options)
                          _OptionCard(
                            option: opt,
                            currency: widget.currency,
                            selected: opt.id == s.selectedOptionId,
                            allowance: s.allowanceAmount,
                            showDelta: s.showAmountDifferences,
                            onPick: () => _pickOption(s, opt),
                            onEdit: () => _editOption(s, opt),
                            onDelete: () async {
                              await _service.deleteOption(opt.id);
                              await _refresh();
                            },
                          ),
                      ],
                    );
                  }),
                const Divider(height: 32),
                _buildFilesLinks(),
                const Divider(height: 32),
                _buildMessages(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (s.status == SelectionStatus.pending &&
                        s.options.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () async {
                          await _service.sendToClient(s.id);
                          if (mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Send to client'),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        await _service.delete(s.id);
                        if (mounted) Navigator.of(context).pop();
                      },
                      icon:
                          const Icon(Icons.delete_outline, color: AppColors.error),
                      label: const Text('Delete',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
      ],
    );
    if (isWide) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
        child: Container(
          width: 720,
          height: media.size.height * 0.85,
          constraints: BoxConstraints(
            maxWidth: media.size.width * 0.9,
            maxHeight: media.size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.r16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r16),
            child: Column(
              children: [
                header,
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              header,
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: true);
      if (result == null || result.files.isEmpty) return;
      final supabase = Supabase.instance.client;
      const maxBytes = 10 * 1024 * 1024;
      final added = <String>[];
      for (var i = 0; i < result.files.length; i++) {
        final f = result.files[i];
        final bytes = f.bytes;
        if (bytes == null || bytes.length > maxBytes) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final ext = (f.extension ?? 'bin');
        final ct = lookupMimeType(f.name) ?? 'application/octet-stream';
        final path =
            '${_current.workspaceId}/selection-files/sel_${_current.id}_${ts}_$i.$ext';
        await supabase.storage.from('project-images').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: ct),
            );
        added.add(supabase.storage.from('project-images').getPublicUrl(path));
      }
      if (added.isEmpty) return;
      await _service.update(_current.id,
          {'attachment_urls': [..._current.attachmentUrls, ...added]});
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(UserFacingError.uiMessage(e, action: 'attach file'))));
      }
    }
  }

  Future<void> _removeAttachment(String url) async {
    await _service.update(_current.id, {
      'attachment_urls':
          _current.attachmentUrls.where((u) => u != url).toList()
    });
    await _refresh();
  }

  Future<void> _editReferenceLink() async {
    final ctrl = TextEditingController(text: _current.referenceUrl ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reference link'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    await _service
        .update(_current.id, {'reference_url': v.isEmpty ? null : v});
    await _refresh();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Adjust this selection's allowance — lets the builder reallocate budget
  /// between allowances (raise one using another's savings).
  Future<void> _editAllowance() async {
    final ctrl = TextEditingController(
        text: _current.allowanceAmount == 0
            ? ''
            : _current.allowanceAmount.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adjust allowance'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '\$', hintText: '0'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, double.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    await _service.update(_current.id, {'allowance_amount': v});
    await _refresh();
    // If already approved, re-apply so the allowance/overage split is
    // recomputed against the new allowance (otherwise the budget goes stale).
    if (_current.status == SelectionStatus.approved &&
        _current.selectedOptionId != null) {
      SelectionOption? opt;
      for (final o in _current.options) {
        if (o.id == _current.selectedOptionId) opt = o;
      }
      if (opt != null) {
        await _service.approveInternally(
            selectionId: _current.id, option: opt, actorName: 'Team');
        await _refresh();
      }
    }
  }

  Widget _buildFilesLinks() {
    final s = _current;
    final fileName = (String url) {
      final seg = Uri.tryParse(url)?.pathSegments;
      return (seg == null || seg.isEmpty) ? 'file' : seg.last;
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Files & links',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: _attachFile,
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('Attach file'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: _editReferenceLink,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.link, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (s.referenceUrl ?? '').isEmpty
                      ? 'Add a reference link'
                      : s.referenceUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (s.referenceUrl ?? '').isEmpty
                        ? AppColors.textTertiary
                        : AppColors.primary,
                  ),
                ),
              ),
              const Icon(Icons.edit, size: 14, color: AppColors.textTertiary),
            ]),
          ),
        ),
        if (s.attachmentUrls.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in s.attachmentUrls)
                InputChip(
                  avatar: const Icon(Icons.insert_drive_file_outlined,
                      size: 16),
                  label: Text(fileName(url),
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () => _openUrl(url),
                  onDeleted: () => _removeAttachment(url),
                ),
            ],
          ),
        if (_signatures.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Signatures',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          for (final sig in _signatures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.draw_outlined,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${sig.signerName ?? sig.signerEmail ?? 'Signed'} · '
                    '${DateFormat.yMMMd().format(sig.signedAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                    onPressed: () => _openUrl(sig.signatureUrl),
                    child: const Text('View')),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _buildMessages() {
    final fmt = DateFormat.MMMd().add_jm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Messages',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (!_commentsLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No messages yet. Ask the client a question.',
                style: TextStyle(color: AppColors.textTertiary)),
          )
        else
          ..._comments.map((c) {
            final mine = !c.isFromClient;
            return Align(
              alignment:
                  mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  color: mine
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.authorName ?? (c.isFromClient ? 'Client' : 'Team')}'
                      ' · ${fmt.format(c.createdAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 2),
                    Text(c.body),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Message the client…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendComment(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _sendComment,
              icon: const Icon(Icons.send, size: 18),
              tooltip: 'Send',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addOption(Selection s) async {
    final result = await showFormPopup<_OptionDraft>(
      context,
      icon: Icons.add_circle_outline,
      title: 'Create New Option',
      width: 420,
      fitContent: false,
      builder: (ctx, scrollController) => _OptionContent(
        workspaceId: s.workspaceId,
        scrollController: scrollController,
      ),
    );
    if (result == null) return;
    await _service.addOption(
      selectionId: s.id,
      workspaceId: s.workspaceId,
      name: result.name,
      description: result.description,
      vendor: result.vendor,
      sku: result.sku,
      unitCost: result.unitCost,
      quantity: result.quantity,
      imageUrls: result.imageUrls,
      sortOrder: s.options.length,
    );
    // Optionally persist this option to the catalog for reuse.
    if (result.saveToCatalog) {
      try {
        await ServiceLocator.catalogService.createCatalogItem(CatalogItem(
          id: '',
          workspaceId: s.workspaceId,
          name: result.name,
          description: result.description,
          unitCost: result.unitCost,
          unitPrice: result.unitCost,
          markup: 0,
          margin: 0,
          imageUrl: result.imageUrls.isNotEmpty ? result.imageUrls.first : null,
          sku: result.sku,
          category: s.category,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'save option to catalog')),
          ));
        }
      }
    }
    await _refresh();
  }

  Future<void> _editOption(Selection s, SelectionOption opt) async {
    final result = await showFormPopup<_OptionDraft>(
      context,
      icon: Icons.edit,
      title: 'Edit Option',
      width: 420,
      fitContent: false,
      builder: (ctx, scrollController) => _OptionContent(
        workspaceId: s.workspaceId,
        existing: opt,
        scrollController: scrollController,
      ),
    );
    if (result == null) return;
    await _service.updateOption(opt.id, {
      'name': result.name,
      'description': result.description,
      'vendor': result.vendor,
      'sku': result.sku,
      'unit_cost': result.unitCost,
      'quantity': result.quantity,
      'image_url':
          result.imageUrls.isNotEmpty ? result.imageUrls.first : null,
      'image_urls': result.imageUrls,
    });
    // If this option is the one currently selected/approved, keep the
    // selection's selected_amount and budget line in sync via the atomic RPC.
    if (s.selectedOptionId == opt.id &&
        s.status == SelectionStatus.approved) {
      await _service.approveInternally(
        selectionId: s.id,
        option: SelectionOption(
          id: opt.id,
          selectionId: opt.selectionId,
          workspaceId: opt.workspaceId,
          name: result.name,
          unitCost: result.unitCost,
          quantity: result.quantity,
        ),
        actorName: 'Team',
      );
    }
    await _refresh();
  }

  /// Create an option directly from a project budget line (JobTread "From
  /// Budget"): pick a leaf budget item, seed name + price from it.
  Future<void> _addOptionFromBudget(Selection s) async {
    final picked = await showDialog<BudgetItem>(
      context: context,
      builder: (_) => _BudgetLinePickerDialog(projectId: s.projectId),
    );
    if (picked == null) return;
    final price =
        picked.approvedPrice > 0 ? picked.approvedPrice : picked.unitPrice;
    await _service.addOption(
      selectionId: s.id,
      workspaceId: s.workspaceId,
      name: picked.name,
      description: picked.description,
      unitCost: price > 0 ? price : picked.unitCost,
      quantity: 1,
      sortOrder: s.options.length,
    );
    await _refresh();
  }
}

class _OptionDraft {
  final String name;
  final String? description;
  final String? vendor;
  final String? sku;
  final double unitCost;
  final double quantity;
  final List<String> imageUrls;
  final bool saveToCatalog;

  /// Storage paths of photos uploaded while building THIS draft (not yet
  /// referenced by a saved option). Let the create dialog clean them up if the
  /// draft is removed or the whole dialog is cancelled, so abandoned photos
  /// don't orphan in the bucket. Empty for catalog-sourced images (don't delete
  /// those — they belong to the catalog item).
  final List<String> imagePaths;
  _OptionDraft({
    required this.name,
    this.description,
    this.vendor,
    this.sku,
    this.unitCost = 0,
    this.quantity = 1,
    this.imageUrls = const [],
    this.saveToCatalog = false,
    this.imagePaths = const [],
  });

  double get totalCost => unitCost * quantity;
}

/// Over/under-allowance delta for an option total. Returns null when there's
/// nothing meaningful to show (no allowance set, or exactly on budget). Shared
/// by the option cards and the create-flow draft rows so both read the same.
/// Pure + top-level so it can be unit-tested without pumping any widget.
({double amount, bool over})? selectionAllowanceDelta(
    double optionTotal, double allowance) {
  if (allowance <= 0) return null;
  final diff = optionTotal - allowance;
  if (diff == 0) return null;
  return (amount: diff.abs(), over: diff > 0);
}

/// Compact row for an option draft assembled in the create dialog: thumbnail,
/// name, total cost, and a remove button.
class _OptionDraftRow extends StatelessWidget {
  final _OptionDraft draft;

  /// Allowance to compare the draft's total against (0 = no allowance set).
  final double allowance;
  final bool showDelta;
  final VoidCallback onRemove;
  const _OptionDraftRow({
    required this.draft,
    required this.allowance,
    required this.showDelta,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.simpleCurrency(decimalDigits: 0);
    final thumb = draft.imageUrls.isNotEmpty ? draft.imageUrls.first : null;
    final delta =
        showDelta ? selectionAllowanceDelta(draft.totalCost, allowance) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: thumb != null
                ? Image.network(thumb,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _OptionThumbFallback())
                : const _OptionThumbFallback(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(draft.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Text(
                        '${money.format(draft.totalCost)}'
                        '${draft.quantity != 1 ? ' · ${draft.quantity.toStringAsFixed(draft.quantity % 1 == 0 ? 0 : 2)} × ${money.format(draft.unitCost)}' : ''}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                    if (delta != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                          delta.over
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 11,
                          color:
                              delta.over ? AppColors.error : AppColors.success),
                      Text(
                        '${money.format(delta.amount)} ${delta.over ? 'over' : 'under'}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: delta.over
                                ? AppColors.error
                                : AppColors.success),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove option',
            icon: const Icon(Icons.close, color: AppColors.textTertiary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _OptionThumbFallback extends StatelessWidget {
  const _OptionThumbFallback();
  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        color: AppColors.cardBorder.withOpacity(0.4),
        child: const Icon(Icons.image_outlined,
            size: 18, color: AppColors.textTertiary),
      );
}

class _OptionContent extends StatefulWidget {
  final String workspaceId;

  /// When non-null the dialog opens in EDIT mode, pre-filled from this option.
  final SelectionOption? existing;
  final ScrollController? scrollController;
  const _OptionContent(
      {required this.workspaceId, this.existing, this.scrollController});
  @override
  State<_OptionContent> createState() => _OptionContentState();
}

class _OptionContentState extends State<_OptionContent> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _vendor =
      TextEditingController(text: widget.existing?.vendor ?? '');
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _desc =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _cost = TextEditingController(
      text: (widget.existing?.unitCost ?? 0).toString());
  late final _qty = TextEditingController(
      text: (widget.existing?.quantity ?? 1).toString());

  late List<String> _imageUrls = [...?widget.existing?.photos];
  bool _uploading = false;
  bool _saveToCatalog = false;

  /// Storage paths uploaded during THIS dialog session that aren't yet
  /// committed to a saved option. Removed if the user cancels (or a thumbnail
  /// is removed), so cancelling never leaves orphaned blobs. Keyed by the
  /// public URL so removing a thumbnail can delete the right blob.
  final _uncommittedByUrl = <String, String>{};

  bool get _isEdit => widget.existing != null;

  Future<void> _deleteStoragePath(String path) async {
    try {
      await Supabase.instance.client.storage
          .from('project-images')
          .remove([path]);
    } catch (_) {/* best-effort cleanup */}
  }

  @override
  void dispose() {
    // Dismissed without committing: abandon any images uploaded this session
    // so closing via the X / scrim / back gesture never orphans blobs.
    // (Committing clears [_uncommittedByUrl] before popping.)
    for (final p in _uncommittedByUrl.values) {
      _deleteStoragePath(p);
    }
    _uncommittedByUrl.clear();
    _name.dispose();
    _vendor.dispose();
    _sku.dispose();
    _desc.dispose();
    _cost.dispose();
    _qty.dispose();
    super.dispose();
  }

  /// Builds the option draft and hands its blob paths to the caller.
  void _commit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    // Committing: hand the blob paths to the caller so it owns cleanup (the
    // editor-sheet callers ignore them — those blobs get referenced by a
    // saved option immediately).
    final newPaths = _uncommittedByUrl.values.toList();
    _uncommittedByUrl.clear();
    Navigator.of(context).pop(_OptionDraft(
      name: name,
      description: clean(_desc),
      vendor: clean(_vendor),
      sku: clean(_sku),
      unitCost: double.tryParse(_cost.text.trim()) ?? 0,
      quantity: double.tryParse(_qty.text.trim()) ?? 1,
      imageUrls: _imageUrls,
      saveToCatalog: _saveToCatalog,
      imagePaths: newPaths,
    ));
  }

  /// Pre-fill the form from a chosen catalog item (JobTread's "From Catalog").
  void _applyCatalogItem(CatalogItem? item) {
    if (item == null) return;
    setState(() {
      _name.text = item.name;
      _desc.text = item.description ?? '';
      _sku.text = item.sku ?? '';
      // Options are client-facing: the amount rolls into the budget and shows
      // to the customer, so seed from the catalog's PRICE (what you charge),
      // falling back to cost for cost-only catalog items.
      _cost.text =
          (item.unitPrice > 0 ? item.unitPrice : item.unitCost).toString();
      if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
        _imageUrls = [item.imageUrl!];
      }
    });
  }

  /// Upload one or more photos and append them to the option's image list.
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      setState(() => _uploading = true);
      final supabase = Supabase.instance.client;
      const maxBytes = 10 * 1024 * 1024;
      final added = <String>[];
      for (var i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        final bytes = file.bytes;
        if (bytes == null || bytes.length > maxBytes) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final contentType = lookupMimeType(file.name) ?? 'image/jpeg';
        final path =
            '${widget.workspaceId}/selection-options/option_${ts}_$i.jpg';
        await supabase.storage.from('project-images').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        final url =
            supabase.storage.from('project-images').getPublicUrl(path);
        _uncommittedByUrl[url] = path;
        added.add(url);
      }
      if (!mounted) return;
      setState(() {
        _imageUrls = [..._imageUrls, ...added];
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(UserFacingError.uiMessage(e, action: 'upload image')),
      ));
    }
  }

  Future<void> _removeImageAt(int i) async {
    final url = _imageUrls[i];
    setState(() => _imageUrls = [..._imageUrls]..removeAt(i));
    // If this was an uncommitted upload from this session, delete the blob.
    final path = _uncommittedByUrl.remove(url);
    if (path != null) await _deleteStoragePath(path);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // From Catalog — pre-fill from a reusable catalog item.
              // Catalog pre-fill only makes sense when creating a new option.
              if (!_isEdit)
                StreamBuilder<List<CatalogItem>>(
                  stream: ServiceLocator.catalogService
                      .getCatalogItems(widget.workspaceId),
                  builder: (context, snap) {
                    final items = snap.data ?? const <CatalogItem>[];
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DropdownButtonFormField<CatalogItem>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'From catalog (optional)'),
                        hint: const Text('Pick a catalog item…'),
                        items: items
                            .map((it) => DropdownMenuItem(
                                  value: it,
                                  child: Text(it.name,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _applyCatalogItem,
                      ),
                    );
                  },
                ),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true),
              TextField(
                  controller: _desc,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                        controller: _vendor,
                        decoration:
                            const InputDecoration(labelText: 'Vendor')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: _sku,
                        decoration: const InputDecoration(labelText: 'SKU')),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                        controller: _cost,
                        decoration: const InputDecoration(
                            labelText: 'Unit cost', prefixText: '\$'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: _qty,
                        decoration:
                            const InputDecoration(labelText: 'Quantity'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Photos: horizontal thumbnail strip + add. Supports multiple.
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Photos',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _imageUrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Image.network(_imageUrls[i],
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: Icon(Icons.broken_image,
                                        color: AppColors.textTertiary))),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton(
                              iconSize: 18,
                              icon: const Icon(Icons.cancel,
                                  color: AppColors.error),
                              onPressed: () => _removeImageAt(i),
                            ),
                          ),
                        ]),
                      ),
                    // Add-photo tile
                    InkWell(
                      onTap: _uploading ? null : _pickImage,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: _uploading
                            ? const Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (!_isEdit)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _saveToCatalog,
                  onChanged: (v) =>
                      setState(() => _saveToCatalog = v ?? false),
                  title: const Text('Also save to catalog for reuse',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: _uploading ? null : _commit,
          submitLabel: _isEdit ? 'Save' : 'Add',
          busy: _uploading,
        ),
      ],
    );
  }
}

// ──────────────────────────── Visual option card ────────────────────────────

/// JobTread-style option card: large photo, name, vendor, price, over/under
/// badge, selected state, and an actions menu. Tapping picks it for the client.
class _OptionCard extends StatelessWidget {
  final SelectionOption option;
  final NumberFormat currency;
  final bool selected;
  final double allowance;
  final bool showDelta;
  final VoidCallback onPick;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OptionCard({
    required this.option,
    required this.currency,
    required this.selected,
    required this.allowance,
    required this.showDelta,
    required this.onPick,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final photos = option.photos;
    final delta = showDelta
        ? selectionAllowanceDelta(option.totalCost, allowance)
        : null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? SelectionStatus.approved.color.withOpacity(0.06)
              : AppColors.surface,
          border: Border.all(
            color: selected
                ? SelectionStatus.approved.color
                : AppColors.cardBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(9)),
              child: SizedBox(
                width: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photos.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: photos.first,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: AppColors.background,
                          child: Icon(Icons.image_not_supported,
                              color: AppColors.textTertiary),
                        ),
                      )
                    else
                      const ColoredBox(
                        color: AppColors.background,
                        child: Icon(Icons.image_outlined,
                            color: AppColors.textTertiary),
                      ),
                    if (photos.length > 1)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.collections,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 2),
                            Text('${photos.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10)),
                          ]),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Icon(Icons.check_circle,
                            size: 18, color: SelectionStatus.approved.color),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (option.isClientSuggested)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: 'Suggested by client',
                              child: Icon(Icons.lightbulb,
                                  size: 14, color: AppColors.warning),
                            ),
                          ),
                        Expanded(
                          child: Text(option.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Option actions',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (v) =>
                              v == 'edit' ? onEdit() : onDelete(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Edit option')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete option')),
                          ],
                        ),
                      ],
                    ),
                    if ((option.vendor ?? '').isNotEmpty)
                      Text(option.vendor!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(currency.format(option.totalCost),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (delta != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                                delta.over
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 12,
                                color: delta.over
                                    ? AppColors.error
                                    : AppColors.success),
                            Text(
                              currency.format(delta.amount),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: delta.over
                                      ? AppColors.error
                                      : AppColors.success),
                            ),
                          ]),
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

// ─────────────────────────── Budget line picker ─────────────────────────────

/// Pick a leaf budget line — used by "Add option → From budget line".
class _BudgetLinePickerDialog extends StatelessWidget {
  final String projectId;
  const _BudgetLinePickerDialog({required this.projectId});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
    final projectTermLower = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: FormPopupHeader(
        icon: Icons.account_tree_outlined,
        title: 'From Budget Line',
        onClose: () => Navigator.of(context).pop(),
      ),
      content: SizedBox(
        width: 420,
        height: 400,
        child: StreamBuilder<List<BudgetItem>>(
          stream: ServiceLocator.budgetService.getBudgetItems(projectId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final lines = snap.data!
                .where((b) => b.itemType == BudgetItemType.item)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            if (lines.isEmpty) {
              return Center(
                  child: Text('No budget lines on this $projectTermLower yet.'));
            }
            return ListView.builder(
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final b = lines[i];
                final amt =
                    b.approvedPrice > 0 ? b.approvedPrice : b.unitPrice;
                return ListTile(
                  title: Text(b.name),
                  trailing: Text(currency.format(amt)),
                  onTap: () => Navigator.of(context).pop(b),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
      ],
    );
  }
}

// ─────────────────────────────── Board toolbar ──────────────────────────────

/// Pick which allowance budget lines to turn into selections (bulk import).
class _ImportSelectionsDialog extends StatefulWidget {
  final List<BudgetItem> candidates;
  final NumberFormat currency;
  const _ImportSelectionsDialog(
      {required this.candidates, required this.currency});

  @override
  State<_ImportSelectionsDialog> createState() =>
      _ImportSelectionsDialogState();
}

class _ImportSelectionsDialogState extends State<_ImportSelectionsDialog> {
  late final Set<String> _checked =
      widget.candidates.map((b) => b.id).toSet();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: FormPopupHeader(
        icon: Icons.playlist_add_check,
        title: 'Import Selections from Budget',
        onClose: () => Navigator.of(context).pop(),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Creates a client selection for each allowance line you pick.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in widget.candidates)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _checked.contains(b.id),
                      onChanged: (v) => setState(() =>
                          v == true ? _checked.add(b.id) : _checked.remove(b.id)),
                      title: Text(b.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      secondary: Text(widget.currency.format(
                          b.approvedPrice > 0
                              ? b.approvedPrice
                              : b.unitPrice * b.quantity)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.candidates
                      .where((b) => _checked.contains(b.id))
                      .toList()),
          child: Text('Import ${_checked.length}'),
        ),
      ],
    );
  }
}

class _BoardToolbar extends StatelessWidget {
  final bool groupByArea;
  final ValueChanged<bool> onToggleGroup;
  final VoidCallback onSummary;
  final VoidCallback? onSend;
  final VoidCallback onImport;
  final VoidCallback onTemplates;
  const _BoardToolbar({
    required this.groupByArea,
    required this.onToggleGroup,
    required this.onSummary,
    required this.onSend,
    required this.onImport,
    required this.onTemplates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        children: [
          // Group: Status | Area
          SegmentedButton<bool>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Status')),
              ButtonSegment(value: true, label: Text('Area')),
            ],
            selected: {groupByArea},
            onSelectionChanged: (s) => onToggleGroup(s.first),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onTemplates,
            icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
            label: const Text('Templates'),
          ),
          TextButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Import from budget'),
          ),
          if (onSend != null)
            TextButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send to client'),
            ),
          TextButton.icon(
            onPressed: onSummary,
            icon: const Icon(Icons.summarize_outlined, size: 18),
            label: const Text('Summary'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Selections summary dialog ────────────────────────

/// JobTread "Selections Summary": per-allowance Total / Selected / Remaining,
/// plus non-allowance "Other Selections". Connects selections to the budget by
/// grouping on the linked allowance budget line.
class _SelectionsSummaryDialog extends StatelessWidget {
  final String projectId;
  final List<Selection> selections;
  final NumberFormat currency;
  const _SelectionsSummaryDialog({
    required this.projectId,
    required this.selections,
    required this.currency,
  });

  /// Build and share a consolidated selections PDF report (JobTread parity).
  Future<void> _exportPdf() async {
    final active = selections
        .where((s) => s.status != SelectionStatus.cancelled)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final money = currency.format;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        build: (ctx) => [
          pw.Header(level: 0, text: 'Selections Summary'),
          pw.Table.fromTextArray(
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: {
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            headers: const ['Selection', 'Area', 'Allowance', 'Selected / Status'],
            data: active
                .map((s) => [
                      s.name,
                      s.location ?? '',
                      money(s.allowanceAmount),
                      s.status == SelectionStatus.approved
                          ? money(s.selectedAmount)
                          : s.status.label,
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Header(level: 1, text: 'Options'),
          ...active.map((s) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(s.name,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ...s.options.map((o) => pw.Bullet(
                          text:
                              '${o.name} — ${money(o.totalCost)}${o.id == s.selectedOptionId ? '  (chosen)' : ''}',
                        )),
                    if (s.options.isEmpty)
                      pw.Text('No options',
                          style: const pw.TextStyle(
                              color: PdfColors.grey, fontSize: 10)),
                  ],
                ),
              )),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: StreamBuilder<List<BudgetItem>>(
          stream: ServiceLocator.budgetService.getBudgetItems(projectId),
          builder: (context, snap) {
            final nameById = {
              for (final b in (snap.data ?? const <BudgetItem>[])) b.id: b.name
            };
            // Group non-cancelled selections by their linked allowance line.
            final allowanceGroups =
                <String, ({double total, double selected, String name})>{};
            final other = <Selection>[];
            for (final s in selections) {
              if (s.status == SelectionStatus.cancelled) continue;
              final lineId = s.budgetItemId;
              if (lineId == null || s.excludeFromBudget) {
                other.add(s);
                continue;
              }
              final prev = allowanceGroups[lineId] ??
                  (total: 0.0, selected: 0.0, name: nameById[lineId] ?? 'Allowance');
              allowanceGroups[lineId] = (
                total: prev.total + s.allowanceAmount,
                selected: prev.selected +
                    (s.status == SelectionStatus.approved
                        ? s.selectedAmount
                        : 0),
                name: prev.name,
              );
            }
            final rows = allowanceGroups.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    children: [
                      const Text('Selections Summary',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined,
                            size: 18),
                        label: const Text('PDF'),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const Text('ALLOWANCES',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      _summaryHeader(),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Text('No allowance-linked selections yet.',
                              style:
                                  TextStyle(color: AppColors.textTertiary)),
                        ),
                      for (final r in rows)
                        _allowanceRow(r.name, r.total, r.selected),
                      if (rows.isNotEmpty) ...[
                        const Divider(),
                        _allowanceRow(
                          'Total',
                          rows.fold(0.0, (s, r) => s + r.total),
                          rows.fold(0.0, (s, r) => s + r.selected),
                          bold: true,
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text('OTHER SELECTIONS',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      if (other.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Text('None.',
                              style:
                                  TextStyle(color: AppColors.textTertiary)),
                        ),
                      for (final s in other)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(child: Text(s.name)),
                              Text(s.status == SelectionStatus.approved
                                  ? currency.format(s.selectedAmount)
                                  : '—'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryHeader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(flex: 4, child: Text('Name',
              style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Total',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Selected',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Remaining',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _allowanceRow(String name, double total, double selected,
      {bool bold = false}) {
    final remaining = total - selected;
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(flex: 4, child: Text(name, style: style)),
        Expanded(
            flex: 2,
            child: Text(currency.format(total),
                textAlign: TextAlign.right, style: style)),
        Expanded(
            flex: 2,
            child: Text(currency.format(selected),
                textAlign: TextAlign.right, style: style)),
        Expanded(
            flex: 2,
            child: Text(currency.format(remaining),
                textAlign: TextAlign.right,
                style: style.copyWith(
                    color: remaining < 0 ? AppColors.error : null))),
      ]),
    );
  }
}

// ───────────────────────── Send selections (bulk) dialog ────────────────────

/// JobTread "Send Selections": release one or more pending selections to the
/// client at once (moves them to Awaiting Client), grouped by Area.
class _SendSelectionsDialog extends StatefulWidget {
  final List<Selection> selections;
  final NumberFormat currency;
  const _SendSelectionsDialog(
      {required this.selections, required this.currency});
  @override
  State<_SendSelectionsDialog> createState() => _SendSelectionsDialogState();
}

class _SendSelectionsDialogState extends State<_SendSelectionsDialog> {
  final _checked = <String>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checked.addAll(widget.selections.map((s) => s.id)); // default: all
  }

  @override
  Widget build(BuildContext context) {
    final byArea = <String, List<Selection>>{};
    for (final s in widget.selections) {
      final area = (s.location ?? '').trim().isEmpty
          ? 'General'
          : s.location!.trim();
      byArea.putIfAbsent(area, () => []).add(s);
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(children: [
                const Text('Send Selections',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Close'),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Text(
                'Choose selections to release. They move to Awaiting Client '
                'so the customer can review and approve.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                children: [
                  for (final area in byArea.keys) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(area,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final s in byArea[area]!)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _checked.contains(s.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _checked.add(s.id);
                          } else {
                            _checked.remove(s.id);
                          }
                        }),
                        title: Text(s.name),
                        secondary: Text(
                          '${s.options.length} option${s.options.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Text('${_checked.length} selected',
                      style:
                          const TextStyle(color: AppColors.textSecondary)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _checked.isEmpty || _sending
                        ? null
                        : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, size: 18),
                    label: const Text('Send to client'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final svc = ServiceLocator.selectionService;
    var ok = 0;
    for (final id in _checked) {
      try {
        await svc.sendToClient(id);
        ok++;
      } catch (_) {/* skip individual failures */}
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent $ok selection${ok == 1 ? '' : 's'} to client')),
    );
  }
}

