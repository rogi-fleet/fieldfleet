import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'project.dart';

/// Centralized color and icon mapping for [ProjectStatus].
///
/// Every widget that needs to render a status color/icon should use this
/// instead of maintaining its own switch statement.
class ProjectStatusTheme {
  ProjectStatusTheme._();

  /// Primary color for the status (used for dots, text, icons).
  static Color color(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.lead:
        return AppColors.textTertiary;
      case ProjectStatus.bidding:
        return AppColors.secondary;
      case ProjectStatus.proposalSent:
        return AppColors.warning;
      case ProjectStatus.awarded:
        return AppColors.messageAccent;
      case ProjectStatus.active:
        return AppColors.success;
      case ProjectStatus.onHold:
        return AppColors.warningDark;
      case ProjectStatus.complete:
        return AppColors.financialAccent;
      case ProjectStatus.lost:
        return AppColors.textSecondary;
      case ProjectStatus.canceled:
        return AppColors.error;
    }
  }

  /// Darker shade for filled badges.
  static Color colorDark(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.lead:
        return AppColors.textSecondary;
      case ProjectStatus.bidding:
        return AppColors.secondaryDark;
      case ProjectStatus.proposalSent:
        return AppColors.warningDark;
      case ProjectStatus.awarded:
        return AppColors.messageAccentDark;
      case ProjectStatus.active:
        return AppColors.successDark;
      case ProjectStatus.onHold:
        return const Color(0xFF92400E);
      case ProjectStatus.complete:
        return const Color(0xFF0E7490);
      case ProjectStatus.lost:
        return AppColors.textSecondary;
      case ProjectStatus.canceled:
        return AppColors.errorDark;
    }
  }

  /// Light background tint for badge backgrounds.
  static Color colorLight(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.lead:
        return AppColors.textTertiary.withValues(alpha: 0.12);
      case ProjectStatus.bidding:
        return AppColors.secondarySurface;
      case ProjectStatus.proposalSent:
        return AppColors.warningLight;
      case ProjectStatus.awarded:
        return AppColors.messageAccentLight;
      case ProjectStatus.active:
        return AppColors.successLight;
      case ProjectStatus.onHold:
        return AppColors.warningLight;
      case ProjectStatus.complete:
        return AppColors.financialAccentLight;
      case ProjectStatus.lost:
        return AppColors.textTertiary.withValues(alpha: 0.12);
      case ProjectStatus.canceled:
        return AppColors.errorLight;
    }
  }

  /// Icon for the status.
  static IconData icon(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.lead:
        return Icons.lightbulb_outline;
      case ProjectStatus.bidding:
        return Icons.edit_note;
      case ProjectStatus.proposalSent:
        return Icons.send;
      case ProjectStatus.awarded:
        return Icons.emoji_events_outlined;
      case ProjectStatus.active:
        return Icons.play_circle_outline;
      case ProjectStatus.onHold:
        return Icons.pause_circle_outline;
      case ProjectStatus.complete:
        return Icons.check_circle_outline;
      case ProjectStatus.lost:
        return Icons.block;
      case ProjectStatus.canceled:
        return Icons.cancel_outlined;
    }
  }
}
