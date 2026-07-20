import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/kpi_dashboard_data.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/kpi_range_utils.dart';

class FinancialSummaryWidget extends StatefulWidget {
  final String workspaceId;
  final VoidCallback? onViewDashboard;

  const FinancialSummaryWidget({
    super.key,
    required this.workspaceId,
    this.onViewDashboard,
  });

  @override
  State<FinancialSummaryWidget> createState() =>
      _FinancialSummaryWidgetState();
}

class _FinancialSummaryWidgetState extends State<FinancialSummaryWidget> {
  late Future<KpiDashboardData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(covariant FinancialSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _dataFuture = _loadData();
    }
  }

  Future<KpiDashboardData> _loadData() {
    return ServiceLocator.reportingService.getKpiDashboardData(
      widget.workspaceId,
      range: const KpiRange.preset(KpiRangePreset.thirtyDays),
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KpiDashboardData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator(minHeight: 4)
                else if (snapshot.hasError)
                  const Text(
                    'Unable to load financial data.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else if (snapshot.data == null)
                  const Text(
                    'No financial data available.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  _buildMetrics(snapshot.data!),
                if (widget.onViewDashboard != null) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: widget.onViewDashboard,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View full dashboard'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.account_balance_wallet, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Financial Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            padding: EdgeInsets.zero,
            tooltip: 'Refresh',
          ),
        ),
      ],
    );
  }

  Widget _buildMetrics(KpiDashboardData data) {
    final currencyFormat = NumberFormat.compactCurrency(symbol: '\$');
    final percentFormat = NumberFormat('0.#');

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        _MetricTile(
          label: 'Revenue',
          value: currencyFormat.format(data.revenue.totalRevenue),
        ),
        _MetricTile(
          label: 'Gross Profit',
          value: currencyFormat.format(data.profit.grossProfit),
        ),
        _MetricTile(
          label: 'Margin',
          value: '${percentFormat.format(data.profit.grossMarginPercent)}%',
        ),
        _MetricTile(
          label: 'Forecast Profit',
          value: currencyFormat.format(data.profit.forecastProfit),
        ),
        _MetricTile(
          label: 'Closing Rate',
          value: '${percentFormat.format(data.jobs.closingRatePercent)}%',
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
