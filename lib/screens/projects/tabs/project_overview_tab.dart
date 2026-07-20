import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/activity_item.dart';
import '../../../models/project.dart';
import '../../../models/customer.dart';
import '../../../services/service_locator.dart';
import '../../../widgets/weather_widget.dart';
import '../../../widgets/adaptive_map_widget.dart';
import '../../../widgets/project_phase_timeline.dart';
import '../widgets/summary_dashboard_widget.dart';
import '../widgets/active_alerts_widget.dart';
import '../widgets/project_details_widget.dart';
import '../widgets/project_timeline_widget.dart';
import '../../../widgets/charts/budget_burndown_chart.dart';
import '../widgets/recent_notes_widget.dart';
import '../widgets/team_on_site_widget.dart';
import '../../../widgets/project_messaging_summary_widget.dart';
import '../../../theme/theme.dart';
import '../../../utils/address_formatter.dart';
import '../../../utils/project_terminology.dart';
import '../../../providers/workspace_provider.dart';
import '../../home/dashboard_edit_controller.dart';
import '../../home/widgets/dashboard_grid.dart';
import '../../home/widgets/widget_grid.dart';
import '../../home/widgets/edit_toolbar_actions.dart';
import '../../home/widgets/manage_widgets_sheet.dart';
import '../../../config/feature_flags.dart';
import 'project_overview_widget_catalog.dart';

class ProjectOverviewTab extends StatefulWidget {
  final Project project;

  const ProjectOverviewTab({super.key, required this.project});

  @override
  State<ProjectOverviewTab> createState() => _ProjectOverviewTabState();
}

class _ProjectOverviewTabState extends State<ProjectOverviewTab> {
  late final DashboardEditController _controller;
  Future<List<ActivityItem>>? _recentActivityPreviewFuture;
  String? _recentActivityWorkspaceKey;

