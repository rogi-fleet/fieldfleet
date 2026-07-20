import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

import '../../models/widget_catalog_provider.dart';
import 'dashboard_widget_catalog.dart';

/// Widget catalog for the field technician dashboard.
///
/// Contains field-specific widgets (schedule, time clock, forms, etc.)
/// plus a curated subset of the shared manager widgets.
class FieldTechnicianCatalog implements WidgetCatalogProvider {
  String projectTerminology;

  FieldTechnicianCatalog({this.projectTerminology = 'Projects'});

  static const List<String> _defaultOrder = [
    'getting_started',
    'todays_schedule',
    'time_clock',
    'driving_directions',
    'safety_checklist',
    'pending_forms',
    'my_tasks',
    'job_site_weather',
    'photo_upload_queue',
    'vehicle_equipment',
    'messaging_summary',
    'material_usage',
    'active_projects',
    'daily_summary',
    'recent_activity',
  ];

  static const List<String> _defaultHidden = [
    'material_usage',
    'active_projects',
    'daily_summary',
    'recent_activity',
  ];

  static const Map<String, String> _labels = {
    'getting_started': 'Getting Started',
    'todays_schedule': "Today's Schedule",
    'time_clock': 'Time Clock',
    'driving_directions': 'Driving Directions',
    'safety_checklist': 'Safety Checklist',
    'pending_forms': 'Pending Forms',
    'job_site_weather': 'Job Site Weather',
    'vehicle_equipment': 'Vehicle & Equipment',
    'photo_upload_queue': 'Photo Upload Queue',
    'material_usage': 'Material Usage',
    'my_tasks': 'My Tasks',
    'active_projects': 'Active Projects',
    'daily_summary': 'Daily Summary',
    'messaging_summary': 'Messaging Summary',
    'recent_activity': 'Recent Activity',
  };

