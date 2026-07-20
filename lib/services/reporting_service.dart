import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project.dart';
import '../models/time_entry.dart';
import '../models/task.dart';
import '../models/kpi_dashboard_data.dart';
import 'kpi_aggregation.dart';
import '../utils/app_logger.dart';
import '../utils/kpi_range_utils.dart';

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

/// One project row of the WIP (work-in-progress) schedule, as returned by
/// the `get_wip_report` RPC. Percent complete is cost-basis (0..1);
/// over/under billing is billed − earned (positive = overbilled/liability,
/// negative = underbilled/asset).
class WipReportRow {
  final String projectId;
  final String projectName;
  final String projectStatus;
  final String priceType;
  final double contractAmount;
  final double estimatedCost;
  final double estimatedRevenue;
  final double costToDate;
  final double committedCost;
  final double percentComplete;
  final double earnedRevenue;
  final double billedToDate;
  final double collectedToDate;
  final double overUnderBilling;

  WipReportRow({
    required this.projectId,
    required this.projectName,
    required this.projectStatus,
    required this.priceType,
    required this.contractAmount,
    required this.estimatedCost,
    required this.estimatedRevenue,
    required this.costToDate,
    required this.committedCost,
    required this.percentComplete,
    required this.earnedRevenue,
    required this.billedToDate,
    required this.collectedToDate,
    required this.overUnderBilling,
  });

  factory WipReportRow.fromRow(Map<String, dynamic> row) {
    double d(String key) => (row[key] as num?)?.toDouble() ?? 0.0;
    return WipReportRow(
      projectId: row['project_id'] as String,
      projectName: (row['project_name'] as String?) ?? '',
      projectStatus: (row['project_status'] as String?) ?? '',
      priceType: (row['price_type'] as String?) ?? 'fixed_price',
      contractAmount: d('contract_amount'),
      estimatedCost: d('estimated_cost'),
      estimatedRevenue: d('estimated_revenue'),
      costToDate: d('cost_to_date'),
      committedCost: d('committed_cost'),
      percentComplete: d('percent_complete'),
      earnedRevenue: d('earned_revenue'),
      billedToDate: d('billed_to_date'),
      collectedToDate: d('collected_to_date'),
      overUnderBilling: d('over_under_billing'),
    );
  }
}

/// One open document balance for the cash-flow projection, as returned by
/// the `get_cash_flow_entries` RPC. Inflows are unpaid customer invoices;
/// outflows are unpaid vendor bills.
class CashFlowEntry {
  final String documentId;
  final String? documentNumber;
  final String documentType;
  final String direction; // 'inflow' | 'outflow'
  final String? projectId;
  final String? projectName;
  final String? counterparty;
  final DateTime dueDate;
  final double balance;

  CashFlowEntry({
    required this.documentId,
    this.documentNumber,
    required this.documentType,
    required this.direction,
    this.projectId,
    this.projectName,
    this.counterparty,
    required this.dueDate,
    required this.balance,
  });

  bool get isInflow => direction == 'inflow';

