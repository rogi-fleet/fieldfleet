import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum CustomerStatus {
  lead,
  active,
  dormant,
  lost,
  internal;

  String get displayName {
    switch (this) {
      case CustomerStatus.lead:
        return 'Lead';
      case CustomerStatus.active:
        return 'Active';
      case CustomerStatus.dormant:
        return 'Dormant';
      case CustomerStatus.lost:
        return 'Lost';
      case CustomerStatus.internal:
        return 'Internal';
    }
  }

  String get description {
    switch (this) {
      case CustomerStatus.lead:
        return 'Potential customer, not yet quoted';
      case CustomerStatus.active:
        return 'Active customer with recent projects';
      case CustomerStatus.dormant:
        return 'No activity in 90+ days';
      case CustomerStatus.lost:
        return 'Lost to competitor or declined services';
      case CustomerStatus.internal:
        return 'Internal or testing customer';
    }
  }

  Color get color {
    switch (this) {
      case CustomerStatus.lead:
        return AppColors.info;
      case CustomerStatus.active:
        return AppColors.success;
      case CustomerStatus.dormant:
        return AppColors.warning;
      case CustomerStatus.lost:
        return AppColors.error;
      case CustomerStatus.internal:
        return AppColors.textTertiary;
    }
  }

  IconData get icon {
    switch (this) {
      case CustomerStatus.lead:
        return Icons.person_add;
      case CustomerStatus.active:
        return Icons.check_circle;
      case CustomerStatus.dormant:
        return Icons.schedule;
      case CustomerStatus.lost:
        return Icons.cancel;
      case CustomerStatus.internal:
        return Icons.settings;
    }
  }

  static CustomerStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'lead':
        return CustomerStatus.lead;
      case 'active':
        return CustomerStatus.active;
      case 'dormant':
        return CustomerStatus.dormant;
      case 'lost':
        return CustomerStatus.lost;
      case 'internal':
        return CustomerStatus.internal;
      default:
        return CustomerStatus.active; // Default to active for unknown statuses
    }
  }
}
