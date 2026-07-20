/// Internal board for change orders on a project.
///
/// First-class screen for the `DocumentType.changeOrder` document type.
/// Status columns (Draft, Sent, Approved, Declined). Cards expose quick
/// actions for send / approve / decline and a link into the full document
/// detail screen for editing, PDF, and portal signing. Approved change
/// orders automatically roll up into the project budget via
/// SupabaseDocumentService.approveDocument → applyChangeOrderToBudget.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/document_status.dart';
import '../../../models/document_type.dart';
import '../../../models/generated_document.dart';
import '../../../models/project.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/common/status_chip.dart';

/// Buckets the full DocumentStatus enum down to the 4 lifecycle stages we
/// surface on the kanban board.
enum ChangeOrderStage { draft, sent, approved, declined }

extension ChangeOrderStageX on ChangeOrderStage {
  String get label {
    switch (this) {
      case ChangeOrderStage.draft:
        return 'Draft';
      case ChangeOrderStage.sent:
        return 'Sent';
      case ChangeOrderStage.approved:
        return 'Approved';
      case ChangeOrderStage.declined:
        return 'Declined';
    }
  }

  Color get color {
    switch (this) {
      case ChangeOrderStage.draft:
        return AppColors.textTertiary;
      case ChangeOrderStage.sent:
        return AppColors.info;
      case ChangeOrderStage.approved:
        return AppColors.success;
      case ChangeOrderStage.declined:
        return AppColors.error;
    }
  }
}

ChangeOrderStage stageFor(DocumentStatus s) {
  switch (s) {
    case DocumentStatus.draft:
    case DocumentStatus.pending:
    case DocumentStatus.changesRequested:
      return ChangeOrderStage.draft;
    case DocumentStatus.sent:
    case DocumentStatus.viewed:
      return ChangeOrderStage.sent;
    case DocumentStatus.signed:
    case DocumentStatus.approved:
    case DocumentStatus.applied:
      return ChangeOrderStage.approved;
    case DocumentStatus.denied:
    case DocumentStatus.notSelected:
    case DocumentStatus.withdrawn:
      return ChangeOrderStage.declined;
    case DocumentStatus.responded:
      return ChangeOrderStage.sent;
  }
}

class ProjectChangeOrdersTab extends StatefulWidget {
  final Project project;
  const ProjectChangeOrdersTab({super.key, required this.project});

  @override
  State<ProjectChangeOrdersTab> createState() =>
      _ProjectChangeOrdersTabState();
}

class _ProjectChangeOrdersTabState extends State<ProjectChangeOrdersTab> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.MMMd();

  Stream<List<GeneratedDocument>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    _stream = ServiceLocator.documentService.getDocuments(
      workspaceId,
      projectId: widget.project.id,
      documentType: DocumentType.changeOrder,
    ) as Stream<List<GeneratedDocument>>;
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) {
      return const Scaffold(
        body: Center(child: Text('No workspace selected.')),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChangeOrder,
        icon: const Icon(Icons.add),
        label: const Text('New change order'),
      ),
      body: StreamBuilder<List<GeneratedDocument>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(UserFacingError.uiMessage(snap.error,
                  action: 'load change orders')),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cos = snap.data!;
          return Column(
            children: [
              ChangeOrderSummaryStrip(orders: cos, currency: _currency),
              const Divider(height: 1),
              Expanded(child: _buildBoard(cos)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoard(List<GeneratedDocument> all) {
    final grouped = <ChangeOrderStage, List<GeneratedDocument>>{
      for (final s in ChangeOrderStage.values) s: [],
    };
    for (final d in all) {
      grouped[stageFor(d.status)]!.add(d);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in ChangeOrderStage.values)
            ChangeOrderColumn(
              stage: s,
              items: grouped[s]!,
              currency: _currency,
              dateFmt: _dateFmt,
              onTap: (d) => context.push('/documents/${d.id}'),
              onSend: _send,
              onApprove: _approve,
              onDecline: _decline,
            ),
        ],
      ),
    );
  }

  Future<void> _newChangeOrder() async {
    context.push(
      '/documents/create?projectId=${widget.project.id}'
      '&prefer_type=${DocumentType.changeOrder.dbValue}',
    );
  }

  Future<void> _send(GeneratedDocument d) async {
    final email = TextEditingController(text: d.sentTo ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send change order'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration:
                const InputDecoration(labelText: 'Recipient email *'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (result != true || email.text.trim().isEmpty) return;
    try {
      await ServiceLocator.documentService.sendDocument(
        documentId: d.id,
        email: email.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Change order sent.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'send change order'))));
      }
    }
  }

  Future<void> _approve(GeneratedDocument d) async {
    final user = context.read<AuthProvider>().appUser;
    final approver = user?.displayName ?? user?.email ?? user?.id ?? 'unknown';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve change order?'),
        content: Text(
            'Approving "${d.templateName}" will roll its line items (${_currency.format(d.totalAmount)}) into the project budget. This cannot be undone in one click — you would need to delete the rolled-up budget rows manually.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceLocator.documentService.approveDocument(
        documentId: d.id,
        approvedBy: approver,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Approved and rolled into budget.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'approve change order'))));
      }
    }
  }

  Future<void> _decline(GeneratedDocument d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline change order?'),
        content: Text(
            'Mark "${d.templateName}" as declined. The document stays on file but is excluded from the budget.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final user = context.read<AuthProvider>().appUser;
    final actor = user?.displayName ?? user?.email ?? user?.id ?? 'unknown';
    try {
      await ServiceLocator.documentService.declineDocument(
        documentId: d.id,
        declinedBy: actor,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Change order declined.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(UserFacingError.uiMessage(e,
                action: 'decline change order'))));
      }
    }
  }
}

