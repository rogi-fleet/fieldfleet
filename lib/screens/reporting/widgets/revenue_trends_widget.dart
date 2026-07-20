import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';

class RevenueTrendsWidget extends StatelessWidget {
  final List<RevenueTrend> trends;

  const RevenueTrendsWidget({
    super.key,
    required this.trends,
  });

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return _buildEmptyState(context);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Revenue Summary
          _buildTotalRevenue(),

          const SizedBox(height: 16),

          // Line Chart
          SizedBox(
            height: 300,
            child: _buildChart(context),
          ),

          const SizedBox(height: 16),

          // Monthly Breakdown
          _buildMonthlyBreakdown(context),
        ],
      ),
    );
  }

  Widget _buildTotalRevenue() {
    final totalRevenue = trends.fold<double>(
      0.0,
      (sum, trend) => sum + trend.totalRevenue,
    );
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Card(
      color: AppColors.infoLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            Icon(Icons.trending_up, size: 32, color: AppColors.infoDark),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Revenue',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(totalRevenue),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.infoDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: trends.asMap().entries.map((entry) {
              return FlSpot(
                entry.key.toDouble(),
                entry.value.totalRevenue,
              );
            }).toList(),
            isCurved: true,
            color: AppColors.info,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.info.withOpacity(0.2),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < trends.length) {
                  final trend = trends[value.toInt()];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('MMM yy').format(trend.month),
                      style: TextStyle(fontSize: 10, color: chrome.scaffoldTextSecondary),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
              interval: trends.length > 12 ? 2 : 1,
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
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: chrome.scaffoldDivider),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
        ),
        minY: 0,
        maxY: _getMaxValue() * 1.2,
      ),
    );
  }

  double _getMaxValue() {
    if (trends.isEmpty) return 100;
    final max = trends.map((t) => t.totalRevenue).reduce((a, b) => a > b ? a : b);
    return max > 0 ? max : 100;
  }

  /// `NumberFormat.compactCurrency` keeps `.00` decimals on values < 100 but
  /// drops them once they reach 100, producing a `$120 / $100 / $80.00 /
  /// $60.00 / $40.00` axis ladder. Stay below the K threshold with a
  /// no-decimal currency format; only fall back to compact (`$1.2K`) once it
  /// actually shortens the label.
  String _formatAxisCurrency(double value) {
    final abs = value.abs();
    if (abs >= 1000) {
      return NumberFormat.compactCurrency(symbol: '\$').format(value);
    }
    return NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value);
  }

  Widget _buildMonthlyBreakdown(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trends.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final trend = trends[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.infoLight,
                    child: Text(
                      DateFormat('MMM').format(trend.month),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.infoDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(DateFormat('MMMM yyyy').format(trend.month)),
                  trailing: Text(
                    currencyFormat.format(trend.totalRevenue),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
            Icon(
              Icons.trending_up,
              size: 64,
              color: chrome.scaffoldTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No revenue data available',
              style: TextStyle(
                fontSize: 18,
                color: chrome.scaffoldText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mark invoices as paid to see revenue trends',
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
