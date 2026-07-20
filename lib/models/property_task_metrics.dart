import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'task.dart';

/// Aggregated task metrics for a single property.
class PropertyTaskMetrics {
  final String propertyId;
  final int totalCount;
  final int completedCount;
  final int overdueCount;
  final int stuckCount;

  const PropertyTaskMetrics({
    required this.propertyId,
    required this.totalCount,
    required this.completedCount,
    required this.overdueCount,
    required this.stuckCount,
  });

  double get progressPercent =>
      totalCount == 0 ? 0 : completedCount / totalCount * 100;

  bool get isFullyComplete => totalCount > 0 && completedCount == totalCount;

  bool get hasOverdue => overdueCount > 0;

  /// Canonical color for progress display: green when done, orange when
  /// overdue, blue otherwise.
  Color get taskColor => isFullyComplete
      ? AppColors.success
      : hasOverdue
          ? AppColors.warning
          : AppColors.info;

  factory PropertyTaskMetrics.fromTasks(
      String propertyId, List<Task> tasks) {
    int completedCount = 0;
    int overdueCount = 0;
    int stuckCount = 0;
    for (final t in tasks) {
      if (t.isComplete) {
        completedCount++;
      } else {
        if (t.isOverdue()) overdueCount++;
        if (t.status == 'stuck') stuckCount++;
      }
    }
    return PropertyTaskMetrics(
      propertyId: propertyId,
      totalCount: tasks.length,
      completedCount: completedCount,
      overdueCount: overdueCount,
      stuckCount: stuckCount,
    );
  }
}
