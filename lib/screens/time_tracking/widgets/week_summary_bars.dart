import 'package:flutter/material.dart';
import '../../../models/time_entry.dart';
import '../../../models/user.dart';
import '../../../theme/theme.dart';

const double _kOtRiskThreshold = 38.0; // hours
const double _kOtThreshold = 40.0; // hours

/// Per-person horizontal progress bars for the admin dashboard.
///
/// Colored by OT status: blue < 38h, amber 38–40h, red ≥ 40h.
class WeekSummaryBars extends StatelessWidget {
  /// All workspace time entries for the current week.
  final List<TimeEntry> weekEntries;
  final Map<String, AppUser> usersMap;

  const WeekSummaryBars({
    super.key,
    required this.weekEntries,
    required this.usersMap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Aggregate hours per worker
    final hoursPerWorker = <String, double>{};
    for (final entry in weekEntries) {
      final hours = entry.totalDuration / 60.0;
      hoursPerWorker[entry.workerId] =
          (hoursPerWorker[entry.workerId] ?? 0.0) + hours;
    }

    if (hoursPerWorker.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
        child: Center(
          child: Text(
            'No hours logged this week',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Sort descending by hours
    final sorted = hoursPerWorker.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxHours = sorted.first.value.clamp(_kOtThreshold, double.infinity);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Week Summary by Person',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...sorted.map((e) {
              final user = usersMap[e.key];
              final name = user?.displayName ?? user?.email ?? 'Unknown';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WorkerBar(
                  name: name,
                  hours: e.value,
                  maxHours: maxHours,
                  userId: e.key,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _WorkerBar extends StatelessWidget {
  final String name;
  final double hours;
  final double maxHours;
  final String userId;

  const _WorkerBar({
    required this.name,
    required this.hours,
    required this.maxHours,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (hours / maxHours).clamp(0.0, 1.0);
    final isOt = hours >= _kOtThreshold;
    final isRisk = hours >= _kOtRiskThreshold && !isOt;
    final barColor = isOt
        ? theme.colorScheme.error
        : isRisk
            ? Colors.orange.shade600
            : theme.colorScheme.primary;
    final hoursLabel = _fmtHours(hours);

    return Row(
      children: [
        // Name
        SizedBox(
          width: 100,
          child: Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isOt ? theme.colorScheme.error : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // Bar
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Stack(
              children: [
                Container(
                  height: 6,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Hours label
        SizedBox(
          width: 44,
          child: Text(
            hoursLabel,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isOt
                  ? theme.colorScheme.error
                  : isRisk
                      ? Colors.orange.shade700
                      : null,
            ),
          ),
        ),
        // OT badge
        if (isOt || isRisk) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isOt
                  ? AppColors.errorLight
                  : AppColors.warningLight,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              isOt ? 'OT' : 'RISK',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: isOt ? AppColors.error : AppColors.warningDark,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _fmtHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
