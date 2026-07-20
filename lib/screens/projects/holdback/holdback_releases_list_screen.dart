import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../models/holdback_release.dart';
import '../../../services/holdback_pdf_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/holdback_service.dart';
import '../../../theme/theme.dart';

/// Per-project list of holdback releases + statement-of-holdback action.
class HoldbackReleasesListScreen extends StatefulWidget {
  final String projectId;
  const HoldbackReleasesListScreen({super.key, required this.projectId});

  @override
  State<HoldbackReleasesListScreen> createState() =>
      _HoldbackReleasesListScreenState();
}

class _HoldbackReleasesListScreenState
    extends State<HoldbackReleasesListScreen> {
  final _svc = HoldbackService();
  final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  final _date = DateFormat.yMMMd();

  Future<_ListData>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<_ListData> _load() async {
    final project =
        await ServiceLocator.projectService.getProject(widget.projectId);
    final releases = await _svc.listForProject(widget.projectId);
    final summary = await _svc.getProjectSummary(widget.projectId);
    return _ListData(
      projectName: project?.name ?? 'Project',
      customerName: project?.customerName,
      releases: releases,
      summary: summary,
    );
  }

  Future<void> _printStatement(_ListData data) async {
    final bytes = await HoldbackPdfService.buildStatement(
      projectName: data.projectName,
      customerName: data.customerName,
      summary: data.summary,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holdback Releases'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: () => context
                  .go('/projects/${widget.projectId}/holdback-releases/new'),
              icon: const Icon(Icons.add),
              label: const Text('New Release'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<_ListData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: SelectableText('Error: ${snap.error}'));
          }
          final data = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryBar(
                summary: data.summary,
                money: _money,
                onPrintStatement: () => _printStatement(data),
              ),
              Expanded(
                child: data.releases.isEmpty
                    ? _EmptyState(projectId: widget.projectId)
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: data.releases.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = data.releases[i];
                          return ListTile(
                            leading: CircleAvatar(
                                child: Text('#${r.releaseNumber}')),
                            title: Text('Release #${r.releaseNumber}'),
                            subtitle: Text(
                                '${r.status.displayLabel} · ${_date.format(r.releaseDate)}'),
                            trailing: Text(
                              _money.format(r.totalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            onTap: () async {
                              await context.push<void>(
                                '/projects/${widget.projectId}/holdback-releases/${r.id}',
                              );
                              if (mounted) _refresh();
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ListData {
  final String projectName;
  final String? customerName;
  final List<HoldbackRelease> releases;
  final HoldbackSummary summary;
  _ListData({
    required this.projectName,
    required this.customerName,
    required this.releases,
    required this.summary,
  });
}

class _SummaryBar extends StatelessWidget {
  final HoldbackSummary summary;
  final NumberFormat money;
  final VoidCallback onPrintStatement;
  const _SummaryBar({
    required this.summary,
    required this.money,
    required this.onPrintStatement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: Row(
        children: [
          Expanded(child: _stat('Total held', money.format(summary.totalHeld))),
          Expanded(
              child: _stat('Released', money.format(summary.totalReleased))),
          Expanded(
              child: _stat(
                  'Outstanding', money.format(summary.totalOutstanding))),
          OutlinedButton.icon(
            onPressed: onPrintStatement,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Statement of Holdback'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String projectId;
  const _EmptyState({required this.projectId});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_outlined,
              size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No holdback releases yet.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context
                .push<void>('/projects/$projectId/holdback-releases/new'),
            icon: const Icon(Icons.add),
            label: const Text('Create the first release'),
          ),
        ],
      ),
    );
  }
}
