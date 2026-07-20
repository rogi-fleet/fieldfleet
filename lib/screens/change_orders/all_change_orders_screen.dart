/// Workspace-wide list of all change orders across projects.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../projects/tabs/project_change_orders_tab.dart'
    show
        stageFor,
        ChangeOrderStage,
        ChangeOrderStageX,
        ChangeOrderSummaryStrip;

class AllChangeOrdersScreen extends StatefulWidget {
  const AllChangeOrdersScreen({super.key});

  @override
  State<AllChangeOrdersScreen> createState() => _AllChangeOrdersScreenState();
}

class _AllChangeOrdersScreenState extends State<AllChangeOrdersScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.yMMMd();
  ChangeOrderStage? _stageFilter;

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        context.watch<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null) {
      return const Scaffold(
          body: Center(child: Text('No workspace selected.')));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Change Orders'),
        actions: [
          PopupMenuButton<ChangeOrderStage?>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter stage',
            onSelected: (s) => setState(() => _stageFilter = s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              for (final s in ChangeOrderStage.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<GeneratedDocument>>(
        stream: ServiceLocator.documentService.getDocuments(
          workspaceId,
          documentType: DocumentType.changeOrder,
        ) as Stream<List<GeneratedDocument>>,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text(UserFacingError.uiMessage(snap.error,
                    action: 'load change orders')));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final filtered = _stageFilter == null
              ? all
              : all.where((d) => stageFor(d.status) == _stageFilter).toList();
          return Column(
            children: [
              ChangeOrderSummaryStrip(orders: all, currency: _currency),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No change orders match this filter.',
                            style: TextStyle(color: AppColors.textTertiary)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _row(filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(GeneratedDocument d) {
    final stage = stageFor(d.status);
    return InkWell(
      onTap: () => context.push('/documents/${d.id}'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                color: stage.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.templateName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.status.displayName} · created ${_dateFmt.format(d.createdAt)}'
                    '${(d.sentTo ?? '').isNotEmpty ? ' · to ${d.sentTo}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(_currency.format(d.totalAmount),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
