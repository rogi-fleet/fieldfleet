import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

class ProfitLossReportWidget extends StatelessWidget {
  final List<FinancialReport> reports;

  const ProfitLossReportWidget({
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
          // Chart
          SizedBox(
            height: 300,
            child: _buildChart(context),
          ),

          const SizedBox(height: 8),

          // Legend
          _buildLegend(context),

          const SizedBox(height: 16),

          // Data Table
          _buildDataTable(context),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxValue() * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final report = reports[groupIndex];
              String label;
              String value;

              if (rodIndex == 0) {
                label = 'Revenue';
                value = NumberFormat.currency(symbol: '\$').format(report.totalInvoiced);
              } else if (rodIndex == 1) {
                label = 'Cost';
                value = NumberFormat.currency(symbol: '\$').format(report.totalLaborCost);
              } else {
                label = 'Profit';
                value = NumberFormat.currency(symbol: '\$').format(report.profit);
              }

              return BarTooltipItem(
                '$label\n$value',
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
                  final label = report.projectName.length > 10
                      ? '${report.projectName.substring(0, 10)}…'
                      : report.projectName;
                  // Rotate labels so adjacent project names don't overlap on
                  // narrow (mobile) charts.
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Transform.rotate(
                      angle: -0.6,
                      alignment: Alignment.topCenter,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: 9,
                          color: chrome.scaffoldTextSecondary,
                        ),
                      ),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 64,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  _formatAxisCurrency(value),
                  style: TextStyle(fontSize: 10, color: chrome.scaffoldTextSecondary),
                );
              },
              reservedSize: 50,
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _getBarGroups(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _getMaxValue() / 5,
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendDot(AppColors.info, 'Revenue', chrome),
        const SizedBox(width: 16),
        _legendDot(AppColors.error, 'Cost', chrome),
        const SizedBox(width: 16),
        _legendDot(AppColors.success, 'Profit', chrome),
      ],
    );
  }

  Widget _legendDot(Color color, String label, ChromeColors chrome) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: chrome.scaffoldTextSecondary)),
      ],
    );
  }

  List<BarChartGroupData> _getBarGroups() {
    return reports.asMap().entries.map((entry) {
      final index = entry.key;
      final report = entry.value;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: report.totalInvoiced,
            color: AppColors.info,
            width: 12,
          ),
          BarChartRodData(
            toY: report.totalLaborCost,
            color: AppColors.error,
            width: 12,
          ),
          BarChartRodData(
            toY: report.profit > 0 ? report.profit : 0,
            color: report.profit >= 0 ? AppColors.success : AppColors.error,
            width: 12,
          ),
        ],
      );
    }).toList();
  }

  double _getMaxValue() {
    double max = 0;
    for (final report in reports) {
      if (report.totalInvoiced > max) max = report.totalInvoiced;
      if (report.totalLaborCost > max) max = report.totalLaborCost;
      if (report.profit > max) max = report.profit;
    }
    return max > 0 ? max : 100;
  }

  /// `NumberFormat.compactCurrency` flips precision based on magnitude — it
  /// drops decimals for whole numbers ≥ 100 but keeps `.00` on smaller ones,
  /// producing an ugly `$120 / $100 / $80.00 / $60.00 / $40.00 / $20.00` axis
  /// ladder. Use compact form (`$1.2K`) only once values cross the K threshold
  /// where it's actually doing useful work; below that, render a uniform
  /// no-decimal axis label so the ticks read consistently.
  String _formatAxisCurrency(double value) {
    final abs = value.abs();
    if (abs >= 1000) {
      return NumberFormat.compactCurrency(symbol: '\$').format(value);
    }
    return NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value);
  }

  Widget _buildDataTable(BuildContext context) {
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology))),
                  const DataColumn(label: Text('Revenue'), numeric: true),
                  const DataColumn(label: Text('Cost'), numeric: true),
                  const DataColumn(label: Text('Profit'), numeric: true),
                  const DataColumn(label: Text('Margin'), numeric: true),
                ],
                rows: reports.map((report) {
                  final margin = report.totalInvoiced > 0
                      ? (report.profit / report.totalInvoiced) * 100
                      : 0.0;

                  return DataRow(
                    cells: [
                      DataCell(Text(report.projectName)),
                      DataCell(Text(currencyFormat.format(report.totalInvoiced))),
                      DataCell(Text(currencyFormat.format(report.totalLaborCost))),
                      DataCell(
                        Text(
                          currencyFormat.format(report.profit),
                          style: TextStyle(
                            color: report.profit >= 0 ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${margin.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: margin >= 0 ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
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
            Icon(
              Icons.assessment_outlined,
              size: 64,
              color: chrome.scaffoldTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No profit/loss data available',
              style: TextStyle(
                fontSize: 18,
                color: chrome.scaffoldText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create ${context.watch<WorkspaceProvider>().projectTerminology.toLowerCase()} and invoices to see profit/loss reports',
              style: TextStyle(
                fontSize: 14,
                color: chrome.scaffoldTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
