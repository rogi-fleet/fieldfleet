/// Internal board for subcontracts on a project.
///
/// Vendor-issued contract records with lifecycle (Draft → Sent → Signed →
/// Active → Completed), multi-party signatures, payment tracking, insurance
/// verification, and full history.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/subcontract.dart';
import '../../../models/vendor.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/forms/po_line_item_dialog.dart';
import '../../../widgets/forms/signature_dialog.dart';

class ProjectSubcontractsTab extends StatefulWidget {
  final Project project;
  const ProjectSubcontractsTab({super.key, required this.project});

  @override
  State<ProjectSubcontractsTab> createState() =>
      _ProjectSubcontractsTabState();
}

class _ProjectSubcontractsTabState extends State<ProjectSubcontractsTab> {
  late final Stream<List<Subcontract>> _stream =
      ServiceLocator.subcontractService.watchByProject(widget.project.id);

  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.MMMd();

  Map<String, Vendor> _vendorsById = {};
  StreamSubscription<List<Vendor>>? _vendorSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vendorSub != null) return;
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final stream = ServiceLocator.vendorService.getVendors(workspaceId)
        as Stream<List<Vendor>>;
    _vendorSub = stream.listen((vendors) {
      if (!mounted) return;
      setState(() {
        _vendorsById = {for (final v in vendors) v.id: v};
      });
    });
  }

  @override
  void dispose() {
    _vendorSub?.cancel();
    super.dispose();
  }

  static const _columns = <SubcontractStatus>[
    SubcontractStatus.draft,
    SubcontractStatus.sent,
    SubcontractStatus.signed,
    SubcontractStatus.active,
    SubcontractStatus.completed,
    SubcontractStatus.terminated,
    SubcontractStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSubcontract,
        icon: const Icon(Icons.add),
        label: const Text('New subcontract'),
      ),
      body: StreamBuilder<List<Subcontract>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text(UserFacingError.uiMessage(snap.error,
                    action: 'load subcontracts')));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          final summary =
              ServiceLocator.subcontractService.summarise(list);

          return Column(
            children: [
              _SummaryStrip(summary: summary, currency: _currency),
              const Divider(height: 1),
              Expanded(child: _buildBoard(list)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<Subcontract> all) {
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
              vendorsById: _vendorsById,
              currency: _currency,
              dateFmt: _dateFmt,
              onTap: _openDetail,
            ),
        ],
      ),
    );
  }

  Future<void> _createSubcontract() async {
    // Subcontracts now start life as a Request for Bid document scoped
    // to this project; the subcontract record itself is materialized
    // downstream when the document is finalized. Send the user straight
    // to the document creator with the right template pre-selected.
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

  Future<void> _openDetail(Subcontract s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => SubcontractDetailSheet(
          subcontract: s,
          vendor: _vendorsById[s.vendorId],
          scrollController: controller,
          currency: _currency,
        ),
      ),
    );
  }
}

