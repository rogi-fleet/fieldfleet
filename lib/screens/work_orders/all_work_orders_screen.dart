/// Workspace-wide list of all work orders across projects.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/work_order.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';

class AllWorkOrdersScreen extends StatefulWidget {
  const AllWorkOrdersScreen({super.key});

  @override
  State<AllWorkOrdersScreen> createState() => _AllWorkOrdersScreenState();
}

class _AllWorkOrdersScreenState extends State<AllWorkOrdersScreen> {
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');
  final _dateFmt = DateFormat.MMMd();
  WorkOrderStatus? _statusFilter;

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
        title: const Text('Work Orders'),
        actions: [
          PopupMenuButton<WorkOrderStatus?>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter status',
            onSelected: (s) => setState(() => _statusFilter = s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              for (final s in WorkOrderStatus.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<WorkOrder>>(
        stream: ServiceLocator.workOrderService.watchByWorkspace(workspaceId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text(UserFacingError.uiMessage(snap.error,
                    action: 'load work orders')));
          }
          if (!snap.hasData) {
            return const ListSkeleton();
          }
          final filtered = _statusFilter == null
              ? snap.data!
              : snap.data!.where((w) => w.status == _statusFilter).toList();
          if (filtered.isEmpty) {
            return const Center(
                child: Text('No work orders yet.',
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

  Widget _row(WorkOrder w) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          final segment = w.kind == 'rental' ? 'rentals' : 'materials';
          context.go(
              '/projects/${w.projectId}?tab=purchase-orders&segment=$segment');
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 40,
                decoration: BoxDecoration(
                  color: w.status.color,
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
                        Text(w.number,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textTertiary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: w.status.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(w.status.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: w.status.color)),
                        ),
                        if (w.kind == 'rental') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('Rental',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.info)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(w.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_currency.format(w.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (w.scheduledStart != null)
                    Text(_dateFmt.format(w.scheduledStart!),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
