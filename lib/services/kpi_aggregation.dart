import '../models/kpi_dashboard_data.dart';
import '../utils/kpi_range_utils.dart';

class KpiRevenueEntry {
  final DateTime date;
  final double amount;
  final String? projectId;

  const KpiRevenueEntry({
    required this.date,
    required this.amount,
    this.projectId,
  });
}

class KpiCostEntry {
  final DateTime date;
  final double amount;

  const KpiCostEntry({required this.date, required this.amount});
}

class KpiProjectEntry {
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KpiProjectEntry({
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
}

class KpiAggregationInput {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final KpiBucketGranularity granularity;
  final List<KpiRevenueEntry> revenueEntries;
  final List<KpiCostEntry> laborEntries;
  final List<KpiCostEntry> costEntries;
  final List<KpiProjectEntry> projectEntries;
  final double projectedCostTotal;

  const KpiAggregationInput({
    required this.rangeStart,
    required this.rangeEnd,
    required this.granularity,
    required this.revenueEntries,
    required this.laborEntries,
    required this.costEntries,
    required this.projectEntries,
    required this.projectedCostTotal,
  });
}

class KpiAggregation {
  static KpiDashboardData aggregate(KpiAggregationInput input) {
    final buckets = generateBucketStarts(
      input.rangeStart,
      input.rangeEnd,
      input.granularity,
    );

    final revenueByBucket = <DateTime, double>{
      for (final bucket in buckets) bucket: 0.0,
    };
    final laborByBucket = <DateTime, double>{
      for (final bucket in buckets) bucket: 0.0,
    };
    final costsByBucket = <DateTime, double>{
      for (final bucket in buckets) bucket: 0.0,
    };

    double totalRevenue = 0.0;
    for (final entry in input.revenueEntries) {
      final bucket = normalizeBucketDate(entry.date, input.granularity);
      if (!revenueByBucket.containsKey(bucket)) continue;
      revenueByBucket[bucket] = (revenueByBucket[bucket] ?? 0.0) + entry.amount;
      totalRevenue += entry.amount;
    }

    double totalLaborCost = 0.0;
    for (final entry in input.laborEntries) {
      final bucket = normalizeBucketDate(entry.date, input.granularity);
      if (!laborByBucket.containsKey(bucket)) continue;
      laborByBucket[bucket] = (laborByBucket[bucket] ?? 0.0) + entry.amount;
      totalLaborCost += entry.amount;
    }

    double totalCostItems = 0.0;
    for (final entry in input.costEntries) {
      final bucket = normalizeBucketDate(entry.date, input.granularity);
      if (!costsByBucket.containsKey(bucket)) continue;
      costsByBucket[bucket] = (costsByBucket[bucket] ?? 0.0) + entry.amount;
      totalCostItems += entry.amount;
    }

    final grossProfit = totalRevenue - totalLaborCost - totalCostItems;
    final forecastProfit = totalRevenue - input.projectedCostTotal;
    final grossMarginPercent = totalRevenue > 0
        ? (grossProfit / totalRevenue) * 100
        : 0.0;
    final forecastMarginPercent = totalRevenue > 0
        ? (forecastProfit / totalRevenue) * 100
        : 0.0;

    final revenueTrend = <KpiBucket>[];
    final grossTrend = <KpiBucket>[];
    final forecastTrend = <KpiBucket>[];
    final bucketCount = buckets.isEmpty ? 1 : buckets.length;
    final projectedCostPerBucket = input.projectedCostTotal / bucketCount;

    for (final bucket in buckets) {
      final revenueValue = revenueByBucket[bucket] ?? 0.0;
      final laborValue = laborByBucket[bucket] ?? 0.0;
      final costValue = costsByBucket[bucket] ?? 0.0;

      revenueTrend.add(KpiBucket(periodStart: bucket, value: revenueValue));
      grossTrend.add(
        KpiBucket(
          periodStart: bucket,
          value: revenueValue - laborValue - costValue,
        ),
      );
      forecastTrend.add(
        KpiBucket(
          periodStart: bucket,
          value: revenueValue - projectedCostPerBucket,
        ),
      );
    }

    final createdCount = input.projectEntries.length;
    const convertedStatuses = {'active', 'awarded', 'on_hold', 'complete'};
    const pipelineStatuses = {'lead', 'bidding', 'proposal_sent'};
    final convertedCount = input.projectEntries
        .where((entry) => convertedStatuses.contains(entry.status))
        .length;
    final openCount = input.projectEntries
        .where((entry) => pipelineStatuses.contains(entry.status))
        .length;

    final completedJobs = input.projectEntries
        .where(
          (entry) =>
              entry.status == 'complete' &&
              !entry.updatedAt.isBefore(input.rangeStart) &&
              !entry.updatedAt.isAfter(input.rangeEnd),
        )
        .length;

    final closingRate = createdCount > 0
        ? (convertedCount / createdCount) * 100
        : 0.0;

    final closingRateTrend = <KpiBucket>[];
    for (final bucket in buckets) {
      final createdForBucket = input.projectEntries
          .where(
            (entry) =>
                normalizeBucketDate(entry.createdAt, input.granularity) ==
                bucket,
          )
          .toList();
      final convertedForBucket = createdForBucket
          .where((entry) => convertedStatuses.contains(entry.status))
          .length;
      final rate = createdForBucket.isEmpty
          ? 0.0
          : (convertedForBucket / createdForBucket.length) * 100;
      closingRateTrend.add(KpiBucket(periodStart: bucket, value: rate));
    }

    return KpiDashboardData(
      rangeStart: input.rangeStart,
      rangeEnd: input.rangeEnd,
      revenue: RevenueKpi(totalRevenue: totalRevenue, trend: revenueTrend),
      profit: ProfitKpi(
        grossProfit: grossProfit,
        forecastProfit: forecastProfit,
        grossMarginPercent: grossMarginPercent,
        forecastMarginPercent: forecastMarginPercent,
        grossTrend: grossTrend,
        forecastTrend: forecastTrend,
      ),
      jobs: JobsKpi(
        createdOpportunities: createdCount,
        convertedOpportunities: convertedCount,
        openOpportunities: openCount,
        completedJobs: completedJobs,
        closingRatePercent: closingRate,
        closingRateTrend: closingRateTrend,
      ),
    );
  }
}
