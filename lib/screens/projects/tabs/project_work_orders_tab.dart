/// Internal board for work orders on a project.
///
/// Status columns (Draft, Issued, In Progress, On Hold, Completed, Cancelled).
/// Tap a card to open a detail sheet with items, signatures, status changes,
/// and history.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/project.dart';
import '../../../models/work_order.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/forms/po_line_item_dialog.dart';
import '../../../widgets/forms/signature_dialog.dart';

class ProjectWorkOrdersTab extends StatefulWidget {
  final Project project;
  /// Discriminator: 'materials' (default — traditional work orders) or
  /// 'rental' (rental-equipment expense requests issued to a third party).
  final String kind;
  /// Singular noun used in dialogs/snackbars/buttons, e.g. "work order" or
  /// "rental request". Should be lowercase.
  final String itemNounSingular;
  /// Plural noun used in error messages, e.g. "work orders" / "rental requests".
  final String itemNounPlural;
  /// Number prefix used by [nextNumber] (WO- / RNT-).
  final String numberPrefix;

  const ProjectWorkOrdersTab({
    super.key,
    required this.project,
    this.kind = 'materials',
    this.itemNounSingular = 'work order',
    this.itemNounPlural = 'work orders',
    this.numberPrefix = 'WO',
  });

  @override
  State<ProjectWorkOrdersTab> createState() => _ProjectWorkOrdersTabState();
}

class _ProjectWorkOrdersTabState extends State<ProjectWorkOrdersTab> {
  late final Stream<List<WorkOrder>> _stream = ServiceLocator.workOrderService
      .watchByProject(widget.project.id, kind: widget.kind);

  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.MMMd();

  static const _columns = <WorkOrderStatus>[
    WorkOrderStatus.draft,
    WorkOrderStatus.issued,
    WorkOrderStatus.inProgress,
    WorkOrderStatus.onHold,
    WorkOrderStatus.completed,
    WorkOrderStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createWorkOrder,
        icon: const Icon(Icons.add),
        label: Text('New ${widget.itemNounSingular}'),
      ),
      body: StreamBuilder<List<WorkOrder>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(UserFacingError.uiMessage(snap.error,
                  action: 'load ${widget.itemNounPlural}')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final wos = snap.data!;
          final summary = ServiceLocator.workOrderService.summarise(wos);

          return Column(
            children: [
              _SummaryStrip(summary: summary, currency: _currency),
              const Divider(height: 1),
              Expanded(child: _buildBoard(wos)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<WorkOrder> all) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in _columns)
            _Column(
              status: status,
              items: all.where((w) => w.status == status).toList(),
              currency: _currency,
              dateFmt: _dateFmt,
              onTap: _openDetail,
            ),
        ],
      ),
    );
  }

  Future<void> _createWorkOrder() async {
    // Materials, Rentals (and any other kinds routed through this board)
    // no longer have their own creation dialog. Creating a new request
    // means generating a Request for Bid document scoped to this project,
    // so the user is sent into the document creator with that template
    // pre-selected. The actual purchase order / work order record is
    // produced downstream when the document is finalized.
    final query = {
      'projectId': widget.project.id,
      'prefer_type': 'request_for_bid',
    }
        .entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    context.go('/documents/create?$query');
  }

  Future<void> _openDetail(WorkOrder w) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => WorkOrderDetailSheet(
          workOrder: w,
          scrollController: controller,
          currency: _currency,
        ),
      ),
    );
  }
}

