import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/maintenance_log.dart';
import '../../../models/user.dart';
import '../../../models/vehicle.dart';
import '../../../theme/theme.dart';
import '../../../widgets/common/card_placeholder_background.dart';
import '../../../widgets/common/entity_card_actions_menu.dart';
import '../../../widgets/common/status_chip.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/vehicle_form_popup.dart';

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final AppUser? assignedUser;
  final MaintenanceLog? latestLog;
  final List<MaintenanceLog> recentLogs;
  final VoidCallback? onQuickLog;
  final VoidCallback? onToggleStatus;

  const VehicleCard({
    super.key,
    required this.vehicle,
    this.assignedUser,
    this.latestLog,
    this.recentLogs = const [],
    this.onQuickLog,
    this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: () => context.push('/vehicles/${vehicle.id}'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(context, compact: compact),
                Padding(
                  padding: EdgeInsets.all(compact ? 12 : AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetaRow(compact),
                      const SizedBox(height: AppSpacing.sm),
                      _buildAssignmentRow(),
                      const SizedBox(height: AppSpacing.sm),
                      if (_maintenanceDue())
                        _buildMaintenanceAlert(compact)
                      else if (_maintenanceDueSoon())
                        _buildMaintenanceSoon(compact)
                      else
                        _buildMaintenanceSummary(),
                      if (!compact) ...[
                        const SizedBox(height: AppSpacing.md),
                        _buildRecentLogs(),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: onQuickLog,
                            icon: const Icon(Icons.build_outlined, size: 18),
                            label: Text(compact ? 'Log' : 'Quick Log'),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          TextButton.icon(
                            onPressed: () =>
                                context.push('/vehicles/${vehicle.id}'),
                            icon: const Icon(Icons.chevron_right, size: 18),
                            label: const Text('Details'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, {required bool compact}) {
    final title = [
      if (vehicle.year > 0) vehicle.year.toString(),
      if (vehicle.make.isNotEmpty) vehicle.make,
      if (vehicle.model.isNotEmpty) vehicle.model,
    ].join(' ');

    return SizedBox(
      height: compact ? 144 : 170,
      child: Stack(
        children: [
          Positioned.fill(child: _buildPhotoSection()),
          Positioned(
            top: 12,
            left: 12,
            child: _StatusChip(status: vehicle.status),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: [
                _buildQrBadge(compact),
                const SizedBox(width: 8),
                EntityCardActionsMenu(
                  compact: true,
                  items: _menuItems(),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        showVehicleFormPopup(context, vehicleId: vehicle.id);
                        break;
                      case 'details':
                        context.push('/vehicles/${vehicle.id}');
                        break;
                      case 'quick_log':
                        onQuickLog?.call();
                        break;
                      case 'toggle_status':
                        onToggleStatus?.call();
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<EntityCardActionItem> _menuItems() {
    final items = <EntityCardActionItem>[
      const EntityCardActionItem(
        value: 'edit',
        label: 'Edit',
        icon: Icons.edit,
      ),
      const EntityCardActionItem(
        value: 'details',
        label: 'View details',
        icon: Icons.open_in_new,
      ),
      if (onQuickLog != null)
        const EntityCardActionItem(
          value: 'quick_log',
          label: 'Quick log',
          icon: Icons.build_outlined,
        ),
    ];

    if (onToggleStatus != null) {
      final retired = vehicle.status == 'retired';
      items.add(
        EntityCardActionItem(
          value: 'toggle_status',
          label: retired ? 'Mark active' : 'Mark retired',
          icon: retired ? Icons.check_circle_outline : Icons.archive_outlined,
          isDestructive: !retired,
        ),
      );
    }

    return items;
  }

  Widget _buildMetaRow(bool compact) {
    return Row(
      children: [
        Expanded(
          child: _MetaPill(
            icon: Icons.confirmation_number_outlined,
            label: vehicle.licensePlate.isEmpty
                ? 'No plate'
                : vehicle.licensePlate,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _MetaPill(
            icon: Icons.speed_outlined,
            label: '${vehicle.currentMileage} mi',
          ),
        ),
        if (!compact && (vehicle.vin ?? '').isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _MetaPill(icon: Icons.numbers, label: 'VIN ${vehicle.vin!}'),
          ),
        ],
      ],
    );
  }

  Widget _buildAssignmentRow() {
    if (assignedUser == null) {
      return Row(
        children: const [
          Icon(Icons.person_outline, size: 16, color: AppColors.textTertiary),
          SizedBox(width: 8),
          Text('Unassigned', style: TextStyle(color: AppColors.textSecondary)),
        ],
      );
    }

    return Row(
      children: [
        UserAvatar(user: assignedUser, size: AvatarSize.small),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            assignedUser!.displayName ?? assignedUser!.email,
            style: const TextStyle(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceAlert(bool compact) {
    final label = _maintenanceDueLabel();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber,
            size: 16,
            color: AppColors.warningDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              compact ? 'Maintenance due' : label,
              style: const TextStyle(
                color: AppColors.warningDark,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceSummary() {
    final summary = _maintenanceSummary();
    return Row(
      children: [
        const Icon(
          Icons.build_circle_outlined,
          size: 16,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            summary,
            style: const TextStyle(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceSoon(bool compact) {
    final label = _maintenanceSoonLabel();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 16, color: AppColors.infoDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              compact ? 'Service due soon' : label,
              style: const TextStyle(
                color: AppColors.infoDark,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLogs() {
    if (recentLogs.isEmpty) {
      return const Text(
        'No recent maintenance logs',
        style: TextStyle(color: AppColors.textTertiary),
      );
    }

    final logs = recentLogs.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Maintenance',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        ...logs.map(
          (log) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.build_outlined,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_formatDate(log.date)} • ${log.description}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrBadge(bool compact) {
    if (vehicle.qrCode == null || vehicle.qrCode!.isEmpty) {
      return Container(
        padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: AppRadius.badgeRadius,
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(
          Icons.qr_code_2_outlined,
          size: compact ? 18 : 24,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: QrImageView(
        data: vehicle.qrCode!,
        size: compact ? 34 : 56,
        gapless: false,
      ),
    );
  }

  Widget _buildPhotoSection() {
    final hasImage = vehicle.imageUrl != null && vehicle.imageUrl!.isNotEmpty;
    return hasImage
        ? CachedNetworkImage(
            imageUrl: vehicle.imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => _buildPlaceholder(),
          )
        : _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return const CardPlaceholderBackground(
      centerOverlay: Icon(
        Icons.directions_car,
        size: 56,
        color: Colors.white70,
      ),
    );
  }

  bool _maintenanceDue() {
    if (latestLog == null) return false;
    final now = DateTime.now();
    if (latestLog!.nextMaintenanceDate != null &&
        now.isAfter(latestLog!.nextMaintenanceDate!)) {
      return true;
    }
    if (latestLog!.nextMaintenanceMileage != null &&
        vehicle.currentMileage >= latestLog!.nextMaintenanceMileage!) {
      return true;
    }
    return false;
  }

  bool _maintenanceDueSoon() {
    if (latestLog == null) return false;
    final now = DateTime.now();
    if (latestLog!.nextMaintenanceDate != null) {
      final dueDate = latestLog!.nextMaintenanceDate!;
      if (!now.isAfter(dueDate)) {
        final daysLeft = dueDate.difference(now).inDays;
        if (daysLeft <= 14) return true;
      }
    }
    if (latestLog!.nextMaintenanceMileage != null) {
      final milesLeft =
          latestLog!.nextMaintenanceMileage! - vehicle.currentMileage;
      if (milesLeft > 0 && milesLeft <= 500) return true;
    }
    return false;
  }

  String _maintenanceDueLabel() {
    if (latestLog == null) return 'Maintenance due';
    if (latestLog!.nextMaintenanceMileage != null &&
        vehicle.currentMileage >= latestLog!.nextMaintenanceMileage!) {
      return 'Maintenance due at ${latestLog!.nextMaintenanceMileage} mi';
    }
    if (latestLog!.nextMaintenanceDate != null) {
      final date = latestLog!.nextMaintenanceDate!;
      return 'Maintenance due ${date.month}/${date.day}/${date.year}';
    }
    return 'Maintenance due';
  }

  String _maintenanceSoonLabel() {
    if (latestLog == null) return 'Maintenance due soon';
    if (latestLog!.nextMaintenanceMileage != null) {
      final milesLeft =
          latestLog!.nextMaintenanceMileage! - vehicle.currentMileage;
      if (milesLeft > 0) {
        return 'Service due in $milesLeft mi';
      }
    }
    if (latestLog!.nextMaintenanceDate != null) {
      final date = latestLog!.nextMaintenanceDate!;
      return 'Service due by ${_formatDate(date)}';
    }
    return 'Maintenance due soon';
  }

  String _maintenanceSummary() {
    if (latestLog == null) return 'No maintenance history yet';
    if (latestLog!.nextMaintenanceMileage != null) {
      return 'Next service at ${latestLog!.nextMaintenanceMileage} mi';
    }
    if (latestLog!.nextMaintenanceDate != null) {
      final date = latestLog!.nextMaintenanceDate!;
      return 'Next service ${date.month}/${date.day}/${date.year}';
    }
    return 'Last service ${latestLog!.date.month}/${latestLog!.date.day}/${latestLog!.date.year}';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.badgeRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status.isEmpty
        ? 'Unknown'
        : status[0].toUpperCase() + status.substring(1);
    return StatusChip(label: label, color: _statusColor(status));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'maintenance':
        return AppColors.warning;
      case 'retired':
        return AppColors.error;
      case 'available':
        return AppColors.info;
      default:
        return AppColors.textTertiary;
    }
  }
}
