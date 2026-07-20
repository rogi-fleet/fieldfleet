import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/project.dart';
import '../../models/time_entry_status.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import 'package:provider/provider.dart';
import '../../providers/workspace_provider.dart';

/// Budget burn-down chart showing planned vs actual labor spend over time
class BudgetBurndownChart extends StatefulWidget {
  final Project project;

  const BudgetBurndownChart({super.key, required this.project});

  @override
  State<BudgetBurndownChart> createState() => _BudgetBurndownChartState();
}

class _BudgetBurndownChartState extends State<BudgetBurndownChart> {
  bool _isLoading = true;
  double _totalProjectedCost = 0;
  List<_DateCost> _cumulativeActuals = [];
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final projectId = widget.project.id;
      final workspaceId = widget.project.workspaceId;

      // Fetch budget summary for total projected cost
      final summary = await ServiceLocator.budgetService
          .calculateBudgetSummary(projectId, workspaceId);
      _totalProjectedCost = summary.totalProjectedCost;

      // Fetch approved time entries for the project
      final timeEntries = await ServiceLocator.timeEntryService
          .getTimeEntriesForProject(projectId, workspaceId: workspaceId)
          .first;

      // Filter to approved entries only and sort by date
      final approved = timeEntries
          .where((e) => e.status == TimeEntryStatus.approved)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (approved.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _hasData = false; });
        return;
      }

      // Build cumulative cost by date
      final dailyCosts = <DateTime, double>{};
      for (final entry in approved) {
        final dateKey = DateTime(entry.date.year, entry.date.month, entry.date.day);
        dailyCosts[dateKey] = (dailyCosts[dateKey] ?? 0) + entry.totalCost;
      }

      final sortedDates = dailyCosts.keys.toList()..sort();
      double cumulative = 0;
      final cumulativeList = <_DateCost>[];
      for (final date in sortedDates) {
        cumulative += dailyCosts[date]!;
        cumulativeList.add(_DateCost(date, cumulative));
      }

      if (mounted) {
        setState(() {
          _cumulativeActuals = cumulativeList;
          _hasData = cumulativeList.isNotEmpty && _totalProjectedCost > 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _hasData = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Icon(Icons.trending_down, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Budget Burn-down',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_down, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Budget Burn-down',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'No costs logged yet. The burn-down charts actual spend '
                'against your budget once time or expenses are recorded.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currencyCode = context.read<WorkspaceProvider>().currencyCode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.show_chart,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Budget Burn-down',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Legend
            Row(
              children: [
                _legendItem('Budget Baseline', AppColors.textTertiary),
                const SizedBox(width: 16),
                _legendItem('Actual Labor Spend', AppColors.info),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildChart(currencyCode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildChart(String currencyCode) {
    final startDate = widget.project.startDate ?? _cumulativeActuals.first.date;
    final endDate = widget.project.targetCompletionDate ??
        _cumulativeActuals.last.date.add(const Duration(days: 30));

    final startMs = startDate.millisecondsSinceEpoch.toDouble();
    final endMs = endDate.millisecondsSinceEpoch.toDouble();

    // Budget baseline: linear from 0 to totalProjectedCost
    final baselineSpots = [
      FlSpot(startMs, 0),
      FlSpot(endMs, _totalProjectedCost),
    ];

    // Actual cumulative labor cost
    final actualSpots = _cumulativeActuals
        .map((dc) => FlSpot(
              dc.date.millisecondsSinceEpoch.toDouble(),
              dc.cost,
            ))
        .toList();

    final rawMaxY = [
      _totalProjectedCost,
      if (_cumulativeActuals.isNotEmpty) _cumulativeActuals.last.cost,
    ].reduce((a, b) => a > b ? a : b) * 1.1;
    final maxY = rawMaxY > 0 ? rawMaxY : 100.0;

    return LineChart(
      LineChartData(
        minX: startMs,
        maxX: endMs,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.cardBorder,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == meta.max) return const SizedBox.shrink();
                return Text(
                  CurrencyUtils.formatCurrencyCompact(value, currencyCode),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (endMs - startMs) / 4,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(date),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          // Baseline
          LineChartBarData(
            spots: baselineSpots,
            isCurved: false,
            color: AppColors.textTertiary,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            dashArray: [6, 4],
          ),
          // Actual
          LineChartBarData(
            spots: actualSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.info,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.info.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final isBaseline = spot.barIndex == 0;
                return LineTooltipItem(
                  '${isBaseline ? "Budget" : "Actual"}: ${CurrencyUtils.formatCurrency(spot.y, currencyCode)}',
                  TextStyle(
                    color: isBaseline ? AppColors.textTertiary : AppColors.info,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class _DateCost {
  final DateTime date;
  final double cost;
  _DateCost(this.date, this.cost);
}
