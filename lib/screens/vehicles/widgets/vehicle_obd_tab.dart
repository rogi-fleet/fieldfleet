import 'package:flutter/material.dart';
import '../../../models/vehicle.dart';
import '../../../theme/theme.dart';

class VehicleObdTab extends StatelessWidget {
  final Vehicle vehicle;

  const VehicleObdTab({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusBanner(context),
          const SizedBox(height: AppSpacing.base),
          _buildLiveDataGrid(context),
          const SizedBox(height: AppSpacing.base),
          _buildFeaturesCard(context),
          const SizedBox(height: AppSpacing.base),
          _buildSetupCard(context),
          const SizedBox(height: AppSpacing.base),
          _buildCompatibilityCard(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.primaryLight.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: AppRadius.cardRadius,
            ),
            child: const Icon(
              Icons.sensors_outlined,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live OBD Data',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Real-time vehicle diagnostics via OBD-II adapter — coming soon',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: AppRadius.chipRadius,
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Coming Soon',
              style: TextStyle(
                color: AppColors.warningDark,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveDataGrid(BuildContext context) {
    final metrics = [
      _ObdMetric(
        icon: Icons.speed_outlined,
        label: 'Speed',
        unit: 'mph',
        color: AppColors.primary,
        placeholder: '—',
      ),
      _ObdMetric(
        icon: Icons.rotate_right_outlined,
        label: 'RPM',
        unit: 'rpm',
        color: AppColors.info,
        placeholder: '—',
      ),
      _ObdMetric(
        icon: Icons.thermostat_outlined,
        label: 'Coolant Temp',
        unit: '°F',
        color: AppColors.error,
        placeholder: '—',
      ),
      _ObdMetric(
        icon: Icons.local_gas_station_outlined,
        label: 'Fuel Level',
        unit: '%',
        color: AppColors.warning,
        placeholder: '—',
      ),
      _ObdMetric(
        icon: Icons.battery_charging_full_outlined,
        label: 'Battery',
        unit: 'V',
        color: AppColors.success,
        placeholder: '—',
      ),
      _ObdMetric(
        icon: Icons.air_outlined,
        label: 'Intake Air',
        unit: '°F',
        color: AppColors.invoiceAccent,
        placeholder: '—',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Metrics',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.2,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, i) => _ObdMetricCard(metric: metrics[i]),
        ),
      ],
    );
  }

  Widget _buildFeaturesCard(BuildContext context) {
    final features = [
      (
        Icons.error_outline,
        'Fault Codes & Diagnostics (DTCs)',
        'Read and clear check engine codes instantly'
      ),
      (
        Icons.local_gas_station_outlined,
        'Fuel Efficiency Tracking',
        'MPG, fuel consumed, refill alerts'
      ),
      (
        Icons.route_outlined,
        'Trip Logging',
        'Automatic start/end detection with distance and duration'
      ),
      (
        Icons.location_on_outlined,
        'Live Location',
        'Real-time GPS tracking on the fleet map'
      ),
      (
        Icons.thermostat_outlined,
        'Engine Health Monitoring',
        'Temperature, pressure, and load analysis'
      ),
      (
        Icons.notifications_outlined,
        'Smart Alerts',
        'Get notified the moment a fault code is triggered'
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: Text(
              'What You\'ll Get',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          ...features.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: AppRadius.badgeRadius,
                        ),
                        child: Icon(f.$1, size: 18, color: AppColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.$3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.lock_outline,
                          size: 14, color: AppColors.textTertiary),
                    ],
                  ),
                ),
                if (i < features.length - 1)
                  const Divider(height: 1, color: AppColors.cardBorder),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSetupCard(BuildContext context) {
    final steps = [
      'Purchase a Bluetooth or Wi-Fi OBD-II adapter (ELM327 compatible)',
      'Plug the adapter into your vehicle\'s OBD-II port (under the dashboard)',
      'Connect FieldFleet to the adapter via the device settings in this screen',
      'Live data streams automatically for this vehicle',
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: Text(
              'How to Set Up',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              children: steps.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, 0, AppSpacing.base, AppSpacing.base),
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.bluetooth_outlined, size: 18),
              label: const Text('Connect OBD Device (Coming Soon)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                disabledForegroundColor:
                    AppColors.textTertiary.withValues(alpha: 0.8),
                disabledMouseCursor: SystemMouseCursors.forbidden,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompatibilityCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'OBD-II is standard on all vehicles manufactured after 1996 '
              '(US) and 2001 (EU). Light trucks, SUVs, and vans are also '
              'supported. Heavy-duty vehicles and diesel trucks may require '
              'a specialized adapter.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── OBD Metric ───────────────────────────────────────────────────────────────

class _ObdMetric {
  final IconData icon;
  final String label;
  final String unit;
  final Color color;
  final String placeholder;

  const _ObdMetric({
    required this.icon,
    required this.label,
    required this.unit,
    required this.color,
    required this.placeholder,
  });
}

class _ObdMetricCard extends StatelessWidget {
  final _ObdMetric metric;

  const _ObdMetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(metric.icon, size: 18, color: metric.color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    metric.placeholder,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  if (metric.placeholder != '—')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 2),
                      child: Text(
                        metric.unit,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                metric.label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
