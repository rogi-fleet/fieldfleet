import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'widgets/project_sub_tab.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../utils/project_terminology.dart';
import '../../models/activity_item.dart';
import '../../widgets/price_type_badge.dart';
import '../../widgets/projects/ai_project_risk_card.dart';
import '../../widgets/projects/ai_schedule_optimizer_card.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import 'widgets/kpi_dashboard_widget.dart';
import '../../widgets/adaptive_navigation.dart';

class ProjectDashboardScreen extends StatefulWidget {
  const ProjectDashboardScreen({super.key});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  dynamic get _dashboardService => ServiceLocator.dashboardService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null || workspaceId.isEmpty) {
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

    return TabSwitchNotifier(controller: _tabController, child: Column(
      children: [
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            padding: EdgeInsets.zero,
            tabAlignment: TabAlignment.start,
            tabs: [
              projectSubTab(icon: Icons.history, label: 'Activity'),
              projectSubTab(icon: Icons.dashboard_outlined, label: 'Overview'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: [
              _buildRecentActivityTab(workspaceId),
              _buildOverviewTab(workspaceId),
            ],
          ),
        ),
      ],
    ));
  }

  Widget _buildOverviewTab(String workspaceId) {
    final userId = context.read<AuthProvider>().appUser?.id;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          KpiDashboardWidget(workspaceId: workspaceId),
          const SizedBox(height: AppSpacing.base),
          if (userId != null) ...[
            AiProjectRiskCard(workspaceId: workspaceId, userId: userId),
            const SizedBox(height: AppSpacing.base),
            AiScheduleOptimizerCard(workspaceId: workspaceId, userId: userId),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentActivityTab(String workspaceId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: _buildActivityCard(workspaceId),
    );
  }

  Widget _buildActivityCard(String workspaceId) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.cardPadding),
            _buildActivityList(workspaceId),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(String workspaceId) {
    return FutureBuilder<List<ActivityItem>>(
      future: _dashboardService.getRecentActivity(workspaceId, limit: 50),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final activities = snapshot.data ?? [];

        if (activities.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timeline,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  const Text(
                    'No recent activity',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Activity will appear here as you work',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: activities
              .map((activity) => _ActivityCard(activity: activity))
              .toList(),
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ActivityItem activity;

  const _ActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final relativeTime = _getRelativeTime(activity.timestamp);
    final isProjectActivity =
        activity.type == ActivityType.projectCreated ||
        activity.type == ActivityType.projectUpdated;

    // Extract project data from metadata for projects
    final photoUrl = isProjectActivity
        ? (activity.metadata?['photoUrl'] as String?)
        : null;
    final projectName = isProjectActivity
        ? (activity.metadata?['name'] as String?)
        : null;
    final customerName = isProjectActivity
        ? (activity.metadata?['customerName'] as String?)
        : null;
    final contractAmount = isProjectActivity
        ? (activity.metadata?['contractAmount'] as double?)
        : null;
    final status = isProjectActivity
        ? (activity.metadata?['status'] as String?)
        : null;
    final city = isProjectActivity
        ? (activity.metadata?['city'] as String?)
        : null;
    final state = isProjectActivity
        ? (activity.metadata?['state'] as String?)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: () {
          final route = activity.getRouteForEntity();
          context.go(route);
        },
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: isProjectActivity
              ? _buildProjectActivityCard(
                  context,
                  photoUrl: photoUrl,
                  projectName: projectName,
                  customerName: customerName,
                  contractAmount: contractAmount,
                  status: status,
                  city: city,
                  state: state,
                  relativeTime: relativeTime,
                  userName: activity.userName,
                  activityTitle: activity.title,
                )
              : _buildGenericActivityCard(context, relativeTime: relativeTime),
        ),
      ),
    );
  }

  Widget _buildProjectActivityCard(
    BuildContext context, {
    required String? photoUrl,
    required String? projectName,
    required String? customerName,
    required double? contractAmount,
    required String? status,
    required String? city,
    required String? state,
    required String relativeTime,
    required String? userName,
    required String activityTitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project Image or Placeholder
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: AppColors.surfaceAlt,
          ),
          clipBehavior: Clip.antiAlias,
          child: photoUrl != null && photoUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => _buildImagePlaceholder(),
                )
              : _buildImagePlaceholder(),
        ),
        const SizedBox(width: AppSpacing.base),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project Name
              if (projectName != null && projectName.isNotEmpty)
                Text(
                  projectName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              const SizedBox(height: 4),
              // Activity Title
              Text(
                substituteProjectTerminology(
                  activityTitle,
                  context.watch<WorkspaceProvider>().projectTerminology,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Status Badge
              if (status != null && status.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(status),
                        size: 12,
                        color: _getStatusColor(status),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Time (Right aligned)
        Text(
          relativeTime,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.schedule;
      case 'complete':
        return Icons.check_circle;
      case 'bidding':
        return Icons.gavel;
      default:
        return Icons.circle;
    }
  }

  Widget _buildGenericActivityCard(
    BuildContext context, {
    required String relativeTime,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Center(
            child: Text(
              activity.getIcon(),
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.base),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                substituteProjectTerminology(
                  activity.title,
                  context.watch<WorkspaceProvider>().projectTerminology,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              if (activity.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  activity.description!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Time
        Text(
          relativeTime,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: AppColors.surfaceAlt,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppColors.info;
      case 'complete':
        return AppColors.success;
      case 'bidding':
        return AppColors.secondary;
      default:
        return AppColors.textTertiary;
    }
  }

  String _getRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      return DateFormat('MMM d').format(timestamp);
    }
  }
}

class ProjectListTile extends StatelessWidget {
  final Project project;

  const ProjectListTile({super.key, required this.project});

  Color _getStatusColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.base),
        title: Text(
          project.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(AddressFormatter.condense(project.address)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    project.status.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: _getStatusColor(
                    project.status,
                  ).withValues(alpha: 0.2),
                  labelStyle: TextStyle(color: _getStatusColor(project.status)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                PriceTypeBadge(priceType: project.priceType),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.go('/projects/${project.id}');
        },
      ),
    );
  }
}
