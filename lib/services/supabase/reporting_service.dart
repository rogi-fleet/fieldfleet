import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/project.dart';
import '../../models/time_entry.dart';
import '../../models/kpi_dashboard_data.dart';
import '../kpi_aggregation.dart';
import '../../utils/app_logger.dart';
import '../../utils/kpi_range_utils.dart';

class FinancialReport {
  final String projectId;
  final String projectName;
  final double totalInvoiced;
  final double totalLaborCost;
  final double profit;

  FinancialReport({
    required this.projectId,
    required this.projectName,
    required this.totalInvoiced,
    required this.totalLaborCost,
    required this.profit,
  });
}

class RevenueTrend {
  final DateTime month;
  final double totalRevenue;

  RevenueTrend({required this.month, required this.totalRevenue});
}

class ProfitTrend {
  final DateTime month;
  final double profit;

  ProfitTrend({required this.month, required this.profit});
}

class ClosingRateTrend {
  final DateTime month;
  final double closingRate;

  ClosingRateTrend({required this.month, required this.closingRate});
}

class LaborReport {
  final String userId;
  final String userName;
  final double totalHours;
  final double totalCost;

  LaborReport({
    required this.userId,
    required this.userName,
    required this.totalHours,
    required this.totalCost,
  });
}

class ProjectCompletionReport {
  final String projectId;
  final String projectName;
  final int totalTasks;
  final int completedTasks;
  final double completionPercentage;

  ProjectCompletionReport({
    required this.projectId,
    required this.projectName,
    required this.totalTasks,
    required this.completedTasks,
    required this.completionPercentage,
  });
}

