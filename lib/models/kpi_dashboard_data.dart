class KpiBucket {
  final DateTime periodStart;
  final double value;

  const KpiBucket({required this.periodStart, required this.value});
}

class RevenueKpi {
  final double totalRevenue;
  final List<KpiBucket> trend;

  const RevenueKpi({required this.totalRevenue, required this.trend});
}

class ProfitKpi {
  final double grossProfit;
  final double forecastProfit;
  final double grossMarginPercent;
  final double forecastMarginPercent;
  final List<KpiBucket> grossTrend;
  final List<KpiBucket> forecastTrend;

  const ProfitKpi({
    required this.grossProfit,
    required this.forecastProfit,
    required this.grossMarginPercent,
    required this.forecastMarginPercent,
    required this.grossTrend,
    required this.forecastTrend,
  });
}

class JobsKpi {
  final int createdOpportunities;
  final int convertedOpportunities;
  final int openOpportunities;
  final int completedJobs;
  final double closingRatePercent;
  final List<KpiBucket> closingRateTrend;

  const JobsKpi({
    required this.createdOpportunities,
    required this.convertedOpportunities,
    required this.openOpportunities,
    required this.completedJobs,
    required this.closingRatePercent,
    required this.closingRateTrend,
  });
}

class KpiDashboardData {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final RevenueKpi revenue;
  final ProfitKpi profit;
  final JobsKpi jobs;

  const KpiDashboardData({
    required this.rangeStart,
    required this.rangeEnd,
    required this.revenue,
    required this.profit,
    required this.jobs,
  });
}

class KpiWorkspaceStats {
  final int totalProjects;
  final int activeProjects;
  final double monthlyRevenue;
  final double monthlyLaborHours;

  const KpiWorkspaceStats({
    required this.totalProjects,
    required this.activeProjects,
    required this.monthlyRevenue,
    required this.monthlyLaborHours,
  });

  Map<String, dynamic> toJson() => {
    'totalProjects': totalProjects,
    'activeProjects': activeProjects,
    'monthlyRevenue': monthlyRevenue,
    'monthlyLaborHours': monthlyLaborHours,
  };
}
