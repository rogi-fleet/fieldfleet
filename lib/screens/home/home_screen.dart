import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/home/authenticated_portal_home.dart';
import '../../widgets/home/getting_started_widget.dart';
import '../../widgets/home/master_admin_tier_banner.dart';
import '../../widgets/home/active_projects_widget.dart';
import '../../widgets/home/daily_summary_card.dart';
import '../../widgets/home/weekly_digest_card.dart';
import '../../widgets/home/recent_projects_widget.dart';
import '../../widgets/home/my_tasks_widget.dart';
import '../../widgets/home/recent_activity_widget.dart';
import '../../widgets/home/capacity_alerts_widget.dart';
import '../../widgets/home/financial_summary_widget.dart';
import '../../widgets/home/team_utilization_widget.dart';
import '../../widgets/home/field/todays_schedule_widget.dart';
import '../../widgets/home/field/time_clock_widget.dart';
import '../../widgets/home/field/pending_forms_widget.dart';
import '../../widgets/home/field/vehicle_equipment_widget.dart';
import '../../widgets/home/field/job_site_weather_widget.dart';
import '../../widgets/home/field/photo_upload_queue_widget.dart';
import '../../widgets/home/field/safety_checklist_widget.dart';
import '../../widgets/home/field/driving_directions_widget.dart';
import '../../widgets/home/field/material_usage_widget.dart';
import '../../widgets/dashboard/messaging_summary_widget.dart';
import '../../widgets/dashboard/company_snapshot_widget.dart';
import 'dashboard_widget_catalog.dart';
import 'dashboard_edit_controller.dart';
import 'field_technician_catalog.dart';
import 'widgets/dashboard_grid.dart';
import 'widgets/widget_grid.dart';
import 'widgets/edit_toolbar_actions.dart';
import 'widgets/manage_widgets_sheet.dart';
import '../../config/feature_flags.dart';
import '../../widgets/adaptive_navigation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _lastQuitTime;
  final DashboardCatalogInstance _managerCatalog = DashboardCatalogInstance();
  final FieldTechnicianCatalog _fieldCatalog = FieldTechnicianCatalog();
  late final DashboardEditController _managerDashboardController =
      DashboardEditController(catalog: _managerCatalog);
  late final DashboardEditController _fieldDashboardController =
      DashboardEditController(
        catalog: _fieldCatalog,
        preferenceKey: 'field_dashboard_widget_config',
      );
  bool _controllersLoaded = false;
  Timer? _workspaceRefreshTimer;
  int _workspaceRefreshAttempts = 0;

  @override
  void initState() {
    super.initState();
    // If the router bounced the user here from a permission-gated route
    // (e.g. /workspaces/settings without admin access), it appends
    // ?denied=<original-path> — surface a snackbar so the user knows the
    // click did something instead of looking like the app froze.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uri = GoRouterState.of(context).uri;
      final denied = uri.queryParameters['denied'];
      if (denied != null && denied.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "You don't have access to $denied. Ask a workspace admin "
              "if you need permissions changed.",
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    });
  }

  void _scheduleWorkspaceRefresh(AuthProvider authProvider) {
    if (_workspaceRefreshTimer?.isActive ?? false) return;
    if (_workspaceRefreshAttempts >= 6) return;
    _workspaceRefreshTimer = Timer(
      Duration(milliseconds: 500 * (_workspaceRefreshAttempts + 1)),
      () async {
        if (!mounted) return;
        _workspaceRefreshAttempts++;
        await authProvider.refreshUser();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final projectTerminology =
        context.read<WorkspaceProvider>().projectTerminology;
    _managerCatalog.projectTerminology = projectTerminology;
    _fieldCatalog.projectTerminology = projectTerminology;
    if (_controllersLoaded) return;
    _controllersLoaded = true;
    _managerDashboardController.load();
    _fieldDashboardController.load();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    _managerCatalog.projectTerminology = projectTerminology;
    _fieldCatalog.projectTerminology = projectTerminology;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;
    final isFieldMode = authProvider.isFieldMode;
    final isPortalUser =
        authProvider.appUser?.role.isExternalPortal ?? false;
    final dashboardController = isFieldMode
        ? _fieldDashboardController
        : _managerDashboardController;

    if (workspaceId == null || workspaceId.isEmpty || userId == null) {
      _scheduleWorkspaceRefresh(authProvider);
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const SelectableText(
                  'Loading your workspace...',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'This should only take a moment',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                const SelectableText(
                  'If this screen persists for more than 10 seconds,\nthere may be a connection issue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    authProvider.signOut();
                  },
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastQuitTime == null ||
            now.difference(_lastQuitTime!) > const Duration(seconds: 2)) {
          _lastQuitTime = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        SystemNavigator.pop();
      },
      child: Column(
        children: [
          // Pre-onboarding banner. The dashboard renders briefly for
          // workspace owners before the redirect-to-/onboarding gate
          // kicks in (workspaces still loading). Every sidebar click
          // then silently bounces to the wizard with no UI signal — so
          // surface the state explicitly here while the user is on the
          // dashboard.
          if (authProvider.canManageUsers &&
              !context
                  .watch<WorkspaceProvider>()
                  .currentWorkspaceOnboardingCompleted)
            Material(
              color: AppColors.warning,
              child: InkWell(
                onTap: () => context.go('/onboarding'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: 10,
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.rocket_launch_outlined,
                          size: 18, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Finish setting up your workspace to unlock '
                          'the sidebar and create records.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Continue setup →',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          MasterAdminTierBanner(
            userId: userId,
            isAdmin: authProvider.canManageUsers,
          ),
          if (isPortalUser)
            Expanded(child: AuthenticatedPortalHome(userId: userId))
          else if (isFieldMode)
            Expanded(
              child: _buildHomeTab(
                context,
                workspaceId,
                userId,
                dashboardController: dashboardController,
              ),
            )
          else
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: TabSwitchNotifier(
                  child: Builder(
                    builder: (context) {
                      final tabController = DefaultTabController.of(context);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: const TabBar(
                              isScrollable: true,
                              padding: EdgeInsets.zero,
                              tabAlignment: TabAlignment.start,
                              tabs: [
                                Tab(icon: Icon(Icons.home_outlined), text: 'Home'),
                                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _buildHomeTab(
                                  context,
                                  workspaceId,
                                  userId,
                                  dashboardController: dashboardController,
                                  onViewDashboard: () =>
                                      tabController.animateTo(1),
                                ),
                                _buildOverviewTab(workspaceId),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(
    BuildContext context,
    String workspaceId,
    String userId, {
    required DashboardEditController dashboardController,
    VoidCallback? onViewDashboard,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (AppBreakpoints.isDesktop(constraints.maxWidth)) {
          return _buildResponsiveDashboard(
            dashboardController: dashboardController,
            workspaceId: workspaceId,
            userId: userId,
            padding: const EdgeInsets.all(AppSpacing.base),
            columns: 2,
            gap: AppSpacing.sm,
            onViewDashboard: onViewDashboard,
          );
        } else if (AppBreakpoints.isTablet(constraints.maxWidth)) {
          return _buildResponsiveDashboard(
            dashboardController: dashboardController,
            workspaceId: workspaceId,
            userId: userId,
            padding: const EdgeInsets.all(AppSpacing.base),
            columns: 2,
            gap: AppSpacing.sm,
            onViewDashboard: onViewDashboard,
          );
        } else {
          final bottomInset = MediaQuery.of(context).padding.bottom;
          return _buildResponsiveDashboard(
            dashboardController: dashboardController,
            workspaceId: workspaceId,
            userId: userId,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              AppSpacing.screenPaddingMobile,
              AppSpacing.screenPaddingMobile,
              AppSpacing.screenPaddingMobile + 70 + bottomInset,
            ),
            columns: 1,
            gap: AppSpacing.xs,
            onViewDashboard: onViewDashboard,
          );
        }
      },
    );
  }

  Widget _buildOverviewTab(String workspaceId) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final EdgeInsets padding;
        if (AppBreakpoints.isDesktop(constraints.maxWidth)) {
          padding = const EdgeInsets.all(AppSpacing.screenPaddingDesktop);
        } else if (AppBreakpoints.isTablet(constraints.maxWidth)) {
          padding = const EdgeInsets.all(AppSpacing.screenPaddingTablet);
        } else {
          final bottomInset = MediaQuery.of(context).padding.bottom;
          padding = EdgeInsets.fromLTRB(
            AppSpacing.screenPaddingMobile,
            AppSpacing.screenPaddingMobile,
            AppSpacing.screenPaddingMobile,
            AppSpacing.screenPaddingMobile + 70 + bottomInset,
          );
        }

        return SingleChildScrollView(
          padding: padding,
          child: CompanySnapshotWidget(workspaceId: workspaceId),
        );
      },
    );
  }

  Widget _buildResponsiveDashboard({
    required DashboardEditController dashboardController,
    required String workspaceId,
    required String userId,
    required EdgeInsets padding,
    required int columns,
    required double gap,
    VoidCallback? onViewDashboard,
  }) {
    return ListenableBuilder(
      listenable: dashboardController,
      builder: (context, _) {
        if (dashboardController.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final hasVisibleWidgets = dashboardController.visibleOrder.isNotEmpty;
        final catalog = dashboardController.catalog;
        final needsProjectData = dashboardController.visibleOrder.any(
          (id) => catalog.metaFor(id).needsProjectData,
        );
        final needsTaskData = dashboardController.visibleOrder.any(
          (id) => catalog.metaFor(id).needsTaskData,
        );

        // Wrap in a light surface so the dark scaffold chrome doesn't bleed
        // through the inter-widget gaps. The grid renders white cards spaced
        // by `gap`; without this, those gaps reveal the navy `sidebarBg`.
        return ColoredBox(
          color: AppColors.background,
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, dashboardController),
                SizedBox(height: gap),
                if (!hasVisibleWidgets)
                  _buildAllWidgetsHiddenState(dashboardController)
                else
                  _buildDashboardGrid(
                    controller: dashboardController,
                    workspaceId: workspaceId,
                    userId: userId,
                    columns: columns,
                    gap: gap,
                    onViewDashboard: onViewDashboard,
                    needsProjectData: needsProjectData,
                    needsTaskData: needsTaskData,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardGrid({
    required DashboardEditController controller,
    required String workspaceId,
    required String userId,
    required int columns,
    required double gap,
    required bool needsProjectData,
    required bool needsTaskData,
    VoidCallback? onViewDashboard,
  }) {
    if (!needsProjectData && !needsTaskData) {
      return _renderGrid(
        controller: controller,
        columns: columns,
        gap: gap,
        widgetBuilder: (id) => _buildDashboardWidget(
          id: id,
          workspaceId: workspaceId,
          userId: userId,
          onViewDashboard: onViewDashboard,
        ),
      );
    }

    return StreamBuilder<List<Project>>(
      stream: needsProjectData
          ? ServiceLocator.projectService.getProjects(workspaceId)
          : const Stream.empty(),
      builder: (context, projectSnapshot) {
        final allProjects = projectSnapshot.hasData
            ? projectSnapshot.data!
            : null;
        final projectNamesById = {
          for (final project in allProjects ?? const <Project>[])
            project.id: project.name,
        };

        if (!needsTaskData) {
          return _renderGrid(
            controller: controller,
            columns: columns,
            gap: gap,
            widgetBuilder: (id) => _buildDashboardWidget(
              id: id,
              workspaceId: workspaceId,
              userId: userId,
              allProjects: allProjects,
              projectNamesById: projectNamesById,
              onViewDashboard: onViewDashboard,
            ),
          );
        }

        return StreamBuilder<List<Task>>(
          stream: ServiceLocator.taskService.getAllWorkspaceTasks(workspaceId),
          builder: (context, taskSnapshot) {
            final allTasks = taskSnapshot.hasData ? taskSnapshot.data! : null;

            return _renderGrid(
              controller: controller,
              columns: columns,
              gap: gap,
              widgetBuilder: (id) => _buildDashboardWidget(
                id: id,
                workspaceId: workspaceId,
                userId: userId,
                allProjects: allProjects,
                projectNamesById: projectNamesById,
                allTasks: allTasks,
                onViewDashboard: onViewDashboard,
              ),
            );
          },
        );
      },
    );
  }

  /// Picks between the legacy [DashboardGrid] and the new [WidgetGrid] based on
  /// [FeatureFlags.dashboardGridV3]. v3 handles both view and edit modes.
  Widget _renderGrid({
    required DashboardEditController controller,
    required int columns,
    required double gap,
    required Widget Function(String id) widgetBuilder,
  }) {
    if (FeatureFlags.dashboardGridV3) {
      return WidgetGrid(
        controller: controller,
        gap: gap,
        widgetBuilder: widgetBuilder,
      );
    }
    return DashboardGrid(
      controller: controller,
      columns: columns,
      gap: gap,
      widgetBuilder: widgetBuilder,
    );
  }

  Widget _buildDashboardWidget({
    required String id,
    required String workspaceId,
    required String userId,
    List<Project>? allProjects,
    Map<String, String> projectNamesById = const <String, String>{},
    List<Task>? allTasks,
    VoidCallback? onViewDashboard,
  }) {
    switch (id) {
      case 'getting_started':
        final isFieldMode = context.read<AuthProvider>().isFieldMode;
        final controller = isFieldMode
            ? _fieldDashboardController
            : _managerDashboardController;
        return GettingStartedWidget(
          key: ValueKey('getting_started_$workspaceId'),
          workspaceId: workspaceId,
          userId: userId,
          isFieldMode: isFieldMode,
          onAutoHide: () => controller.hideWidget('getting_started'),
        );
      case 'daily_summary':
        return DailySummaryCard(workspaceId: workspaceId, userId: userId);
      case 'weekly_digest':
        return WeeklyDigestCard(workspaceId: workspaceId, userId: userId);
      case 'recent_projects':
        return RecentProjectsWidget(
          workspaceId: workspaceId,
          allProjects: allProjects,
        );
      case 'active_projects':
        return ActiveProjectsWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
        );
      case 'my_tasks':
        return MyTasksWidget(
          workspaceId: workspaceId,
          userId: userId,
          projectNamesById: projectNamesById,
          allTasks: allTasks,
          allProjects: allProjects,
        );
      case 'messaging_summary':
        return MessagingSummaryWidget(workspaceId: workspaceId);
      case 'team_utilization':
        return TeamUtilizationWidget(workspaceId: workspaceId);
      case 'capacity_alerts':
        return CapacityAlertsWidget(workspaceId: workspaceId);
      case 'financial_summary':
        return FinancialSummaryWidget(
          workspaceId: workspaceId,
          onViewDashboard: onViewDashboard,
        );
      case 'recent_activity':
        return RecentActivityWidget(workspaceId: workspaceId);
      case 'todays_schedule':
        return TodaysScheduleWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
          projectNamesById: projectNamesById,
          allTasks: allTasks,
        );
      case 'time_clock':
        return TimeClockWidget(workspaceId: workspaceId, userId: userId);
      case 'pending_forms':
        return PendingFormsWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
        );
      case 'vehicle_equipment':
        return VehicleEquipmentWidget(workspaceId: workspaceId, userId: userId);
      case 'job_site_weather':
        return JobSiteWeatherWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
        );
      case 'photo_upload_queue':
        return PhotoUploadQueueWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
        );
      case 'safety_checklist':
        return SafetyChecklistWidget(workspaceId: workspaceId, userId: userId);
      case 'driving_directions':
        return DrivingDirectionsWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
          allTasks: allTasks,
        );
      case 'material_usage':
        return MaterialUsageWidget(
          workspaceId: workspaceId,
          userId: userId,
          allProjects: allProjects,
          projectNamesById: projectNamesById,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAllWidgetsHiddenState(DashboardEditController controller) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All dashboard widgets are hidden',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Use Customize to show widgets and arrange your dashboard.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.base),
            FilledButton.icon(
              onPressed: controller.resetDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Reset Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    DashboardEditController dashboardController,
  ) {
    final authProvider = context.watch<AuthProvider>();
    final userName = authProvider.appUser?.displayName ?? 'there';
    final firstName = userName.split(' ').first;

    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    final dateStr = DateFormat('EEEE, MMMM d').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dashboard content is wrapped in a light ColoredBox
                  // (see _buildResponsiveDashboard), so use the light text
                  // tokens directly — chrome.scaffoldText is white in
                  // dark-chrome mode and would be invisible here.
                  Text(
                    '$greeting, $firstName',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            ListenableBuilder(
              listenable: dashboardController,
              builder: (context, _) {
                final editing = dashboardController.editMode;
                if (!editing) {
                  // Icon + label: the icon-only button tested poorly for
                  // discoverability — "Customize" is the entry point to the
                  // whole layout system, so say its name.
                  return OutlinedButton.icon(
                    onPressed: dashboardController.toggleEditMode,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Customize'),
                  );
                }
                final saving = dashboardController.saving;
                return FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () => dashboardController.toggleEditMode(),
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(saving ? 'Saving…' : 'Done'),
                );
              },
            ),
          ],
        ),
        // Edit mode action bar
        ListenableBuilder(
          listenable: dashboardController,
          builder: (context, _) {
            if (!dashboardController.editMode) {
              return const SizedBox.shrink();
            }
            showSaveErrorIfAny(context, dashboardController);
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: EditToolbarActions(
                controller: dashboardController,
                onManage: () =>
                    showManageWidgetsSheet(context, dashboardController),
                onReset: () =>
                    showResetDashboardConfirmation(context, dashboardController),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _workspaceRefreshTimer?.cancel();
    _managerDashboardController.dispose();
    _fieldDashboardController.dispose();
    super.dispose();
  }
}
