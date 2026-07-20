import 'package:flutter/foundation.dart';
import '../services/reporting_service.dart';
import '../services/service_locator.dart';
import '../utils/app_logger.dart';
import '../utils/kpi_range_utils.dart';

enum ReportType {
  projectProfitLoss,
  revenueTrends,
  hoursByWorker,
  projectCompletion,
  wipSchedule,
  cashFlow,
}

class ReportingProvider extends ChangeNotifier {
  final dynamic _reportingService = ServiceLocator.reportingService;

  // State
  bool _isLoading = false;
  String? _error;
  ReportType _selectedReportType = ReportType.projectProfitLoss;

  // Report data
  List<FinancialReport> _profitLossReports = [];
  List<RevenueTrend> _revenueTrends = [];
  List<LaborReport> _laborReports = [];
  List<ProjectCompletionReport> _completionReports = [];
  List<WipReportRow> _wipReport = [];
  List<CashFlowEntry> _cashFlowEntries = [];
  Map<String, dynamic>? _workspaceStats;

  // Date range for filtering
  DateTime? _startDate;
  DateTime? _endDate;
  KpiRange _selectedRange = const KpiRange.preset(KpiRangePreset.thirtyDays);

  ReportingProvider() {
    final resolved = resolveKpiRange(_selectedRange);
    _startDate = resolved.start;
    _endDate = resolved.end;
  }

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  ReportType get selectedReportType => _selectedReportType;

  List<FinancialReport> get profitLossReports => _profitLossReports;
  List<RevenueTrend> get revenueTrends => _revenueTrends;
  List<LaborReport> get laborReports => _laborReports;
  List<ProjectCompletionReport> get completionReports => _completionReports;
  List<WipReportRow> get wipReport => _wipReport;
  List<CashFlowEntry> get cashFlowEntries => _cashFlowEntries;
  Map<String, dynamic>? get workspaceStats => _workspaceStats;

  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  KpiRange get selectedRange => _selectedRange;

  // Actions

  void selectReportType(ReportType type) {
    if (_selectedReportType != type) {
      _selectedReportType = type;
      notifyListeners();
    }
  }

  void setRange(KpiRange range) {
    _selectedRange = range;
    final resolved = resolveKpiRange(range);
    _startDate = resolved.start;
    _endDate = resolved.end;
    notifyListeners();
  }

  Future<void> loadWorkspaceStats(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading workspace stats');
      _workspaceStats = await _reportingService.getWorkspaceStats(workspaceId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading workspace stats', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadProfitLossReport(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading profit/loss report');
      final reports = await _reportingService.getProjectProfitLoss(
        workspaceId,
        startDate: _startDate,
        endDate: _endDate,
      );
      _profitLossReports = (reports as List)
          .map(
            (report) => FinancialReport(
              projectId: report.projectId as String,
              projectName: report.projectName as String,
              totalInvoiced: (report.totalInvoiced as num).toDouble(),
              totalLaborCost: (report.totalLaborCost as num).toDouble(),
              profit: (report.profit as num).toDouble(),
            ),
          )
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading profit/loss report', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRevenueTrends(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading revenue trends');
      final trends = await _reportingService.getRevenueTrends(
        workspaceId,
        startDate: _startDate,
        endDate: _endDate,
      );
      _revenueTrends = (trends as List)
          .map(
            (trend) => RevenueTrend(
              month: trend.month as DateTime,
              totalRevenue: (trend.totalRevenue as num).toDouble(),
            ),
          )
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading revenue trends', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadLaborReport(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading labor report');
      final reports = await _reportingService.getHoursByWorker(
        workspaceId,
        startDate: _startDate,
        endDate: _endDate,
      );
      _laborReports = (reports as List)
          .map(
            (report) => LaborReport(
              userId: report.userId as String,
              userName: report.userName as String,
              totalHours: (report.totalHours as num).toDouble(),
              totalCost: (report.totalCost as num).toDouble(),
            ),
          )
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading labor report', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCompletionReport(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading completion report');
      final reports = await _reportingService.getProjectCompletionRates(
        workspaceId,
        startDate: _startDate,
        endDate: _endDate,
      );
      _completionReports = (reports as List)
          .map(
            (report) => ProjectCompletionReport(
              projectId: report.projectId as String,
              projectName: report.projectName as String,
              totalTasks: report.totalTasks as int,
              completedTasks: report.completedTasks as int,
              completionPercentage:
                  (report.completionPercentage as num).toDouble(),
            ),
          )
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading completion report', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCurrentReport(String workspaceId) async {
    switch (_selectedReportType) {
      case ReportType.projectProfitLoss:
        await loadProfitLossReport(workspaceId);
        break;
      case ReportType.revenueTrends:
        await loadRevenueTrends(workspaceId);
        break;
      case ReportType.hoursByWorker:
        await loadLaborReport(workspaceId);
        break;
      case ReportType.projectCompletion:
        await loadCompletionReport(workspaceId);
        break;
      case ReportType.wipSchedule:
        await loadWipReport(workspaceId);
        break;
      case ReportType.cashFlow:
        await loadCashFlowEntries(workspaceId);
        break;
    }
  }

  Future<void> loadWipReport(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading WIP report');
      final rows = await _reportingService.getWipReport(workspaceId);
      _wipReport = (rows as List)
          .map((row) => WipReportRow.fromRow(Map<String, dynamic>.from(row)))
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading WIP report', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCashFlowEntries(String workspaceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      AppLogger.info('Loading cash flow entries');
      final rows = await _reportingService.getCashFlowEntries(workspaceId);
      _cashFlowEntries = (rows as List)
          .map((row) => CashFlowEntry.fromRow(Map<String, dynamic>.from(row)))
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Error loading cash flow entries', error: e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAllReports(String workspaceId) async {
    await loadWorkspaceStats(workspaceId);
    await loadProfitLossReport(workspaceId);
    await loadRevenueTrends(workspaceId);
    await loadLaborReport(workspaceId);
    await loadCompletionReport(workspaceId);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
