import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/opportunity.dart';
import '../../models/opportunity_activity.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/opportunity_service.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/common/async_state_view.dart';

class OpportunityDetailScreen extends StatefulWidget {
  final String opportunityId;
  const OpportunityDetailScreen({super.key, required this.opportunityId});

  @override
  State<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState extends State<OpportunityDetailScreen> {
  late SupabaseOpportunityService _svc;
  Opportunity? _opp;
  List<OpportunityActivity> _activities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = ServiceLocator.opportunityService;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final opp = await _svc.getOpportunity(widget.opportunityId);
      final acts = await _svc.listActivities(widget.opportunityId);
      if (!mounted) return;
      setState(() {
        _opp = opp;
        _activities = acts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addActivity(OpportunityActivityKind kind) async {
    final opp = _opp;
    if (opp == null) return;
    final result = await showDialog<_NewActivity>(
      context: context,
      builder: (_) => _ActivityDialog(kind: kind),
    );
    if (result == null) return;
    try {
      await _svc.addActivity(
        opportunityId: opp.id,
        workspaceId: opp.workspaceId,
        kind: kind,
        subject: result.subject,
        body: result.body,
        dueAt: result.dueAt,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _markWon() async {
    final opp = _opp;
    if (opp == null) return;
    final projectTerm = singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark as won?'),
        content: Text(
            'This will create a new $projectTerm linked to this opportunity.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark won')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final projectId = await _svc.markWonAndCreateProject(opp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} created — id $projectId',
          ),
        ),
      );
      context.go('/projects/$projectId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _markLost() async {
    final opp = _opp;
    if (opp == null) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark as lost'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Mark lost')),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _svc.changeStage(opp.id, OpportunityStage.lost, lostReason: reason);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_opp?.name ?? 'Opportunity'),
        actions: [
          if (_opp != null && !_opp!.stage.isClosed) ...[
            TextButton(
              onPressed: _markLost,
              child: const Text('Lost'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _markWon,
              child: const Text('Mark won'),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _opp == null
                ? null
                : () => context.go('/opportunities/${_opp!.id}/edit'),
          ),
        ],
      ),
      body: AsyncStateView(
        isLoading: _loading,
        error: _error,
        errorAction: 'load this opportunity',
        onRetry: _load,
        isEmpty: _opp == null,
        emptyState: const Center(child: Text('Not found')),
        builder: (context) => _Body(
          opp: _opp!,
          activities: _activities,
          onAdd: _addActivity,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Opportunity opp;
  final List<OpportunityActivity> activities;
  final Future<void> Function(OpportunityActivityKind) onAdd;
  const _Body(
      {required this.opp, required this.activities, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        _SummaryCard(opp: opp),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            PopupMenuButton<OpportunityActivityKind>(
              icon: const Icon(Icons.add),
              tooltip: 'Log activity',
              onSelected: onAdd,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: OpportunityActivityKind.note,
                    child: Text('Note')),
                PopupMenuItem(
                    value: OpportunityActivityKind.call,
                    child: Text('Call')),
                PopupMenuItem(
                    value: OpportunityActivityKind.email,
                    child: Text('Email')),
                PopupMenuItem(
                    value: OpportunityActivityKind.meeting,
                    child: Text('Meeting')),
                PopupMenuItem(
                    value: OpportunityActivityKind.followUp,
                    child: Text('Follow-up')),
              ],
            ),
          ],
        ),
        const Divider(),
        if (activities.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text('No activity yet',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          )
        else
          ...activities.map((a) => _ActivityTile(activity: a)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Opportunity opp;
  const _SummaryCard({required this.opp});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(opp.stage.displayName)),
                const Spacer(),
                Text('\$${opp.estimatedValue.toStringAsFixed(0)} '
                    '· ${opp.probability}%'),
              ],
            ),
            const SizedBox(height: 8),
            if (opp.description != null && opp.description!.isNotEmpty)
              Text(opp.description!),
            const SizedBox(height: 8),
            if (opp.expectedCloseDate != null)
              Text('Expected close: ${df.format(opp.expectedCloseDate!)}',
                  style: TextStyle(color: AppColors.textSecondary)),
            if (opp.actualCloseDate != null)
              Text('Closed: ${df.format(opp.actualCloseDate!)}',
                  style: TextStyle(color: AppColors.textSecondary)),
            if (opp.lostReason != null && opp.lostReason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Lost reason: ${opp.lostReason}',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            if (opp.nextAction != null && opp.nextAction!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.flag, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(child: Text('Next: ${opp.nextAction}')),
                  ],
                ),
              ),
            if (opp.projectId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    'Open linked ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()}',
                  ),
                  onPressed: () => context.go('/projects/${opp.projectId}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final OpportunityActivity activity;
  const _ActivityTile({required this.activity});

  IconData get _icon {
    switch (activity.kind) {
      case OpportunityActivityKind.note:
        return Icons.sticky_note_2_outlined;
      case OpportunityActivityKind.call:
        return Icons.call;
      case OpportunityActivityKind.email:
        return Icons.email_outlined;
      case OpportunityActivityKind.meeting:
        return Icons.event;
      case OpportunityActivityKind.followUp:
        return Icons.flag_outlined;
      case OpportunityActivityKind.stageChange:
        return Icons.swap_horiz;
      case OpportunityActivityKind.won:
        return Icons.emoji_events;
      case OpportunityActivityKind.lost:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd().add_jm();
    return ListTile(
      leading: Icon(_icon),
      title: Text(activity.subject ?? activity.kind.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activity.body != null && activity.body!.isNotEmpty)
            Text(activity.body!),
          Text(df.format(activity.createdAt.toLocal()),
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ],
      ),
      trailing: activity.dueAt != null && activity.completedAt == null
          ? Chip(
              label: Text('Due ${df.format(activity.dueAt!.toLocal())}'),
              backgroundColor: Colors.amber.withValues(alpha: 0.2),
            )
          : null,
    );
  }
}

class _NewActivity {
  final String? subject;
  final String? body;
  final DateTime? dueAt;
  _NewActivity({this.subject, this.body, this.dueAt});
}

class _ActivityDialog extends StatefulWidget {
  final OpportunityActivityKind kind;
  const _ActivityDialog({required this.kind});

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  DateTime? _due;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFollowUp = widget.kind == OpportunityActivityKind.followUp;
    return AlertDialog(
      title: Text('Log ${widget.kind.displayName.toLowerCase()}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Subject'),
              autofocus: true,
            ),
            TextField(
              controller: _body,
              decoration: const InputDecoration(labelText: 'Details'),
              maxLines: 3,
            ),
            if (isFollowUp) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_due == null
                    ? 'Due — pick a date'
                    : 'Due ${_due!.toLocal()}'),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _due = d);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              _NewActivity(
                subject: _subject.text.trim().isEmpty
                    ? null
                    : _subject.text.trim(),
                body: _body.text.trim().isEmpty ? null : _body.text.trim(),
                dueAt: _due,
              )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
