import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/project.dart';
import '../../../models/project_modules/daily_log.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/service_locator.dart';
import '../../../utils/confirm_dialog.dart';
import '_project_modules_common.dart';
import '../../../theme/theme.dart';

class ProjectDailyLogsTab extends StatelessWidget {
  final Project project;
  const ProjectDailyLogsTab({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final wsId = auth.appUser?.currentWorkspaceId;
    final userId = auth.appUser?.id;
    if (wsId == null || userId == null) {
      return const PmEmptyState(icon: Icons.warning_amber,
        title: 'Workspace not loaded');
    }
    final svc = ServiceLocator.projectDailyLogServiceFor(
      workspaceId: wsId, projectId: project.id);
    return _DailyLogsView(svc: svc, projectId: project.id,
      workspaceId: wsId, userId: userId);
  }
}

class _DailyLogsView extends StatelessWidget {
  final ProjectDailyLogService svc;
  final String projectId;
  final String workspaceId;
  final String userId;
  const _DailyLogsView({required this.svc, required this.projectId,
    required this.workspaceId, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text(
            'Track and report important daily events on this project site',
            style: TextStyle(color: Colors.black54))),
          FilledButton.icon(onPressed: () => _add(context),
            icon: const Icon(Icons.add), label: const Text('New daily log')),
        ]),
      ),
      Expanded(child: StreamBuilder<List<ProjectDailyLog>>(
        stream: svc.watchLogs(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return PmEmptyState(icon: Icons.event_note_outlined,
              title: 'No daily logs yet',
              subtitle: 'Log weather, crew, work performed, materials and incidents.',
              actionLabel: 'New daily log', onAction: () => _add(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _logCard(context, list[i]),
          );
        },
      )),
    ]);
  }

  Widget _logCard(BuildContext context, ProjectDailyLog l) {
    final temp = (l.temperatureHigh != null || l.temperatureLow != null)
      ? '${l.temperatureLow?.toStringAsFixed(0) ?? "—"}° / ${l.temperatureHigh?.toStringAsFixed(0) ?? "—"}°'
      : null;
    return Card(elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
      child: ExpansionTile(
        leading: Icon(Icons.event_note_outlined,
          color: pmStatusColor(l.status)),
        title: Text(fmtPmDate(l.logDate),
          style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (l.weatherConditions != null) l.weatherConditions!,
            if (temp != null) temp,
            if (l.crewCount > 0) '${l.crewCount} crew',
            if (l.hoursWorked != null) '${l.hoursWorked!.toStringAsFixed(1)} hrs',
          ].join('  •  ')),
        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PmStatusChip(label: labelize(l.status), color: pmStatusColor(l.status)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') return _add(context, existing: l);
              if (v == 'submit') return svc.submitLog(l.id, userId);
              if (v == 'approve') return svc.approveLog(l.id, userId);
              if (v == 'reopen') return svc.updateLog(l.id, {'status': 'draft',
                'submitted_at': null, 'approved_at': null});
              if (v == 'delete') return _confirmDelete(context, l);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (l.status == 'draft')
                const PopupMenuItem(value: 'submit', child: Text('Submit')),
              if (l.status == 'submitted')
                const PopupMenuItem(value: 'approve', child: Text('Approve')),
              if (l.status != 'draft')
                const PopupMenuItem(value: 'reopen', child: Text('Reopen as draft')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (l.workPerformed != null) _kv('Work performed', l.workPerformed!),
          if (l.materialsDelivered != null) _kv('Materials delivered', l.materialsDelivered!),
          if (l.equipmentOnSite != null) _kv('Equipment on-site', l.equipmentOnSite!),
          if (l.subcontractors != null) _kv('Subcontractors', l.subcontractors!),
          if (l.visitors != null) _kv('Visitors', l.visitors!),
          if (l.delays != null) _kv('Delays', l.delays!),
          if (l.safetyNotes != null) _kv('Safety notes', l.safetyNotes!),
          if (l.incidents != null) _kv('Incidents', l.incidents!),
          if (l.notes != null) _kv('Notes', l.notes!),
          if (l.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft,
              child: Text('${l.photos.length} photo${l.photos.length == 1 ? "" : "s"} attached',
                style: const TextStyle(color: Colors.black54, fontSize: 12))),
          ],
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

  Future<void> _confirmDelete(BuildContext context, ProjectDailyLog l) async {
    final ok = await confirmDestructive(context,
      title: 'Delete daily log?',
      message: 'Permanently delete the log for ${fmtPmDate(l.logDate)}?');
    if (ok) await svc.deleteLog(l.id);
  }

  Future<void> _add(BuildContext context, {ProjectDailyLog? existing}) async {
    final weatherCtrl = TextEditingController(text: existing?.weatherConditions);
    final tHighCtrl = TextEditingController(text: existing?.temperatureHigh?.toString());
    final tLowCtrl = TextEditingController(text: existing?.temperatureLow?.toString());
    final windCtrl = TextEditingController(text: existing?.wind);
    final crewCtrl = TextEditingController(text: existing?.crewCount.toString() ?? '0');
    final hoursCtrl = TextEditingController(text: existing?.hoursWorked?.toStringAsFixed(2));
    final workCtrl = TextEditingController(text: existing?.workPerformed);
    final matCtrl = TextEditingController(text: existing?.materialsDelivered);
    final equipCtrl = TextEditingController(text: existing?.equipmentOnSite);
    final subCtrl = TextEditingController(text: existing?.subcontractors);
    final visitCtrl = TextEditingController(text: existing?.visitors);
    final delayCtrl = TextEditingController(text: existing?.delays);
    final safetyCtrl = TextEditingController(text: existing?.safetyNotes);
    final incidentCtrl = TextEditingController(text: existing?.incidents);
    final notesCtrl = TextEditingController(text: existing?.notes);
    DateTime logDate = existing?.logDate ?? DateTime.now();

    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New daily log' : 'Edit daily log'),
      content: StatefulBuilder(builder: (ctx, setSt) => SizedBox(width: 540,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton(onPressed: () async {
            final d = await pickPmDate(ctx, initial: logDate);
            if (d != null) setSt(() => logDate = d);
          }, child: Text('Date: ${fmtPmDate(logDate)}')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: weatherCtrl,
              decoration: const InputDecoration(labelText: 'Weather conditions',
                hintText: 'Sunny / Cloudy / Rain'))),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: TextField(controller: tHighCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'High °F'))),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: TextField(controller: tLowCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Low °F'))),
          ]),
          TextField(controller: windCtrl,
            decoration: const InputDecoration(labelText: 'Wind / other')),
          Row(children: [
            Expanded(child: TextField(controller: crewCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Crew count'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: hoursCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hours worked'))),
          ]),
          TextField(controller: workCtrl, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Work performed today')),
          TextField(controller: matCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Materials delivered')),
          TextField(controller: equipCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Equipment on-site')),
          TextField(controller: subCtrl, maxLines: 1,
            decoration: const InputDecoration(labelText: 'Subcontractors on-site')),
          TextField(controller: visitCtrl, maxLines: 1,
            decoration: const InputDecoration(labelText: 'Visitors')),
          TextField(controller: delayCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Delays / impacts')),
          TextField(controller: safetyCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Safety notes / talks')),
          TextField(controller: incidentCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Incidents')),
          TextField(controller: notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Other notes')),
        ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final patch = <String, dynamic>{
            'log_date': logDate.toIso8601String().substring(0, 10),
            'weather_conditions': _nullable(weatherCtrl.text),
            'temperature_high': double.tryParse(tHighCtrl.text.trim()),
            'temperature_low': double.tryParse(tLowCtrl.text.trim()),
            'wind': _nullable(windCtrl.text),
            'crew_count': int.tryParse(crewCtrl.text.trim()) ?? 0,
            'hours_worked': double.tryParse(hoursCtrl.text.trim()),
            'work_performed': _nullable(workCtrl.text),
            'materials_delivered': _nullable(matCtrl.text),
            'equipment_on_site': _nullable(equipCtrl.text),
            'subcontractors': _nullable(subCtrl.text),
            'visitors': _nullable(visitCtrl.text),
            'delays': _nullable(delayCtrl.text),
            'safety_notes': _nullable(safetyCtrl.text),
            'incidents': _nullable(incidentCtrl.text),
            'notes': _nullable(notesCtrl.text),
          };
          if (existing == null) {
            await svc.createLog(ProjectDailyLog(
              id: '', workspaceId: workspaceId, projectId: projectId,
              logDate: logDate,
              weatherConditions: patch['weather_conditions'] as String?,
              temperatureHigh: patch['temperature_high'] as double?,
              temperatureLow: patch['temperature_low'] as double?,
              wind: patch['wind'] as String?,
              crewCount: patch['crew_count'] as int,
              hoursWorked: patch['hours_worked'] as double?,
              workPerformed: patch['work_performed'] as String?,
              materialsDelivered: patch['materials_delivered'] as String?,
              equipmentOnSite: patch['equipment_on_site'] as String?,
              subcontractors: patch['subcontractors'] as String?,
              visitors: patch['visitors'] as String?,
              delays: patch['delays'] as String?,
              safetyNotes: patch['safety_notes'] as String?,
              incidents: patch['incidents'] as String?,
              notes: patch['notes'] as String?,
            ));
          } else {
            await svc.updateLog(existing.id, patch);
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
}
