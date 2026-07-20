import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';

/// WIP (work-in-progress) schedule: per project — contract, estimated cost,
/// cost to date, percent complete (cost basis), earned revenue, billed to
/// date, and over/under billing (positive = overbilled / liability, negative
/// = underbilled / asset).
class WipScheduleWidget extends StatefulWidget {
  final List<WipReportRow> rows;

  const WipScheduleWidget({super.key, required this.rows});

  @override
  State<WipScheduleWidget> createState() => _WipScheduleWidgetState();
}

class _WipScheduleWidgetState extends State<WipScheduleWidget> {
  static final _currency = NumberFormat.currency(symbol: r'$', decimalDigits: 0);

  bool _activeOnly = true;

  List<WipReportRow> get _visibleRows {
    var rows = widget.rows;
    if (_activeOnly) {
      rows = rows.where((r) => r.projectStatus == 'active').toList();
      // Don't show an empty report just because nothing is marked active.
      if (rows.isEmpty) return widget.rows;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;

    if (widget.rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Center(child: Text('No projects to report on yet.')),
        ),
      );
    }

    final totalContract = rows.fold(0.0, (s, r) => s + r.contractAmount);
    final totalCost = rows.fold(0.0, (s, r) => s + r.costToDate);
    final totalEarned = rows.fold(0.0, (s, r) => s + r.earnedRevenue);
    final totalBilled = rows.fold(0.0, (s, r) => s + r.billedToDate);
    final totalOverUnder = rows.fold(0.0, (s, r) => s + r.overUnderBilling);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'WIP Schedule',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                FilterChip(
                  label: const Text('Active projects only'),
                  selected: _activeOnly,
                  onSelected: (v) => setState(() => _activeOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Percent complete is cost-basis (cost to date ÷ estimated '
              'cost). Positive over/under = overbilled (billings ahead of '
              'work); negative = underbilled (work ahead of billings).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Project')),
                  DataColumn(label: Text('Contract'), numeric: true),
                  DataColumn(label: Text('Est. Cost'), numeric: true),
                  DataColumn(label: Text('Cost to Date'), numeric: true),
                  DataColumn(label: Text('Committed'), numeric: true),
                  DataColumn(label: Text('% Compl.'), numeric: true),
                  DataColumn(label: Text('Earned'), numeric: true),
                  DataColumn(label: Text('Billed'), numeric: true),
                  DataColumn(label: Text('Collected'), numeric: true),
                  DataColumn(label: Text('Over/(Under)'), numeric: true),
                ],
                rows: [
                  for (final row in rows) _dataRow(row),
                  _totalsRow(
                    totalContract,
                    totalCost,
                    totalEarned,
                    totalBilled,
                    totalOverUnder,
                    rows,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _dataRow(WipReportRow row) {
    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(row.projectName, overflow: TextOverflow.ellipsis),
          ),
        ),
        DataCell(Text(_currency.format(row.contractAmount))),
        DataCell(Text(_currency.format(row.estimatedCost))),
        DataCell(Text(_currency.format(row.costToDate))),
        DataCell(Text(_currency.format(row.committedCost))),
        DataCell(Text('${(row.percentComplete * 100).toStringAsFixed(0)}%')),
        DataCell(Text(_currency.format(row.earnedRevenue))),
        DataCell(Text(_currency.format(row.billedToDate))),
        DataCell(Text(_currency.format(row.collectedToDate))),
        DataCell(_overUnderCell(row.overUnderBilling)),
      ],
    );
  }

  DataRow _totalsRow(
    double contract,
    double cost,
    double earned,
    double billed,
    double overUnder,
    List<WipReportRow> rows,
  ) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return DataRow(
      cells: [
        DataCell(Text('Total (${rows.length})', style: bold)),
        DataCell(Text(_currency.format(contract), style: bold)),
        DataCell(
          Text(
            _currency.format(rows.fold(0.0, (s, r) => s + r.estimatedCost)),
            style: bold,
          ),
        ),
        DataCell(Text(_currency.format(cost), style: bold)),
        DataCell(
          Text(
            _currency.format(rows.fold(0.0, (s, r) => s + r.committedCost)),
            style: bold,
          ),
        ),
        const DataCell(Text('')),
        DataCell(Text(_currency.format(earned), style: bold)),
        DataCell(Text(_currency.format(billed), style: bold)),
        DataCell(
          Text(
            _currency.format(rows.fold(0.0, (s, r) => s + r.collectedToDate)),
            style: bold,
          ),
        ),
        DataCell(_overUnderCell(overUnder, bold: true)),
      ],
    );
  }

  Widget _overUnderCell(double value, {bool bold = false}) {
    final isUnder = value < -0.005;
    final isOver = value > 0.005;
    final color = isUnder
        ? AppColors.error
        : isOver
            ? AppColors.warning
            : AppColors.textSecondary;
    final label = isUnder
        ? '(${_currency.format(value.abs())})'
        : _currency.format(value);
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.w600,
      ),
    );
  }
}
