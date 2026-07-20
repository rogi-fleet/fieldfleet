import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

import '../../../models/widget_catalog_provider.dart';
import '../../home/dashboard_widget_catalog.dart';

/// Widget catalog for the project detail Overview tab.
class ProjectOverviewCatalog implements WidgetCatalogProvider {
  const ProjectOverviewCatalog();

  // Order is tuned so each row of the 3-col desktop grid is a coherent
  // group. Every widget defaults to 1/3 width except Recent Activity
  // (2/3 — anchors the bottom alongside Recent Notes at 1/3).
  //
  //   Row 1 (3 × 1/3): summary_kpis    active_alerts   project_details
  //                      ↑ status snapshot (financial KPIs, urgent
  //                        attention, metadata)
  //   Row 2 (3 × 1/3): project_timeline  phase_timeline  budget_burndown
  //                      ↑ schedule + money — "where are we, on budget?"
  //   Row 3 (3 × 1/3): location_weather  team_on_site   messaging_summary
  //                      ↑ where & who & talking
  //   Row 4 (1/3 + 2/3): recent_notes    recent_activity
  //                      ↑ notes + activity feed
  static const List<String> _defaultOrder = [
    'summary_kpis',
    'active_alerts',
    'project_details',
    'project_timeline',
    'phase_timeline',
    'budget_burndown',
    'location_weather',
    'team_on_site',
    'messaging_summary',
    'recent_notes',
    'recent_activity',
  ];

  static const Map<String, String> _labels = {
    'summary_kpis': 'Summary KPIs',
    'active_alerts': 'Active Alerts',
    'budget_burndown': 'Budget Burndown',
    'phase_timeline': 'Phase Timeline',
    'project_timeline': 'Timeline',
    'project_details': 'Project Details',
    'recent_activity': 'Recent Activity',
    'location_weather': 'Location & Weather',
    'team_on_site': 'Team On Site',
    'messaging_summary': 'Messages',
    'recent_notes': 'Recent Notes',
  };

  // All widgets default to 1/3 of the 12-col desktop grid (defaultW: 4) — three
  // cards per row at desktop, scaled by the breakpoint logic to ~2 per row on
  // tablet (8 col) and one per row on mobile (4 col, always full). Charts that
  // benefit from horizontal room (budget burndown, phase timeline) default
  // wider so they don't cramp at 1/3.
  static final Map<String, DashboardWidgetMeta> _widgets = {
    'summary_kpis': const DashboardWidgetMeta(
      id: 'summary_kpis',
      label: 'Summary KPIs',
      icon: Icons.dashboard,
      accentColor: Color(0xFF2563EB),
      description: 'Approved, collected, profit and balance',
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'active_alerts': const DashboardWidgetMeta(
      id: 'active_alerts',
      label: 'Active Alerts',
      icon: Icons.warning_amber,
      accentColor: AppColors.error,
      description: 'Issues needing attention on this Project',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'budget_burndown': const DashboardWidgetMeta(
      id: 'budget_burndown',
      label: 'Budget Burndown',
      icon: Icons.trending_down,
      accentColor: AppColors.success,
      description: 'Actual spend charted against the budget',
      // 1/3 width — pairs with project_timeline + phase_timeline in
      // the "schedule + money" row. Empty state stays proportional.
      defaultW: 4,
      defaultH: 4,
      autoHeight: true,
    ),
    'phase_timeline': const DashboardWidgetMeta(
      id: 'phase_timeline',
      label: 'Phase Timeline',
      icon: Icons.timeline,
      accentColor: Color(0xFF7C3AED),
      description: 'Phases and how far along each one is',
      // 1/3 width — phase cards wrap to 2-3 rows inside the card. The
      // dense vertical stack reads cleanly at narrow widths.
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'project_timeline': const DashboardWidgetMeta(
      id: 'project_timeline',
      label: 'Timeline',
      icon: Icons.event,
      accentColor: Color(0xFF0284C7),
      description: 'Start and end dates at a glance',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'project_details': const DashboardWidgetMeta(
      id: 'project_details',
      label: 'Project Details',
      icon: Icons.info_outline,
      accentColor: Color(0xFF475569),
      description: 'Type, number and key details',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'recent_activity': const DashboardWidgetMeta(
      id: 'recent_activity',
      label: 'Recent Activity',
      icon: Icons.history,
      accentColor: Color(0xFF4F46E5),
      description: 'Latest events on this Project',
      // 2/3 width — anchors the bottom row paired with Recent Notes at
      // 1/3, so the activity feed has room for the longer event
      // descriptions and the row fills the grid cleanly (4 + 8 = 12).
      defaultW: 8,
      defaultH: 4,
      autoHeight: true,
    ),
    'location_weather': const DashboardWidgetMeta(
      id: 'location_weather',
      label: 'Location & Weather',
      icon: Icons.place,
      accentColor: Color(0xFF0891B2),
      description: 'Site map, address and weather',
      defaultW: 4,
      defaultH: 4,
      autoHeight: true,
    ),
    'team_on_site': const DashboardWidgetMeta(
      id: 'team_on_site',
      label: 'Team On Site',
      icon: Icons.groups,
      accentColor: AppColors.warningDark,
      description: 'Who is on site today',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'messaging_summary': const DashboardWidgetMeta(
      id: 'messaging_summary',
      label: 'Messages',
      icon: Icons.chat_bubble_outline,
      accentColor: Color(0xFFDB2777),
      description: 'Recent messages about this Project',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'recent_notes': const DashboardWidgetMeta(
      id: 'recent_notes',
      label: 'Recent Notes',
      icon: Icons.sticky_note_2,
      accentColor: Color(0xFF8B5CF6),
      description: 'Latest notes on this Project',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
  };

  @override
  List<String> get defaultOrder => _defaultOrder;

  @override
  List<String> get defaultHidden => const [];

  @override
  Map<String, String> get labels => _labels;

  @override
  DashboardWidgetMeta metaFor(String id) =>
      _widgets[id] ??
      DashboardWidgetMeta(
        id: id,
        label: id,
        icon: Icons.widgets,
        accentColor: const Color(0xFF64748B),
      );
}
