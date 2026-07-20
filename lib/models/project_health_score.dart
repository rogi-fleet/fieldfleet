import 'package:flutter/material.dart';
import '../theme/theme.dart';

class ProjectHealthScore {
  final int overallScore; // 0-100
  final int scheduleScore; // 0-100
  final int budgetScore; // 0-100
  final int taskVelocityScore; // 0-100
  final int overdueTasksScore; // 0-100

  const ProjectHealthScore({
    required this.overallScore,
    required this.scheduleScore,
    required this.budgetScore,
    required this.taskVelocityScore,
    required this.overdueTasksScore,
  });

  String get label {
    if (overallScore >= 70) return 'Healthy';
    if (overallScore >= 40) return 'At Risk';
    return 'Critical';
  }

  Color get color {
    if (overallScore >= 70) return AppColors.success;
    if (overallScore >= 40) return AppColors.secondary;
    return AppColors.error;
  }

  static const empty = ProjectHealthScore(
    overallScore: 0,
    scheduleScore: 0,
    budgetScore: 0,
    taskVelocityScore: 0,
    overdueTasksScore: 0,
  );
}
