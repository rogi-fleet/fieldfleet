import 'package:flutter/material.dart';

import 'app_colors.dart';

enum AppSeverity { neutral, info, success, warning, error }

class AppSeverityColors {
  final Color accent;
  final Color background;
  final Color border;
  final Color label;
  final Color value;

  const AppSeverityColors({
    required this.accent,
    required this.background,
    required this.border,
    required this.label,
    required this.value,
  });
}

abstract final class AppSeverityTheme {
  static AppSeverityColors colors(
    AppSeverity severity, {
    Color neutralBackground = AppColors.surfaceAlt,
    Color neutralBorder = AppColors.cardBorder,
  }) {
    switch (severity) {
      case AppSeverity.neutral:
        return AppSeverityColors(
          accent: AppColors.textSecondary,
          background: neutralBackground,
          border: neutralBorder,
          label: AppColors.textTertiary,
          value: AppColors.textPrimary,
        );
      case AppSeverity.info:
        return AppSeverityColors(
          accent: AppColors.info,
          background: AppColors.infoLight,
          border: AppColors.info.withValues(alpha: 0.3),
          label: AppColors.infoDark,
          value: AppColors.infoDark,
        );
      case AppSeverity.success:
        return AppSeverityColors(
          accent: AppColors.success,
          background: AppColors.successLight,
          border: AppColors.success.withValues(alpha: 0.3),
          label: AppColors.successDark,
          value: AppColors.successDark,
        );
      case AppSeverity.warning:
        return AppSeverityColors(
          accent: AppColors.warning,
          background: AppColors.warningLight,
          border: AppColors.warning.withValues(alpha: 0.4),
          label: AppColors.warningDark,
          value: AppColors.warningDark,
        );
      case AppSeverity.error:
        return AppSeverityColors(
          accent: AppColors.error,
          background: AppColors.errorLight,
          border: AppColors.error.withValues(alpha: 0.35),
          label: AppColors.errorDark,
          value: AppColors.errorDark,
        );
    }
  }
}
