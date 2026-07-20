import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum TimeEntryStatus {
  draft,
  submitted,
  approved,
  rejected;

  String get displayName {
    switch (this) {
      case TimeEntryStatus.draft:
        return 'Draft';
      case TimeEntryStatus.submitted:
        return 'Submitted';
      case TimeEntryStatus.approved:
        return 'Approved';
      case TimeEntryStatus.rejected:
        return 'Rejected';
    }
  }

  Color get color {
    switch (this) {
      case TimeEntryStatus.draft:
        return AppColors.textTertiary;
      case TimeEntryStatus.submitted:
        return AppColors.warning;
      case TimeEntryStatus.approved:
        return AppColors.success;
      case TimeEntryStatus.rejected:
        return AppColors.error;
    }
  }

  String toJson() => name;

  static TimeEntryStatus fromString(String value) {
    return TimeEntryStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TimeEntryStatus.draft,
    );
  }
}
