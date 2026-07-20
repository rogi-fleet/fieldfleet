import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/maintenance_log.dart';
import '../../../models/vehicle.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/supabase/vehicle_service.dart';
import '../../../theme/theme.dart';
import '../../../widgets/common/list_skeleton.dart';
import '../../../widgets/forms/stacked_field.dart';
import '../../../utils/numeric_input.dart';

class VehicleMaintenanceTab extends StatefulWidget {
  final Vehicle vehicle;
  final SupabaseVehicleService vehicleService;

  const VehicleMaintenanceTab({
    super.key,
    required this.vehicle,
    required this.vehicleService,
  });

  @override
  State<VehicleMaintenanceTab> createState() => _VehicleMaintenanceTabState();
}

class _VehicleMaintenanceTabState extends State<VehicleMaintenanceTab> {
  String _filter = 'all';

  static const _types = [
    ('all', 'All'),
    ('oil_change', 'Oil Change'),
    ('tire', 'Tires'),
    ('brake', 'Brakes'),
    ('fluid', 'Fluids'),
    ('filter', 'Filters'),
    ('inspection', 'Inspection'),
    ('repair', 'Repair'),
    ('other', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MaintenanceLog>>(
      stream: widget.vehicleService.getMaintenanceLogs(widget.vehicle.id),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];
        final filtered = _filter == 'all'
            ? logs
            : logs.where((l) => l.type == _filter).toList();

        final totalCost = logs.fold<double>(0.0, (s, l) => s + l.cost);

        return Column(
          children: [
            _buildHeader(context, logs, totalCost),
            _buildFilterChips(),
            Expanded(
              child: snapshot.connectionState == ConnectionState.waiting &&
                      logs.isEmpty
                  ? const ListSkeleton(itemCount: 3)
                  : filtered.isEmpty
                  ? _buildEmpty(context)
                  : _buildList(context, filtered),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, List<MaintenanceLog> logs, double totalCost) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.sm, AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${logs.length} record${logs.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (logs.isNotEmpty)
                  Text(
                    'Total: \$${totalCost.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          _buildNextServiceBadge(logs),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () => _showMaintenanceForm(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildNextServiceBadge(List<MaintenanceLog> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();
    final latest = logs.first;
    final now = DateTime.now();
    bool due = false;
    bool soon = false;
    String label = '';

    if (latest.nextMaintenanceDate != null) {
      if (now.isAfter(latest.nextMaintenanceDate!)) {
        due = true;
        label = 'Service overdue';
      } else {
        final days = latest.nextMaintenanceDate!.difference(now).inDays;
        if (days <= 14) {
          soon = true;
          label = 'Due in $days days';
        }
      }
    }
    if (latest.nextMaintenanceMileage != null) {
      final milesLeft =
          latest.nextMaintenanceMileage! - widget.vehicle.currentMileage;
      if (milesLeft <= 0) {
        due = true;
        label = 'Service overdue';
      } else if (milesLeft <= 500) {
        soon = true;
        label = 'Due in $milesLeft mi';
      }
    }

    if (!due && !soon) return const SizedBox.shrink();
    final color = due ? AppColors.error : AppColors.warning;
    final bg = due ? AppColors.errorLight : AppColors.warningLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: _types.map((t) {
          final selected = _filter == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: FilterChip(
              label: Text(t.$2),
              selected: selected,
              onSelected: (_) => setState(() => _filter = t.$1),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<MaintenanceLog> logs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, 0, AppSpacing.base, 80),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) =>
          _MaintenanceCard(
            log: logs[index],
            vehicleService: widget.vehicleService,
            vehicle: widget.vehicle,
            onEdit: () => _showMaintenanceForm(context, log: logs[index]),
          ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_circle_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.base),
            const Text(
              'No maintenance records',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Log oil changes, inspections, repairs\nand set next service reminders.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => _showMaintenanceForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add First Record'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMaintenanceForm(BuildContext context,
      {MaintenanceLog? log}) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.activeWorkspaceId ??
        authProvider.appUser?.workspaceId ?? '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => _MaintenanceFormDialog(
        vehicleId: widget.vehicle.id,
        workspaceId: workspaceId,
        vehicleService: widget.vehicleService,
        existingLog: log,
        currentMileage: widget.vehicle.currentMileage,
      ),
    );
  }
}

// ─── Maintenance Card ────────────────────────────────────────────────────────

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceLog log;
  final SupabaseVehicleService vehicleService;
  final Vehicle vehicle;
  final VoidCallback onEdit;

  const _MaintenanceCard({
    required this.log,
    required this.vehicleService,
    required this.vehicle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _typeColor(log.type).withValues(alpha: 0.1),
                  borderRadius: AppRadius.badgeRadius,
                ),
                child: Icon(
                  _typeIcon(log.type),
                  size: 18,
                  color: _typeColor(log.type),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(log.type),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatDate(log.date),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '\$${log.cost.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildMenu(context),
            ],
          ),
          if (log.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              log.description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if ((log.performedBy ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  log.performedBy!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
          if (log.nextMaintenanceDate != null ||
              log.nextMaintenanceMileage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.cardBorder),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.schedule_outlined,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  _nextServiceLabel(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18,
          color: AppColors.textTertiary),
      onSelected: (v) async {
        if (v == 'edit') {
          onEdit();
        } else if (v == 'delete') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Record'),
              content: const Text(
                  'Remove this maintenance record permanently?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await vehicleService.deleteMaintenanceLog(log.id);
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }

  String _nextServiceLabel() {
    final parts = <String>[];
    if (log.nextMaintenanceDate != null) {
      final d = log.nextMaintenanceDate!;
      parts.add('Next service: ${d.month}/${d.day}/${d.year}');
    }
    if (log.nextMaintenanceMileage != null) {
      parts.add('at ${log.nextMaintenanceMileage} mi');
    }
    return parts.join(' ');
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  static String _typeLabel(String type) {
    switch (type) {
      case 'oil_change':
        return 'Oil Change';
      case 'tire':
        return 'Tire Service';
      case 'brake':
        return 'Brake Service';
      case 'fluid':
        return 'Fluid Change';
      case 'filter':
        return 'Filter Replacement';
      case 'inspection':
        return 'Inspection';
      case 'repair':
        return 'Repair';
      default:
        return 'Maintenance';
    }
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'oil_change':
        return Icons.opacity_outlined;
      case 'tire':
        return Icons.tire_repair_outlined;
      case 'brake':
        return Icons.radio_button_checked_outlined;
      case 'fluid':
        return Icons.water_drop_outlined;
      case 'filter':
        return Icons.filter_alt_outlined;
      case 'inspection':
        return Icons.fact_check_outlined;
      case 'repair':
        return Icons.build_outlined;
      default:
        return Icons.handyman_outlined;
    }
  }

  static Color _typeColor(String type) {
    switch (type) {
      case 'oil_change':
        return AppColors.warning;
      case 'tire':
        return AppColors.info;
      case 'brake':
        return AppColors.error;
      case 'fluid':
        return AppColors.primary;
      case 'filter':
        return AppColors.success;
      case 'inspection':
        return AppColors.invoiceAccent;
      case 'repair':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }
}

// ─── Maintenance Form Dialog ─────────────────────────────────────────────────

class _MaintenanceFormDialog extends StatefulWidget {
  final String vehicleId;
  final String workspaceId;
  final SupabaseVehicleService vehicleService;
  final MaintenanceLog? existingLog;
  final int currentMileage;

  const _MaintenanceFormDialog({
    required this.vehicleId,
    required this.workspaceId,
    required this.vehicleService,
    this.existingLog,
    required this.currentMileage,
  });

  @override
  State<_MaintenanceFormDialog> createState() =>
      _MaintenanceFormDialogState();
}

class _MaintenanceFormDialogState extends State<_MaintenanceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descController;
  late TextEditingController _costController;
  late TextEditingController _performedByController;
  late TextEditingController _nextMileageController;
  late String _type;
  late DateTime _date;
  DateTime? _nextDate;
  bool _saving = false;

  static const _typeOptions = [
    ('oil_change', 'Oil Change'),
    ('tire', 'Tire Service'),
    ('brake', 'Brake Service'),
    ('fluid', 'Fluid Change'),
    ('filter', 'Filter Replacement'),
    ('inspection', 'Inspection'),
    ('repair', 'Repair'),
    ('other', 'Other'),
  ];

  bool get _isEditing => widget.existingLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.existingLog;
    _type = log?.type ?? 'oil_change';
    _date = log?.date ?? DateTime.now();
    _nextDate = log?.nextMaintenanceDate;
    _descController =
        TextEditingController(text: log?.description ?? '');
    _costController = TextEditingController(
        text: log != null && log.cost > 0
            ? log.cost.toStringAsFixed(2)
            : '');
    _performedByController =
        TextEditingController(text: log?.performedBy ?? '');
    _nextMileageController = TextEditingController(
        text: log?.nextMaintenanceMileage?.toString() ?? '');
  }

  @override
  void dispose() {
    _descController.dispose();
    _costController.dispose();
    _performedByController.dispose();
    _nextMileageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogHeader(),
              const Divider(height: 1, color: AppColors.cardBorder),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StackedField(
                        label: 'Type *',
                        child: DropdownButtonFormField<String>(
                          value: _type,
                          decoration: const InputDecoration(),
                          items: _typeOptions
                              .map((t) => DropdownMenuItem(
                                    value: t.$1,
                                    child: Text(t.$2),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _type = v ?? _type),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      StackedField(
                        label: 'Description',
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'What was done?',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Row(
                        children: [
                          Expanded(
                            child: StackedField(
                              label: 'Date *',
                              child: InkWell(
                                onTap: _pickDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(),
                                  child: Text(_formatDate(_date)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StackedField(
                              label: 'Cost (\$)',
                              child: TextFormField(
                                controller: _costController,
                                keyboardType: NumericInput.keyboard,
                                inputFormatters: NumericInput.currency,
                                decoration: const InputDecoration(
                                    prefixText: '\$ '),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      StackedField(
                        label: 'Performed By',
                        child: TextFormField(
                          controller: _performedByController,
                          decoration: const InputDecoration(
                            hintText: 'Person or shop name',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const Text(
                        'Next Service Reminder',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: StackedField(
                              label: 'Next Date',
                              child: InkWell(
                                onTap: _pickNextDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    suffixIcon: Icon(
                                        Icons.calendar_today_outlined,
                                        size: 18),
                                  ),
                                  child: Text(
                                    _nextDate != null
                                        ? _formatDate(_nextDate!)
                                        : 'Set date',
                                    style: TextStyle(
                                      color: _nextDate != null
                                          ? AppColors.textPrimary
                                          : AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: StackedField(
                              label: 'Next Mileage',
                              child: TextFormField(
                                controller: _nextMileageController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                    hintText: 'e.g. 55000'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.cardBorder),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(_isEditing ? 'Save Changes' : 'Add Record'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.base, AppSpacing.sm, AppSpacing.base),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: AppRadius.badgeRadius,
            ),
            child: const Icon(Icons.build_outlined,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEditing ? 'Edit Maintenance Record' : 'Add Maintenance Record',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickNextDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _nextDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final log = MaintenanceLog(
        id: widget.existingLog?.id ?? '',
        workspaceId: widget.workspaceId,
        entityId: widget.vehicleId,
        entityType: 'vehicle',
        date: _date,
        type: _type,
        description: _descController.text.trim(),
        cost: double.tryParse(_costController.text.trim()) ?? 0.0,
        performedBy: _performedByController.text.trim().isEmpty
            ? null
            : _performedByController.text.trim(),
        nextMaintenanceDate: _nextDate,
        nextMaintenanceMileage:
            int.tryParse(_nextMileageController.text.trim()),
      );

      if (_isEditing) {
        await widget.vehicleService.updateMaintenanceLog(log);
      } else {
        await widget.vehicleService.addMaintenanceLog(log);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';
}
