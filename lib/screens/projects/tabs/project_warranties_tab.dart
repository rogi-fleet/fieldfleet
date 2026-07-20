import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/project_modules/warranty.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../utils/confirm_dialog.dart';
import '_project_modules_common.dart';
import '../../../theme/theme.dart';

class ProjectWarrantiesTab extends StatelessWidget {
  final Project project;
  const ProjectWarrantiesTab({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final wsId = context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (wsId == null) {
      return const PmEmptyState(icon: Icons.warning_amber,
        title: 'Workspace not loaded');
    }
    final svc = ServiceLocator.projectWarrantyServiceFor(
      workspaceId: wsId, projectId: project.id);
    return _WarrantiesView(svc: svc, projectId: project.id, workspaceId: wsId);
  }
}

class _WarrantiesView extends StatelessWidget {
  final ProjectWarrantyService svc;
  final String projectId;
  final String workspaceId;
  const _WarrantiesView({required this.svc, required this.projectId,
    required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text(
            'Track warranties given on this job for liability and follow-up',
            style: TextStyle(color: Colors.black54))),
          FilledButton.icon(onPressed: () => _add(context),
            icon: const Icon(Icons.add), label: const Text('Add warranty')),
        ]),
      ),
      Expanded(child: StreamBuilder<List<ProjectWarranty>>(
        stream: svc.watchWarranties(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return PmEmptyState(icon: Icons.verified_outlined,
              title: 'No warranties yet',
              subtitle: 'Add warranties for labor, materials, equipment or workmanship.',
              actionLabel: 'Add warranty', onAction: () => _add(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _warrantyCard(context, list[i]),
          );
        },
      )),
    ]);
  }

  Widget _warrantyCard(BuildContext context, ProjectWarranty w) {
    final days = w.daysRemaining;
    final isExpiring = days != null && days >= 0 && days <= 30;
    final statusForChip = w.isExpired ? 'expired' : (isExpiring ? 'expiring_soon' : w.status);
    return Card(elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ExpansionTile(
        leading: Icon(Icons.verified_outlined,
          color: pmStatusColor(statusForChip)),
        title: Text(w.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${labelize(w.warrantyType)}'
          '${w.providerName != null ? " · ${w.providerName}" : ""}'
          '\n${fmtPmDate(w.startsOn)} → ${fmtPmDate(w.endsOn)}'
          '${days != null ? "  (${days >= 0 ? "$days days left" : "expired"})" : ""}'),
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (w.claimCount > 0)
            PmStatusChip(label: '${w.claimCount} claim${w.claimCount == 1 ? "" : "s"}',
              color: pmStatusColor('claimed')),
          PmStatusChip(label: labelize(statusForChip), color: pmStatusColor(statusForChip)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') return _add(context, existing: w);
              if (v == 'claim') return _addClaim(context, w);
              if (v == 'void') return svc.updateWarranty(w.id, {'status': 'void'});
              if (v == 'reactivate') return svc.updateWarranty(w.id, {'status': 'active'});
              if (v == 'delete') return _confirmDelete(context, w);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'claim', child: Text('Log claim')),
              if (w.status != 'void')
                const PopupMenuItem(value: 'void', child: Text('Mark void'))
              else
                const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (w.beneficiary != null) _kv('Beneficiary', w.beneficiary!),
          if (w.referenceNo != null) _kv('Reference #', w.referenceNo!),
          if (w.coverageAmount != null)
            _kv('Coverage', '${w.currency} \$${w.coverageAmount!.toStringAsFixed(2)}'),
          if (w.description != null && w.description!.isNotEmpty)
            _kv('Description', w.description!),
          if (w.terms != null && w.terms!.isNotEmpty) _kv('Terms', w.terms!),
          if (w.notes != null && w.notes!.isNotEmpty) _kv('Notes', w.notes!),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft,
            child: Text('Claims', style: Theme.of(context).textTheme.titleSmall)),
          StreamBuilder<List<ProjectWarrantyClaim>>(
            stream: svc.watchClaims(w.id),
            builder: (_, s) {
              final claims = s.data ?? const [];
              if (claims.isEmpty) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text('No claims logged.', style: TextStyle(color: Colors.black54)));
              }
              return Column(children: claims.map((c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.report_problem_outlined,
                  color: pmStatusColor(c.status), size: 20),
                title: Text(c.description),
                subtitle: Text('${fmtPmDate(c.claimDate)}'
                  '${c.cost != null ? "  •  \$${c.cost!.toStringAsFixed(2)}" : ""}'
                  '${c.resolution != null ? "\n${c.resolution}" : ""}'),
                isThreeLine: c.resolution != null,
                trailing: Wrap(spacing: 4, children: [
                  PmStatusChip(label: labelize(c.status), color: pmStatusColor(c.status)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Update',
                    onPressed: () => _editClaim(context, c)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    onPressed: () => svc.deleteClaim(c.id)),
                ]),
              )).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: RichText(text: TextSpan(
      style: const TextStyle(color: Colors.black87, fontSize: 13),
      children: [
        TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: v),
      ])));

  Future<void> _confirmDelete(BuildContext context, ProjectWarranty w) async {
    final ok = await confirmDestructive(context,
      title: 'Delete warranty?',
      message: 'Permanently delete "${w.title}" and all its claims?');
    if (ok) await svc.deleteWarranty(w.id);
  }

  Future<void> _add(BuildContext context, {ProjectWarranty? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title);
    final providerCtrl = TextEditingController(text: existing?.providerName);
    final beneficiaryCtrl = TextEditingController(text: existing?.beneficiary);
    final descCtrl = TextEditingController(text: existing?.description);
    final termsCtrl = TextEditingController(text: existing?.terms);
    final amountCtrl = TextEditingController(
      text: existing?.coverageAmount?.toStringAsFixed(2) ?? '');
    final refCtrl = TextEditingController(text: existing?.referenceNo);
    final notesCtrl = TextEditingController(text: existing?.notes);
    String wType = existing?.warrantyType ?? 'workmanship';
    DateTime? startsOn = existing?.startsOn ?? DateTime.now();
    DateTime? endsOn = existing?.endsOn ??
      DateTime.now().add(const Duration(days: 365));

    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add warranty' : 'Edit warranty'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 480,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Title *')),
          DropdownButtonFormField<String>(
            initialValue: wType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const ['workmanship', 'labor', 'materials', 'equipment',
              'manufacturer', 'extended', 'other']
              .map((t) => DropdownMenuItem(value: t, child: Text(labelize(t))))
              .toList(),
            onChanged: (v) => setSt(() => wType = v ?? wType)),
          TextField(controller: providerCtrl,
            decoration: const InputDecoration(labelText: 'Provider (vendor / contractor)')),
          TextField(controller: beneficiaryCtrl,
            decoration: const InputDecoration(labelText: 'Beneficiary (client/owner)')),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async {
              final d = await pickPmDate(ctx, initial: startsOn);
              if (d != null) setSt(() => startsOn = d);
            }, child: Text('Starts: ${fmtPmDate(startsOn)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () async {
              final d = await pickPmDate(ctx, initial: endsOn);
              if (d != null) setSt(() => endsOn = d);
            }, child: Text('Ends: ${fmtPmDate(endsOn)}'))),
          ]),
          TextField(controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Coverage amount (optional)')),
          TextField(controller: refCtrl,
            decoration: const InputDecoration(labelText: 'Reference / certificate #')),
          TextField(controller: descCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: termsCtrl, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Terms / conditions')),
          TextField(controller: notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Internal notes')),
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (titleCtrl.text.trim().isEmpty) return;
          final amount = double.tryParse(amountCtrl.text.trim());
          if (existing == null) {
            await svc.createWarranty(ProjectWarranty(
              id: '', workspaceId: workspaceId, projectId: projectId,
              title: titleCtrl.text.trim(),
              warrantyType: wType,
              providerName: _nullable(providerCtrl.text),
              beneficiary: _nullable(beneficiaryCtrl.text),
              description: _nullable(descCtrl.text),
              terms: _nullable(termsCtrl.text),
              coverageAmount: amount,
              startsOn: startsOn, endsOn: endsOn,
              referenceNo: _nullable(refCtrl.text),
              notes: _nullable(notesCtrl.text),
            ));
          } else {
            await svc.updateWarranty(existing.id, {
              'title': titleCtrl.text.trim(),
              'warranty_type': wType,
              'provider_name': _nullable(providerCtrl.text),
              'beneficiary': _nullable(beneficiaryCtrl.text),
              'description': _nullable(descCtrl.text),
              'terms': _nullable(termsCtrl.text),
              'coverage_amount': amount,
              'starts_on': startsOn?.toIso8601String().substring(0, 10),
              'ends_on': endsOn?.toIso8601String().substring(0, 10),
              'reference_no': _nullable(refCtrl.text),
              'notes': _nullable(notesCtrl.text),
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  Future<void> _addClaim(BuildContext context, ProjectWarranty w) async {
    final descCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    DateTime claimDate = DateTime.now();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Log claim — ${w.title}'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton(onPressed: () async {
            final d = await pickPmDate(ctx, initial: claimDate);
            if (d != null) setSt(() => claimDate = d);
          }, child: Text('Claim date: ${fmtPmDate(claimDate)}')),
          TextField(controller: descCtrl, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description *')),
          TextField(controller: costCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cost (optional)')),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (descCtrl.text.trim().isEmpty) return;
          await svc.createClaim(ProjectWarrantyClaim(
            id: '', workspaceId: workspaceId, warrantyId: w.id,
            claimDate: claimDate, description: descCtrl.text.trim(),
            cost: double.tryParse(costCtrl.text.trim())));
          await svc.updateWarranty(w.id, {'status': 'claimed'});
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  Future<void> _editClaim(BuildContext context, ProjectWarrantyClaim c) async {
    final resolutionCtrl = TextEditingController(text: c.resolution);
    String status = c.status;
    DateTime? resolvedAt = c.resolvedAt;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Update claim'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const ['open', 'in_progress', 'resolved', 'denied']
              .map((s) => DropdownMenuItem(value: s, child: Text(labelize(s)))).toList(),
            onChanged: (v) => setSt(() => status = v ?? status)),
          TextField(controller: resolutionCtrl, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Resolution')),
          if (status == 'resolved' || status == 'denied')
            OutlinedButton(onPressed: () async {
              final d = await pickPmDate(ctx, initial: resolvedAt ?? DateTime.now());
              if (d != null) setSt(() => resolvedAt = d);
            }, child: Text('Resolved: ${fmtPmDate(resolvedAt)}')),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          await svc.updateClaim(c.id, {
            'status': status,
            'resolution': _nullable(resolutionCtrl.text),
            'resolved_at': resolvedAt?.toIso8601String().substring(0, 10),
          });
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
}
