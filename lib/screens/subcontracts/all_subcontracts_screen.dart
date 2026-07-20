/// Workspace-wide list of all subcontracts across projects.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/subcontract.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';

class AllSubcontractsScreen extends StatefulWidget {
  const AllSubcontractsScreen({super.key});

  @override
  State<AllSubcontractsScreen> createState() => _AllSubcontractsScreenState();
}

class _AllSubcontractsScreenState extends State<AllSubcontractsScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  SubcontractStatus? _statusFilter;

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
        title: const Text('Subcontracts'),
        actions: [
          PopupMenuButton<SubcontractStatus?>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter status',
            onSelected: (s) => setState(() => _statusFilter = s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              for (final s in SubcontractStatus.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Subcontract>>(
        stream:
            ServiceLocator.subcontractService.watchByWorkspace(workspaceId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text(UserFacingError.uiMessage(snap.error,
                    action: 'load subcontracts')));
          }
          if (!snap.hasData) {
            return const ListSkeleton();
          }
          final filtered = _statusFilter == null
              ? snap.data!
              : snap.data!
                  .where((s) => s.status == _statusFilter)
                  .toList();
          if (filtered.isEmpty) {
            return const Center(
                child: Text('No subcontracts yet.',
                    style: TextStyle(color: AppColors.textTertiary)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _row(filtered[i]),
          );
        },
      ),
    );
  }

  Widget _row(Subcontract s) {
    final progress = s.contractAmount > 0
        ? (s.paidToDate / s.contractAmount).clamp(0.0, 1.0)
        : 0.0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () =>
            context.go(
                '/projects/${s.projectId}?tab=purchase-orders&segment=subcontracts'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 32,
                    decoration: BoxDecoration(
                      color: s.status.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(s.number,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textTertiary)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: s.status.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(s.status.label,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: s.status.color)),
                            ),
                            if (s.insuranceRequired && !s.insuranceVerified) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.warning_amber,
                                  size: 14, color: AppColors.warning),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(s.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_currency.format(s.contractAmount),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${_currency.format(s.paidToDate)} paid',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AppColors.background,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
