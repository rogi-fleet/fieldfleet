import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/maintenance_log.dart';
import '../../../models/vehicle.dart';
import '../../../models/vehicle_expense.dart';
import '../../../services/supabase/vehicle_service.dart';
import '../../../theme/theme.dart';

class VehicleOverviewTab extends StatelessWidget {
  final Vehicle vehicle;
  final SupabaseVehicleService vehicleService;

  const VehicleOverviewTab({
    super.key,
    required this.vehicle,
    required this.vehicleService,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(context),
          const SizedBox(height: AppSpacing.base),
          _buildStatsRow(context),
          const SizedBox(height: AppSpacing.base),
          _buildInfoSection(context),
          const SizedBox(height: AppSpacing.base),
          _buildFinancialSummary(context),
          if ((vehicle.qrCode ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _buildQrSection(context),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final hasImage = (vehicle.imageUrl ?? '').isNotEmpty;
    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: vehicle.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surfaceAlt,
      child: const Center(
        child: Icon(
          Icons.directions_car,
          size: 72,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.speed_outlined,
            label: 'Mileage',
            value: _formatMileage(vehicle.currentMileage),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: Icons.calendar_today_outlined,
            label: 'Year',
            value: vehicle.year > 0 ? vehicle.year.toString() : '—',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            icon: _statusIcon(vehicle.status),
            label: 'Status',
            value: _statusLabel(vehicle.status),
            color: _statusColor(vehicle.status),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return _Card(
      title: 'Vehicle Info',
      children: [
        _InfoRow(label: 'Name', value: vehicle.name),
        _InfoRow(label: 'Make', value: vehicle.make.isEmpty ? '—' : vehicle.make),
        _InfoRow(label: 'Model', value: vehicle.model.isEmpty ? '—' : vehicle.model),
        _InfoRow(label: 'Year', value: vehicle.year > 0 ? vehicle.year.toString() : '—'),
        _InfoRow(
          label: 'License Plate',
          value: vehicle.licensePlate.isEmpty ? '—' : vehicle.licensePlate,
          mono: true,
        ),
        if ((vehicle.vin ?? '').isNotEmpty)
          _InfoRow(
            label: 'VIN',
            value: vehicle.vin!,
            mono: true,
            copyable: true,
          ),
        _InfoRow(label: 'Status', value: _statusLabel(vehicle.status)),
        if (vehicle.insuranceExpiry != null)
          _InfoRow(
            label: 'Insurance Expiry',
            value: _expiryValue(vehicle.insuranceExpiry!),
            valueColor: _expiryColor(vehicle.insuranceExpiry!),
            bold: _isExpiringSoon(vehicle.insuranceExpiry!),
          ),
        if (vehicle.registrationExpiry != null)
          _InfoRow(
            label: 'Registration Expiry',
            value: _expiryValue(vehicle.registrationExpiry!),
            valueColor: _expiryColor(vehicle.registrationExpiry!),
            bold: _isExpiringSoon(vehicle.registrationExpiry!),
          ),
      ],
    );
  }

  bool _isExpiringSoon(DateTime d) =>
      d.difference(DateTime.now()).inDays <= 30;

  String _expiryValue(DateTime d) {
    final days = d.difference(DateTime.now()).inDays;
    final date = _formatDate(d);
    if (days < 0) return '$date · EXPIRED';
    if (days == 0) return '$date · expires today';
    if (days <= 30) return '$date · in $days ${days == 1 ? 'day' : 'days'}';
    return date;
  }

  Color _expiryColor(DateTime d) {
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return AppColors.error;
    if (days <= 30) return AppColors.warning;
    return AppColors.textPrimary;
  }

  Widget _buildFinancialSummary(BuildContext context) {
    return FutureBuilder<List<MaintenanceLog>>(
      future: vehicleService.getMaintenanceLogsOnce(vehicle.id),
      builder: (context, maintSnap) {
        return FutureBuilder<List<VehicleExpense>>(
          future: vehicleService.getExpensesOnce(vehicle.id),
          builder: (context, expSnap) {
            final maintLogs = maintSnap.data ?? [];
            final expenses = expSnap.data ?? [];

            final totalMaint = maintLogs.fold<double>(
              0.0, (sum, l) => sum + l.cost);
            final totalExp = expenses.fold<double>(
              0.0, (sum, e) => sum + e.amount);

            final lastService = maintLogs.isNotEmpty ? maintLogs.first : null;

            return _Card(
              title: 'Fleet Summary',
              children: [
                _InfoRow(
                  label: 'Total Maintenance',
                  value: '\$${totalMaint.toStringAsFixed(2)}',
                ),
                _InfoRow(
                  label: 'Total Expenses',
                  value: '\$${totalExp.toStringAsFixed(2)}',
                ),
                _InfoRow(
                  label: 'Combined Cost',
                  value: '\$${(totalMaint + totalExp).toStringAsFixed(2)}',
                  bold: true,
                ),
                if (lastService != null)
                  _InfoRow(
                    label: 'Last Service',
                    value: _formatDate(lastService.date),
                  ),
                _InfoRow(
                  label: 'Maintenance Records',
                  value: maintLogs.length.toString(),
                ),
                _InfoRow(
                  label: 'Expense Records',
                  value: expenses.length.toString(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildQrSection(BuildContext context) {
    return _Card(
      title: 'QR Code',
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.cardRadius,
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: QrImageView(
              data: vehicle.qrCode!,
              version: QrVersions.auto,
              size: 160,
              gapless: false,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            vehicle.qrCode!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatMileage(int miles) {
    if (miles >= 1000) {
      return '${(miles / 1000).toStringAsFixed(1)}k mi';
    }
    return '$miles mi';
  }

  String _formatDate(DateTime d) =>
      '${d.month}/${d.day}/${d.year}';

  String _statusLabel(String s) {
    if (s.isEmpty) return 'Unknown';
    return s[0].toUpperCase() + s.substring(1);
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'active':
        return Icons.check_circle_outline;
      case 'maintenance':
        return Icons.build_circle_outlined;
      case 'retired':
        return Icons.archive_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return AppColors.success;
      case 'maintenance':
        return AppColors.warning;
      case 'retired':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool bold;
  final bool copyable;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.bold = false,
    this.copyable = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: copyable
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$label copied'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: mono ? 'monospace' : null,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                        color: valueColor ?? AppColors.textPrimary,
                        decoration: copyable
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                  if (copyable)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.copy_outlined,
                        size: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
