import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/asset.dart';
import '../../../models/inventory/equipment_rental.dart';
import '../../../models/project.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../widgets/project_sub_tab.dart';
import '../../../utils/project_terminology.dart';
import '../../../utils/user_facing_error.dart';
import '../../inventory/forms/equipment_rental_form.dart';
import 'project_materials_tab.dart';

/// Combined Inventory tab for the project detail screen.
/// Houses two sub-tabs that mirror the sidebar Inventory module:
///   • Materials — stock issued from the warehouse to this job
///   • Assets    — owned equipment assigned to the job + equipment on site (rentals)
class ProjectInventoryTab extends StatefulWidget {
  final Project project;
  const ProjectInventoryTab({super.key, required this.project});

  @override
  State<ProjectInventoryTab> createState() => _ProjectInventoryTabState();
}

class _ProjectInventoryTabState extends State<ProjectInventoryTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              projectSubTab(icon: Icons.warehouse_outlined, label: 'Materials'),
              projectSubTab(icon: Icons.handyman_outlined, label: 'Equipment'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ProjectMaterialsTab(project: widget.project),
              _AssetsSubTab(project: widget.project),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Assets sub-tab — owned assets assigned to the job + equipment on site
// =============================================================================

class _AssetsSubTab extends StatefulWidget {
  final Project project;
  const _AssetsSubTab({required this.project});

  @override
  State<_AssetsSubTab> createState() => _AssetsSubTabState();
}

class _AssetsSubTabState extends State<_AssetsSubTab> {
  String get _wsId =>
      context.read<AuthProvider>().appUser?.activeWorkspaceId ??
      context.read<AuthProvider>().appUser?.workspaceId ??
      '';

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _openRentalDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: EquipmentRentalForm(
            workspaceId: _wsId,
            projectId: widget.project.id,
          ),
        ),
      ),
    );
  }

  Future<void> _closeRental(EquipmentRental r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Return equipment?'),
        content: Text(
          'Closes this rental as of today. '
          '${r.isBillable ? 'A cost line for ${r.daysBilled()} day(s) will be added to financials.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Return'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ServiceLocator.equipmentRentalServiceFor(_wsId).closeRental(r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Close failed: $e')),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available':
        return AppColors.success;
      case 'assigned':
        return AppColors.info;
      case 'maintenance':
        return AppColors.secondary;
      case 'retired':
        return AppColors.textTertiary;
      default:
        return AppColors.textTertiary;
    }
  }

  Future<void> _showAssignDialog(
    BuildContext context, {
    required String workspaceId,
    required List<Asset> assignedAssets,
  }) async {
    final assetService = ServiceLocator.assetServiceFor(workspaceId);
    final assignedIds = assignedAssets.map((a) => a.id).toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final selectedIds = <String>{};
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Assign Equipment'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search available equipment',
                      ),
                      onChanged: (v) => setDialogState(
                          () => searchQuery = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: StreamBuilder<List<Asset>>(
                        stream: assetService.getAssets(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(
                                child: Text(UserFacingError.uiMessage(
                                    snapshot.error,
                                    action: 'load equipment')));
                          }
                          final available = (snapshot.data ?? []).where((a) {
                            if (assignedIds.contains(a.id)) return false;
                            if (a.status != 'available') return false;
                            if (a.assignedToProjectId != null ||
                                a.assignedToUserId != null) return false;
                            if (searchQuery.isEmpty) return true;
                            return a.name.toLowerCase().contains(searchQuery) ||
                                (a.description
                                        ?.toLowerCase()
                                        .contains(searchQuery) ??
                                    false) ||
                                (a.serialNumber
                                        ?.toLowerCase()
                                        .contains(searchQuery) ??
                                    false);
                          }).toList();
                          if (available.isEmpty) {
                            return const Center(
                                child: Text(
                                    'No available equipment matches this search.'));
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            itemCount: available.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final a = available[i];
                              return CheckboxListTile(
                                value: selectedIds.contains(a.id),
                                onChanged: (v) => setDialogState(() {
                                  if (v == true) {
                                    selectedIds.add(a.id);
                                  } else {
                                    selectedIds.remove(a.id);
                                  }
                                }),
                                contentPadding: EdgeInsets.zero,
                                title: Text(a.name),
                                subtitle: Text(
                                    a.serialNumber?.isNotEmpty == true
                                        ? a.serialNumber!
                                        : 'No serial number'),
                                secondary:
                                    const Icon(Icons.inventory_2_outlined),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          try {
                            for (final id in selectedIds) {
                              await assetService.assignAssetToProject(
                                  id, widget.project.id);
                            }
                            if (!ctx.mounted) return;
                            Navigator.of(dialogCtx).pop();
                            final projTerm = ctx
                                .read<WorkspaceProvider>()
                                .projectTerminology;
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(selectedIds.length == 1
                                  ? 'Equipment assigned to ${singularProjectTerminology(projTerm).toLowerCase()}'
                                  : '${selectedIds.length} equipment items assigned to ${singularProjectTerminology(projTerm).toLowerCase()}'),
                            ));
                          } catch (e) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(UserFacingError.uiMessage(e,
                                  action: 'assign equipment')),
                              backgroundColor: AppColors.error,
                            ));
                          }
                        },
                  child: Text(selectedIds.isEmpty
                      ? 'Assign'
                      : 'Assign (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    final projTerm = context.watch<WorkspaceProvider>().projectTerminology;

    return StreamBuilder<List<Asset>>(
      stream: ServiceLocator.projectService
          .getProjectAssets(widget.project.id, widget.project.workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text(UserFacingError.uiMessage(snapshot.error,
                  action: 'load equipment')));
        }
        final assets = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Assigned assets header ──────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned equipment',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          'Owned equipment tied to this job.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: workspaceId.isEmpty
                        ? null
                        : () => _showAssignDialog(context,
                            workspaceId: workspaceId, assignedAssets: assets),
                    icon: const Icon(Icons.add),
                    label: const Text('Assign equipment'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (assets.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No equipment assigned to this ${singularProjectTerminology(projTerm).toLowerCase()} yet.',
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => context.push('/inventory'),
                          child: const Text('Go to Inventory'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: assets.length,
                  itemBuilder: (context, i) {
                    final asset = assets[i];
                    final statusColor = _statusColor(asset.status);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.2),
                          child: Icon(Icons.inventory_2, color: statusColor),
                        ),
                        title: Text(asset.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (asset.description != null)
                              Text(asset.description!),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Chip(
                                  label: Text(asset.status[0].toUpperCase() +
                                      asset.status.substring(1)),
                                  backgroundColor:
                                      statusColor.withValues(alpha: 0.2),
                                  labelStyle: TextStyle(
                                      color: statusColor, fontSize: 12),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (asset.purchasePrice != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '\$${asset.purchasePrice!.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              child: const Row(children: [
                                Icon(Icons.visibility, size: 20),
                                SizedBox(width: 8),
                                Text('View Details'),
                              ]),
                              onTap: () => Future.delayed(Duration.zero,
                                  () => context.push('/equipment/${asset.id}')),
                            ),
                            PopupMenuItem(
                              child: const Row(children: [
                                Icon(Icons.close,
                                    size: 20, color: AppColors.errorDark),
                                SizedBox(width: 8),
                                Text('Unassign',
                                    style:
                                        TextStyle(color: AppColors.errorDark)),
                              ]),
                              onTap: () async {
                                final wsId = context
                                        .read<AuthProvider>()
                                        .appUser
                                        ?.currentWorkspaceId ??
                                    '';
                                await ServiceLocator.assetServiceFor(wsId)
                                    .unassignAsset(asset.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '${asset.name} unassigned from ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology).toLowerCase()}')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // ── Equipment on site (rentals) ─────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Equipment on site',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          'Closing a billable rental writes its rate × days to Financials.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openRentalDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add rental'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<EquipmentRental>>(
                stream: ServiceLocator.equipmentRentalServiceFor(_wsId)
                    .watchRentalsForProject(widget.project.id),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final rentals = [...snap.data!]..sort((a, b) {
                      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
                      return b.startDate.compareTo(a.startDate);
                    });
                  if (rentals.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Row(
                          children: [
                            Icon(Icons.precision_manufacturing_outlined,
                                color: Theme.of(context).colorScheme.outline),
                            const SizedBox(width: 12),
                            const Expanded(
                                child:
                                    Text('No equipment rentals on this job.')),
                          ],
                        ),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: rentals.map((r) {
                        final days = r.daysBilled();
                        final billed = r.billedAmount();
                        return ListTile(
                          leading: Icon(
                            r.isOpen
                                ? Icons.precision_manufacturing
                                : Icons.check_circle_outline,
                            color:
                                r.isOpen ? AppColors.info : AppColors.success,
                          ),
                          title: Text(
                            '${_d(r.startDate)} → ${r.endDate == null ? 'Open' : _d(r.endDate!)}',
                          ),
                          subtitle: Text(
                            '$days day${days == 1 ? '' : 's'}'
                            ' · \$${r.dailyRate.toStringAsFixed(2)}/day'
                            ' · ${r.isBillable ? 'Billable' : 'Internal'}',
                          ),
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Text(
                                '\$${billed.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              if (r.isOpen)
                                TextButton.icon(
                                  onPressed: () => _closeRental(r),
                                  icon: const Icon(Icons.exit_to_app, size: 18),
                                  label: const Text('Return'),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // ── Asset costs summary ─────────────────────────────────────
              FutureBuilder<
                  ({double purchase, double maintenance, double total})>(
                future: ServiceLocator.projectService
                    .getAssetCosts(widget.project.id),
                builder: (context, snap) {
                  if (!snap.hasData || assets.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final c = snap.data!;
                  return Card(
                    color: AppColors.infoLight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Equipment Costs Summary',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Purchase Costs:'),
                              Text('\$${c.purchase.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Maintenance Costs:'),
                              Text('\$${c.maintenance.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Equipment Costs:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Text('\$${c.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.infoDark)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
