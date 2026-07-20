import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/maintenance_log.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/supabase/maintenance_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/currency_utils.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/forms/stacked_field.dart';

/// Maintenance history card for an asset's detail screen.
///
/// Lists all logs newest-first and exposes a "Log maintenance" action that
/// opens the entry dialog. Surfaces the next-service-due date prominently
/// when the latest log carries one — assets earn an attention chip when
/// that date is in the past.
class AssetMaintenanceSection extends StatelessWidget {
  final String assetId;
  final String workspaceId;

  const AssetMaintenanceSection({
    super.key,
    required this.assetId,
    required this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    final service = SupabaseMaintenanceService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Maintenance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showLogDialog(context, service),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log maintenance'),
                ),
              ],
            ),
            const Divider(),
            StreamBuilder<List<MaintenanceLog>>(
              stream: service.streamLogs(assetId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load maintenance',
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final logs = snapshot.data ?? const <MaintenanceLog>[];
                if (logs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No maintenance logged yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                final next = logs.first.nextMaintenanceDate;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (next != null) ...[
                      _NextServiceBanner(date: next),
                      const SizedBox(height: 12),
                    ],
                    for (int i = 0; i < logs.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _LogRow(
                        log: logs[i],
                        onEdit: () =>
                            _showLogDialog(context, service, existing: logs[i]),
                        onDelete: () => _confirmDelete(context, service, logs[i]),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogDialog(
    BuildContext context,
    SupabaseMaintenanceService service, {
    MaintenanceLog? existing,
  }) async {
    final result = await showDialog<MaintenanceLog>(
      context: context,
      builder: (_) => _MaintenanceLogDialog(
        assetId: assetId,
        workspaceId: workspaceId,
        existing: existing,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      if (existing == null) {
        await service.addLog(result);
      } else {
        await service.updateLog(result);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Maintenance logged' : 'Maintenance updated',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'save maintenance'),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SupabaseMaintenanceService service,
    MaintenanceLog log,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete maintenance log?'),
        content: Text('Remove "${log.description}" from this equipment\'s history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.deleteLog(log.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'delete maintenance'),
          ),
        ),
      );
    }
  }
}

class _NextServiceBanner extends StatelessWidget {
  final DateTime date;

  const _NextServiceBanner({required this.date});

  @override
  Widget build(BuildContext context) {
    final overdue = date.isBefore(DateTime.now());
    final color = overdue ? AppColors.error : AppColors.info;
    final label = overdue ? 'Service overdue' : 'Next service';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ${_formatDate(date)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final MaintenanceLog log;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LogRow({
    required this.log,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _typeColor(log.type).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              _typeIcon(log.type),
              size: 18,
              color: _typeColor(log.type),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.description.isEmpty ? _typeLabel(log.type) : log.description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(log, currencyCode),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(MaintenanceLog log, String currencyCode) {
    final parts = <String>[_formatDate(log.date)];
    if (log.cost > 0) {
      parts.add(CurrencyUtils.formatCurrency(log.cost, currencyCode));
    }
    if (log.performedBy != null && log.performedBy!.isNotEmpty) {
      parts.add(log.performedBy!);
    }
    return parts.join(' • ');
  }
}

class _MaintenanceLogDialog extends StatefulWidget {
  final String assetId;
  final String workspaceId;
  final MaintenanceLog? existing;

  const _MaintenanceLogDialog({
    required this.assetId,
    required this.workspaceId,
    this.existing,
  });

  @override
  State<_MaintenanceLogDialog> createState() => _MaintenanceLogDialogState();
}

class _MaintenanceLogDialogState extends State<_MaintenanceLogDialog> {
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _performedByController = TextEditingController();
  late DateTime _date;
  DateTime? _nextDate;
  String _type = 'inspection';

  static const _typeOptions = ['inspection', 'repair', 'oil_change', 'other'];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _descriptionController.text = existing.description;
      _costController.text = existing.cost > 0
          ? existing.cost.toStringAsFixed(2)
          : '';
      _performedByController.text = existing.performedBy ?? '';
      _date = existing.date;
      _nextDate = existing.nextMaintenanceDate;
      _type = existing.type;
    } else {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _costController.dispose();
    _performedByController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final currencySymbol = CurrencyUtils.getSymbol(
      context.read<WorkspaceProvider>().currencyCode,
    );
    return AlertDialog(
      title: Text(isEdit ? 'Edit maintenance' : 'Log maintenance'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StackedField(
                label: 'Type',
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: _typeOptions
                      .map(
                        (o) => DropdownMenuItem(value: o, child: Text(_typeLabel(o))),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
              ),
              const SizedBox(height: 12),
              StackedField(
                label: 'Description *',
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(_formatDate(_date)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Next service due'),
                subtitle: Text(
                  _nextDate == null ? 'Not set' : _formatDate(_nextDate!),
                ),
                trailing: _nextDate == null
                    ? const Icon(Icons.calendar_today, size: 18)
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _nextDate = null),
                      ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _nextDate ??
                        DateTime.now().add(const Duration(days: 90)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => _nextDate = picked);
                },
              ),
              const SizedBox(height: 12),
              StackedField(
                label: 'Cost',
                child: TextField(
                  controller: _costController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixText: '$currencySymbol ',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(height: 12),
              StackedField(
                label: 'Performed by',
                child: TextField(
                  controller: _performedByController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Vendor or team member',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final description = _descriptionController.text.trim();
            if (description.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Description is required')),
              );
              return;
            }
            final base = widget.existing;
            final log = MaintenanceLog(
              id: base?.id ?? '',
              workspaceId: widget.workspaceId,
              entityId: widget.assetId,
              entityType: 'asset',
              date: _date,
              type: _type,
              description: description,
              cost: double.tryParse(_costController.text.trim()) ?? 0.0,
              performedBy: _performedByController.text.trim().isEmpty
                  ? null
                  : _performedByController.text.trim(),
              nextMaintenanceDate: _nextDate,
            );
            Navigator.of(context).pop(log);
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'oil_change':
      return 'Oil change';
    case 'repair':
      return 'Repair';
    case 'inspection':
      return 'Inspection';
    default:
      return 'Other';
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'oil_change':
      return Icons.oil_barrel_outlined;
    case 'repair':
      return Icons.build_outlined;
    case 'inspection':
      return Icons.fact_check_outlined;
    default:
      return Icons.handyman_outlined;
  }
}

Color _typeColor(String type) {
  switch (type) {
    case 'oil_change':
      return AppColors.info;
    case 'repair':
      return AppColors.warning;
    case 'inspection':
      return AppColors.primary;
    default:
      return AppColors.textSecondary;
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
