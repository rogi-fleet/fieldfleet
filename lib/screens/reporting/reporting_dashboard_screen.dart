import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/backend_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reporting_provider.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../theme/theme.dart';
import '../../utils/kpi_range_utils.dart';
import '../../utils/raw_data_export.dart';
import '../../widgets/common/module_header.dart';
import 'widgets/profit_loss_report_widget.dart';
import 'widgets/revenue_trends_widget.dart';
import 'widgets/labor_report_widget.dart';
import 'widgets/project_completion_widget.dart';
import 'widgets/wip_schedule_widget.dart';
import 'widgets/cash_flow_projection_widget.dart';
import 'widgets/workspace_stats_widget.dart';

class ReportingDashboardScreen extends StatefulWidget {
  const ReportingDashboardScreen({super.key});

  @override
  State<ReportingDashboardScreen> createState() =>
      _ReportingDashboardScreenState();
}

class _ReportingDashboardScreenState extends State<ReportingDashboardScreen>
    with WorkspaceGatedLoader {
  final RawDataExportService _rawDataExportService = RawDataExportService();

  // One-shot post-frame loading raced cold-load auth hydration: appUser was
  // still null, nothing was fetched, and the screen sat on its empty states
  // forever. WorkspaceGatedLoader re-fires the moment the workspace id is
  // available (and on workspace switches).
  @override
  void onWorkspaceReady(String workspaceId) {
    final reportingProvider = context.read<ReportingProvider>();
    reportingProvider.loadWorkspaceStats(workspaceId);
    reportingProvider.loadCurrentReport(workspaceId);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final reportingProvider = context.watch<ReportingProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final chrome = ChromeColors.of(context);

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          const ModuleHeader(
            icon: Icons.assessment_outlined,
            title: 'Reporting',
            description:
                'Operational KPIs and financial summaries across the business.',
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Workspace Stats Summary
                  WorkspaceStatsWidget(
              stats: reportingProvider.workspaceStats,
              isLoading:
                  reportingProvider.isLoading &&
                  reportingProvider.workspaceStats == null,
            ),

            // Report Type Selector + Export button
            _buildReportTypeSelector(reportingProvider, workspaceId, chrome),
            _buildRangeSelector(reportingProvider, workspaceId, chrome),

            // Report Content
            reportingProvider.error != null
                ? _buildErrorState(
                    reportingProvider.error!,
                    reportingProvider,
                    workspaceId,
                    chrome,
                  )
                : _buildReportContent(reportingProvider),
          ],
        ),
      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showColumnGuide() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('CSV Column Guide'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final type in _rawDataExportService.exportTypes)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('${type.label} CSV'),
                      children: [
                        for (final guide
                            in _rawDataExportService.getColumnGuide(type))
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            title: Text(
                              guide.column,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(guide.description),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showExportBottomSheet(String workspaceId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            var isExporting = false;
            String? exportingLabel;

            return StatefulBuilder(
              builder: (context, setSheetState) {
                Future<void> runExport(
                  String label,
                  Future<void> Function() action,
                ) async {
                  if (isExporting) return;
                  setSheetState(() {
                    isExporting = true;
                    exportingLabel = label;
                  });
                  try {
                    await action();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('$label export started')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Failed to export $label: $e')),
                    );
                  } finally {
                    if (mounted) {
                      setSheetState(() {
                        isExporting = false;
                        exportingLabel = null;
                      });
                    }
                  }
                }

                return Column(
                  children: [
                    // Drag handle
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.download_for_offline_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Data Export',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showColumnGuide,
                            icon: const Icon(Icons.help_outline, size: 16),
                            label: const Text('Column Guide'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(AppSpacing.base),
                        children: [
                          // Export progress
                          if (isExporting) ...[
                            Card(
                              color: AppColors.infoLight,
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Preparing ${exportingLabel ?? ''} export...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Raw Data section
                          Text(
                            'Raw Data (CSV)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: const Icon(Icons.download),
                            title: const Text('Download All Data'),
                            subtitle: const Text(
                              'Export all tables as CSV files',
                            ),
                            enabled: !isExporting,
                            onTap: () => runExport(
                              'All data',
                              () => _rawDataExportService
                                  .exportAll(workspaceId),
                            ),
                          ),
                          const Divider(),
                          for (final type
                              in _rawDataExportService.exportTypes) ...[
                            ListTile(
                              leading: const Icon(
                                Icons.file_download_outlined,
                                size: 20,
                              ),
                              title: Text(type.label),
                              enabled: !isExporting,
                              onTap: () => runExport(
                                type.label,
                                () => _rawDataExportService.exportType(
                                  type: type,
                                  workspaceId: workspaceId,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Import Templates section
                          Text(
                            'Import Templates',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: const Icon(Icons.table_view_outlined),
                            title: const Text('Download All Templates'),
                            subtitle: const Text(
                              'Get blank templates for data import',
                            ),
                            enabled: !isExporting,
                            onTap: () => runExport(
                              'All templates',
                              () =>
                                  _rawDataExportService.exportAllTemplates(),
                            ),
                          ),
                          const Divider(),
                          for (final type
                              in _rawDataExportService.exportTypes) ...[
                            ListTile(
                              leading: const Icon(
                                Icons.description_outlined,
                                size: 20,
                              ),
                              title: Text('${type.label} Template'),
                              enabled: !isExporting,
                              onTap: () => runExport(
                                '${type.label} template',
                                () => _rawDataExportService
                                    .exportTemplateType(type),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRangeSelector(ReportingProvider provider, String workspaceId, ChromeColors chrome) {
    final presets = const [
      KpiRangePreset.sevenDays,
      KpiRangePreset.thirtyDays,
      KpiRangePreset.quarterToDate,
      KpiRangePreset.yearToDate,
      KpiRangePreset.twelveMonths,
    ];

    final customRange = provider.selectedRange;
    final customLabel =
        customRange.isCustom &&
            customRange.customStart != null &&
            customRange.customEnd != null
        ? '${DateFormat('M/d').format(customRange.customStart!)}-${DateFormat('M/d').format(customRange.customEnd!)}'
        : 'Custom';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Chip backgrounds come from chipTheme (always light surfaceAlt),
          // so use textPrimary directly — chrome.scaffoldText is white in
          // dark-chrome mode and disappears against the light chip fill.
          for (final preset in presets)
            ChoiceChip(
              selected: provider.selectedRange.preset == preset,
              label: Text(KpiRange.preset(preset).label),
              side: BorderSide(color: chrome.scaffoldDivider),
              labelStyle: const TextStyle(color: AppColors.textPrimary),
              onSelected: (selected) {
                if (!selected) return;
                provider.setRange(KpiRange.preset(preset));
                provider.loadCurrentReport(workspaceId);
              },
            ),
          ChoiceChip(
            selected: provider.selectedRange.isCustom,
            label: Text(customLabel),
            side: BorderSide(color: chrome.scaffoldDivider),
            labelStyle: const TextStyle(color: AppColors.textPrimary),
            onSelected: (_) => _pickCustomRange(provider, workspaceId),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(
    ReportingProvider provider,
    String workspaceId,
  ) async {
    final initialStart =
        provider.startDate ?? DateTime.now().subtract(const Duration(days: 29));
    final initialEnd = provider.endDate ?? DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (result == null) return;

    provider.setRange(KpiRange.custom(start: result.start, end: result.end));
    await provider.loadCurrentReport(workspaceId);
  }

  Widget _buildReportTypeSelector(
    ReportingProvider provider,
    String workspaceId,
    ChromeColors chrome,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildReportTypeChip(
                    'Profit/Loss',
                    ReportType.projectProfitLoss,
                    Icons.attach_money,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                  const SizedBox(width: 8),
                  _buildReportTypeChip(
                    'Revenue Trends',
                    ReportType.revenueTrends,
                    Icons.trending_up,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                  const SizedBox(width: 8),
                  _buildReportTypeChip(
                    'Labor Hours',
                    ReportType.hoursByWorker,
                    Icons.access_time,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                  const SizedBox(width: 8),
                  _buildReportTypeChip(
                    '${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} Progress',
                    ReportType.projectCompletion,
                    Icons.check_circle_outline,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                  const SizedBox(width: 8),
                  _buildReportTypeChip(
                    'WIP Schedule',
                    ReportType.wipSchedule,
                    Icons.stacked_bar_chart,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                  const SizedBox(width: 8),
                  _buildReportTypeChip(
                    'Cash Flow',
                    ReportType.cashFlow,
                    Icons.waterfall_chart,
                    provider,
                    workspaceId,
                    chrome,
                  ),
                ],
              ),
            ),
          ),
          if (BackendConfig.isSupabaseEnabled) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.download_outlined, color: chrome.scaffoldText),
              tooltip: 'Export Data',
              onPressed: () => _showExportBottomSheet(workspaceId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportTypeChip(
    String label,
    ReportType type,
    IconData icon,
    ReportingProvider provider,
    String workspaceId,
    ChromeColors chrome,
  ) {
    final isSelected = provider.selectedReportType == type;

    return ChoiceChip(
      selected: isSelected,
      side: BorderSide(color: chrome.scaffoldDivider),
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textPrimary),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      onSelected: (selected) {
        if (!selected) return;
        provider.selectReportType(type);
        provider.loadCurrentReport(workspaceId);
      },
    );
  }

  Widget _buildReportContent(ReportingProvider provider) {
    if (provider.isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    switch (provider.selectedReportType) {
      case ReportType.projectProfitLoss:
        return ProfitLossReportWidget(reports: provider.profitLossReports);
      case ReportType.revenueTrends:
        return RevenueTrendsWidget(trends: provider.revenueTrends);
      case ReportType.hoursByWorker:
        return LaborReportWidget(reports: provider.laborReports);
      case ReportType.projectCompletion:
        return ProjectCompletionWidget(reports: provider.completionReports);
      case ReportType.wipSchedule:
        return WipScheduleWidget(rows: provider.wipReport);
      case ReportType.cashFlow:
        return CashFlowProjectionWidget(entries: provider.cashFlowEntries);
    }
  }

  Widget _buildErrorState(
    String error,
    ReportingProvider provider,
    String workspaceId,
    ChromeColors chrome,
  ) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error loading report',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: chrome.scaffoldText,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: SelectableText(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: chrome.scaffoldTextSecondary),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                provider.clearError();
                provider.loadCurrentReport(workspaceId);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