  factory CashFlowEntry.fromRow(Map<String, dynamic> row) {
    return CashFlowEntry(
      documentId: row['document_id'] as String,
      documentNumber: row['document_number'] as String?,
      documentType: (row['document_type'] as String?) ?? '',
      direction: (row['direction'] as String?) ?? 'inflow',
      projectId: row['project_id'] as String?,
      projectName: row['project_name'] as String?,
      counterparty: row['counterparty'] as String?,
      dueDate: DateTime.parse(row['due_date'] as String).toLocal(),
      balance: (row['balance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ReportingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Financial Reports

  /// Get profit/loss by project
  Future<List<FinancialReport>> getProjectProfitLoss(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      AppLogger.info(
        'Fetching profit/loss report',
        metadata: {'workspaceId': workspaceId},
      );

      // Get all projects for workspace
      Query<Map<String, dynamic>> projectsQuery = _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId);
      if (startDate != null) {
        projectsQuery = projectsQuery.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );
      }
      if (endDate != null) {
        projectsQuery = projectsQuery.where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate),
        );
      }
      final projectsSnapshot = await projectsQuery.get();

      final reports = <FinancialReport>[];

      for (final projectDoc in projectsSnapshot.docs) {
        final project = Project.fromJson(projectDoc.data(), projectDoc.id);

        // Get total invoiced for this project
        Query<Map<String, dynamic>> invoicesQuery = _firestore
            .collection('invoices')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('projectId', isEqualTo: project.id)
            .where('status', whereIn: ['paid', 'sent']);
        if (startDate != null) {
          invoicesQuery = invoicesQuery.where(
            'paidDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          );
        }
        if (endDate != null) {
          invoicesQuery = invoicesQuery.where(
            'paidDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          );
        }
        final invoicesSnapshot = await invoicesQuery.get();

        double totalInvoiced = 0.0;
        for (final invoiceDoc in invoicesSnapshot.docs) {
          final invoiceData = invoiceDoc.data();
          totalInvoiced += (invoiceData['total'] as num?)?.toDouble() ?? 0.0;
        }

        // Get total cost for this project
        Query<Map<String, dynamic>> timeEntriesQuery = _firestore
            .collection('time_entries')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('projectId', isEqualTo: project.id)
            .where('status', isEqualTo: 'approved');
        if (startDate != null) {
          timeEntriesQuery = timeEntriesQuery.where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          );
        }
        if (endDate != null) {
          timeEntriesQuery = timeEntriesQuery.where(
            'date',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate),
          );
        }
        final timeEntriesSnapshot = await timeEntriesQuery.get();

        double totalLaborCost = 0.0;
        for (final timeEntryDoc in timeEntriesSnapshot.docs) {
          final timeEntry = TimeEntry.fromJson(
            timeEntryDoc.data(),
            timeEntryDoc.id,
          );
          totalLaborCost += timeEntry.totalCost;
        }

        final profit = totalInvoiced - totalLaborCost;

        reports.add(
          FinancialReport(
            projectId: project.id,
            projectName: project.name,
            totalInvoiced: totalInvoiced,
            totalLaborCost: totalLaborCost,
            profit: profit,
          ),
        );
      }

      AppLogger.info(
        'Profit/loss report generated',
        metadata: {'reportCount': reports.length},
      );
      return reports;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating profit/loss report',
        error: e,
        stackTrace: stackTrace,
      );
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

      AppLogger.info(
        'Fetching revenue trends',
        metadata: {
          'workspaceId': workspaceId,
          'startDate': start.toIso8601String(),
          'endDate': end.toIso8601String(),
        },
      );

