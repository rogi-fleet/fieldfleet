import 'package:flutter/material.dart';
import '../../models/widget_catalog_provider.dart';
import '../../theme/theme.dart';

/// Metadata for a single dashboard widget.
///
/// Grid sizing fields ([defaultW], [defaultH], [minW], [minH], [maxW], [maxH],
/// [autoHeight]) are used by the v3 grid layout system. They're optional and
/// fall back to values derived from [defaultSize] for widgets that haven't
/// been explicitly tuned.
class DashboardWidgetMeta {
  final String id;
  final String label;
  final IconData icon;
  final Color accentColor;
  final String defaultSize; // "half" | "full"
  final bool needsProjectData;
  final bool needsTaskData;

  /// One-line summary of what the widget shows, displayed in the manage-
  /// widgets sheet so users can decide what to show without trial and error.
  /// May contain the words "Project"/"Projects" — render through
  /// [substituteProjectTerminology] like [label].
  final String description;

  /// Default width in 12-column grid units. If null, derived from [defaultSize]
  /// (half → 6, full → 12).
  final int? defaultW;

  /// Default height in row units (one row unit ≈ 64px). If null, defaults to 3.
  final int? defaultH;

  /// Minimum width the user can resize to. Defaults to 2 (1/6 of a 12-col
  /// desktop grid), so widgets can be packed compactly side by side.
  final int minW;

  /// Minimum height the user can resize to. Defaults to 1, letting sparse
  /// widgets (e.g. an empty alerts feed) shrink instead of leaving dead space.
  final int minH;

  /// Maximum width. Null = no cap (subject to grid columns).
  final int? maxW;

  /// Maximum height. Null = no cap.
  final int? maxH;

  /// When true, the widget reports its content height and the grid shrinks `h`
  /// to match (clamped to [minH]). Used for variable-content lists/feeds to
  /// avoid trailing visual gaps.
  final bool autoHeight;

  const DashboardWidgetMeta({
    required this.id,
    required this.label,
    required this.icon,
    required this.accentColor,
    this.defaultSize = 'half',
    this.needsProjectData = false,
    this.needsTaskData = false,
    this.description = '',
    this.defaultW,
    this.defaultH,
    this.minW = 2,
    this.minH = 1,
    this.maxW,
    this.maxH,
    this.autoHeight = false,
  });

  /// Effective default width on a 12-column desktop grid.
  int get desktopDefaultW =>
      defaultW ?? (defaultSize == 'full' ? 12 : 6);

  /// Effective default height in row units.
  int get desktopDefaultH => defaultH ?? 3;
}

/// Public catalog of all available dashboard widgets with metadata.
class DashboardWidgetCatalog {
  DashboardWidgetCatalog._();

  // Order is tuned so each row of the 3-col desktop grid is a coherent
  // group. Every widget defaults to 1/3 width except the dismissable
  // onboarding banner (full row at top) and Recent Activity (2/3, anchors
  // the bottom alongside Messaging).
  //
  //   Row 1 (full):   getting_started
  //   Row 2 (3 × 1/3): daily_summary    weekly_digest    todays_schedule
  //                      ↑ at-a-glance period summaries + today's plan
  //   Row 3 (3 × 1/3): my_tasks         active_projects  recent_projects
  //                      ↑ your work + portfolio
  //   Row 4 (3 × 1/3): financial_summary  team_utilization  capacity_alerts
  //                      ↑ health: money + team
  //   Row 5 (1/3 + 2/3): messaging_summary  recent_activity
  //                      ↑ communications + activity feed
  static const List<String> defaultOrder = [
    'getting_started',
    'daily_summary',
    'weekly_digest',
    'todays_schedule',
    'my_tasks',
    'active_projects',
    'recent_projects',
    'financial_summary',
    'team_utilization',
    'capacity_alerts',
    'messaging_summary',
    'recent_activity',
  ];