/// Supabase implementation of ReportingService
class SupabaseReportingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Financial Reports

  /// Get profit/loss by project
  Future<List<FinancialReport>> getProjectProfitLoss(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get all projects for workspace. Deliberately NOT windowed by the
      // project's created_at — a job started before the period still
      // belongs in the report when it has in-period invoices/labor (the
      // per-project queries below carry the date range).
      final projectsResponse = await _supabase
          .from('projects')
          .select('id, name')
          .eq('workspace_id', workspaceId);

      final reports = <FinancialReport>[];

      for (final projectRow in projectsResponse) {
        final project = _normalizeRow(projectRow);
        final projectId = project['id']?.toString();
        if (projectId == null || projectId.isEmpty) {
          continue;
        }
        final projectName = project['name']?.toString() ?? 'Untitled Project';

        // Get total invoiced for this project. "Billed out" matches
        // isStatusBilled (sent/viewed/signed/approved) — the old
        // ['signed','sent'] filter hid approved invoices, and filtering by
        // paid_date dropped every unpaid invoice from the report.
        var invoicesQuery = _supabase
            .from('generated_documents')
            .select('total_price:total_amount')
            .eq('workspace_id', workspaceId)
            .eq('project_id', projectId)
            .eq('document_type', 'invoice')
            .inFilter('status', ['signed', 'sent', 'viewed', 'approved']);
        if (startDate != null) {
          invoicesQuery = invoicesQuery.gte(
            'created_at',
            kpiDateOnlyString(startDate),
          );
        }
        if (endDate != null) {
          invoicesQuery = invoicesQuery.lte(
            'created_at',
            kpiDateOnlyString(endDate),
          );
        }
        final invoicesResponse = await invoicesQuery;

        double totalInvoiced = 0.0;
        for (final invoiceRow in invoicesResponse) {
          final normalized = _normalizeRow(invoiceRow);
          totalInvoiced += (normalized['total_price'] as num?)?.toDouble() ?? 0.0;
        }

        // Get total cost for this project.
        var timeEntriesQuery = _supabase
            .from('time_entries')
            .select('total_cost')
            .eq('workspace_id', workspaceId)
            .eq('project_id', projectId)
            .eq('status', 'approved');
        if (startDate != null) {
          timeEntriesQuery = timeEntriesQuery.gte(
            'date',
            kpiDateOnlyString(startDate),
          );
        }
        if (endDate != null) {
          timeEntriesQuery = timeEntriesQuery.lte(
            'date',
            kpiDateOnlyString(endDate),
          );
        }
        final timeEntriesResponse = await timeEntriesQuery;

        double totalLaborCost = 0.0;
        for (final timeEntryRow in timeEntriesResponse) {
          final timeEntry = _normalizeRow(timeEntryRow);
          totalLaborCost += (timeEntry['total_cost'] as num?)?.toDouble() ?? 0.0;
        }

        final profit = totalInvoiced - totalLaborCost;

        reports.add(
          FinancialReport(
            projectId: projectId,
            projectName: projectName,
            totalInvoiced: totalInvoiced,
            totalLaborCost: totalLaborCost,
            profit: profit,
          ),
        );
      }

      return reports;
    } catch (e) {
      throw Exception('Failed to generate profit/loss report: $e');
    }
  }

  /// Get revenue trends by month
  Future<List<RevenueTrend>> getRevenueTrends(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 365));
      final end = endDate ?? DateTime.now();

      // Get all paid invoices in date range (from generated_documents)
      final invoicesResponse = await _supabase
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('document_type', 'invoice')
          .eq('status', 'signed')
          .not('paid_date', 'is', null)
          .gte('paid_date', start.toIso8601String())
          .lte('paid_date', end.toIso8601String());

      // Group by month
      final Map<String, double> monthlyRevenue = {};

      for (final invoiceRow in invoicesResponse) {
        final normalized = _normalizeRow(invoiceRow);
        final paidDateStr = normalized['paid_date'] as String?;
        final total = (normalized['total_price'] as num?)?.toDouble() ?? 0.0;
        if (paidDateStr != null) {
          final paidDate = DateTime.parse(paidDateStr);
          final monthKey =
              '${paidDate.year}-${paidDate.month.toString().padLeft(2, '0')}';
          monthlyRevenue[monthKey] =
              (monthlyRevenue[monthKey] ?? 0.0) + total;
        }
      }

      // Convert to list and sort
      final trends = monthlyRevenue.entries.map((entry) {
        final parts = entry.key.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        return RevenueTrend(
          month: DateTime(year, month),
          totalRevenue: entry.value,
        );
      }).toList()..sort((a, b) => a.month.compareTo(b.month));

      return trends;
    } catch (e) {
      throw Exception('Failed to generate revenue trends: $e');
    }
  }

  /// Get profit trends by month
  Future<List<ProfitTrend>> getProfitTrends(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 365));
      final end = endDate ?? DateTime.now();

      // 1. Get Revenue (Invoices from generated_documents)
      final invoicesResponse = await _supabase
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('document_type', 'invoice')
          .eq('status', 'signed')
          .not('paid_date', 'is', null)
          .gte('paid_date', start.toIso8601String())
          .lte('paid_date', end.toIso8601String());

      // 2. Get Costs (Time Entries)
      final timeEntriesResponse = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('status', 'approved')
          .gte('date', start.toIso8601String())
          .lte('date', end.toIso8601String());

      // Group by month
      final Map<String, double> monthlyProfit = {};

      // Add Revenue
      for (final row in invoicesResponse) {
        final normalized = _normalizeRow(row);
        final paidDateStr = normalized['paid_date'] as String?;
        final total = (normalized['total_price'] as num?)?.toDouble() ?? 0.0;
        if (paidDateStr != null) {
          final paidDate = DateTime.parse(paidDateStr);
          final monthKey =
              '${paidDate.year}-${paidDate.month.toString().padLeft(2, '0')}';
          monthlyProfit[monthKey] =
              (monthlyProfit[monthKey] ?? 0.0) + total;
        }
      }

      // Subtract Costs
      for (final row in timeEntriesResponse) {
        final entry = TimeEntry.fromJson(
          _toTimeEntryFirestoreFormat(row),
          row['id'],
        );
        final monthKey =
            '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
        monthlyProfit[monthKey] =
            (monthlyProfit[monthKey] ?? 0.0) - entry.totalCost;
      }

      // Convert to list and sort
      final trends = monthlyProfit.entries.map((entry) {
        final parts = entry.key.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        return ProfitTrend(month: DateTime(year, month), profit: entry.value);
      }).toList()..sort((a, b) => a.month.compareTo(b.month));

      return trends;
    } catch (e) {
      throw Exception('Failed to generate profit trends: $e');
    }
  }

  /// Get closing rate trends
  Future<List<ClosingRateTrend>> getClosingRateTrends(
    String workspaceId, {
    int months = 6,
  }) async {
    try {
      final now = DateTime.now();
      final trends = <ClosingRateTrend>[];

      for (int i = 0; i < months; i++) {
        final monthDate = DateTime(now.year, now.month - i, 1);
        final nextMonthDate = DateTime(now.year, now.month - i + 1, 1);

        // Fetch projects created in this month
        final projectsResponse = await _supabase
            .from('projects')
            .select()
            .eq('workspace_id', workspaceId)
            .gte('created_at', monthDate.toIso8601String())
            .lt('created_at', nextMonthDate.toIso8601String());

        int totalOpportunities = 0;
        int wonOpportunities = 0;

        for (final row in projectsResponse) {
          final project = Project.fromJson(
            _toProjectFirestoreFormat(row),
            row['id'],
          );
          totalOpportunities++;

          if (project.status == ProjectStatus.active ||
              project.status == ProjectStatus.complete ||
              project.status == ProjectStatus.awarded ||
              project.status == ProjectStatus.onHold) {
            wonOpportunities++;
          }
        }

        final closingRate = totalOpportunities > 0
            ? (wonOpportunities / totalOpportunities) * 100
            : 0.0;

        trends.add(
          ClosingRateTrend(month: monthDate, closingRate: closingRate),
        );
      }

      // Sort chronological
      trends.sort((a, b) => a.month.compareTo(b.month));

      return trends;
    } catch (e) {
      throw Exception('Failed to generate closing rate trends: $e');
    }
  }

  // Labor Reports

  /// Get hours by worker for a date range
  Future<List<LaborReport>> getHoursByWorker(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      // Get all approved time entries in date range
      final timeEntriesResponse = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('status', 'approved')
          .gte('date', start.toIso8601String())
          .lte('date', end.toIso8601String());

      // Group by user
      final Map<String, Map<String, dynamic>> userStats = {};

      for (final row in timeEntriesResponse) {
        final timeEntry = TimeEntry.fromJson(
          _toTimeEntryFirestoreFormat(row),
          row['id'],
        );

        if (!userStats.containsKey(timeEntry.workerId)) {
          // Fetch user name
          final userResponse = await _supabase
              .from('users')
              .select('display_name, email')
              .eq('id', timeEntry.workerId)
              .maybeSingle();

          final userName = userResponse != null
              ? (userResponse['display_name'] as String? ??
                    userResponse['email'] as String? ??
                    'Unknown User')
              : 'Unknown User';

          userStats[timeEntry.workerId] = {
            'userName': userName,
            'totalHours': 0.0,
            'totalCost': 0.0,
          };
        }

        // Calculate total hours from regular + overtime + double time
        final totalHours =
            timeEntry.regularHours +
            timeEntry.overtimeHours +
            timeEntry.doubleTimeHours;
        userStats[timeEntry.workerId]!['totalHours'] += totalHours;
        userStats[timeEntry.workerId]!['totalCost'] += timeEntry.totalCost;
      }

      // Convert to list
      final reports =
          userStats.entries.map((entry) {
            return LaborReport(
              userId: entry.key,
              userName: entry.value['userName'] as String,
              totalHours: entry.value['totalHours'] as double,
              totalCost: entry.value['totalCost'] as double,
            );
          }).toList()..sort(
            (a, b) => b.totalHours.compareTo(a.totalHours),
          ); // Sort by hours descending

      return reports;
    } catch (e) {
      throw Exception('Failed to generate hours by worker report: $e');
    }
  }

  // Project Reports

  /// Get project completion rates
  Future<List<ProjectCompletionReport>> getProjectCompletionRates(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Get all projects
      var projectsQuery = _supabase
          .from('projects')
          .select('id, name, status')
          .eq('workspace_id', workspaceId);
      if (startDate != null) {
        projectsQuery = projectsQuery.gte(
          'created_at',
          startDate.toIso8601String(),
        );
      }
      if (endDate != null) {
        projectsQuery = projectsQuery.lte(
          'created_at',
          endDate.toIso8601String(),
        );
      }
      final projectsResponse = await projectsQuery;

      final reports = <ProjectCompletionReport>[];

      for (final projectRow in projectsResponse) {
        final project = _normalizeRow(projectRow);
        final projectId = project['id']?.toString();
        if (projectId == null || projectId.isEmpty) {
          continue;
        }
        final projectName = project['name']?.toString() ?? 'Untitled Project';

        // Get all tasks for this project
        final tasksResponse = await _supabase
            .from('tasks')
            .select('is_complete, status, progress, completed_at')
            .eq('workspace_id', workspaceId)
            .eq('project_id', projectId);

        final totalTasks = tasksResponse.length;
        if (totalTasks == 0) {
          reports.add(
            ProjectCompletionReport(
              projectId: projectId,
              projectName: projectName,
              totalTasks: 0,
              completedTasks: 0,
              completionPercentage: 0.0,
            ),
          );
          continue;
        }

        int completedTasks = 0;
        for (final taskRow in tasksResponse) {
          final task = _normalizeRow(taskRow);
          final isComplete = task['is_complete'] == true ||
              task['status'] == 'done' ||
              (task['progress'] is num && (task['progress'] as num) >= 100) ||
              task['completed_at'] != null;
          if (isComplete) {
            completedTasks++;
          }
        }

        final completionPercentage = (completedTasks / totalTasks) * 100;

        reports.add(
          ProjectCompletionReport(
            projectId: projectId,
            projectName: projectName,
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            completionPercentage: completionPercentage,
          ),
        );
      }

      return reports;
    } catch (e) {
      throw Exception('Failed to generate project completion report: $e');
    }
  }

  // Summary/Dashboard Stats

  /// Get overall workspace statistics
  Future<Map<String, dynamic>> getWorkspaceStats(String workspaceId) async {
    try {
      // Get total projects
      final projectsResponse = await _supabase
          .from('projects')
          .select()
          .eq('workspace_id', workspaceId);

      final totalProjects = projectsResponse.length;

      // Get active projects (awarded, active, on_hold)
      const openStatuses = {'active', 'awarded', 'on_hold'};
      final activeProjects = projectsResponse
          .where((row) => openStatuses.contains(row['status']))
          .length;

      // Get total invoices this month
      final firstDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      final invoicesResponse = await _supabase
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('document_type', 'invoice')
          .eq('status', 'signed')
          .not('paid_date', 'is', null)
          .gte('paid_date', firstDayOfMonth.toIso8601String());

      double monthlyRevenue = 0.0;
      for (final row in invoicesResponse) {
        final normalized = _normalizeRow(row);
        monthlyRevenue += (normalized['total_price'] as num?)?.toDouble() ?? 0.0;
      }

      // Get total labor hours this month
      final timeEntriesResponse = await _supabase
          .from('time_entries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('status', 'approved')
          .gte('date', firstDayOfMonth.toIso8601String());

      double monthlyLaborHours = 0.0;
      for (final row in timeEntriesResponse) {
        final timeEntry = TimeEntry.fromJson(
          _toTimeEntryFirestoreFormat(row),
          row['id'],
        );
        monthlyLaborHours +=
            timeEntry.regularHours +
            timeEntry.overtimeHours +
            timeEntry.doubleTimeHours;
      }

      return {
        'totalProjects': totalProjects,
        'activeProjects': activeProjects,
        'monthlyRevenue': monthlyRevenue,
        'monthlyLaborHours': monthlyLaborHours,
      };
    } catch (e) {
      throw Exception('Failed to generate workspace stats: $e');
    }
  }

  // Dashboard KPI Stats

  Future<KpiDashboardData> getKpiDashboardData(
    String workspaceId, {
    required KpiRange range,
  }) async {
    try {
      final resolved = resolveKpiRange(range);
      final start = resolved.start;
      final end = resolved.end;

      AppLogger.info(
        'Loading KPI dashboard data',
        metadata: {
          'workspaceId': workspaceId,
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'granularity': resolved.granularity.name,
        },
      );

      final results = await Future.wait<dynamic>([
        _supabase
            .from('generated_documents')
            .select('project_id, paid_date, total_price:total_amount')
            .eq('workspace_id', workspaceId)
            .eq('document_type', 'invoice')
            .eq('status', 'signed')
            .not('paid_date', 'is', null)
            .gte('paid_date', kpiDateOnlyString(start))
            .lte('paid_date', kpiDateOnlyString(end)),
        _supabase
            .from('time_entries')
            .select('date, total_cost')
            .eq('workspace_id', workspaceId)
            .eq('status', 'approved')
            .gte('date', kpiDateOnlyString(start))
            .lte('date', kpiDateOnlyString(end)),
        _supabase
            .from('cost_items')
            .select('date, total_cost')
            .eq('workspace_id', workspaceId)
            .gte('date', kpiDateOnlyString(start))
            .lte('date', kpiDateOnlyString(end)),
        _supabase
            .from('projects')
            .select('id, status, created_at, updated_at')
            .eq('workspace_id', workspaceId)
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String()),
        _supabase
            .from('budget_items')
            .select('parent_id, projected_cost, project_id')
            .eq('workspace_id', workspaceId),
        // Statuses for every project in the workspace, used to decide which
        // projects contribute to forecast profit. Pre-conversion statuses
        // (lead, bidding, proposal_sent) are pipeline, not commitments.
        _supabase
            .from('projects')
            .select('id, status')
            .eq('workspace_id', workspaceId),
      ]);

      final invoicesResponse = (results[0] as List);
      final timeEntriesResponse = (results[1] as List);
      final costItemsResponse = (results[2] as List);
      final projectsResponse = (results[3] as List);
      final budgetItemsResponse = (results[4] as List);
      final allProjectsResponse = (results[5] as List);

      // Status set that represents committed (not pipeline) work.
      const committedStatuses = {
        'active',
        'awarded',
        'in_progress',
        'complete',
      };
      final committedProjectIds = <String>{
        for (final p in allProjectsResponse)
          if (committedStatuses.contains(p['status'] as String?))
            p['id'] as String,
      };

      double totalProjectedCost = 0.0;
      for (final row in budgetItemsResponse) {
        if (row['parent_id'] != null) continue;
        final projectId = row['project_id'] as String?;
        if (projectId == null) continue;
        if (!committedProjectIds.contains(projectId)) continue;
        totalProjectedCost +=
            (row['projected_cost'] as num?)?.toDouble() ?? 0.0;
      }

      final revenueEntries = <KpiRevenueEntry>[];
      for (final row in invoicesResponse) {
        final paidDate = _parseDate(row['paid_date']);
        if (paidDate == null) continue;
        revenueEntries.add(
          KpiRevenueEntry(
            date: paidDate,
            amount: (row['total_price'] as num?)?.toDouble() ?? 0.0,
            projectId: row['project_id'] as String?,
          ),
        );
      }

      final laborEntries = <KpiCostEntry>[];
      for (final row in timeEntriesResponse) {
        final date = _parseDate(row['date']);
        if (date == null) continue;
        laborEntries.add(
          KpiCostEntry(
            date: date,
            amount: (row['total_cost'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }

      final costEntries = <KpiCostEntry>[];
      for (final row in costItemsResponse) {
        final date = _parseDate(row['date']);
        if (date == null) continue;
        costEntries.add(
          KpiCostEntry(
            date: date,
            amount: (row['total_cost'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }

      final projectEntries = <KpiProjectEntry>[];
      for (final row in projectsResponse) {
        final createdAt = _parseDateTime(row['created_at']);
        final updatedAt = _parseDateTime(row['updated_at']);
        if (createdAt == null || updatedAt == null) continue;
        projectEntries.add(
          KpiProjectEntry(
            status: (row['status'] as String?) ?? '',
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        );
      }

      return KpiAggregation.aggregate(
        KpiAggregationInput(
          rangeStart: start,
          rangeEnd: end,
          granularity: resolved.granularity,
          revenueEntries: revenueEntries,
          laborEntries: laborEntries,
          costEntries: costEntries,
          projectEntries: projectEntries,
          projectedCostTotal: totalProjectedCost,
        ),
      );
    } catch (e) {
      AppLogger.error('Failed to load KPI dashboard data', error: e);
      rethrow;
    }
  }

  /// Compatibility wrapper for legacy KPI cards.
  /// Returns the selected range total in the `ytd` key.
  Future<Map<String, double>> getRevenueStats(String workspaceId) async {
    try {
      final data = await getKpiDashboardData(
        workspaceId,
        range: const KpiRange.preset(KpiRangePreset.yearToDate),
      );
      return {
        'wtd': 0.0,
        'mtd': 0.0,
        'qtd': 0.0,
        'ytd': data.revenue.totalRevenue,
      };
    } catch (_) {
      return {'wtd': 0.0, 'mtd': 0.0, 'qtd': 0.0, 'ytd': 0.0};
    }
  }

  /// Compatibility wrapper for legacy KPI cards.
  /// Returns gross profit in the `ytd` key.
  Future<Map<String, double>> getProfitStats(String workspaceId) async {
    try {
      final data = await getKpiDashboardData(
        workspaceId,
        range: const KpiRange.preset(KpiRangePreset.yearToDate),
      );
      return {
        'wtd': 0.0,
        'mtd': 0.0,
        'qtd': 0.0,
        'ytd': data.profit.grossProfit,
      };
    } catch (_) {
      return {'wtd': 0.0, 'mtd': 0.0, 'qtd': 0.0, 'ytd': 0.0};
    }
  }

  /// Compatibility wrapper for legacy KPI cards.
  Future<Map<String, dynamic>> getProjectStats(String workspaceId) async {
    try {
      final data = await getKpiDashboardData(
        workspaceId,
        range: const KpiRange.preset(KpiRangePreset.thirtyDays),
      );
      return {
        'total': data.jobs.createdOpportunities,
        'completed': data.jobs.completedJobs,
        'converted': data.jobs.convertedOpportunities,
        'opp': data.jobs.openOpportunities,
        'closingRate': data.jobs.closingRatePercent,
      };
    } catch (_) {
      return {
        'total': 0,
        'completed': 0,
        'converted': 0,
        'opp': 0,
        'closingRate': 0.0,
      };
    }
  }

  // Helper methods to convert Supabase format to Firestore format

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> _toProjectFirestoreFormat(dynamic row) {
    final normalized = _normalizeRow(row);
    return {
      'workspaceId': normalized['workspace_id'],
      'name': normalized['name'],
      'description': normalized['description'],
      'status': normalized['status'],
      'customerId': normalized['customer_id'],
      'customerName': normalized['customer_name'],
      'contractAmount': normalized['contract_amount'],
      'address': normalized['address'],
      'latitude': normalized['latitude'],
      'longitude': normalized['longitude'],
      'startDate': normalized['start_date'] != null
          ? _FakeTimestamp(DateTime.parse(normalized['start_date'] as String))
          : null,
      'endDate': normalized['end_date'] != null
          ? _FakeTimestamp(DateTime.parse(normalized['end_date'] as String))
          : null,
      'assignedToIds': normalized['assigned_to_ids'],
      'assignedToNames': normalized['assigned_to_names'],
      'tags': normalized['tags'],
      'createdAt': normalized['created_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['created_at'] as String),
            )
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': normalized['updated_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['updated_at'] as String),
            )
          : _FakeTimestamp(DateTime.now()),
    };
  }

  Map<String, dynamic> _toTimeEntryFirestoreFormat(dynamic row) {
    final normalized = _normalizeRow(row);
    return {
      'workspaceId': normalized['workspace_id'],
      'workerId': normalized['worker_id'],
      'projectId': normalized['project_id'],
      'taskId': normalized['task_id'],
      'date': normalized['date'] != null
          ? _FakeTimestamp(DateTime.parse(normalized['date'] as String))
          : _FakeTimestamp(DateTime.now()),
      'clockIn': normalized['clock_in'] != null
          ? _FakeTimestamp(DateTime.parse(normalized['clock_in'] as String))
          : _FakeTimestamp(DateTime.now()),
      'clockOut': normalized['clock_out'] != null
          ? _FakeTimestamp(DateTime.parse(normalized['clock_out'] as String))
          : null,
      'breakDuration': normalized['break_duration'] ?? 0,
      'totalDuration': normalized['total_duration'] ?? 0,
      'regularHours': (normalized['regular_hours'] as num?)?.toDouble() ?? 0.0,
      'overtimeHours':
          (normalized['overtime_hours'] as num?)?.toDouble() ?? 0.0,
      'doubleTimeHours':
          (normalized['double_time_hours'] as num?)?.toDouble() ?? 0.0,
      'hourlyRate': (normalized['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      'regularCost': (normalized['regular_cost'] as num?)?.toDouble() ?? 0.0,
      'overtimeCost':
          (normalized['overtime_cost'] as num?)?.toDouble() ?? 0.0,
      'doubleTimeCost':
          (normalized['double_time_cost'] as num?)?.toDouble() ?? 0.0,
      'totalCost': (normalized['total_cost'] as num?)?.toDouble() ?? 0.0,
      'notes': normalized['notes'],
      'status': normalized['status'],
      'submittedAt': normalized['submitted_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['submitted_at'] as String),
            )
          : null,
      'approvedBy': normalized['approved_by'],
      'approvedAt': normalized['approved_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['approved_at'] as String),
            )
          : null,
      'rejectionReason': normalized['rejection_reason'],
      'createdAt': normalized['created_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['created_at'] as String),
            )
          : _FakeTimestamp(DateTime.now()),
      'updatedAt': normalized['updated_at'] != null
          ? _FakeTimestamp(
              DateTime.parse(normalized['updated_at'] as String),
            )
          : _FakeTimestamp(DateTime.now()),
    };
  }

  /// Workspace WIP schedule rows from the `get_wip_report` RPC.
  /// Returned as raw maps; callers map them into typed rows.
  Future<List<Map<String, dynamic>>> getWipReport(String workspaceId) async {
    try {
      final rows = await _supabase.rpc(
        'get_wip_report',
        params: {'p_workspace_id': workspaceId},
      );
      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to load WIP report', error: e);
      rethrow;
    }
  }

  /// Open invoice/bill balances from the `get_cash_flow_entries` RPC.
  Future<List<Map<String, dynamic>>> getCashFlowEntries(
    String workspaceId,
  ) async {
    try {
      final rows = await _supabase.rpc(
        'get_cash_flow_entries',
        params: {'p_workspace_id': workspaceId},
      );
      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to load cash flow entries', error: e);
      rethrow;
    }
  }

  Map<String, dynamic> _normalizeRow(dynamic row) {
    if (row is Map<String, dynamic>) {
      if (!row.containsKey('total_price') && row.containsKey('total_amount')) {
        return <String, dynamic>{...row, 'total_price': row['total_amount']};
      }
      return row;
    }
    if (row is Map) {
      final normalized = row.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (!normalized.containsKey('total_price') &&
          normalized.containsKey('total_amount')) {
        normalized['total_price'] = normalized['total_amount'];
      }
      return normalized;
    }
    throw StateError(
      'Unexpected Supabase row type: ${row.runtimeType}',
    );
  }
}

class _FakeTimestamp {
  final DateTime _dateTime;
  _FakeTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
}
