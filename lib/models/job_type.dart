import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum JobType {
  smallRepairs,
  majorRepairs,
  newConstruction,
  renovation,
  maintenance,
  emergency;

  String get displayName {
    switch (this) {
      case JobType.smallRepairs:
        return 'Small Repairs';
      case JobType.majorRepairs:
        return 'Major Repairs';
      case JobType.newConstruction:
        return 'New Construction';
      case JobType.renovation:
        return 'Renovation';
      case JobType.maintenance:
        return 'Maintenance';
      case JobType.emergency:
        return 'Emergency';
    }
  }

  Color get color {
    switch (this) {
      case JobType.smallRepairs:
        return AppColors.info;
      case JobType.majorRepairs:
        return AppColors.warning;
      case JobType.newConstruction:
        return AppColors.success;
      case JobType.renovation:
        return AppColors.messageAccent;
      case JobType.maintenance:
        return AppColors.financialAccent;
      case JobType.emergency:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case JobType.smallRepairs:
        return Icons.build;
      case JobType.majorRepairs:
        return Icons.construction;
      case JobType.newConstruction:
        return Icons.apartment;
      case JobType.renovation:
        return Icons.home_repair_service;
      case JobType.maintenance:
        return Icons.settings;
      case JobType.emergency:
        return Icons.warning;
    }
  }

  static JobType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'smallrepairs':
      case 'small_repairs':
        return JobType.smallRepairs;
      case 'majorrepairs':
      case 'major_repairs':
        return JobType.majorRepairs;
      case 'newconstruction':
      case 'new_construction':
        return JobType.newConstruction;
      case 'renovation':
        return JobType.renovation;
      case 'maintenance':
        return JobType.maintenance;
      case 'emergency':
        return JobType.emergency;
      default:
        throw ArgumentError('Invalid job type: $value');
    }
  }

  String toJson() {
    return name;
  }
}
