import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../theme/theme.dart';
import '../../models/time_entry.dart';
import '../../models/time_entry_status.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import 'widgets/time_tracking_view_bar.dart';

class WeeklyTimesheetScreen extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;
  final bool showViewBar;

  const WeeklyTimesheetScreen({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
  });

  @override
  State<WeeklyTimesheetScreen> createState() => _WeeklyTimesheetScreenState();
}

class _WeeklyTimesheetScreenState extends State<WeeklyTimesheetScreen> {
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _projectService => ServiceLocator.projectService;

  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  bool _isGeneratingPdf = false;

  static DateTime _getWeekStart(DateTime date) {
    // Get Monday of the week
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime get _selectedWeekEnd => _selectedWeekStart.add(
    const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
  );

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userName = authProvider.appUser?.displayName ?? 'Unknown User';

    if (userId == null || workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: Not authenticated')),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.weekly,
              onViewChanged: widget.onViewChanged,
              quickToggles: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                onPressed: _isGeneratingPdf
                    ? null
                    : () => _generatePdf(userId, workspaceId, userName),
                tooltip: 'Export PDF',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          _buildWeekSelector(),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<TimeEntry>>(
              stream: _timeEntryService.getTimeEntriesForDateRange(
                userId,
                _selectedWeekStart,
                _selectedWeekEnd,
                workspaceId: workspaceId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load data',
                      ),
                    ),
                  );
                }

                final allEntries = snapshot.data ?? [];
                final entries = widget.projectId == null
                    ? allEntries
                    : allEntries
                          .where((e) => e.projectId == widget.projectId)
                          .toList();

                if (entries.isEmpty) {
                  return _buildEmptyState();
                }