// ───────────────────────────── Summary strip ────────────────────────────────

class ChangeOrderSummaryStrip extends StatelessWidget {
  final List<GeneratedDocument> orders;
  final NumberFormat currency;
  const ChangeOrderSummaryStrip(
      {super.key, required this.orders, required this.currency});

  @override
  Widget build(BuildContext context) {
    double approved = 0;
    double pending = 0;
    double declined = 0;
    var countApproved = 0;
    var countPending = 0;
    var countDeclined = 0;
    for (final d in orders) {
      switch (stageFor(d.status)) {
        case ChangeOrderStage.approved:
          approved += d.totalAmount;
          countApproved++;
          break;
        case ChangeOrderStage.sent:
        case ChangeOrderStage.draft:
          pending += d.totalAmount;
          countPending++;
          break;
        case ChangeOrderStage.declined:
          declined += d.totalAmount;
          countDeclined++;
          break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      color: AppColors.surface,
      child: Row(
        children: [
          _kpi('Budget impact', currency.format(approved),
              color: AppColors.success),
          const SizedBox(width: 24),
          _kpi('Pending', currency.format(pending), color: AppColors.info),
          const SizedBox(width: 24),
          _kpi('Declined', currency.format(declined),
              color: AppColors.error),
          const Spacer(),
          Text(
            '${orders.length} total · '
            '$countApproved approved · '
            '$countPending pending · '
            '$countDeclined declined',
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

// ───────────────────────────── Column ───────────────────────────────────────

class ChangeOrderColumn extends StatelessWidget {
  final ChangeOrderStage stage;
  final List<GeneratedDocument> items;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final ValueChanged<GeneratedDocument> onTap;
  final ValueChanged<GeneratedDocument> onSend;
  final ValueChanged<GeneratedDocument> onApprove;
  final ValueChanged<GeneratedDocument> onDecline;

  const ChangeOrderColumn({
    super.key,
    required this.stage,
    required this.items,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
    required this.onSend,
    required this.onApprove,
    required this.onDecline,
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
              color: stage.color.withOpacity(0.10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: stage.color),
                const SizedBox(width: 8),
                Text(stage.label,
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
                    itemBuilder: (_, i) => _ChangeOrderCard(
                      doc: items[i],
                      stage: stage,
                      currency: currency,
                      dateFmt: dateFmt,
                      onTap: () => onTap(items[i]),
                      onSend: () => onSend(items[i]),
                      onApprove: () => onApprove(items[i]),
                      onDecline: () => onDecline(items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChangeOrderCard extends StatelessWidget {
  final GeneratedDocument doc;
  final ChangeOrderStage stage;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback onSend;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const _ChangeOrderCard({
    required this.doc,
    required this.stage,
    required this.currency,
    required this.dateFmt,
    required this.onTap,
    required this.onSend,
    required this.onApprove,
    required this.onDecline,
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
                Expanded(
                  child: Text(
                    doc.templateName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: doc.status),
              ],
            ),
            if ((doc.sentTo ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('To: ${doc.sentTo}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_money,
                    size: 14, color: AppColors.textTertiary),
                Text(currency.format(doc.totalAmount),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                Text(dateFmt.format(doc.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
            if (stage != ChangeOrderStage.approved &&
                stage != ChangeOrderStage.declined) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (stage == ChangeOrderStage.draft)
                    _miniButton(Icons.send, 'Send', onSend, AppColors.info),
                  if (stage == ChangeOrderStage.sent)
                    _miniButton(Icons.send, 'Resend', onSend, AppColors.info),
                  const SizedBox(width: 6),
                  _miniButton(Icons.check, 'Approve', onApprove,
                      AppColors.success),
                  const SizedBox(width: 6),
                  _miniButton(Icons.close, 'Decline', onDecline,
                      AppColors.error),
                ],
              ),
            ],
            if (stage == ChangeOrderStage.approved &&
                doc.pdfUrl != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.picture_as_pdf,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('PDF available',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniButton(
      IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

}

class _StatusChip extends StatelessWidget {
  final DocumentStatus status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: status.displayName,
      color: stageFor(status).color,
      size: StatusChipSize.compact,
    );
  }
}

