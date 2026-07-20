import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/kpi_dashboard_data.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/kpi_range_utils.dart';
import '../../../utils/user_facing_error.dart';

enum _KpiSection { revenue, profitability, pipeline }

class KpiDashboardWidget extends StatefulWidget {
  final String workspaceId;

  const KpiDashboardWidget({super.key, required this.workspaceId});

  @override
  State<KpiDashboardWidget> createState() => _KpiDashboardWidgetState();
}

class _KpiDashboardWidgetState extends State<KpiDashboardWidget> {
  KpiRange _selectedRange = const KpiRange.preset(KpiRangePreset.twelveMonths);
  _KpiSection _selectedSection = _KpiSection.revenue;
  late Future<KpiDashboardData> _kpiFuture;
  DateTime? _lastUpdatedAt;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _isRefreshing = true;
    _kpiFuture = _loadInitialKpiData();
  }

  Future<KpiDashboardData> _loadInitialKpiData() async {
    try {
      final raw = await ServiceLocator.userPreferencesService
          .getKpiDashboardRangeConfig();
      final restoredRange = _rangeFromConfig(raw);
      if (restoredRange != null) {
        _selectedRange = restoredRange;
      }
    } catch (_) {
      // Ignore preference load errors; fallback to default range.
    }
    return _loadKpiData();
  }

  Future<KpiDashboardData> _loadKpiData() async {
    try {
      final data =
          await (ServiceLocator.reportingService.getKpiDashboardData(
                widget.workspaceId,
                range: _selectedRange,
              )
              as Future<KpiDashboardData>);
      if (mounted) {
        setState(() {
          _lastUpdatedAt = DateTime.now();
          _isRefreshing = false;
        });
      }
      return data;
    } catch (error) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
      rethrow;
    }
  }

  void _setRange(KpiRange range) {
    setState(() {
      _selectedRange = range;
      _isRefreshing = true;
      _kpiFuture = _loadKpiData();
    });
    _saveRangePreference(range);
  }

  void _selectPreset(KpiRangePreset preset) =>
      _setRange(KpiRange.preset(preset));

  Future<void> _pickCustomRange() async {
    final initialStart =
        _selectedRange.customStart ??
        DateTime.now().subtract(const Duration(days: 29));
    final initialEnd = _selectedRange.customEnd ?? DateTime.now();

    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );

    if (result == null) return;
    _setRange(KpiRange.custom(start: result.start, end: result.end));
  }

  void _refresh() {
    setState(() {
      _isRefreshing = true;
      _kpiFuture = _loadKpiData();
    });
  }

  Future<void> _saveRangePreference(KpiRange range) async {
    try {
      await ServiceLocator.userPreferencesService.saveKpiDashboardRangeConfig(
        preset: range.preset.name,
        customStart: range.customStart,
        customEnd: range.customEnd,
      );
    } catch (_) {
      // Non-blocking preference save.
    }
  }

  KpiRange? _rangeFromConfig(Map<String, dynamic> raw) {
    final presetName = raw['preset'] as String?;
    if (presetName == null || presetName.isEmpty) return null;

    KpiRangePreset? preset;
    for (final value in KpiRangePreset.values) {
      if (value.name == presetName) {
        preset = value;
        break;
      }
    }
    if (preset == null) return null;

    if (preset == KpiRangePreset.custom) {
      final startString = raw['custom_start'] as String?;
      final endString = raw['custom_end'] as String?;
      final start = startString != null ? DateTime.tryParse(startString) : null;
      final end = endString != null ? DateTime.tryParse(endString) : null;
      if (start != null && end != null) {
        return KpiRange.custom(start: start, end: end);
      }
      return const KpiRange.preset(KpiRangePreset.thirtyDays);
    }

    return KpiRange.preset(preset);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 6),
        _buildRangeSelector(),
        const SizedBox(height: 6),
        _buildSectionSelector(),
        const SizedBox(height: 8),
        FutureBuilder<KpiDashboardData>(
          future: _kpiFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load KPI data',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return const _NoDataState(
                message: 'No KPI data available for this range.',
              );
            }

            final items = switch (_selectedSection) {
              _KpiSection.revenue => _revenueItems(data),
              _KpiSection.profitability => _profitItems(data),
              _KpiSection.pipeline => _pipelineItems(data),
            };

            return _PanelGrid(items: items);
          },
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final subtitle = _lastUpdatedAt == null
        ? 'Last updated: --'
        : 'Last updated: ${DateFormat('MMM d, h:mm a').format(_lastUpdatedAt!)}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financial Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ChromeColors.of(context).scaffoldText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: ChromeColors.of(context).scaffoldTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          onPressed: _isRefreshing ? null : _refresh,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          tooltip: 'Refresh',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildRangeSelector() {
    const presets = [
      KpiRangePreset.sevenDays,
      KpiRangePreset.thirtyDays,
      KpiRangePreset.quarterToDate,
      KpiRangePreset.yearToDate,
      KpiRangePreset.twelveMonths,
    ];

    final customLabel =
        _selectedRange.isCustom &&
            _selectedRange.customStart != null &&
            _selectedRange.customEnd != null
        ? '${DateFormat('M/d').format(_selectedRange.customStart!)}-${DateFormat('M/d').format(_selectedRange.customEnd!)}'
        : 'Custom';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Builder(builder: (context) {
            final chrome = ChromeColors.of(context);
            return SegmentedButton<KpiRangePreset>(
              segments: [
                for (final preset in presets)
                  ButtonSegment<KpiRangePreset>(
                    value: preset,
                    label: Text(KpiRange.preset(preset).label),
                  ),
              ],
              selected: _selectedRange.isCustom
                  ? <KpiRangePreset>{}
                  : {_selectedRange.preset},
              emptySelectionAllowed: true,
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  _selectPreset(selected.first);
                }
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return null;
                  return chrome.scaffoldText;
                }),
                side: WidgetStatePropertyAll(
                  BorderSide(color: chrome.scaffoldDivider),
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _pickCustomRange,
            icon: const Icon(Icons.calendar_today, size: 14),
            label: Text(customLabel),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: _selectedRange.isCustom
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              foregroundColor: _selectedRange.isCustom
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSelector() {
    const sections = [
      (_KpiSection.revenue, 'Revenue', AppColors.financialAccent),
      (_KpiSection.profitability, 'Profitability', AppColors.success),
      (_KpiSection.pipeline, 'Pipeline', AppColors.secondary),
    ];

    return Row(
      children: sections.map((entry) {
        final (section, label, color) = entry;
        final isSelected = _selectedSection == section;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: isSelected
              ? FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  child: Text(label),
                )
              : OutlinedButton(
                  onPressed: () => setState(() => _selectedSection = section),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.4)),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  child: Text(label),
                ),
        );
      }).toList(),
    );
  }
}