                return Column(
                  children: [
                    _buildSummaryCard(entries),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        children: [
                          _buildDailyBreakdown(entries),
                          const SizedBox(height: 16),
                          _buildProjectBreakdown(entries),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _selectedWeekStart = _selectedWeekStart.subtract(
                  const Duration(days: 7),
                );
              });
            },
          ),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedWeekStart,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _selectedWeekStart = _getWeekStart(picked);
                });
              }
            },
            child: Column(
              children: [
                Text(
                  'Week of ${DateFormat('MMM d').format(_selectedWeekStart)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${DateFormat('MMM d').format(_selectedWeekStart)} - ${DateFormat('MMM d, yyyy').format(_selectedWeekEnd)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: _isCurrentWeek() ? AppColors.textTertiary : null,
            ),
            onPressed: _isCurrentWeek()
                ? null
                : () {
                    setState(() {
                      _selectedWeekStart = _selectedWeekStart.add(
                        const Duration(days: 7),
                      );
                    });
                  },
          ),
        ],
      ),
    );
  }

  bool _isCurrentWeek() {
    final now = DateTime.now();
    final currentWeekStart = _getWeekStart(now);
    return _selectedWeekStart.year == currentWeekStart.year &&
        _selectedWeekStart.month == currentWeekStart.month &&
        _selectedWeekStart.day == currentWeekStart.day;
  }

  Widget _buildSummaryCard(List<TimeEntry> entries) {
    double totalHours = 0;
    double regularHours = 0;
    double overtimeHours = 0;
    double doubleTimeHours = 0;
    double totalCost = 0;
    int approvedCount = 0;

    for (final entry in entries) {
      regularHours += entry.regularHours;
      overtimeHours += entry.overtimeHours;
      doubleTimeHours += entry.doubleTimeHours;
      totalHours +=
          entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
      totalCost += entry.totalCost;
      if (entry.status == TimeEntryStatus.approved) approvedCount++;
    }

    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  'Total Hours',
                  totalHours.toStringAsFixed(1),
                  Icons.access_time,
                  AppColors.info,
                ),
                _buildSummaryItem(
                  'Total Cost',
                  '\$${totalCost.toStringAsFixed(2)}',
                  Icons.attach_money,
                  AppColors.success,
                ),
                _buildSummaryItem(
                  'Entries',
                  '${entries.length}',
                  Icons.list,
                  AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHoursBreakdownItem(
                  'Regular',
                  regularHours,
                  AppColors.info,
                ),
                _buildHoursBreakdownItem(
                  'OT',
                  overtimeHours,
                  AppColors.warning,
                ),
                _buildHoursBreakdownItem(
                  'Double',
                  doubleTimeHours,
                  AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: entries.isEmpty ? 0 : approvedCount / entries.length,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
            const SizedBox(height: 8),
            Text(
              '$approvedCount of ${entries.length} entries approved',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildHoursBreakdownItem(String label, double hours, Color color) {
    return Column(
      children: [
        Text(
          hours.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDailyBreakdown(List<TimeEntry> entries) {
    // Group entries by day
    final Map<String, List<TimeEntry>> entriesByDay = {};
    for (final entry in entries) {
      final dayKey = DateFormat('yyyy-MM-dd').format(entry.date);
      entriesByDay.putIfAbsent(dayKey, () => []).add(entry);
    }

    // Sort days
    final sortedDays = entriesByDay.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...sortedDays.map((dayKey) {
              final dayEntries = entriesByDay[dayKey]!;
              final date = DateTime.parse(dayKey);
              double dayHours = 0;
              double dayCost = 0;

              for (final entry in dayEntries) {
                dayHours +=
                    entry.regularHours +
                    entry.overtimeHours +
                    entry.doubleTimeHours;
                dayCost += entry.totalCost;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(date),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${dayEntries.length} entries',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${dayHours.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.info,
                          ),
                        ),
                        Text(
                          '\$${dayCost.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectBreakdown(List<TimeEntry> entries) {
    // Group entries by project
    final Map<String, List<TimeEntry>> entriesByProject = {};
    for (final entry in entries) {
      entriesByProject.putIfAbsent(entry.projectId, () => []).add(entry);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} Breakdown',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...entriesByProject.entries.map((projectEntry) {
              final projectId = projectEntry.key;
              final projectEntries = projectEntry.value;
              double projectHours = 0;
              double projectCost = 0;

              for (final entry in projectEntries) {
                projectHours +=
                    entry.regularHours +
                    entry.overtimeHours +
                    entry.doubleTimeHours;
                projectCost += entry.totalCost;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: FutureBuilder<Project?>(
                  future: _projectService.getProject(projectId),
                  builder: (context, snapshot) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                snapshot.data?.name ?? 'Loading...',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${projectEntries.length} entries',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${projectHours.toStringAsFixed(1)}h',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.info,
                              ),
                            ),
                            Text(
                              '\$${projectCost.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No time entries for this week',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf(
    String userId,
    String workspaceId,
    String userName,
  ) async {
    setState(() => _isGeneratingPdf = true);

    try {
      // Fetch entries
      final List<TimeEntry> allEntries = await _timeEntryService
          .getTimeEntriesForDateRange(
            userId,
            _selectedWeekStart,
            _selectedWeekEnd,
            workspaceId: workspaceId,
          )
          .first;

      final entries = widget.projectId == null
          ? allEntries
          : allEntries
                .where((e) => e.projectId == widget.projectId)
                .toList();

      if (entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No entries to export')));
        }
        setState(() => _isGeneratingPdf = false);
        return;
      }

      final pdfSingular = singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology);

      // Calculate totals
      double totalHours = 0;
      double regularHours = 0;
      double overtimeHours = 0;
      double doubleTimeHours = 0;
      double totalCost = 0;

      for (final entry in entries) {
        regularHours += entry.regularHours;
        overtimeHours += entry.overtimeHours;
        doubleTimeHours += entry.doubleTimeHours;
        totalHours +=
            entry.regularHours + entry.overtimeHours + entry.doubleTimeHours;
        totalCost += entry.totalCost;
      }

      // Fetch project names
      final Map<String, String> projectNames = {};
      for (final entry in entries) {
        if (!projectNames.containsKey(entry.projectId)) {
          final project = await _projectService.getProject(entry.projectId);
          projectNames[entry.projectId] = project?.name ?? 'Unknown $pdfSingular';
        }
      }

      // Generate PDF
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(AppSpacing.xxl),
          build: (pw.Context context) {
            return [
              // Header
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Weekly Time',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(userName, style: const pw.TextStyle(fontSize: 16)),
                    pw.Text(
                      '${DateFormat('MMM d, yyyy').format(_selectedWeekStart)} - ${DateFormat('MMM d, yyyy').format(_selectedWeekEnd)}',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated: ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Summary section
              pw.Container(
                padding: const pw.EdgeInsets.all(AppSpacing.md),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Summary',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Total Hours: ${totalHours.toStringAsFixed(2)}',
                            ),
                            pw.Text(
                              'Regular: ${regularHours.toStringAsFixed(2)}h',
                            ),
                            pw.Text(
                              'Overtime: ${overtimeHours.toStringAsFixed(2)}h',
                            ),
                            pw.Text(
                              'Double Time: ${doubleTimeHours.toStringAsFixed(2)}h',
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Total Cost: \$${totalCost.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text('Entries: ${entries.length}'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Entries table
              pw.Text(
                'Time Entries',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: [
                      _buildTableCell('Date', isHeader: true),
                      _buildTableCell(pdfSingular, isHeader: true),
                      _buildTableCell('Hours', isHeader: true),
                      _buildTableCell('Cost', isHeader: true),
                      _buildTableCell('Status', isHeader: true),
                    ],
                  ),
                  // Data rows
                  ...entries.map((entry) {
                    final hours =
                        entry.regularHours +
                        entry.overtimeHours +
                        entry.doubleTimeHours;
                    return pw.TableRow(
                      children: [
                        _buildTableCell(DateFormat('MMM d').format(entry.date)),
                        _buildTableCell(
                          projectNames[entry.projectId] ?? 'Unknown',
                        ),
                        _buildTableCell(hours.toStringAsFixed(2)),
                        _buildTableCell(
                          '\$${entry.totalCost.toStringAsFixed(2)}',
                        ),
                        _buildTableCell(entry.status.displayName),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );

      // Show PDF preview/print dialog
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'timesheet_${DateFormat('yyyy-MM-dd').format(_selectedWeekStart)}.pdf',
      );

      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'generating PDF'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
