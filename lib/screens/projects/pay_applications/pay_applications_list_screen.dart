import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/pay_application.dart';
import '../../../services/supabase/pay_application_service.dart';
import '../../../theme/theme.dart';

/// Project-scoped list of AIA Pay Applications, with a "New" CTA.
///
/// Set [embedded] to true when hosting inside another screen (e.g. the
/// Financials tab) to drop the outer [Scaffold]/[AppBar] and use
/// `context.push` for child navigation so the back-stack is preserved.
class PayApplicationsListScreen extends StatefulWidget {
  final String projectId;
  final bool embedded;
  const PayApplicationsListScreen({
    super.key,
    required this.projectId,
    this.embedded = false,
  });

  @override
  State<PayApplicationsListScreen> createState() =>
      _PayApplicationsListScreenState();
}

class _PayApplicationsListScreenState
    extends State<PayApplicationsListScreen> {
  final _svc = PayApplicationService();
  final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 0);
  final _date = DateFormat.yMMMd();
  late Future<List<PayApplication>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.listForProject(widget.projectId);
  }

  void _reload() {
    setState(() {
      _future = _svc.listForProject(widget.projectId);
    });
  }

  Future<void> _openNew() async {
    if (widget.embedded) {
      await context.push<void>(
          '/projects/${widget.projectId}/pay-applications/new');
      if (mounted) _reload();
    } else {
      context.go('/projects/${widget.projectId}/pay-applications/new');
    }
  }

  Future<void> _openExisting(String id) async {
    if (widget.embedded) {
      await context
          .push<void>('/projects/${widget.projectId}/pay-applications/$id');
      if (mounted) _reload();
    } else {
      context.go('/projects/${widget.projectId}/pay-applications/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<PayApplication>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: SelectableText('Error: ${snapshot.error}'));
        }
        final apps = snapshot.data ?? [];
        if (apps.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('No pay applications yet.'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _openNew,
                  icon: const Icon(Icons.add),
                  label: const Text('Create the first one'),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: apps.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = apps[i];
            return ListTile(
              leading: CircleAvatar(
                child: Text('#${a.applicationNumber}'),
              ),
              title: Text('Application #${a.applicationNumber}'),
              subtitle: Text([
                a.status.displayLabel,
                if (a.periodTo != null) 'Period to ${_date.format(a.periodTo!)}',
              ].join(' · ')),
              trailing: Text(
                // List stream is header-only — use the saved snapshot
                // instead of the line-derived getter (which would be $0).
                _money.format(a.currentPaymentDueSnapshot ?? 0),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onTap: () => _openExisting(a.id),
            );
          },
        );
      },
    );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pay Applications (AIA G702/G703)',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openNew,
                  icon: const Icon(Icons.add),
                  label: const Text('New Application'),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Applications (AIA G702/G703)'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: _openNew,
              icon: const Icon(Icons.add),
              label: const Text('New Application'),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
