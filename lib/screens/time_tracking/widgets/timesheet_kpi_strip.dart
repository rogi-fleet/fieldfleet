import 'package:flutter/material.dart';
import '../../../theme/theme.dart';

/// Four KPI cards across the top of the admin timesheet dashboard.
class TimesheetKpiStrip extends StatelessWidget {
  final int activeWorkers;
  final int totalWorkers;
  final double weekTotalHours;
  final int pendingApprovals;
  final int otAlerts;

  const TimesheetKpiStrip({
    super.key,
    required this.activeWorkers,
    required this.totalWorkers,
    required this.weekTotalHours,
    required this.pendingApprovals,
    required this.otAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final h = weekTotalHours.floor();
    final m = ((weekTotalHours - h) * 60).round();
    final hoursLabel = m > 0 ? '${h}h ${m}m' : '${h}h';

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          // 2×2 on narrow mobile
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      label: 'On the Clock',
                      value: '$activeWorkers',
                      subtitle: totalWorkers > 0 ? 'of $totalWorkers this week' : 'clocked in',
                      dotColor: AppColors.success,
                      showDot: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiCard(
                      label: 'Week Hours',
                      value: hoursLabel,
                      subtitle: 'Mon – today',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      label: 'Awaiting Approval',
                      value: '$pendingApprovals',
                      subtitle: 'Pending review',
                      valueColor: pendingApprovals > 0
                          ? AppColors.warningDark
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiCard(
                      label: 'OT Alerts',
                      value: '$otAlerts',
                      subtitle: otAlerts > 0 ? 'Action needed' : 'All clear',
                      valueColor: otAlerts > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        // 4 across on wider screens
        return Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'On the Clock',
                value: '$activeWorkers',
                subtitle: 'of $totalWorkers team members',
                dotColor: AppColors.success,
                showDot: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                label: 'Week Hours',
                value: hoursLabel,
                subtitle: 'Mon – today',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                label: 'Awaiting Approval',
                value: '$pendingApprovals',
                subtitle: 'Pending review',
                valueColor: pendingApprovals > 0
                    ? AppColors.warningDark
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                label: 'OT Alerts',
                value: '$otAlerts',
                subtitle: otAlerts > 0 ? 'Action needed' : 'All clear',
                valueColor: otAlerts > 0
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color? valueColor;
  final Color? dotColor;
  final bool showDot;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    this.valueColor,
    this.dotColor,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (showDot && dotColor != null) ...[
                  _PulseDot(color: dotColor!),
                  const SizedBox(width: 5),
                ],
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