// ─── Grid Item ────────────────────────────────────────────────────────────────

class _GridItem {
  final Widget child;
  final int colSpan;

  const _GridItem({required this.child, this.colSpan = 1});
}

// ─── Section Builder Functions ────────────────────────────────────────────────

List<_GridItem> _revenueItems(KpiDashboardData data) {
  final trend = data.revenue.trend;
  final average = trend.isEmpty
      ? 0.0
      : data.revenue.totalRevenue / trend.length;
  final bestBucket = trend.isEmpty
      ? 0.0
      : trend.map((p) => p.value).reduce((a, b) => a > b ? a : b);

  return [
    _GridItem(
      colSpan: 2,
      child: _StatPanel(
        label: 'Total Revenue',
        value: _formatCurrency(data.revenue.totalRevenue),
        size: _StatSize.hero,
        accentColor: AppColors.financialAccent,
        tooltip:
            'Sum of paid invoice totals whose paid date falls within the selected range.',
        buckets: trend,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Avg / Period',
        value: _formatCurrency(average),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Best Period',
        value: _formatCurrency(bestBucket),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      colSpan: 4,
      child: _ChartPanel(
        title: 'Revenue Trend',
        dotColor: AppColors.financialAccent,
        chart: _TrendChart(
          title: 'Revenue Trend',
          primaryColor: AppColors.financialAccent,
          primary: trend,
          primaryLabel: 'Revenue',
        ),
      ),
    ),
  ];
}

List<_GridItem> _profitItems(KpiDashboardData data) {
  return [
    _GridItem(
      child: _StatPanel(
        label: 'Gross Profit',
        value: _formatCurrency(data.profit.grossProfit),
        size: _StatSize.hero,
        accentColor: AppColors.success,
        tooltip:
            'Paid revenue minus approved time-entry labor and all cost items in the selected range.',
        buckets: data.profit.grossTrend,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Gross Margin',
        value: '${data.profit.grossMarginPercent.toStringAsFixed(1)}%',
        size: _StatSize.compact,
        tooltip: 'Gross profit divided by paid revenue for the selected range.',
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Forecast Profit',
        value: _formatCurrency(data.profit.forecastProfit),
        size: _StatSize.hero,
        accentColor: AppColors.primary,
        tooltip:
            'Paid revenue minus projected cost from top-level budget items.',
        buckets: data.profit.forecastTrend,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Forecast Margin',
        value: '${data.profit.forecastMarginPercent.toStringAsFixed(1)}%',
        size: _StatSize.compact,
        tooltip:
            'Forecast profit divided by paid revenue for the selected range.',
      ),
    ),
    _GridItem(
      colSpan: 4,
      child: _ChartPanel(
        title: 'Gross vs Forecast Profit',
        dotColor: AppColors.success,
        chart: _TrendChart(
          title: 'Gross vs Forecast Profit',
          primaryColor: AppColors.success,
          secondaryColor: AppColors.primary,
          primary: data.profit.grossTrend,
          secondary: data.profit.forecastTrend,
          primaryLabel: 'Gross Profit',
          secondaryLabel: 'Forecast',
        ),
      ),
    ),
  ];
}

List<_GridItem> _pipelineItems(KpiDashboardData data) {
  return [
    _GridItem(
      colSpan: 4,
      child: _StatPanel(
        label: 'Closing Rate',
        value: '${data.jobs.closingRatePercent.toStringAsFixed(1)}%',
        size: _StatSize.hero,
        accentColor: AppColors.secondary,
        tooltip:
            'Converted opportunities (active + complete) divided by opportunities created in the selected range.',
        buckets: data.jobs.closingRateTrend,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Created',
        value: data.jobs.createdOpportunities.toString(),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Converted',
        value: data.jobs.convertedOpportunities.toString(),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Open',
        value: data.jobs.openOpportunities.toString(),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      child: _StatPanel(
        label: 'Completed',
        value: data.jobs.completedJobs.toString(),
        size: _StatSize.compact,
      ),
    ),
    _GridItem(
      colSpan: 4,
      child: _ChartPanel(
        title: 'Closing Rate Trend',
        dotColor: AppColors.secondary,
        chart: _TrendChart(
          title: 'Closing Rate Trend',
          primaryColor: AppColors.secondary,
          primary: data.jobs.closingRateTrend,
          primaryLabel: 'Closing Rate',
          isPercentage: true,
        ),
      ),
    ),
  ];
}

// ─── Panel Grid ───────────────────────────────────────────────────────────────

class _PanelGrid extends StatelessWidget {
  final List<_GridItem> items;

  const _PanelGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int totalCols;
        if (AppBreakpoints.isMobile(width)) {
          totalCols = 1;
        } else if (width < AppBreakpoints.desktop) {
          totalCols = 2;
        } else {
          totalCols = 4;
        }

        const gutter = AppSpacing.sm;
        final unitWidth = (width - gutter * (totalCols - 1)) / totalCols;

        return Wrap(
          spacing: gutter,
          runSpacing: gutter,
          children: items.map((item) {
            final span = item.colSpan.clamp(1, totalCols);
            final itemWidth = unitWidth * span + gutter * (span - 1);
            return SizedBox(width: itemWidth, child: item.child);
          }).toList(),
        );
      },
    );
  }
}

