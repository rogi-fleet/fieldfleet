import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';

class LaborReportWidget extends StatelessWidget {
  final List<LaborReport> reports;

  const LaborReportWidget({
    super.key,
    required this.reports,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return _buildEmptyState(context);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Summary
          _buildTotalSummary(),

          const SizedBox(height: 16),

          // Bar Chart
          SizedBox(
            height: 300,
            child: _buildChart(context),
          ),

          const SizedBox(height: 16),

          // Worker List
          _buildWorkerList(context),
        ],
      ),
    );
  }

  Widget _buildTotalSummary() {
    final totalHours = reports.fold<double>(0.0, (sum, r) => sum + r.totalHours);
    final totalCost = reports.fold<double>(0.0, (sum, r) => sum + r.totalCost);

    return Row(
      children: [
        Expanded(
          child: Card(
            color: AppColors.secondarySurface,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.access_time, color: AppColors.warning),
                  const SizedBox(height: 8),
                  Text(
                    '${totalHours.toStringAsFixed(1)} hrs',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                    ),
                  ),
                  Text(
                    'Total Hours',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: AppColors.infoLight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.attach_money, color: AppColors.infoDark),
                  const SizedBox(height: 8),
                  Text(
                    NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(totalCost),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.infoDark,
                    ),
                  ),
                  Text(
                    'Total Cost',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxHours() * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final report = reports[groupIndex];
              return BarTooltipItem(
                '${report.userName}\n${report.totalHours.toStringAsFixed(1)} hrs\n${NumberFormat.currency(symbol: '\$').format(report.totalCost)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < reports.length) {
                  final report = reports[value.toInt()];
                  final name = report.userName.split(' ').first;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      name.length > 10 ? '${name.substring(0, 10)}...' : name,
                      style: TextStyle(fontSize: 10, color: chrome.scaffoldTextSecondary),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}h',
                  style: TextStyle(fontSize: 10, color: chrome.scaffoldTextSecondary),
                );
              },
              reservedSize: 40,
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: reports.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.totalHours,
                color: AppColors.warning,
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }

  double _getMaxHours() {
    if (reports.isEmpty) return 8;
    final max = reports.map((r) => r.totalHours).reduce((a, b) => a > b ? a : b);
    return max > 0 ? max : 8;
  }

  Widget _buildWorkerList(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detailed Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reports.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final report = reports[index];
                final hourlyRate = report.totalHours > 0 ? report.totalCost / report.totalHours : 0.0;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondarySurface,
                    child: Text(
                      report.userName.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(report.userName),
                  subtitle: Text('${currencyFormat.format(hourlyRate)}/hr average'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${report.totalHours.toStringAsFixed(1)} hrs',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        currencyFormat.format(report.totalCost),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: chrome.scaffoldTextSecondary),
            const SizedBox(height: 16),
            Text('No labor data available', style: TextStyle(fontSize: 18, color: chrome.scaffoldText)),
            const SizedBox(height: 8),
            Text('Track time entries to see labor reports', style: TextStyle(fontSize: 14, color: chrome.scaffoldTextSecondary)),
          ],
        ),
      ),
    );
  }
}