  @override
  void initState() {
    super.initState();
    _controller = DashboardEditController(
      catalog: const ProjectOverviewCatalog(),
      preferenceKey: 'project_overview_widget_config',
    );
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant ProjectOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.workspaceId != widget.project.workspaceId) {
      // Invalidate the cached recent activity future on workspace switch.
      _recentActivityPreviewFuture = null;
      _recentActivityWorkspaceKey = null;
    }
  }

  Future<List<ActivityItem>> _ensureRecentActivityFuture() {
    if (_recentActivityPreviewFuture == null ||
        _recentActivityWorkspaceKey != widget.project.workspaceId) {
      _recentActivityWorkspaceKey = widget.project.workspaceId;
      _recentActivityPreviewFuture = ServiceLocator.dashboardService
          .getRecentActivity(widget.project.workspaceId, limit: 50);
    }
    return _recentActivityPreviewFuture!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        showSaveErrorIfAny(context, _controller);

        return Column(
          children: [
            _buildToolbar(context),
            Expanded(
              // Light surface behind the widget grid so the dark scaffold
              // chrome doesn't show through the inter-widget gaps — matches
              // the home dashboard pattern.
              child: ColoredBox(
                color: AppColors.background,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final int columns;
                    final EdgeInsets padding;
                    final double gap;

                    if (constraints.maxWidth > AppBreakpoints.tablet) {
                      columns = 2;
                      padding = const EdgeInsets.all(6);
                      gap = 6;
                    } else {
                      columns = 1;
                      padding = const EdgeInsets.all(6);
                      gap = 6;
                    }

                    final hasVisibleWidgets = _controller.visibleOrder.isNotEmpty;

                    return SingleChildScrollView(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!hasVisibleWidgets)
                            _buildAllWidgetsHiddenState()
                          else if (FeatureFlags.dashboardGridV3)
                            WidgetGrid(
                              controller: _controller,
                              gap: gap,
                              widgetBuilder: (id) => _buildWidget(id),
                            )
                          else
                            DashboardGrid(
                              controller: _controller,
                              columns: columns,
                              gap: gap,
                              widgetBuilder: (id) => _buildWidget(id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final editing = _controller.editMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.background,
        border: Border(bottom: BorderSide(color: chrome.divider)),
      ),
      child: Row(
        children: [
          const Spacer(),
          if (editing)
            EditToolbarActions(
              controller: _controller,
              onDone: () => _controller.toggleEditMode(),
              onManage: () => showManageWidgetsSheet(context, _controller),
              onReset: () => showResetDashboardConfirmation(
                context,
                _controller,
                title: 'Reset Overview',
              ),
            )
          else
            // Icon + label for discoverability — a lone tune icon in an
            // otherwise empty toolbar row was easy to miss.
            OutlinedButton.icon(
              onPressed: () => _controller.toggleEditMode(),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Customize'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: AppSpacing.xs),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllWidgetsHiddenState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All overview widgets are hidden',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Use Customize to show widgets and arrange your overview.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.base),
            FilledButton.icon(
              onPressed: () => _controller.resetDefaults(),
              icon: const Icon(Icons.restore),
              label: const Text('Reset Overview'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidget(String id) {
    switch (id) {
      case 'summary_kpis':
        return SummaryDashboardWidget(
          project: widget.project,
          preferHalfLayout: _controller.config.sizeOf(id) == 'half',
        );
      case 'active_alerts':
        return ActiveAlertsWidget(project: widget.project);
      case 'project_timeline':
        return ProjectTimelineWidget(project: widget.project);
      case 'project_details':
        return ProjectDetailsWidget(project: widget.project);
      case 'budget_burndown':
        return BudgetBurndownChart(project: widget.project);
      case 'phase_timeline':
        return ProjectPhaseTimeline(
          projectId: widget.project.id,
          workspaceId: widget.project.workspaceId,
        );
      case 'recent_activity':
        return _buildRecentActivityPreview(context);
      case 'location_weather':
        return _buildCompactLocationWeatherCard(context);
      case 'team_on_site':
        return TeamOnSiteTodayWidget(project: widget.project);
      case 'messaging_summary':
        return ProjectMessagingSummaryWidget(
          workspaceId: widget.project.workspaceId,
          projectId: widget.project.id,
          projectName: widget.project.name,
        );
      case 'recent_notes':
        return RecentNotesWidget(project: widget.project);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCompactLocationWeatherCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _buildPropertyContextAndWeather(context),
    );
  }

  Widget _buildPropertyContextAndWeather(BuildContext context) {
    final hasCoordinates =
        widget.project.latitude != null && widget.project.longitude != null;
    final formattedAddress = widget.project.address.isNotEmpty
        ? AddressFormatter.condense(widget.project.address)
        : 'No address set';

    return StreamBuilder<Customer?>(
      stream: widget.project.clientId != null
          ? ServiceLocator.customerService.watchCustomer(widget.project.clientId!)
          : const Stream.empty(),
      builder: (context, snapshot) {
        final customer = snapshot.data;
        final primaryContact = customer?.getPrimaryContact();

        return Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_city,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Site Info',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (customer != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Primary contact name + phone/email icons
                      if (primaryContact != null) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    primaryContact.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (primaryContact.phone != null &&
                                primaryContact.phone!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone, size: 18),
                                onPressed: () async {
                                  final uri = Uri(
                                    scheme: 'tel',
                                    path: primaryContact.phone!,
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                tooltip: 'Call ${primaryContact.phone}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            if (primaryContact.email != null &&
                                primaryContact.email!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.email, size: 18),
                                onPressed: () async {
                                  final uri = Uri(
                                    scheme: 'mailto',
                                    path: primaryContact.email!,
                                    query:
                                        'subject=${Uri.encodeComponent('Regarding your ${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology).toLowerCase()}')}',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                tooltip: 'Email ${primaryContact.email}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                          ],
                        ),
                        if (primaryContact.title != null &&
                            primaryContact.title!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: Text(
                              primaryContact.title!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              Text(
                formattedAddress,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasCoordinates) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: SizedBox(
                    height: 160,
                    child: AdaptiveMapWidget(
                      address: widget.project.address,
                      latitude: widget.project.latitude!,
                      longitude: widget.project.longitude!,
                      height: 160,
                      zoom: 14,
                      markerTitle: widget.project.name,
                    ),
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              ),
              WeatherWidget(
                locationQuery: hasCoordinates
                    ? '${widget.project.latitude},${widget.project.longitude}'
                    : widget.project.address,
                height: 120,
                compact: false,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivityPreview(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => _showAllActivityDialog(context),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<ActivityItem>>(
              future: _ensureRecentActivityFuture(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.base),
                    child: Text(
                      'Unable to load activity',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.base),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final activities = snapshot.data!
                    .where(_isProjectActivity)
                    .take(6)
                    .toList();

                if (activities.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No recent activity for this ${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology).toLowerCase()}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                return Column(
                  children: activities
                      .map(
                        (activity) => _ActivityPreviewItem(activity: activity),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAllActivityDialog(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width - 48)
        .clamp(0.0, 560.0);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recent Activity'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SizedBox(
            width: dialogWidth,
            height: MediaQuery.of(context).size.height * 0.6,
            child: FutureBuilder<List<ActivityItem>>(
              future: ServiceLocator.dashboardService.getRecentActivity(
                widget.project.workspaceId,
                limit: 100,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load activity'));
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final items = snapshot.data!
                    .where(_isProjectActivity)
                    .toList(growable: false);
                if (items.isEmpty) {
                  return const Center(child: Text('No recent activity'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) =>
                      _ActivityPreviewItem(activity: items[index]),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  bool _isProjectActivity(ActivityItem activity) {
    if (activity.type == ActivityType.projectCreated ||
        activity.type == ActivityType.projectUpdated ||
        activity.type == ActivityType.projectCompleted) {
      return activity.entityId == widget.project.id;
    }

    final metadata = activity.metadata;
    final projectId =
        metadata?['projectId']?.toString() ??
        metadata?['project_id']?.toString();
    return projectId == widget.project.id;
  }
}

class _ActivityPreviewItem extends StatelessWidget {
  final ActivityItem activity;

  const _ActivityPreviewItem({required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(activity.getRouteForEntity()),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.activityAccentLight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  activity.getIcon(),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          substituteProjectTerminology(
                            activity.title,
                            context
                                .watch<WorkspaceProvider>()
                                .projectTerminology,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _formatRelativeTime(activity.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (activity.description != null &&
                      activity.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      activity.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }
    return DateFormat('MMM d').format(timestamp);
  }
}