// ─── Panel Frame ──────────────────────────────────────────────────────────────

class _PanelFrame extends StatelessWidget {
  final Widget child;
  final Color? accentColor;

  const _PanelFrame({required this.child, this.accentColor});

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppShadows.sm,
      ),
      child: child,
    );

    if (accentColor != null) {
      content = ClipRRect(
        borderRadius: AppRadius.cardRadius,
        child: Stack(
          children: [
            content,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: accentColor),
            ),
          ],
        ),
      );
    }

    return content;
  }
}

// ─── Stat Panel ───────────────────────────────────────────────────────────────

enum _StatSize { hero, compact }

class _StatPanel extends StatelessWidget {
  final String label;
  final String value;
  final _StatSize size;
  final Color? accentColor;
  final String? tooltip;
  final List<KpiBucket>? buckets;

  const _StatPanel({
    required this.label,
    required this.value,
    required this.size,
    this.accentColor,
    this.tooltip,
    this.buckets,
  });

  @override
  Widget build(BuildContext context) {
    final isHero = size == _StatSize.hero;
    final fontSize = isHero ? 28.0 : 20.0;
    final fontWeight = isHero ? FontWeight.w800 : FontWeight.w700;
    final valueColor = accentColor ?? AppColors.textPrimary;

    return _PanelFrame(
      accentColor: accentColor,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  title: label,
                  tooltip: tooltip,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: valueColor,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (buckets != null) _TrendIndicator(buckets: buckets!),
        ],
      ),
    );
  }
}

// ─── Chart Panel ──────────────────────────────────────────────────────────────

class _ChartPanel extends StatelessWidget {
  final String title;
  final Color dotColor;
  final _TrendChart chart;

  const _ChartPanel({
    required this.title,
    required this.dotColor,
    required this.chart,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          chart,
        ],
      ),
    );
  }
}

// ─── Trend Indicator ──────────────────────────────────────────────────────────

class _TrendIndicator extends StatelessWidget {
  final List<KpiBucket> buckets;