// ───────────────────────────── Summary strip ────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final SubcontractSummary summary;
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
              '${summary.countTotal} total · ${summary.countActive} active · ${summary.countCompleted} done',
              style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
  final SubcontractStatus status;
  final List<Subcontract> items;
  final Map<String, Vendor> vendorsById;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final ValueChanged<Subcontract> onTap;

  const _Column({
    required this.status,
    required this.items,
    required this.vendorsById,
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
                      sc: items[i],
                      vendor: vendorsById[items[i].vendorId],
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
  final Subcontract sc;
  final Vendor? vendor;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onTap;

  const _Card({
    required this.sc,
    required this.vendor,
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
                Text(sc.number,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (sc.insuranceRequired && !sc.insuranceVerified)
                  Tooltip(
                    message: 'Insurance not verified',
                    child: Icon(Icons.warning_amber,
                        size: 14, color: AppColors.warning),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(sc.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(vendor?.companyName ?? 'Unknown vendor',
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_money,
                    size: 14, color: AppColors.textTertiary),
                Text(currency.format(sc.contractAmount),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                if (sc.endDate != null) ...[
                  Icon(Icons.event,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 2),
                  Text(dateFmt.format(sc.endDate!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ],
            ),
            if (sc.contractAmount > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (sc.paidToDate / sc.contractAmount).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.background,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Detail sheet ─────────────────────────────────

class SubcontractDetailSheet extends StatefulWidget {
  final Subcontract subcontract;
  final Vendor? vendor;
  final ScrollController scrollController;
  final NumberFormat currency;
  const SubcontractDetailSheet({
    super.key,
    required this.subcontract,
    required this.vendor,
    required this.scrollController,
    required this.currency,
  });

  @override
  State<SubcontractDetailSheet> createState() =>
      _SubcontractDetailSheetState();
}

class _SubcontractDetailSheetState extends State<SubcontractDetailSheet> {
  late Future<List<SubcontractHistoryEvent>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture =
        ServiceLocator.subcontractService.historyFor(widget.subcontract.id);
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = ServiceLocator.subcontractService
          .historyFor(widget.subcontract.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sc = widget.subcontract;
    final dateFmt = DateFormat.yMMMd();
    final dateTimeFmt = DateFormat.yMMMd().add_jm();
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
                  color: sc.status.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(sc.status.label,
                    style: TextStyle(
                        color: sc.status.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(sc.number,
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
          Text(sc.title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(widget.vendor?.companyName ?? 'Unknown vendor',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          if ((sc.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(sc.description!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          _statusActions(sc),
          const SizedBox(height: 16),
          _factsGrid(sc, dateFmt),
          const SizedBox(height: 20),
          _section('Scope of work'),
          if ((sc.scopeOfWork ?? '').isEmpty)
            const Text('No scope specified.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            Text(sc.scopeOfWork!),
          const SizedBox(height: 20),
          _section('Line items',
              trailing: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add item'),
              )),
          if (sc.items.isEmpty)
            const Text('No items.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ...sc.items.map((it) => _itemRow(it)),
          if (sc.items.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(widget.currency.format(sc.contractAmount),
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
              _fact('Paid to date', widget.currency.format(sc.paidToDate),
                  color: AppColors.success),
              const SizedBox(width: 24),
              _fact('Remaining', widget.currency.format(sc.remaining),
                  color: AppColors.warning),
              const SizedBox(width: 24),
              _fact('Retainage', '${sc.retainagePercent.toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: 20),
          _section('Insurance'),
          Row(
            children: [
              Icon(
                sc.insuranceVerified
                    ? Icons.verified
                    : (sc.insuranceRequired
                        ? Icons.warning_amber
                        : Icons.do_not_disturb_on_outlined),
                color: sc.insuranceVerified
                    ? AppColors.success
                    : (sc.insuranceRequired
                        ? AppColors.warning
                        : AppColors.textTertiary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sc.insuranceVerified
                      ? 'Verified on ${sc.insuranceVerifiedAt != null ? dateFmt.format(sc.insuranceVerifiedAt!) : 'unknown date'}'
                      : (sc.insuranceRequired
                          ? 'Required but not verified'
                          : 'Not required'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              if (sc.insuranceRequired && !sc.insuranceVerified)
                TextButton(
                  onPressed: _markInsuranceVerified,
                  child: const Text('Mark verified'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _section('Signatures',
              trailing: TextButton.icon(
                onPressed: _addSignature,
                icon: const Icon(Icons.draw, size: 16),
                label: const Text('Add signature'),
              )),
          if (sc.signatures.isEmpty)
            const Text('Not signed yet.',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ...sc.signatures.map((s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.draw, color: AppColors.success),
                  title: Text('${s.roleLabel}: ${s.signerName}'),
                  subtitle: Text(dateTimeFmt.format(s.signedAt)),
                )),
          const SizedBox(height: 20),
          _section('History'),
          FutureBuilder<List<SubcontractHistoryEvent>>(
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
                children:
                    events.map((e) => _historyRow(e, dateTimeFmt)).toList(),
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

  Widget _factsGrid(Subcontract sc, DateFormat fmt) {
    String dateOrDash(DateTime? d) => d == null ? '—' : fmt.format(d);
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _fact('Contract amount', widget.currency.format(sc.contractAmount)),
        _fact('Start', dateOrDash(sc.startDate)),
        _fact('End', dateOrDash(sc.endDate)),
        _fact('Sent', dateOrDash(sc.sentAt)),
        _fact('Signed', dateOrDash(sc.signedAt)),
        _fact('Completed', dateOrDash(sc.completedAt)),
        _fact('Payment terms', sc.paymentTerms ?? '—'),
      ],
    );
  }

  Widget _fact(String label, String value, {Color? color}) {
    return SizedBox(
      width: 160,
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

  Widget _statusActions(Subcontract sc) {
    final transitions = _validTransitions(sc.status);
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

  List<SubcontractStatus> _validTransitions(SubcontractStatus s) {
    switch (s) {
      case SubcontractStatus.draft:
        return [SubcontractStatus.sent, SubcontractStatus.cancelled];
      case SubcontractStatus.sent:
        return [SubcontractStatus.signed, SubcontractStatus.cancelled];
      case SubcontractStatus.signed:
        return [SubcontractStatus.active, SubcontractStatus.terminated];
      case SubcontractStatus.active:
        return [
          SubcontractStatus.completed,
          SubcontractStatus.terminated,
        ];
      case SubcontractStatus.completed:
      case SubcontractStatus.terminated:
      case SubcontractStatus.cancelled:
        return [];
    }
  }

  Future<void> _setStatus(SubcontractStatus next) async {
    try {
      await ServiceLocator.subcontractService
          .setStatus(widget.subcontract.id, next);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'update status'))));
      }
    }
  }

  Future<void> _markInsuranceVerified() async {
    try {
      await ServiceLocator.subcontractService
          .markInsuranceVerified(widget.subcontract.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'mark insurance verified'))));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete subcontract?'),
        content: Text(
            'Delete "${widget.subcontract.number}: ${widget.subcontract.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceLocator.subcontractService.delete(widget.subcontract.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'delete subcontract'))));
      }
    }
  }

  Widget _itemRow(SubcontractItem it) {
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
            onPressed: () => ServiceLocator.subcontractService
                .deleteItem(it.id, it.subcontractId),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem() async {
    final result = await showPoLineItemDialog(
      context,
      projectId: widget.subcontract.projectId,
      workspaceId: widget.subcontract.workspaceId,
      title: 'Add subcontract line',
    );
    if (result == null) return;
    try {
      await ServiceLocator.subcontractService.addItem(
        subcontractId: widget.subcontract.id,
        workspaceId: widget.subcontract.workspaceId,
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
      await ServiceLocator.subcontractService
          .recordPayment(widget.subcontract.id, amount);
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
    final pickedRole = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Signer role'),
        children: [
          for (final r in const ['contractor', 'vendor', 'client', 'witness'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(r[0].toUpperCase() + r.substring(1)),
            ),
        ],
      ),
    );
    if (pickedRole == null) return;
    if (!mounted) return;
    await SignatureDialog.show(
      context,
      title:
          'Sign as ${pickedRole[0].toUpperCase()}${pickedRole.substring(1)}',
      requireEmail: false,
      onSign: (name, email, pngBytes) async {
        final url = await ServiceLocator.storageService.uploadSignature(
          signatureBytes: pngBytes,
          workspaceId: widget.subcontract.workspaceId,
          documentId: widget.subcontract.id,
        );
        await ServiceLocator.subcontractService.addSignature(
          subcontractId: widget.subcontract.id,
          workspaceId: widget.subcontract.workspaceId,
          role: pickedRole,
          signerName: name,
          signerEmail: email.isEmpty ? null : email,
          signatureUrl: url,
        );
        _refreshHistory();
      },
    );
  }

  Widget _historyRow(SubcontractHistoryEvent e, DateFormat fmt) {
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
// and is shared with the work-orders board.