  static final Map<String, DashboardWidgetMeta> _widgets = {
    'getting_started': const DashboardWidgetMeta(
      id: 'getting_started',
      label: 'Getting Started',
      icon: Icons.rocket_launch,
      accentColor: AppColors.success,
      description: 'Setup checklist to get your workspace ready',
      defaultSize: 'full',
      defaultH: 3,
      autoHeight: true,
    ),
    'todays_schedule': const DashboardWidgetMeta(
      id: 'todays_schedule',
      label: "Today's Schedule",
      icon: Icons.calendar_today,
      accentColor: Color(0xFF2563EB),
      description: 'Your jobs and tasks scheduled for today',
      defaultSize: 'full',
      defaultH: 3,
      needsProjectData: true,
      needsTaskData: true,
      autoHeight: true,
    ),
    'time_clock': const DashboardWidgetMeta(
      id: 'time_clock',
      label: 'Time Clock',
      icon: Icons.timer,
      accentColor: AppColors.success,
      description: 'Clock in and out of jobs',
      defaultH: 2,
      minH: 2,
      autoHeight: true,
    ),
    'driving_directions': const DashboardWidgetMeta(
      id: 'driving_directions',
      label: 'Driving Directions',
      icon: Icons.directions_car,
      accentColor: Color(0xFF0891B2),
      description: "Directions to today's job sites",
      needsProjectData: true,
      needsTaskData: true,
      defaultSize: 'full',
      defaultH: 3,
    ),
    'safety_checklist': const DashboardWidgetMeta(
      id: 'safety_checklist',
      label: 'Safety Checklist',
      icon: Icons.health_and_safety,
      accentColor: AppColors.error,
      description: 'Daily safety checks before work starts',
      defaultH: 3,
      autoHeight: true,
    ),
    'pending_forms': const DashboardWidgetMeta(
      id: 'pending_forms',
      label: 'Pending Forms',
      icon: Icons.assignment,
      accentColor: AppColors.warningDark,
      description: 'Field forms waiting to be filled out',
      needsProjectData: true,
      defaultH: 3,
      autoHeight: true,
    ),
    'job_site_weather': const DashboardWidgetMeta(
      id: 'job_site_weather',
      label: 'Job Site Weather',
      icon: Icons.wb_sunny,
      accentColor: Color(0xFFE8973A),
      description: 'Weather at your assigned job sites',
      needsProjectData: true,
      defaultH: 2,
      minH: 2,
    ),
    'vehicle_equipment': const DashboardWidgetMeta(
      id: 'vehicle_equipment',
      label: 'Vehicle & Equipment',
      icon: Icons.local_shipping,
      accentColor: Color(0xFF0891B2),
      description: 'Vehicle and equipment assigned to you',
      defaultH: 3,
      autoHeight: true,
    ),
    'photo_upload_queue': const DashboardWidgetMeta(
      id: 'photo_upload_queue',
      label: 'Photo Upload Queue',
      icon: Icons.camera_alt,
      accentColor: Color(0xFF4F46E5),
      description: 'Photos waiting to upload from the field',
      needsProjectData: true,
      defaultH: 3,
      autoHeight: true,
    ),
    'material_usage': const DashboardWidgetMeta(
      id: 'material_usage',
      label: 'Material Usage',
      icon: Icons.inventory,
      accentColor: Color(0xFFE8973A),
      description: 'Log materials used on the job',
      defaultSize: 'full',
      defaultH: 3,
      needsProjectData: true,
    ),
    // Shared widgets from manager catalog.
    'my_tasks': const DashboardWidgetMeta(
      id: 'my_tasks',
      label: 'My Tasks',
      icon: Icons.check_circle_outline,
      accentColor: AppColors.warningDark,
      description: 'Tasks assigned to you, overdue first',
      defaultSize: 'full',
      defaultH: 3,
      needsProjectData: true,
      needsTaskData: true,
      autoHeight: true,
    ),
    'active_projects': const DashboardWidgetMeta(
      id: 'active_projects',
      label: 'Active Projects',
      icon: Icons.folder_open,
      accentColor: Color(0xFF0891B2),
      description: 'Your in-progress Projects at a glance',
      needsProjectData: true,
      defaultH: 3,
      autoHeight: true,
    ),
    'daily_summary': const DashboardWidgetMeta(
      id: 'daily_summary',
      label: 'Daily Summary',
      icon: Icons.today,
      accentColor: Color(0xFF2563EB),
      description: "AI recap of today's urgent actions and inbox",
      defaultH: 2,
      minH: 2,
      autoHeight: true,
    ),
    'messaging_summary': const DashboardWidgetMeta(
      id: 'messaging_summary',
      label: 'Messaging Summary',
      icon: Icons.chat_bubble_outline,
      accentColor: Color(0xFFDB2777),
      description: 'Unread conversations and recent messages',
      defaultH: 2,
      autoHeight: true,
    ),
    'recent_activity': const DashboardWidgetMeta(
      id: 'recent_activity',
      label: 'Recent Activity',
      icon: Icons.timeline,
      accentColor: Color(0xFF4F46E5),
      description: 'Latest changes across your workspace',
      defaultH: 3,
      autoHeight: true,
    ),
  };

  @override
  List<String> get defaultOrder => _defaultOrder;

  @override
  List<String> get defaultHidden => _defaultHidden;

  @override
  Map<String, String> get labels => {
        for (final entry in _labels.entries)
          entry.key: entry.key == 'active_projects'
              ? 'Active $projectTerminology'
              : entry.value,
      };

  @override
  DashboardWidgetMeta metaFor(String id) {
    final base = _widgets[id];
    if (id == 'active_projects' && base != null) {
      return DashboardWidgetMeta(
        id: base.id,
        label: 'Active $projectTerminology',
        icon: base.icon,
        accentColor: base.accentColor,
        defaultSize: base.defaultSize,
        needsProjectData: base.needsProjectData,
        needsTaskData: base.needsTaskData,
        description: base.description,
        defaultW: base.defaultW,
        defaultH: base.defaultH,
        minW: base.minW,
        minH: base.minH,
        maxW: base.maxW,
        maxH: base.maxH,
        autoHeight: base.autoHeight,
      );
    }
    return base ??
        DashboardWidgetMeta(
          id: id,
          label: id,
          icon: Icons.widgets,
          accentColor: const Color(0xFF64748B),
        );
  }
}