  const _TrendIndicator({required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.length < 4) return const SizedBox.shrink();

    final mid = buckets.length ~/ 2;
    final firstHalf = buckets
        .sublist(0, mid)
        .fold<double>(0, (s, b) => s + b.value);
    final secondHalf = buckets
        .sublist(mid)
        .fold<double>(0, (s, b) => s + b.value);

    if (firstHalf == 0 && secondHalf == 0) return const SizedBox.shrink();

    final change = firstHalf == 0
        ? 100.0
        : ((secondHalf - firstHalf) / firstHalf.abs()) * 100;
    final isPositive = change >= 0;
    final color = isPositive ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trend Chart ──────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final String title;
  final Color primaryColor;
  final Color? secondaryColor;
  final List<KpiBucket> primary;
  final List<KpiBucket>? secondary;
  final String primaryLabel;
  final String? secondaryLabel;
  final bool isPercentage;

  const _TrendChart({
    required this.title,
    required this.primaryColor,
    required this.primary,
    required this.primaryLabel,
    this.secondaryColor,
    this.secondary,
    this.secondaryLabel,
    this.isPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (primary.isEmpty) {
      return const _NoDataState(message: 'No data in selected range.');
    }

    final labels = primary.map((p) => p.periodStart).toList();
    final primarySpots = primary
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();
    final secondarySpots = secondary
        ?.asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();

    final allValues = <double>[...primary.map((p) => p.value)];
    if (secondary != null) {
      allValues.addAll(secondary!.map((p) => p.value));
    }

    var minY = allValues.reduce((a, b) => a < b ? a : b);
    var maxY = allValues.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      final delta = minY == 0 ? 10.0 : minY.abs() * 0.1;
      minY -= delta;
      maxY += delta;
    } else {
      final padding = (maxY - minY) * 0.12;
      minY -= padding;
      maxY += padding;
    }
    // Don't show a negative Y-axis when all data points are non-negative.
    if (allValues.every((v) => v >= 0)) minY = minY.clamp(0.0, double.maxFinite);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (secondarySpots != null) ...[
          Row(
            children: [
              _LegendDot(color: primaryColor, label: primaryLabel),
              const SizedBox(width: 12),
              _LegendDot(
                color: secondaryColor ?? AppColors.secondary,
                label: secondaryLabel ?? 'Secondary',
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (primarySpots.length - 1).toDouble(),
              minY: minY,
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _bottomInterval(primarySpots.length),
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      final date = labels[index];
                      final fmt = _labelFormat(labels);
                      return Text(
                        DateFormat(fmt).format(date),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    getTitlesWidget: (value, meta) {
                      final String text;
                      if (isPercentage) {
                        text = '${value.toStringAsFixed(0)}%';
                      } else if (value.abs() >= 1000) {
                        text = NumberFormat.compactCurrency(symbol: '\$').format(value);
                      } else {
                        // compactCurrency adds `.00` only below 100, producing
                        // an axis ladder like `$120 / $100 / $80.00 / $60.00`.
                        // Use a no-decimal currency format under the K
                        // threshold so the ticks read consistently.
                        text = NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value);
                      }
                      return Text(
                        text,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x.toInt();
                      final dateStr = index >= 0 && index < labels.length
                          ? DateFormat('MMM d, y').format(labels[index])
                          : '';
                      final valueStr = isPercentage
                          ? '${spot.y.toStringAsFixed(1)}%'
                          : NumberFormat.currency(
                              symbol: '\$',
                              decimalDigits: 0,
                            ).format(spot.y);
                      final seriesLabel = spot.barIndex == 0
                          ? primaryLabel
                          : (secondaryLabel ?? 'Secondary');
                      return LineTooltipItem(
                        '$dateStr\n$seriesLabel: $valueStr',
                        TextStyle(
                          color: spot.barIndex == 0
                              ? primaryColor
                              : (secondaryColor ?? AppColors.secondary),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: primarySpots,
                  isCurved: true,
                  color: primaryColor,
                  barWidth: 2.2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                if (secondarySpots != null)
                  LineChartBarData(
                    spots: secondarySpots,
                    isCurved: true,
                    color: secondaryColor ?? AppColors.secondary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: const [4, 3],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _labelFormat(List<DateTime> labels) {
    if (labels.length < 2) return 'M/d';
    final diff = labels[1].difference(labels[0]).inDays;
    return diff <= 1 ? 'M/d' : 'MMM';
  }

  double _bottomInterval(int length) {
    if (length <= 8) return 1;
    if (length <= 16) return 2;
    if (length <= 24) return 3;
    return 4;
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _CardTitle extends StatelessWidget {
  final String title;
  final String? tooltip;
  final Color color;

  const _CardTitle({required this.title, required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (tooltip != null && tooltip!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: tooltip!,
            child: Icon(
              Icons.info_outline,
              size: 14,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _NoDataState extends StatelessWidget {
  final String message;

  const _NoDataState({required this.message});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 48,
              color: chrome.scaffoldTextSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: chrome.scaffoldTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _formatCurrency(double value) {
  return NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(value);
}
