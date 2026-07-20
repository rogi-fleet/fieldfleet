import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum PlanDiscipline {
  architectural,
  structural,
  electrical,
  plumbing,
  hvac,
  siteCivil,
  other;

  String get displayName {
    switch (this) {
      case PlanDiscipline.architectural:
        return 'Architectural';
      case PlanDiscipline.structural:
        return 'Structural';
      case PlanDiscipline.electrical:
        return 'Electrical';
      case PlanDiscipline.plumbing:
        return 'Plumbing';
      case PlanDiscipline.hvac:
        return 'HVAC';
      case PlanDiscipline.siteCivil:
        return 'Site/Civil';
      case PlanDiscipline.other:
        return 'Other';
    }
  }

  String get description {
    switch (this) {
      case PlanDiscipline.architectural:
        return 'Floor plans, elevations, sections, details';
      case PlanDiscipline.structural:
        return 'Foundation plans, framing plans, structural details';
      case PlanDiscipline.electrical:
        return 'Electrical plans, lighting, power distribution';
      case PlanDiscipline.plumbing:
        return 'Plumbing plans, drainage, water supply';
      case PlanDiscipline.hvac:
        return 'Mechanical plans, ductwork, HVAC systems';
      case PlanDiscipline.siteCivil:
        return 'Site plans, grading, utilities, landscaping';
      case PlanDiscipline.other:
        return 'Specifications, details, other documents';
    }
  }

  Color get color {
    switch (this) {
      case PlanDiscipline.architectural:
        return AppColors.info;
      case PlanDiscipline.structural:
        return AppColors.textTertiary;
      case PlanDiscipline.electrical:
        return AppColors.warning;
      case PlanDiscipline.plumbing:
        return AppColors.financialAccent;
      case PlanDiscipline.hvac:
        return AppColors.secondary;
      case PlanDiscipline.siteCivil:
        return AppColors.success;
      case PlanDiscipline.other:
        return AppColors.messageAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case PlanDiscipline.architectural:
        return Icons.architecture;
      case PlanDiscipline.structural:
        return Icons.foundation;
      case PlanDiscipline.electrical:
        return Icons.electrical_services;
      case PlanDiscipline.plumbing:
        return Icons.plumbing;
      case PlanDiscipline.hvac:
        return Icons.hvac;
      case PlanDiscipline.siteCivil:
        return Icons.landscape;
      case PlanDiscipline.other:
        return Icons.description;
    }
  }

  /// Convert to database value (snake_case)
  String toDbValue() {
    switch (this) {
      case PlanDiscipline.siteCivil:
        return 'site_civil';
      default:
        return name;
    }
  }

  static PlanDiscipline fromString(String value) {
    switch (value.toLowerCase()) {
      case 'architectural':
        return PlanDiscipline.architectural;
      case 'structural':
        return PlanDiscipline.structural;
      case 'electrical':
        return PlanDiscipline.electrical;
      case 'plumbing':
        return PlanDiscipline.plumbing;
      case 'hvac':
        return PlanDiscipline.hvac;
      case 'sitecivil':
      case 'site_civil':
        return PlanDiscipline.siteCivil;
      case 'other':
        return PlanDiscipline.other;
      default:
        return PlanDiscipline.other;
    }
  }

  @override
  String toString() {
    return name;
  }
}