      // Get all paid invoices in date range
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'paid')
          .where('paidDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('paidDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // Group by month
      final Map<String, double> monthlyRevenue = {};

      for (final invoiceDoc in invoicesSnapshot.docs) {
        final data = invoiceDoc.data();
        final paidDateRaw = data['paidDate'];
        final paidDate = paidDateRaw is Timestamp ? paidDateRaw.toDate() : null;
        if (paidDate != null) {
          final monthKey =
              '${paidDate.year}-${paidDate.month.toString().padLeft(2, '0')}';
          final total = (data['total'] as num?)?.toDouble() ?? 0.0;
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

      AppLogger.info(
        'Revenue trends generated',
        metadata: {'trendCount': trends.length},
      );
      return trends;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating revenue trends',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to generate revenue trends: $e');
    }
  }

  // Profit Trends
  Future<List<ProfitTrend>> getProfitTrends(
    String workspaceId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 365));
      final end = endDate ?? DateTime.now();

      AppLogger.info(
        'Fetching profit trends',
        metadata: {
          'workspaceId': workspaceId,
          'startDate': start.toIso8601String(),
          'endDate': end.toIso8601String(),
        },
      );

      // 1. Get Revenue (Invoices)
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'paid')
          .where('paidDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('paidDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // 2. Get Costs (Time Entries)
      final timeEntriesSnapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'approved')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // Group by month
      final Map<String, double> monthlyProfit = {};

      // Add Revenue
      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final paidDateRaw = data['paidDate'];
        final paidDate = paidDateRaw is Timestamp ? paidDateRaw.toDate() : null;
        if (paidDate != null) {
          final monthKey =
              '${paidDate.year}-${paidDate.month.toString().padLeft(2, '0')}';
          final total = (data['total'] as num?)?.toDouble() ?? 0.0;
          monthlyProfit[monthKey] =
              (monthlyProfit[monthKey] ?? 0.0) + total;
        }
      }

      // Subtract Costs
      for (final doc in timeEntriesSnapshot.docs) {
        final entry = TimeEntry.fromJson(doc.data(), doc.id);
        final monthKey =
            '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
        // Only subtract if we have revenue for this month or initialize it?
        // Profit can be negative, so we initialize if missing
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

      AppLogger.info(
        'Profit trends generated',
        metadata: {'trendCount': trends.length},
      );
      return trends;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating profit trends',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to generate profit trends: $e');
    }
  }

  // Closing Rate Trends
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
        final projectsSnapshot = await _firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthDate),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(nextMonthDate))
            .get();

        int totalOpportunities = 0;
        int wonOpportunities = 0;

        for (final doc in projectsSnapshot.docs) {
          final project = Project.fromJson(doc.data(), doc.id);
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
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating closing rate trends',
        error: e,
        stackTrace: stackTrace,
      );
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

      AppLogger.info(
        'Fetching hours by worker',
        metadata: {
          'workspaceId': workspaceId,
          'startDate': start.toIso8601String(),
          'endDate': end.toIso8601String(),
        },
      );

      // Get all approved time entries in date range
      final timeEntriesSnapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'approved')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // Group by user
      final Map<String, Map<String, dynamic>> userStats = {};

      for (final timeEntryDoc in timeEntriesSnapshot.docs) {
        final timeEntry = TimeEntry.fromJson(
          timeEntryDoc.data(),
          timeEntryDoc.id,
        );

        if (!userStats.containsKey(timeEntry.workerId)) {
          // Fetch user name
          final userDoc = await _firestore
              .collection('users')
              .doc(timeEntry.workerId)
              .get();
          final userName = userDoc.exists
              ? (userDoc.data()?['displayName'] as String? ??
                    userDoc.data()?['email'] as String?)
              : 'Unknown User';

          userStats[timeEntry.workerId] = {
            'userName': userName ?? 'Unknown',
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

      AppLogger.info(
        'Hours by worker report generated',
        metadata: {'reportCount': reports.length},
      );
      return reports;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating hours by worker report',
        error: e,
        stackTrace: stackTrace,
      );
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
      AppLogger.info(
        'Fetching project completion rates',
        metadata: {'workspaceId': workspaceId},
      );

      // Get all projects
      Query<Map<String, dynamic>> projectsQuery = _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId);
      if (startDate != null) {
        projectsQuery = projectsQuery.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );
      }
      if (endDate != null) {
        projectsQuery = projectsQuery.where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate),
        );
      }
      final projectsSnapshot = await projectsQuery.get();

      final reports = <ProjectCompletionReport>[];

      for (final projectDoc in projectsSnapshot.docs) {
        final project = Project.fromJson(projectDoc.data(), projectDoc.id);

        // Get all tasks for this project
        final tasksSnapshot = await _firestore
            .collection('tasks')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('projectId', isEqualTo: project.id)
            .get();

        final totalTasks = tasksSnapshot.docs.length;
        if (totalTasks == 0) {
          reports.add(
            ProjectCompletionReport(
              projectId: project.id,
              projectName: project.name,
              totalTasks: 0,
              completedTasks: 0,
              completionPercentage: 0.0,
            ),
          );
          continue;
        }

        int completedTasks = 0;
        for (final taskDoc in tasksSnapshot.docs) {
          final task = Task.fromJson(taskDoc.data(), taskDoc.id);
          if (task.isComplete) {
            completedTasks++;
          }
        }

        final completionPercentage = (completedTasks / totalTasks) * 100;

        reports.add(
          ProjectCompletionReport(
            projectId: project.id,
            projectName: project.name,
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            completionPercentage: completionPercentage,
          ),
        );
      }

      AppLogger.info(
        'Project completion report generated',
        metadata: {'reportCount': reports.length},
      );
      return reports;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating project completion report',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to generate project completion report: $e');
    }
  }

  // Summary/Dashboard Stats

  /// Get overall workspace statistics
  Future<Map<String, dynamic>> getWorkspaceStats(String workspaceId) async {
    try {
      AppLogger.info(
        'Fetching workspace stats',
        metadata: {'workspaceId': workspaceId},
      );

      // Get total projects
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .get();
      final totalProjects = projectsSnapshot.docs.length;

      // Get active projects
      final activeProjects = projectsSnapshot.docs
          .where(
            (doc) =>
                Project.fromJson(doc.data(), doc.id).status ==
                ProjectStatus.active,
          )
          .length;

      // Get total invoices this month
      final firstDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      final invoicesSnapshot = await _firestore
          .collection('invoices')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'paid')
          .where(
            'paidDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth),
          )
          .get();

      double monthlyRevenue = 0.0;
      for (final invoiceDoc in invoicesSnapshot.docs) {
        final data = invoiceDoc.data();
        monthlyRevenue += (data['total'] as num?)?.toDouble() ?? 0.0;
      }

      // Get total labor hours this month
      final timeEntriesSnapshot = await _firestore
          .collection('time_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'approved')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth),
          )
          .get();

      double monthlyLaborHours = 0.0;
      for (final timeEntryDoc in timeEntriesSnapshot.docs) {
        final timeEntry = TimeEntry.fromJson(
          timeEntryDoc.data(),
          timeEntryDoc.id,
        );
        // Calculate total hours from regular + overtime + double time
        monthlyLaborHours +=
            timeEntry.regularHours +
            timeEntry.overtimeHours +
            timeEntry.doubleTimeHours;
      }

      final stats = {
        'totalProjects': totalProjects,
        'activeProjects': activeProjects,
        'monthlyRevenue': monthlyRevenue,
        'monthlyLaborHours': monthlyLaborHours,
      };

      AppLogger.info('Workspace stats generated', metadata: stats);
      return stats;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error generating workspace stats',
        error: e,
        stackTrace: stackTrace,
      );
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

      final results = await Future.wait<dynamic>([
        _firestore
            .collection('invoices')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('status', isEqualTo: 'paid')
            .where(
              'paidDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('paidDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .get(),
        _firestore
            .collection('time_entries')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('status', isEqualTo: 'approved')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .get(),
        _firestore
            .collection('cost_items')
            .where('workspaceId', isEqualTo: workspaceId)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .get(),
        _firestore
            .collection('projects')
            .where('workspaceId', isEqualTo: workspaceId)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .get(),
        _firestore
            .collection('budget_items')
            .where('workspaceId', isEqualTo: workspaceId)
            .get(),
      ]);

      final invoicesSnapshot =
          results[0] as QuerySnapshot<Map<String, dynamic>>;
      final timeEntriesSnapshot =
          results[1] as QuerySnapshot<Map<String, dynamic>>;
      final costItemsSnapshot =
          results[2] as QuerySnapshot<Map<String, dynamic>>;
      final projectsSnapshot =
          results[3] as QuerySnapshot<Map<String, dynamic>>;
      final budgetItemsSnapshot =
          results[4] as QuerySnapshot<Map<String, dynamic>>;

      double totalProjectedCost = 0.0;
      for (final doc in budgetItemsSnapshot.docs) {
        final data = doc.data();
        if (data['parentId'] != null) continue;
        totalProjectedCost +=
            (data['projectedCost'] as num?)?.toDouble() ?? 0.0;
      }

      final revenueEntries = <KpiRevenueEntry>[];
      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final paidDateRaw = data['paidDate'];
        final paidDate = paidDateRaw is Timestamp ? paidDateRaw.toDate() : null;
        if (paidDate == null) continue;
        final total = (data['total'] as num?)?.toDouble() ?? 0.0;
        revenueEntries.add(
          KpiRevenueEntry(
            date: paidDate,
            amount: total,
            projectId: data['projectId'] as String? ?? '',
          ),
        );
      }

      final laborEntries = <KpiCostEntry>[];
      for (final doc in timeEntriesSnapshot.docs) {
        final entry = TimeEntry.fromJson(doc.data(), doc.id);
        laborEntries.add(
          KpiCostEntry(date: entry.date, amount: entry.totalCost),
        );
      }

      final costEntries = <KpiCostEntry>[];
      for (final doc in costItemsSnapshot.docs) {
        final data = doc.data();
        final date = _toDate(data['date']);
        if (date == null) continue;
        final cost =
            (data['totalCost'] as num?)?.toDouble() ??
            ((data['quantity'] as num?)?.toDouble() ?? 0.0) *
                ((data['unitPrice'] as num?)?.toDouble() ?? 0.0);
        costEntries.add(KpiCostEntry(date: date, amount: cost));
      }

      final projectEntries = <KpiProjectEntry>[];
      for (final doc in projectsSnapshot.docs) {
        final project = Project.fromJson(doc.data(), doc.id);
        projectEntries.add(
          KpiProjectEntry(
            status: project.status.displayName,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
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
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error loading KPI dashboard data',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

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

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
