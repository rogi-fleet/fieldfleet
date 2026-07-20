import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/time_entry.dart';
import '../../../theme/theme.dart';

/// Shows the current week at a glance: a bar chart (Mon–Sun) plus totals.
///
/// Consumed by [ClockInOutScreen] as the right panel on desktop or as a card
/// below the clock widget on mobile.
class MyWeekCard extends StatefulWidget {
  final List<TimeEntry> weekEntries;
  final bool isLoading;
  final bool isClockedIn;

  const MyWeekCard({
    super.key,
    required this.weekEntries,
    this.isLoading = false,
    this.isClockedIn = false,
  });

  @override
  State<MyWeekCard> createState() => _MyWeekCardState();
}

class _MyWeekCardState extends State<MyWeekCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isClockedIn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant MyWeekCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isClockedIn && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isClockedIn && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final weekStart = _weekStart(now);

    // Hours per day (Mon=0 … Sun=6).
    final List<double> dayHours = List.filled(7, 0.0);
    for (final entry in widget.weekEntries) {
      final dayIndex = entry.date.weekday - 1; // 1=Mon→0 … 7=Sun→6
      if (dayIndex >= 0 && dayIndex < 7) {
        dayHours[dayIndex] += entry.totalDuration / 60.0;
      }
    }

    final todayIndex = now.weekday - 1;
    final weekTotal = dayHours.fold(0.0, (a, b) => a + b);
    final todayHours = dayHours[todayIndex];
    final maxY = dayHours.fold(8.0, (a, b) => b > a ? b : a).ceilToDouble();

    // Today's entries for the bottom summary strip.
    final todayEntries = widget.weekEntries
        .where(
          (e) =>
              e.date.year == now.year &&
              e.date.month == now.month &&
              e.date.day == now.day,
        )
        .toList();
    final lastProject = todayEntries.isNotEmpty ? todayEntries.last : null;
    final targetHours = 40.0;
    final progressPct = (weekTotal / targetHours).clamp(0.0, 1.0);
    final overtimeThreshold = 38.0;

    final card = AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulseController.value);
        final glow = widget.isClockedIn ? t : 0.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(
              color: widget.isClockedIn
                  ? Color.lerp(
                      AppColors.success.withValues(alpha: 0.35),
                      AppColors.success,
                      glow,
                    )!
                  : theme.colorScheme.outlineVariant,
              width: widget.isClockedIn ? 1.5 : 1,
            ),
            boxShadow: widget.isClockedIn
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(
                        alpha: 0.15 + 0.25 * glow,
                      ),
                      blurRadius: 10 + 14 * glow,
                      spreadRadius: 1 + 3 * glow,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'My Week',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _WeekRangeBadge(weekStart: weekStart),
                ],
              ),
              const SizedBox(height: 20),
              if (widget.isLoading)
                const SizedBox(
                  height: 120,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                SizedBox(
                  height: 120,
                  child: _WeekBarChart(
                    dayHours: dayHours,
                    todayIndex: todayIndex,
                    maxY: maxY,
                    theme: theme,
                  ),
                ),
              const SizedBox(height: 16),
              // Totals row
              Row(
                children: [
                  Expanded(
                    child: _StatCell(
                      label: 'This week',
                      value: _fmtHours(weekTotal),
                      valueColor: weekTotal >= targetHours
                          ? theme.colorScheme.error
                          : weekTotal >= overtimeThreshold
                              ? Colors.orange.shade700
                              : null,
                    ),
                  ),
                  Expanded(
                    child: _StatCell(
                      label: 'Today',
                      value: _fmtHours(todayHours),
                    ),
                  ),
                  Expanded(
                    child: _StatCell(
                      label: 'Entries',
                      value: widget.weekEntries.length.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Progress bar toward 40h
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress toward 40h',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${(progressPct * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: weekTotal >= targetHours
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(
                      value: progressPct,
                      minHeight: 6,
                      backgroundColor: AppColors.background,
                      valueColor: AlwaysStoppedAnimation(
                        weekTotal >= targetHours
                            ? theme.colorScheme.error
                            : weekTotal >= overtimeThreshold
                                ? Colors.orange.shade600
                                : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              // TODAY summary strip
              if (todayEntries.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'TODAY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Logged hours
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtHours(todayHours),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Logged',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // Entry count
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${todayEntries.length}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          todayEntries.length == 1 ? 'Entry' : 'Entries',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (lastProject != null) ...[
                      const SizedBox(width: 24),
                      // Last clock-in time
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('h:mm a').format(lastProject.clockIn),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Last clock-in',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return card;
  }

  String _fmtHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h == 0 && m == 0) return '—';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  DateTime _weekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }
}

class _WeekBarChart extends StatelessWidget {
  final List<double> dayHours;
  final int todayIndex;
  final double maxY;
  final ThemeData theme;

  const _WeekBarChart({
    required this.dayHours,
    required this.todayIndex,
    required this.maxY,
    required this.theme,
  });

  static const _dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final accent =
        const Color(0xFFF97316); // orange – matches FieldFleet accent
    final primary = theme.colorScheme.primary;

    return BarChart(
      BarChartData(
        maxY: maxY + 1,
        minY: 0,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 4,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                final isToday = idx == todayIndex;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dayLabels[idx],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color:
                          isToday ? accent : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 8,
              color: theme.colorScheme.outlineVariant,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        barGroups: List.generate(7, (i) {
          final isToday = i == todayIndex;
          final hours = dayHours[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: hours > 0 ? hours : 0,
                width: 16,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isToday
                      ? [accent, accent.withOpacity(0.7)]
                      : [primary, primary.withOpacity(0.7)],
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY + 1,
                  color: AppColors.background,
                ),
              ),
            ],
          );
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final hours = rod.toY;
              final h = hours.floor();
              final m = ((hours - h) * 60).round();
              final label = m > 0 ? '${h}h ${m}m' : '${h}h';
              return BarTooltipItem(
                label,
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WeekRangeBadge extends StatelessWidget {
  final DateTime weekStart;

  const _WeekRangeBadge({required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = weekStart.add(const Duration(days: 6));
    final startFmt = _fmt(weekStart);
    final endFmt = _fmt(end);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        '$startFmt–$endFmt',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