// ───────────────────────────── Summary strip ────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final WorkOrderSummary summary;
  final NumberFormat currency;
  const _SummaryStrip({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      color: AppColors.surface,
      child: Row(
        children: [
          _kpi('Committed', currency.format(summary.totalCommitted)),
          const SizedBox(width: 24),
          _kpi('Paid', currency.format(summary.totalPaid),
              color: AppColors.success),
          const SizedBox(width: 24),
          _kpi('Remaining', currency.format(summary.totalRemaining),
              color: AppColors.warning),
          const Spacer(),
          Text(
            '${summary.countTotal} total · '
            '${summary.countOpen} open · '
            '${summary.countCompleted} done',
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
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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

// ───────────────────────────── Column ───────────────────────────────────────

class _Column extends StatelessWidget {
  final WorkOrderStatus status;
  final List<WorkOrder> items;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final ValueChanged<WorkOrder> onTap;

  const _Column({
    required this.status,
    required this.items,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
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
                Icon(Icons.circle, size: 10, color: status.color),
                const SizedBox(width: 8),
                Text(status.label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    child: Text('Nothing here yet.',
                        style: TextStyle(color: AppColors.textTertiary)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _Card(
                      wo: items[i],
                      currency: currency,
                      dateFmt: dateFmt,
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
  final WorkOrder wo;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onTap;

  const _Card({
    required this.wo,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [
                Text(wo.number,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (wo.priority != WorkOrderPriority.normal)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: wo.priority.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(wo.priority.label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: wo.priority.color)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(wo.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((wo.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(wo.location!,
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_money,
                    size: 14, color: AppColors.textTertiary),
                Text(currency.format(wo.totalAmount),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                if (wo.scheduledStart != null || wo.scheduledEnd != null) ...[
                  Icon(Icons.event,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 2),
                  Text(
                      dateFmt.format(
                          (wo.scheduledStart ?? wo.scheduledEnd)!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ],
            ),
            if (wo.signatures.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.draw,
                      size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('${wo.signatures.length} signature(s)',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.success)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Detail sheet ─────────────────────────────────

class WorkOrderDetailSheet extends StatefulWidget {
  final WorkOrder workOrder;
  final ScrollController scrollController;
  final NumberFormat currency;
  const WorkOrderDetailSheet({
    super.key,
    required this.workOrder,
    required this.scrollController,
    required this.currency,
  });

  @override
  State<WorkOrderDetailSheet> createState() => _WorkOrderDetailSheetState();
}

class _WorkOrderDetailSheetState extends State<WorkOrderDetailSheet> {
  late Future<List<WorkOrderHistoryEvent>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture =
        ServiceLocator.workOrderService.historyFor(widget.workOrder.id);
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture =
          ServiceLocator.workOrderService.historyFor(widget.workOrder.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wo = widget.workOrder;
    final dateFmt = DateFormat.yMMMd().add_jm();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: wo.status.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(wo.status.label,
                    style: TextStyle(
                        color: wo.status.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(wo.number,
                  style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmDelete,
                tooltip: 'Delete',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(wo.title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          if ((wo.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(wo.description!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          _statusActions(wo),
          const SizedBox(height: 16),
          _factsGrid(wo, dateFmt),
          const SizedBox(height: 20),
          _section('Scope of work'),
          if ((wo.scopeOfWork ?? '').isEmpty)
            const Text('No scope specified.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            Text(wo.scopeOfWork!),
          const SizedBox(height: 20),
          _section('Line items',
              trailing: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add item'),
              )),
          if (wo.items.isEmpty)
            const Text('No items.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ...wo.items.map((it) => _itemRow(it)),
          if (wo.items.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(widget.currency.format(wo.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _section('Payments',
              trailing: TextButton.icon(
                onPressed: _recordPayment,
                icon: const Icon(Icons.payments, size: 16),
                label: const Text('Record payment'),
              )),
          Row(
            children: [
              _fact('Committed', widget.currency.format(wo.totalAmount)),
              const SizedBox(width: 24),
              _fact('Paid to date', widget.currency.format(wo.paidToDate),
                  color: AppColors.success),
              const SizedBox(width: 24),
              _fact('Remaining',
                  widget.currency
                      .format((wo.totalAmount - wo.paidToDate).clamp(0, double.infinity)),
                  color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 20),
          _section('Signatures',
              trailing: TextButton.icon(
                onPressed: _addSignature,
                icon: const Icon(Icons.draw, size: 16),
                label: const Text('Add signature'),
              )),
          if (wo.signatures.isEmpty)
            const Text('Not signed yet.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ...wo.signatures.map((s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.draw, color: AppColors.success),
                  title: Text('${s.roleLabel}: ${s.signerName}'),
                  subtitle: Text(dateFmt.format(s.signedAt)),
                )),
          const SizedBox(height: 20),
          _section('History'),
          FutureBuilder<List<WorkOrderHistoryEvent>>(
            future: _historyFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  UserFacingError.uiMessage(snap.error,
                      action: 'load history'),
                  style: const TextStyle(color: AppColors.error),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Center(
                      child: SizedBox(
                          height: 18,
                          width: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              final events = snap.data!;
              if (events.isEmpty) {
                return const Text('No history yet.',
                    style: TextStyle(color: AppColors.textTertiary));
              }
              return Column(
                children: events
                    .map((e) => _historyRow(e, dateFmt))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _section(String label, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _factsGrid(WorkOrder wo, DateFormat fmt) {
    String dateOrDash(DateTime? d) => d == null ? '—' : fmt.format(d);
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _fact('Priority', wo.priority.label, color: wo.priority.color),
        _fact('Location', wo.location ?? '—'),
        _fact('Scheduled start', dateOrDash(wo.scheduledStart)),
        _fact('Scheduled end', dateOrDash(wo.scheduledEnd)),
        _fact('Started', dateOrDash(wo.startedAt)),
        _fact('Completed', dateOrDash(wo.completedAt)),
        _fact('Estimated hrs', wo.estimatedHours?.toString() ?? '—'),
        _fact('Total', widget.currency.format(wo.totalAmount)),
      ],
    );
  }

  Widget _fact(String label, String value, {Color? color}) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _statusActions(WorkOrder wo) {
    final transitions = _validTransitions(wo.status);
    if (transitions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: transitions
          .map((s) => OutlinedButton.icon(
                icon: Icon(Icons.circle, size: 10, color: s.color),
                label: Text('Move to ${s.label}'),
                onPressed: () => _setStatus(s),
              ))
          .toList(),
    );
  }

  List<WorkOrderStatus> _validTransitions(WorkOrderStatus s) {
    switch (s) {
      case WorkOrderStatus.draft:
        return [WorkOrderStatus.issued, WorkOrderStatus.cancelled];
      case WorkOrderStatus.issued:
        return [WorkOrderStatus.inProgress, WorkOrderStatus.onHold, WorkOrderStatus.cancelled];
      case WorkOrderStatus.inProgress:
        return [WorkOrderStatus.onHold, WorkOrderStatus.completed, WorkOrderStatus.cancelled];
      case WorkOrderStatus.onHold:
        return [WorkOrderStatus.inProgress, WorkOrderStatus.cancelled];
      case WorkOrderStatus.completed:
      case WorkOrderStatus.cancelled:
        return [];
    }
  }

  Future<void> _setStatus(WorkOrderStatus next) async {
    try {
      await ServiceLocator.workOrderService
          .setStatus(widget.workOrder.id, next);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'update status'))));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final noun =
        widget.workOrder.kind == 'rental' ? 'rental request' : 'work order';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $noun?'),
        content: Text(
            'Delete "${widget.workOrder.number}: ${widget.workOrder.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceLocator.workOrderService.delete(widget.workOrder.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                UserFacingError.uiMessage(e,
                    action:
                        'delete ${widget.workOrder.kind == 'rental' ? 'rental request' : 'work order'}'))));
      }
    }
  }

  Widget _itemRow(WorkOrderItem it) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.description),
                Text(
                  '${it.quantity} ${it.unit ?? ''} × ${widget.currency.format(it.unitCost)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Text(widget.currency.format(it.total),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () =>
                ServiceLocator.workOrderService.deleteItem(it.id, it.workOrderId),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem() async {
    final result = await showPoLineItemDialog(
      context,
      projectId: widget.workOrder.projectId,
      workspaceId: widget.workOrder.workspaceId,
      title: widget.workOrder.kind == 'rental'
          ? 'Add rental line'
          : 'Add material line',
    );
    if (result == null) return;
    try {
      await ServiceLocator.workOrderService.addItem(
        workOrderId: widget.workOrder.id,
        workspaceId: widget.workOrder.workspaceId,
        description: result.description,
        quantity: result.quantity,
        unit: result.unit,
        unitCost: result.unitCost,
        budgetItemId: result.budgetItemId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(UserFacingError.uiMessage(e, action: 'add item'))));
      }
    }
  }

  Future<void> _recordPayment() async {
    final ctl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Record payment'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                final v = double.tryParse(ctl.text.trim());
                Navigator.of(context).pop(v);
              },
              child: const Text('Record')),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      await ServiceLocator.workOrderService
          .recordPayment(widget.workOrder.id, amount);
      _refreshHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'record payment'))));
      }
    }
  }

  Future<void> _addSignature() async {
    String role = 'contractor';
    final pickedRole = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Signer role'),
        children: [
          for (final r in const ['contractor', 'client', 'vendor', 'witness'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(r[0].toUpperCase() + r.substring(1)),
            ),
        ],
      ),
    );
    if (pickedRole == null) return;
    role = pickedRole;

    if (!mounted) return;
    await SignatureDialog.show(
      context,
      title: 'Sign as ${role[0].toUpperCase()}${role.substring(1)}',
      requireEmail: false,
      onSign: (name, email, pngBytes) async {
        final url = await ServiceLocator.storageService.uploadSignature(
          signatureBytes: pngBytes,
          workspaceId: widget.workOrder.workspaceId,
          documentId: widget.workOrder.id,
        );
        await ServiceLocator.workOrderService.addSignature(
          workOrderId: widget.workOrder.id,
          workspaceId: widget.workOrder.workspaceId,
          role: role,
          signerName: name,
          signerEmail: email.isEmpty ? null : email,
          signatureUrl: url,
        );
        _refreshHistory();
      },
    );
  }

  Widget _historyRow(WorkOrderHistoryEvent e, DateFormat fmt) {
    IconData icon;
    Color color;
    switch (e.eventType) {
      case 'status_changed':
        icon = Icons.swap_horiz;
        color = AppColors.info;
        break;
      case 'signed':
        icon = Icons.draw;
        color = AppColors.success;
        break;
      case 'item_added':
        icon = Icons.add_circle_outline;
        color = AppColors.textSecondary;
        break;
      case 'payment_recorded':
        icon = Icons.payments;
        color = AppColors.success;
        break;
      case 'created':
        icon = Icons.add;
        color = AppColors.textSecondary;
        break;
      default:
        icon = Icons.circle;
        color = AppColors.textTertiary;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.message ?? e.eventType,
                    style: const TextStyle(fontSize: 13)),
                Text(fmt.format(e.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Line-item add dialog now lives in lib/widgets/forms/po_line_item_dialog.dart
// and is shared with the Subcontracts board to keep all three POs (Materials,
// Rentals, Subcontracts) visually and behaviorally consistent.
