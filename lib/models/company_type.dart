import 'package:flutter/material.dart';

/// Enum representing different types of companies/businesses
enum CompanyType {
  restoration,
  construction,
  roofing,
  plumbing,
  hvac,
  electrical,
  painting,
  flooring,
  remodeling,
  landscaping,
  propertyManagement,
  cleaningServices,
  pestControl,
  poolService,
  generalContractor,
  other;

  /// Display name for UI
  String get displayName {
    switch (this) {
      case CompanyType.restoration:
        return 'Restoration';
      case CompanyType.construction:
        return 'Construction';
      case CompanyType.roofing:
        return 'Roofing';
      case CompanyType.plumbing:
        return 'Plumbing';
      case CompanyType.hvac:
        return 'HVAC';
      case CompanyType.electrical:
        return 'Electrical';
      case CompanyType.painting:
        return 'Painting';
      case CompanyType.flooring:
        return 'Flooring';
      case CompanyType.remodeling:
        return 'Remodeling';
      case CompanyType.landscaping:
        return 'Landscaping';
      case CompanyType.propertyManagement:
        return 'Property Management';
      case CompanyType.cleaningServices:
        return 'Cleaning Services';
      case CompanyType.pestControl:
        return 'Pest Control';
      case CompanyType.poolService:
        return 'Pool Service';
      case CompanyType.generalContractor:
        return 'General Contractor';
      case CompanyType.other:
        return 'Other';
    }
  }

  /// Category grouping for UI display
  String get category {
    switch (this) {
      case CompanyType.restoration:
      case CompanyType.construction:
      case CompanyType.roofing:
      case CompanyType.plumbing:
      case CompanyType.hvac:
      case CompanyType.electrical:
      case CompanyType.painting:
      case CompanyType.flooring:
      case CompanyType.remodeling:
      case CompanyType.landscaping:
        return 'Service Trades';
      case CompanyType.propertyManagement:
      case CompanyType.cleaningServices:
      case CompanyType.pestControl:
      case CompanyType.poolService:
        return 'Property Services';
      case CompanyType.generalContractor:
      case CompanyType.other:
        return 'General';
    }
  }

  /// Description for each company type
  String get description {
    switch (this) {
      case CompanyType.restoration:
        return 'Water, fire, mold damage restoration';
      case CompanyType.construction:
        return 'General construction and building';
      case CompanyType.roofing:
        return 'Roof installation and repair';
      case CompanyType.plumbing:
        return 'Plumbing services and repairs';
      case CompanyType.hvac:
        return 'Heating, ventilation, and air conditioning';
      case CompanyType.electrical:
        return 'Electrical installation and repair';
      case CompanyType.painting:
        return 'Interior and exterior painting';
      case CompanyType.flooring:
        return 'Flooring installation and repair';
      case CompanyType.remodeling:
        return 'Home and commercial remodeling';
      case CompanyType.landscaping:
        return 'Landscape design and maintenance';
      case CompanyType.propertyManagement:
        return 'Property management services';
      case CompanyType.cleaningServices:
        return 'Commercial and residential cleaning';
      case CompanyType.pestControl:
        return 'Pest control and extermination';
      case CompanyType.poolService:
        return 'Pool maintenance and repair';
      case CompanyType.generalContractor:
        return 'General contracting services';
      case CompanyType.other:
        return 'Other business type';
    }
  }

  /// Icon for each company type
  IconData get icon {
    switch (this) {
      case CompanyType.restoration:
        return Icons.water_damage;
      case CompanyType.construction:
        return Icons.construction;
      case CompanyType.roofing:
        return Icons.roofing;
      case CompanyType.plumbing:
        return Icons.plumbing;
      case CompanyType.hvac:
        return Icons.hvac;
      case CompanyType.electrical:
        return Icons.electrical_services;
      case CompanyType.painting:
        return Icons.format_paint;
      case CompanyType.flooring:
        return Icons.layers;
      case CompanyType.remodeling:
        return Icons.home_repair_service;
      case CompanyType.landscaping:
        return Icons.grass;
      case CompanyType.propertyManagement:
        return Icons.apartment;
      case CompanyType.cleaningServices:
        return Icons.cleaning_services;
      case CompanyType.pestControl:
        return Icons.pest_control;
      case CompanyType.poolService:
        return Icons.pool;
      case CompanyType.generalContractor:
        return Icons.engineering;
      case CompanyType.other:
        return Icons.business;
    }
  }

  /// Parse string to CompanyType, defaulting to 'other' for unknown values
  static CompanyType fromString(String value) {
    try {
      return CompanyType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => CompanyType.other,
      );
    } catch (e) {
      return CompanyType.other;
    }
  }
}

/// Extension for smart defaults based on company type
extension CompanyTypeDefaults on CompanyType {
  /// Default project terminology for this company type
  String get defaultProjectTerminology {
    switch (this) {
      case CompanyType.restoration:
      case CompanyType.roofing:
      case CompanyType.plumbing:
      case CompanyType.hvac:
      case CompanyType.electrical:
      case CompanyType.painting:
      case CompanyType.flooring:
      case CompanyType.landscaping:
      case CompanyType.cleaningServices:
      case CompanyType.pestControl:
      case CompanyType.poolService:
        return 'Jobs';
      case CompanyType.propertyManagement:
        return 'Properties';
      case CompanyType.construction:
      case CompanyType.remodeling:
      case CompanyType.generalContractor:
      case CompanyType.other:
        return 'Projects';
    }
  }

  /// Default enabled project tabs for this company type
  List<String> get defaultEnabledTabs {
    // Most types use standard tabs (empty list = all enabled).
    // Restoration historically pinned an extra tab — that now lives under
    // 'overview', so the override is unnecessary
    // and we let the consolidated default kick in.
    return [];
  }
}
