import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/time_entry.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

/// Quick clock-in/out widget showing current status and hours worked.
class TimeClockWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;

  const TimeClockWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  @override
  State<TimeClockWidget> createState() => _TimeClockWidgetState();
}

class _TimeClockWidgetState extends State<TimeClockWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),
            StreamBuilder<List<TimeEntry>>(
              stream: ServiceLocator.timeEntryService.getTimeEntries(
                widget.userId,
                workspaceId: widget.workspaceId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) return _buildErrorState();
                if (!snapshot.hasData) return _buildLoadingState();

                final entries = snapshot.data!;
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);

                // Find active entry (no clock out).
                final activeEntry = entries.cast<TimeEntry?>().firstWhere(
                  (e) => e!.clockOut == null,
                  orElse: () => null,
                );

                // Today's completed hours.
                final todaysEntries = entries.where((e) {
                  final entryDate = DateTime(
                    e.date.year,
                    e.date.month,
                    e.date.day,
                  );
                  return entryDate == today && e.clockOut != null;
                });

                double todaysMinutes = 0;
                for (final e in todaysEntries) {
                  todaysMinutes += e.totalDuration;
                }

                // Week hours (Mon-Sun).
                final weekday = now.weekday; // 1=Mon
                final weekStart = today.subtract(Duration(days: weekday - 1));
                final weekEntries = entries.where((e) {
                  final entryDate = DateTime(
                    e.date.year,
                    e.date.month,
                    e.date.day,
                  );
                  return !entryDate.isBefore(weekStart) &&
                      entryDate.isBefore(today.add(const Duration(days: 1))) &&
                      e.clockOut != null;
                });

                double weekMinutes = 0;
                for (final e in weekEntries) {
                  weekMinutes += e.totalDuration;
                }

                // Add active entry elapsed time to today/week.
                Duration elapsed = Duration.zero;
                if (activeEntry != null) {
                  elapsed = now.difference(activeEntry.clockIn);
                  todaysMinutes += elapsed.inMinutes;
                  weekMinutes += elapsed.inMinutes;
                }

                final isClockedIn = activeEntry != null;

                return Column(
                  children: [
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.iconGap,
                      ),
                      decoration: BoxDecoration(
                        color: isClockedIn
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: isClockedIn
                              ? AppColors.success.withValues(alpha: 0.3)
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isClockedIn
                                  ? AppColors.success
                                  : AppColors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.iconGap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isClockedIn ? 'Clocked In' : 'Clocked Out',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: isClockedIn
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                if (isClockedIn)
                                  Text(
                                    _formatElapsed(elapsed),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.iconGap),

                    // Hours summary row
                    Row(
                      children: [
                        Expanded(
                          child: _HoursSummary(
                            label: 'Today',
                            hours: todaysMinutes / 60,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.iconGap),
                        Expanded(
                          child: _HoursSummary(
                            label: 'This Week',
                            hours: weekMinutes / 60,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.iconGap),

                    // Clock in/out button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.go('/time-tracking'),
                        icon: Icon(
                          isClockedIn ? Icons.timer_off : Icons.timer,
                          size: 18,
                        ),
                        label: Text(
                          isClockedIn ? 'Clock Out' : 'Clock In',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: isClockedIn
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.timer,
            color: AppColors.success,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Time Clock',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/time-tracking'),
          child: const Text('History'),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Text(
        'Unable to load time data',
        style: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m elapsed';
    return '${minutes}m elapsed';
  }
}

class _HoursSummary extends StatelessWidget {
  final String label;
  final double hours;

  const _HoursSummary({required this.label, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${hours.toStringAsFixed(1)}h',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
