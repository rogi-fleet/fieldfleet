import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/activity_item.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';

class RecentActivityWidget extends StatefulWidget {
  final String workspaceId;

  const RecentActivityWidget({super.key, required this.workspaceId});

  @override
  State<RecentActivityWidget> createState() => _RecentActivityWidgetState();
}

class _RecentActivityWidgetState extends State<RecentActivityWidget> {
  late Future<List<ActivityItem>> _activityFuture;

  @override
  void initState() {
    super.initState();
    _activityFuture = _loadActivity();
  }

  @override
  void didUpdateWidget(covariant RecentActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _activityFuture = _loadActivity();
    }
  }

  Future<List<ActivityItem>> _loadActivity() {
    return ServiceLocator.dashboardService.getRecentActivity(
      widget.workspaceId,
      limit: 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.activityAccentLight,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(
                    Icons.timeline,
                    color: AppColors.activityAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.iconGap),
                const Expanded(
                  child: Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),

            // Activity list
            FutureBuilder<List<ActivityItem>>(
              future: _activityFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState();
                }

                if (!snapshot.hasData) {
                  return _buildLoadingState();
                }

                final activities = snapshot.data!;

                if (activities.isEmpty) {
                  return _buildEmptyState();
                }

                return Column(
                  children: activities
                      .map(
                        (activity) => _ActivityTimelineItem(activity: activity),
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

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 150,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.base),
      child: Text(
        'Unable to load activity',
        style: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.timeline, size: 48, color: AppColors.cardBorder),
            SizedBox(height: AppSpacing.iconGap),
            Text(
              'No recent activity',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Activity will appear as you work',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTimelineItem extends StatelessWidget {
  final ActivityItem activity;

  const _ActivityTimelineItem({required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final route = activity.getRouteForEntity();
        context.go(route);
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline indicator
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getActivityColor().withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      activity.getIcon(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.iconGap),

            // Content
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  if (activity.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      activity.description!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (activity.userName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'by ${activity.userName}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
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

  Color _getActivityColor() {
    switch (activity.type) {
      case ActivityType.projectCreated:
      case ActivityType.projectUpdated:
      case ActivityType.projectCompleted:
        return AppColors.projectAccent;
      case ActivityType.taskCreated:
      case ActivityType.taskUpdated:
      case ActivityType.taskCompleted:
        return AppColors.taskAccent;
      case ActivityType.customerCreated:
        return AppColors.customerAccent;
      case ActivityType.invoiceCreated:
        return AppColors.invoiceAccent;
      case ActivityType.planUploaded:
        return AppColors.planAccent;
    }
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(timestamp);
    }
  }
}
