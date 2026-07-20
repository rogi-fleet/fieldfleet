import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/project_modules/inspection.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../utils/confirm_dialog.dart';
import '_project_modules_common.dart';
import '../../../theme/theme.dart';

class ProjectInspectionsTab extends StatelessWidget {
  final Project project;
  const ProjectInspectionsTab({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final wsId = context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (wsId == null) {
      return const PmEmptyState(icon: Icons.warning_amber,
        title: 'Workspace not loaded');
    }
    final svc = ServiceLocator.projectInspectionServiceFor(
      workspaceId: wsId, projectId: project.id);
    return _InspectionsView(svc: svc, projectId: project.id, workspaceId: wsId);
  }
}

class _InspectionsView extends StatelessWidget {
  final ProjectInspectionService svc;
  final String projectId;
  final String workspaceId;
  const _InspectionsView({required this.svc, required this.projectId,
    required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text(
            'Schedule and run inspections with checklists, results and signatures',
            style: TextStyle(color: Colors.black54))),
          FilledButton.icon(onPressed: () => _add(context),
            icon: const Icon(Icons.add), label: const Text('New inspection')),
        ]),
      ),
      Expanded(child: StreamBuilder<List<ProjectInspection>>(
        stream: svc.watchInspections(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return PmEmptyState(icon: Icons.checklist_rtl_outlined,
              title: 'No inspections yet',
              subtitle: 'Create checklist-based inspections for safety, quality, code, or punch.',
              actionLabel: 'New inspection', onAction: () => _add(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _inspectionCard(context, list[i]),
          );
        },
      )),
    ]);
  }

  Widget _inspectionCard(BuildContext context, ProjectInspection i) {
    final scoreText = i.score != null ? '${i.score!.toStringAsFixed(0)}%' : '—';
    return Card(elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ListTile(
        leading: Icon(Icons.checklist_rtl, color: pmStatusColor(i.status)),
        title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${labelize(i.inspectionType)}'
          '${i.location != null ? " · ${i.location}" : ""}'
          '${i.scheduledFor != null ? "\nScheduled: ${fmtPmDateTime(i.scheduledFor)}" : ""}'
          '${i.totalItems > 0 ? "\n${i.passCount} pass · ${i.failCount} fail · score $scoreText" : ""}'),
        isThreeLine: true,
        onTap: () => _openDetail(context, i),
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PmStatusChip(label: labelize(i.status), color: pmStatusColor(i.status)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'open') return _openDetail(context, i);
              if (v == 'edit') return _add(context, existing: i);
              if (v == 'pass') return svc.updateInspection(i.id, {
                'status': 'passed',
                'performed_at': DateTime.now().toIso8601String(),
              });
              if (v == 'fail') return svc.updateInspection(i.id, {
                'status': 'failed',
                'performed_at': DateTime.now().toIso8601String(),
              });
              if (v == 'followup') return svc.updateInspection(i.id, {
                'status': 'requires_followup',
              });
              if (v == 'delete') return _confirmDelete(context, i);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open checklist')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'pass', child: Text('Mark passed')),
              const PopupMenuItem(value: 'fail', child: Text('Mark failed')),
              const PopupMenuItem(value: 'followup', child: Text('Requires follow-up')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ProjectInspection i) async {
    final ok = await confirmDestructive(context,
      title: 'Delete inspection?',
      message: 'Delete "${i.name}" and all its checklist items?');
    if (ok) await svc.deleteInspection(i.id);
  }

  Future<void> _add(BuildContext context, {ProjectInspection? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final locCtrl = TextEditingController(text: existing?.location);
    final inspectorCtrl = TextEditingController(text: existing?.inspectorName);
    final companyCtrl = TextEditingController(text: existing?.inspectorCompany);
    final notesCtrl = TextEditingController(text: existing?.notes);
    String type = existing?.inspectionType ?? 'quality';
    DateTime? scheduled = existing?.scheduledFor ?? DateTime.now().add(const Duration(days: 1));

    // Optional preset checklist for new inspections
    String? presetTemplate;

    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New inspection' : 'Edit inspection'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 480,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Name *')),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const ['pre_construction', 'progress', 'punch', 'final',
              'safety', 'quality', 'code', 'warranty', 'other']
              .map((t) => DropdownMenuItem(value: t, child: Text(labelize(t)))).toList(),
            onChanged: (v) => setSt(() => type = v ?? type)),
          TextField(controller: locCtrl,
            decoration: const InputDecoration(labelText: 'Location / area')),
          OutlinedButton(onPressed: () async {
            final d = await pickPmDate(ctx, initial: scheduled);
            if (d != null) setSt(() => scheduled = d);
          }, child: Text('Scheduled: ${fmtPmDate(scheduled)}')),
          TextField(controller: inspectorCtrl,
            decoration: const InputDecoration(labelText: 'Inspector name')),
          TextField(controller: companyCtrl,
            decoration: const InputDecoration(labelText: 'Inspector company / agency')),
          TextField(controller: notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes')),
          if (existing == null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: presetTemplate,
              decoration: const InputDecoration(labelText: 'Start with template (optional)'),
              items: const [
                DropdownMenuItem(value: null, child: Text('— none —')),
                DropdownMenuItem(value: 'safety', child: Text('Safety walkthrough')),
                DropdownMenuItem(value: 'quality', child: Text('Quality / workmanship')),
                DropdownMenuItem(value: 'final', child: Text('Final / punch walkthrough')),
              ],
              onChanged: (v) => setSt(() => presetTemplate = v)),
          ],
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (nameCtrl.text.trim().isEmpty) return;
          if (existing == null) {
            final created = await svc.createInspection(ProjectInspection(
              id: '', workspaceId: workspaceId, projectId: projectId,
              name: nameCtrl.text.trim(),
              inspectionType: type,
              location: _nullable(locCtrl.text),
              scheduledFor: scheduled,
              inspectorName: _nullable(inspectorCtrl.text),
              inspectorCompany: _nullable(companyCtrl.text),
              notes: _nullable(notesCtrl.text),
            ));
            if (presetTemplate != null) {
              final items = _templateItems(presetTemplate!, created.id);
              await svc.addItems(items);
            }
          } else {
            await svc.updateInspection(existing.id, {
              'name': nameCtrl.text.trim(),
              'inspection_type': type,
              'location': _nullable(locCtrl.text),
              'scheduled_for': scheduled?.toIso8601String(),
              'inspector_name': _nullable(inspectorCtrl.text),
              'inspector_company': _nullable(companyCtrl.text),
              'notes': _nullable(notesCtrl.text),
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  List<ProjectInspectionItem> _templateItems(String template, String inspectionId) {
    Map<String, List<String>> groups;
    switch (template) {
      case 'safety':
        groups = {
          'PPE': ['Hard hats worn', 'Eye protection in use', 'High-vis vests on'],
          'Site': ['Walkways clear', 'Fire extinguishers accessible',
            'First aid kit stocked', 'Emergency exits unobstructed'],
          'Equipment': ['Ladders inspected', 'Power tools have guards',
            'Scaffolding tagged'],
        };
        break;
      case 'quality':
        groups = {
          'Framing': ['Framing plumb and square', 'Connectors per spec'],
          'Drywall': ['Joints taped and finished', 'Corners straight'],
          'Paint': ['Coverage uniform', 'No drips or runs'],
          'Trim': ['Mitres tight', 'Caulking complete'],
        };
        break;
      case 'final':
      default:
        groups = {
          'Exterior': ['Siding installed correctly', 'Caulking complete',
            'Site cleaned'],
          'Interior': ['All trim installed', 'All doors operate',
            'Hardware installed'],
          'Mechanical': ['HVAC tested', 'Plumbing fixtures operate',
            'Electrical outlets tested'],
          'Cleanup': ['Dust removed', 'Trash removed', 'Touch-up paint complete'],
        };
        break;
    }
    var sort = 0;
    final items = <ProjectInspectionItem>[];
    groups.forEach((cat, labels) {
      for (final lbl in labels) {
        items.add(ProjectInspectionItem(
          id: '', workspaceId: workspaceId, inspectionId: inspectionId,
          category: cat, label: lbl, sortOrder: sort++));
      }
    });
    return items;
  }

  void _openDetail(BuildContext context, ProjectInspection inspection) {
    showDialog<void>(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: SizedBox(width: 720, height: 600,
        child: _InspectionDetail(svc: svc, inspection: inspection,
          workspaceId: workspaceId)),
    ));
  }

  String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
}

class _InspectionDetail extends StatelessWidget {
  final ProjectInspectionService svc;
  final ProjectInspection inspection;
  final String workspaceId;
  const _InspectionDetail({required this.svc, required this.inspection,
    required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inspection.name, style: Theme.of(context).textTheme.titleLarge),
            Text('${labelize(inspection.inspectionType)}'
              '${inspection.location != null ? " · ${inspection.location}" : ""}',
              style: Theme.of(context).textTheme.bodySmall),
          ])),
          PmStatusChip(label: labelize(inspection.status),
            color: pmStatusColor(inspection.status)),
          IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close)),
        ])),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: () => _addItem(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item')),
        ])),
      Expanded(child: StreamBuilder<List<ProjectInspectionItem>>(
        stream: svc.watchItems(inspection.id),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const PmEmptyState(icon: Icons.checklist,
              title: 'No checklist items',
              subtitle: 'Add items or pick a template when creating an inspection.');
          }
          // Group by category
          final groups = <String, List<ProjectInspectionItem>>{};
          for (final it in items) {
            groups.putIfAbsent(it.category ?? 'General', () => []).add(it);
          }
          return ListView(padding: const EdgeInsets.all(AppSpacing.base), children: [
            for (final entry in groups.entries) ...[
              Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(entry.key,
                  style: Theme.of(context).textTheme.titleSmall)),
              ...entry.value.map((it) => _itemRow(context, it)),
              const SizedBox(height: 12),
            ],
          ]);
        },
      )),
    ]);
  }

  Widget _itemRow(BuildContext context, ProjectInspectionItem it) {
    return Card(elevation: 0, margin: const EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ListTile(
        title: Text(it.label),
        subtitle: it.notes != null && it.notes!.isNotEmpty
          ? Text(it.notes!) : null,
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final r in const ['pass', 'fail', 'na'])
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(r.toUpperCase(), style: const TextStyle(fontSize: 11)),
                selected: it.result == r,
                selectedColor: pmStatusColor(r == 'pass' ? 'passed'
                  : r == 'fail' ? 'failed' : 'cancelled').withValues(alpha: 0.3),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => svc.updateItem(it.id, {'result': r}))),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editItem(context, it),
            tooltip: 'Edit'),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => svc.deleteItem(it.id),
            tooltip: 'Delete'),
        ]),
      ),
    );
  }

  Future<void> _addItem(BuildContext context) async {
    final labelCtrl = TextEditingController();
    final catCtrl = TextEditingController();
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add checklist item'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: catCtrl,
          decoration: const InputDecoration(labelText: 'Category')),
        TextField(controller: labelCtrl,
          decoration: const InputDecoration(labelText: 'Item / question *')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (labelCtrl.text.trim().isEmpty) return;
          await svc.addItem(ProjectInspectionItem(
            id: '', workspaceId: workspaceId, inspectionId: inspection.id,
            category: catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
            label: labelCtrl.text.trim()));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Add')),
      ],
    ));
  }

  Future<void> _editItem(BuildContext context, ProjectInspectionItem it) async {
    final labelCtrl = TextEditingController(text: it.label);
    final notesCtrl = TextEditingController(text: it.notes);
    final catCtrl = TextEditingController(text: it.category);
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit item'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: catCtrl,
          decoration: const InputDecoration(labelText: 'Category')),
        TextField(controller: labelCtrl,
          decoration: const InputDecoration(labelText: 'Item / question')),
        TextField(controller: notesCtrl, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          await svc.updateItem(it.id, {
            'label': labelCtrl.text.trim(),
            'category': catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
            'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          });
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }
}
