import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';

/// Cash-flow projection from open document balances: expected inflows
/// (unpaid customer invoices) vs outflows (unpaid vendor bills) bucketed by
/// week, with an overdue bucket for anything already past due.
class CashFlowProjectionWidget extends StatelessWidget {
  final List<CashFlowEntry> entries;

  const CashFlowProjectionWidget({super.key, required this.entries});

  static final _currency = NumberFormat.compactCurrency(symbol: r'$');
  static final _fullCurrency =
      NumberFormat.currency(symbol: r'$', decimalDigits: 0);

  static const int _weekCount = 8;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: Text(
              'No open invoices or bills — nothing to project. '
              'Documents in draft are not counted.',
            ),
          ),
        ),
      );
    }

    final buckets = _buildBuckets();
    final maxY = buckets.fold(
      0.0,
      (m, b) => math.max(m, math.max(b.inflow, b.outflow)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cash Flow Projection',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Open invoice balances (in) vs open bills (out) by due date. '
              'Documents without a due date are assumed net-30.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY <= 0 ? 1 : maxY * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final bucket = buckets[group.x.toInt()];
                        final isInflow = rodIndex == 0;
                        return BarTooltipItem(
                          '${bucket.label}\n'
                          '${isInflow ? 'In' : 'Out'}: '
                          '${_fullCurrency.format(rod.toY)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) => Text(
                          _currency.format(value),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= buckets.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              buckets[index].label,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < buckets.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: buckets[i].inflow,
                            color: AppColors.success,
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          BarChartRodData(
                            toY: buckets[i].outflow,
                            color: AppColors.error,
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columnSpacing: 28,
                columns: const [
                  DataColumn(label: Text('Period')),
                  DataColumn(label: Text('Expected In'), numeric: true),
                  DataColumn(label: Text('Expected Out'), numeric: true),
                  DataColumn(label: Text('Net'), numeric: true),
                  DataColumn(label: Text('Cumulative'), numeric: true),
                ],
                rows: _bucketRows(buckets),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_CashFlowBucket> _buildBuckets() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Weeks start today so "Wk of <date>" buckets read naturally.
    final buckets = <_CashFlowBucket>[
      _CashFlowBucket('Overdue', null),
      for (var week = 0; week < _weekCount; week++)
        _CashFlowBucket(
          'Wk ${DateFormat('M/d').format(today.add(Duration(days: week * 7)))}',
          today.add(Duration(days: week * 7)),
        ),
      _CashFlowBucket('Later', null),
    ];

    final horizon = today.add(const Duration(days: _weekCount * 7));
    for (final entry in entries) {
      final due = DateTime(
        entry.dueDate.year,
        entry.dueDate.month,
        entry.dueDate.day,
      );
      final _CashFlowBucket bucket;
      if (due.isBefore(today)) {
        bucket = buckets.first;
      } else if (!due.isBefore(horizon)) {
        bucket = buckets.last;
      } else {
        final weekIndex = due.difference(today).inDays ~/ 7;
        bucket = buckets[weekIndex + 1];
      }
      if (entry.isInflow) {
        bucket.inflow += entry.balance;
      } else {
        bucket.outflow += entry.balance;
      }
    }
    return buckets;
  }

  List<DataRow> _bucketRows(List<_CashFlowBucket> buckets) {
    var cumulative = 0.0;
    final rows = <DataRow>[];
    for (final bucket in buckets) {
      final net = bucket.inflow - bucket.outflow;
      cumulative += net;
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(bucket.label)),
            DataCell(Text(_fullCurrency.format(bucket.inflow))),
            DataCell(Text(_fullCurrency.format(bucket.outflow))),
            DataCell(
              Text(
                _fullCurrency.format(net),
                style: TextStyle(
                  color: net < 0 ? AppColors.error : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DataCell(
              Text(
                _fullCurrency.format(cumulative),
                style: TextStyle(
                  color:
                      cumulative < 0 ? AppColors.error : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return rows;
  }
}

class _CashFlowBucket {
  final String label;
  final DateTime? weekStart;
  double inflow = 0;
  double outflow = 0;

  _CashFlowBucket(this.label, this.weekStart);
}
