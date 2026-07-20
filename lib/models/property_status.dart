import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Status of a property in a restoration project.
enum PropertyStatus {
  pending,
  mitigation,
  monitoring,
  completed,
  archived;

  String get displayName {
    switch (this) {
      case PropertyStatus.pending:
        return 'Pending';
      case PropertyStatus.mitigation:
        return 'Mitigation';
      case PropertyStatus.monitoring:
        return 'Monitoring';
      case PropertyStatus.completed:
        return 'Completed';
      case PropertyStatus.archived:
        return 'Archived';
    }
  }

  Color get color {
    switch (this) {
      case PropertyStatus.pending:
        return AppColors.textTertiary;
      case PropertyStatus.mitigation:
        return AppColors.warning;
      case PropertyStatus.monitoring:
        return AppColors.info;
      case PropertyStatus.completed:
        return AppColors.success;
      case PropertyStatus.archived:
        return AppColors.textSecondary;
    }
  }

  IconData get icon {
    switch (this) {
      case PropertyStatus.pending:
        return Icons.hourglass_empty;
      case PropertyStatus.mitigation:
        return Icons.construction;
      case PropertyStatus.monitoring:
        return Icons.monitor_heart;
      case PropertyStatus.completed:
        return Icons.check_circle;
      case PropertyStatus.archived:
        return Icons.archive;
    }
  }

  /// Convert to database value
  /// DB enum: 'pending', 'inspected', 'drying', 'complete'
  String toDbValue() {
    switch (this) {
      case PropertyStatus.pending:
        return 'pending';
      case PropertyStatus.mitigation:
        return 'inspected';
      case PropertyStatus.monitoring:
        return 'drying';
      case PropertyStatus.completed:
      case PropertyStatus.archived:
        return 'complete';
    }
  }

  static PropertyStatus fromString(String value) {
    switch (value.toLowerCase()) {
      // Dart enum values
      case 'pending':
        return PropertyStatus.pending;
      case 'mitigation':
        return PropertyStatus.mitigation;
      case 'monitoring':
        return PropertyStatus.monitoring;
      case 'completed':
        return PropertyStatus.completed;
      case 'archived':
        return PropertyStatus.archived;
      // DB enum values
      case 'inspected':
        return PropertyStatus.mitigation;
      case 'drying':
        return PropertyStatus.monitoring;
      case 'complete':
        return PropertyStatus.completed;
      default:
        return PropertyStatus.pending;
    }
  }
}
