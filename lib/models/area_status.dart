import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Status of an area within a property.
enum AreaStatus {
  notAffected,
  affected,
  drying,
  dry,
  restored;

  String get displayName {
    switch (this) {
      case AreaStatus.notAffected:
        return 'Not Affected';
      case AreaStatus.affected:
        return 'Affected';
      case AreaStatus.drying:
        return 'Drying';
      case AreaStatus.dry:
        return 'Dry';
      case AreaStatus.restored:
        return 'Restored';
    }
  }

  Color get color {
    switch (this) {
      case AreaStatus.notAffected:
        return AppColors.textTertiary;
      case AreaStatus.affected:
        return AppColors.error;
      case AreaStatus.drying:
        return AppColors.warning;
      case AreaStatus.dry:
        return AppColors.success;
      case AreaStatus.restored:
        return AppColors.financialAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case AreaStatus.notAffected:
        return Icons.check_circle_outline;
      case AreaStatus.affected:
        return Icons.water_drop;
      case AreaStatus.drying:
        return Icons.air;
      case AreaStatus.dry:
        return Icons.wb_sunny;
      case AreaStatus.restored:
        return Icons.done_all;
    }
  }

  /// Convert to database value (snake_case)
  String toDbValue() {
    switch (this) {
      case AreaStatus.notAffected:
        return 'not_affected';
      case AreaStatus.affected:
        return 'affected';
      case AreaStatus.drying:
        return 'drying';
      case AreaStatus.dry:
        return 'dry';
      case AreaStatus.restored:
        return 'restored';
    }
  }

  static AreaStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'notaffected':
      case 'not_affected':
        return AreaStatus.notAffected;
      case 'affected':
        return AreaStatus.affected;
      case 'drying':
        return AreaStatus.drying;
      case 'dry':
        return AreaStatus.dry;
      case 'restored':
        return AreaStatus.restored;
      default:
        return AreaStatus.notAffected;
    }
  }
}
