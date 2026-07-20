import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/project_modules/punch_list.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../utils/confirm_dialog.dart';
import '_project_modules_common.dart';
import '../../../theme/theme.dart';

class ProjectPunchListTab extends StatelessWidget {
  final Project project;
  const ProjectPunchListTab({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final wsId = auth.appUser?.currentWorkspaceId;
    final userId = auth.appUser?.id;
    if (wsId == null || userId == null) {
      return const PmEmptyState(icon: Icons.warning_amber,
        title: 'Workspace not loaded');
    }
    final svc = ServiceLocator.projectPunchListServiceFor(
      workspaceId: wsId, projectId: project.id);
    return _PunchListsView(svc: svc, projectId: project.id,
      workspaceId: wsId, userId: userId);
  }
}

class _PunchListsView extends StatelessWidget {
  final ProjectPunchListService svc;
  final String projectId;
  final String workspaceId;
  final String userId;
  const _PunchListsView({required this.svc, required this.projectId,
    required this.workspaceId, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text(
            'Track deficiencies and their repair / completion through closeout',
            style: TextStyle(color: Colors.black54))),
          FilledButton.icon(onPressed: () => _addList(context),
            icon: const Icon(Icons.add), label: const Text('New punch list')),
        ]),
      ),
      Expanded(child: StreamBuilder<List<ProjectPunchList>>(
        stream: svc.watchLists(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final lists = snap.data ?? const [];
          if (lists.isEmpty) {
            return PmEmptyState(icon: Icons.fact_check_outlined,
              title: 'No punch lists yet',
              subtitle: 'Create a list to track deficiencies, then add items by trade or area.',
              actionLabel: 'New punch list', onAction: () => _addList(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: lists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _listCard(context, lists[i]),
          );
        },
      )),
    ]);
  }

  Widget _listCard(BuildContext context, ProjectPunchList l) {
    final pct = l.completionPercent;
    return Card(elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ExpansionTile(
        leading: Icon(Icons.fact_check_outlined, color: pmStatusColor(l.status)),
        title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (l.location != null) Text(l.location!),
            if (l.dueDate != null) Text('Due: ${fmtPmDate(l.dueDate)}'),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(value: pct / 100,
                minHeight: 6, backgroundColor: Colors.black12,
                color: pmStatusColor(l.status))),
            const SizedBox(height: 2),
            Text('${l.completedCount}/${l.totalItems} complete  •  ${l.openCount} open',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ])),
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PmStatusChip(label: labelize(l.status), color: pmStatusColor(l.status)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') return _addList(context, existing: l);
              if (v == 'close') return svc.updateList(l.id, {'status': 'closed'});
              if (v == 'reopen') return svc.updateList(l.id, {'status': 'open'});
              if (v == 'delete') return _confirmDeleteList(context, l);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit list')),
              if (l.status != 'closed')
                const PopupMenuItem(value: 'close', child: Text('Close list'))
              else
                const PopupMenuItem(value: 'reopen', child: Text('Reopen list')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(children: [
              const Spacer(),
              OutlinedButton.icon(onPressed: () => _addItem(context, l),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add deficiency')),
            ])),
          StreamBuilder<List<ProjectPunchListItem>>(
            stream: svc.watchItems(l.id),
            builder: (_, snap) {
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text('No deficiencies on this list yet.',
                    style: TextStyle(color: Colors.black54)));
              }
              return Column(children: items.map((it) => _itemTile(context, it)).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _itemTile(BuildContext context, ProjectPunchListItem it) {
    return Card(elevation: 0, margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ListTile(
        leading: Container(width: 6, height: 40,
          decoration: BoxDecoration(color: pmPriorityColor(it.priority),
            borderRadius: BorderRadius.circular(3))),
        title: Text(it.title),
        subtitle: Text([
          if (it.locationDetail != null) it.locationDetail!,
          if (it.trade != null) it.trade!,
          if (it.assigneeName != null) 'Assigned: ${it.assigneeName}',
          if (it.dueDate != null) 'Due: ${fmtPmDate(it.dueDate)}',
          if (it.description != null) it.description!,
        ].where((s) => s.isNotEmpty).join('  •  ')),
        isThreeLine: it.description != null,
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PmStatusChip(label: it.priority.toUpperCase(),
            color: pmPriorityColor(it.priority)),
          PmStatusChip(label: labelize(it.status), color: pmStatusColor(it.status)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') return _editItem(context, it);
              if (v == 'progress') return svc.updateItem(it.id, {'status': 'in_progress'});
              if (v == 'review') return svc.updateItem(it.id, {'status': 'ready_review'});
              if (v == 'complete') return svc.markComplete(it.id, userId);
              if (v == 'verify') return svc.verifyItem(it.id, userId);
              if (v == 'wont_fix') return svc.updateItem(it.id, {'status': 'wont_fix'});
              if (v == 'reopen') return svc.updateItem(it.id, {
                'status': 'open',
                'completed_at': null, 'verified_at': null,
              });
              if (v == 'delete') return svc.deleteItem(it.id);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'progress', child: Text('Mark in progress')),
              const PopupMenuItem(value: 'review', child: Text('Ready for review')),
              const PopupMenuItem(value: 'complete', child: Text('Mark complete')),
              const PopupMenuItem(value: 'verify', child: Text('Verify (close)')),
              const PopupMenuItem(value: 'wont_fix', child: Text("Won't fix")),
              const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmDeleteList(BuildContext context, ProjectPunchList l) async {
    final ok = await confirmDestructive(context,
      title: 'Delete punch list?',
      message: 'Delete "${l.name}" and all ${l.totalItems} item(s)?');
    if (ok) await svc.deleteList(l.id);
  }

  Future<void> _addList(BuildContext context, {ProjectPunchList? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final descCtrl = TextEditingController(text: existing?.description);
    final locCtrl = TextEditingController(text: existing?.location);
    DateTime? due = existing?.dueDate;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New punch list' : 'Edit punch list'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Name *',
              hintText: 'e.g. Final walkthrough — Unit 3B')),
          TextField(controller: descCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: locCtrl,
            decoration: const InputDecoration(labelText: 'Location')),
          OutlinedButton(onPressed: () async {
            final d = await pickPmDate(ctx, initial: due ?? DateTime.now());
            if (d != null) setSt(() => due = d);
          }, child: Text('Due date: ${fmtPmDate(due)}')),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (nameCtrl.text.trim().isEmpty) return;
          if (existing == null) {
            await svc.createList(ProjectPunchList(
              id: '', workspaceId: workspaceId, projectId: projectId,
              name: nameCtrl.text.trim(),
              description: _nullable(descCtrl.text),
              location: _nullable(locCtrl.text),
              dueDate: due));
          } else {
            await svc.updateList(existing.id, {
              'name': nameCtrl.text.trim(),
              'description': _nullable(descCtrl.text),
              'location': _nullable(locCtrl.text),
              'due_date': due?.toIso8601String().substring(0, 10),
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  Future<void> _addItem(BuildContext context, ProjectPunchList l,
      {ProjectPunchListItem? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title);
    final descCtrl = TextEditingController(text: existing?.description);
    final locCtrl = TextEditingController(text: existing?.locationDetail);
    final tradeCtrl = TextEditingController(text: existing?.trade);
    final assigneeCtrl = TextEditingController(text: existing?.assigneeName);
    final notesCtrl = TextEditingController(text: existing?.notes);
    String priority = existing?.priority ?? 'medium';
    DateTime? due = existing?.dueDate;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add deficiency' : 'Edit deficiency'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 460,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Title *',
              hintText: 'e.g. Drywall ding by entry door')),
          TextField(controller: descCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Description')),
          Row(children: [
            Expanded(child: TextField(controller: locCtrl,
              decoration: const InputDecoration(labelText: 'Location / room'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: tradeCtrl,
              decoration: const InputDecoration(labelText: 'Trade'))),
          ]),
          DropdownButtonFormField<String>(
            initialValue: priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: const ['low', 'medium', 'high', 'critical']
              .map((p) => DropdownMenuItem(value: p, child: Text(labelize(p)))).toList(),
            onChanged: (v) => setSt(() => priority = v ?? priority)),
          TextField(controller: assigneeCtrl,
            decoration: const InputDecoration(labelText: 'Assigned to (vendor / person)')),
          OutlinedButton(onPressed: () async {
            final d = await pickPmDate(ctx, initial: due ?? DateTime.now());
            if (d != null) setSt(() => due = d);
          }, child: Text('Due: ${fmtPmDate(due)}')),
          TextField(controller: notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes')),
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (titleCtrl.text.trim().isEmpty) return;
          if (existing == null) {
            await svc.addItem(ProjectPunchListItem(
              id: '', workspaceId: workspaceId, punchListId: l.id,
              title: titleCtrl.text.trim(),
              description: _nullable(descCtrl.text),
              locationDetail: _nullable(locCtrl.text),
              trade: _nullable(tradeCtrl.text),
              priority: priority,
              assigneeName: _nullable(assigneeCtrl.text),
              dueDate: due,
              notes: _nullable(notesCtrl.text)));
          } else {
            await svc.updateItem(existing.id, {
              'title': titleCtrl.text.trim(),
              'description': _nullable(descCtrl.text),
              'location_detail': _nullable(locCtrl.text),
              'trade': _nullable(tradeCtrl.text),
              'priority': priority,
              'assignee_name': _nullable(assigneeCtrl.text),
              'due_date': due?.toIso8601String().substring(0, 10),
              'notes': _nullable(notesCtrl.text),
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  Future<void> _editItem(BuildContext context, ProjectPunchListItem it) async {
    // Need parent list — fetch by reading items stream isn't straightforward,
    // so reuse _addItem with a synthesized parent (only id is used).
    final parent = ProjectPunchList(
      id: it.punchListId, workspaceId: workspaceId,
      projectId: projectId, name: '');
    await _addItem(context, parent, existing: it);
  }

  String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
}