  static const Map<String, String> labels = {
    'getting_started': 'Getting Started',
    'daily_summary': 'Daily Summary',
    'weekly_digest': 'Weekly Digest',
    'team_utilization': 'Team Utilization',
    'recent_projects': 'Recent Projects',
    'active_projects': 'Active Projects',
    'my_tasks': 'My Tasks',
    'todays_schedule': "Today's Schedule",
    'messaging_summary': 'Messaging Summary',
    'capacity_alerts': 'Capacity Alerts',
    'financial_summary': 'Financial Summary',
    'recent_activity': 'Recent Activity',
  };

  // Default widget widths are designed for a 3-per-row desktop layout on the
  // 12-col grid (most widgets at defaultW: 4 = a third). The breakpoint
  // scaler maps that to ~3/8 width on tablet (~2 per row) and a full row on
  // mobile. Widgets that genuinely benefit from horizontal room — the
  // onboarding banner, the schedule, the team chart — default to wider spans
  // (8 or 12) so they don't cramp.
  static final Map<String, DashboardWidgetMeta> widgets = {
    'getting_started': const DashboardWidgetMeta(
      id: 'getting_started',
      label: 'Getting Started',
      icon: Icons.rocket_launch,
      accentColor: AppColors.success,
      description: 'Setup checklist to get your workspace ready',
      defaultW: 12,
      defaultH: 3,
      autoHeight: true,
    ),
    'daily_summary': const DashboardWidgetMeta(
      id: 'daily_summary',
      label: 'Daily Summary',
      icon: Icons.today,
      accentColor: Color(0xFF2563EB),
      description: "AI recap of today's urgent actions and inbox",
      defaultW: 4,
      defaultH: 2,
      minH: 2,
      autoHeight: true,
    ),
    'weekly_digest': const DashboardWidgetMeta(
      id: 'weekly_digest',
      label: 'Weekly Digest',
      icon: Icons.auto_awesome,
      accentColor: Color(0xFF7C3AED),
      description: 'AI week-over-week digest for a Project',
      defaultW: 4,
      defaultH: 2,
      minH: 2,
      autoHeight: true,
    ),
    'recent_projects': const DashboardWidgetMeta(
      id: 'recent_projects',
      label: 'Recent Projects',
      icon: Icons.history,
      accentColor: AppColors.success,
      description: 'Projects you viewed most recently',
      needsProjectData: true,
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'active_projects': const DashboardWidgetMeta(
      id: 'active_projects',
      label: 'Active Projects',
      icon: Icons.folder_open,
      accentColor: Color(0xFF0891B2),
      description: 'Your in-progress Projects at a glance',
      needsProjectData: true,
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'my_tasks': const DashboardWidgetMeta(
      id: 'my_tasks',
      label: 'My Tasks',
      icon: Icons.check_circle_outline,
      accentColor: AppColors.warningDark,
      description: 'Tasks assigned to you, overdue first',
      needsProjectData: true,
      needsTaskData: true,
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'messaging_summary': const DashboardWidgetMeta(
      id: 'messaging_summary',
      label: 'Messaging Summary',
      icon: Icons.chat_bubble_outline,
      accentColor: Color(0xFFDB2777),
      description: 'Unread conversations and recent messages',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'team_utilization': const DashboardWidgetMeta(
      id: 'team_utilization',
      label: 'Team Utilization',
      icon: Icons.groups,
      accentColor: Color(0xFF7C3AED),
      description: "Who's busy and who has capacity this week",
      // The widget uses a LayoutBuilder inside its content branch to switch
      // between compact and full chip layouts. LayoutBuilder reports 0 to
      // intrinsic-height calculations, so autoHeight under-measures the cell
      // at ~96 px (header + padding only) and the chips paint outside the
      // card boundary. Sized to its declared slot instead.
      //
      // 1/3 width by default — the summary chips + a few member rows fit
      // comfortably there. The widget switches to a compact chip layout
      // below 300 px so very narrow widths still render cleanly.
      defaultW: 4,
      defaultH: 3,
    ),
    'capacity_alerts': const DashboardWidgetMeta(
      id: 'capacity_alerts',
      label: 'Capacity Alerts',
      icon: Icons.warning_amber,
      accentColor: AppColors.error,
      description: 'Warnings when team members are overloaded',
      defaultW: 4,
      defaultH: 2,
      autoHeight: true,
    ),
    'financial_summary': const DashboardWidgetMeta(
      id: 'financial_summary',
      label: 'Financial Summary',
      icon: Icons.account_balance_wallet,
      accentColor: AppColors.financialAccent,
      description: 'Revenue, profit and forecast across all Projects',
      defaultW: 4,
      defaultH: 3,
      autoHeight: true,
    ),
    'recent_activity': const DashboardWidgetMeta(
      id: 'recent_activity',
      label: 'Recent Activity',
      icon: Icons.timeline,
      accentColor: Color(0xFF4F46E5),
      description: 'Latest changes across your workspace',
      // 2/3 width — the activity feed is a long vertical list of events,
      // and using 2/3 lets it anchor the bottom row of the dashboard
      // alongside the 1/3-wide Messaging card (4 + 8 = 12 fills the row).
      defaultW: 8,
      defaultH: 3,
      autoHeight: true,
    ),
    'todays_schedule': const DashboardWidgetMeta(
      id: 'todays_schedule',
      label: "Today's Schedule",
      icon: Icons.calendar_today,
      accentColor: Color(0xFF2563EB),
      description: 'Projects and tasks scheduled for today',
      // 1/3 width — sits in the top "at-a-glance" row alongside the daily
      // and weekly summaries, and the empty state stays proportional.
      defaultW: 4,
      defaultH: 3,
      needsProjectData: true,
      needsTaskData: true,
      autoHeight: true,
    ),
  };

  /// Returns metadata for a widget, with a sensible fallback.
  static DashboardWidgetMeta metaFor(String id) {
    return metaForWithTerminology(id, 'Projects');
  }

  /// Returns metadata for a widget, using workspace terminology where relevant.
  static DashboardWidgetMeta metaForWithTerminology(
    String id,
    String projectTerminology,
  ) {
    final baseMeta =
        widgets[id] ??
        DashboardWidgetMeta(
          id: id,
          label: id,
          icon: Icons.widgets,
          accentColor: const Color(0xFF64748B),
        );

    if (id == 'recent_projects') {
      return _withLabel(baseMeta, 'Recent $projectTerminology');
    }

    if (id == 'active_projects') {
      return _withLabel(baseMeta, 'Active $projectTerminology');
    }

    return baseMeta;
  }

  static DashboardWidgetMeta _withLabel(DashboardWidgetMeta m, String label) =>
      DashboardWidgetMeta(
        id: m.id,
        label: label,
        icon: m.icon,
        accentColor: m.accentColor,
        defaultSize: m.defaultSize,
        needsProjectData: m.needsProjectData,
        needsTaskData: m.needsTaskData,
        description: m.description,
        defaultW: m.defaultW,
        defaultH: m.defaultH,
        minW: m.minW,
        minH: m.minH,
        maxW: m.maxW,
        maxH: m.maxH,
        autoHeight: m.autoHeight,
      );
}

/// Instance wrapper that delegates to [DashboardWidgetCatalog] statics,
/// implementing [WidgetCatalogProvider] so it can be injected into
/// [DashboardEditController].
class DashboardCatalogInstance implements WidgetCatalogProvider {
  String projectTerminology;
  final List<String> _excludedWidgetIds;

  DashboardCatalogInstance({
    this.projectTerminology = 'Projects',
    List<String> excludedWidgetIds = const [],
  }) : _excludedWidgetIds = excludedWidgetIds;

  @override
  List<String> get defaultOrder => DashboardWidgetCatalog.defaultOrder
      .where((id) => !_excludedWidgetIds.contains(id))
      .toList(growable: false);

  @override
  List<String> get defaultHidden => const [];

  @override
  Map<String, String> get labels => Map.unmodifiable({
    for (final entry in DashboardWidgetCatalog.labels.entries)
      if (!_excludedWidgetIds.contains(entry.key))
        entry.key: switch (entry.key) {
          'recent_projects' => 'Recent $projectTerminology',
          'active_projects' => 'Active $projectTerminology',
          _ => entry.value,
        },
  });

  @override
  DashboardWidgetMeta metaFor(String id) =>
      DashboardWidgetCatalog.metaForWithTerminology(id, projectTerminology);
}
