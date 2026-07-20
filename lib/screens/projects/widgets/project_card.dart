import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../models/customer.dart';
import '../../../models/project_financial_summary.dart';
import '../../../models/project_health_score.dart';
import '../../../models/project_task_metrics.dart';
import '../../../models/project_status_theme.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../services/project_health_service.dart';

import '../../../models/user.dart';
import '../../../theme/theme.dart';
import '../../../widgets/project_form_popup.dart';
import '../../../widgets/project_health_badge.dart';
import '../../../widgets/common/card_placeholder_background.dart';
import '../../../utils/address_formatter.dart';
import '../../../utils/project_customer_name.dart';
import '../../../utils/project_terminology.dart';
import 'active_alerts_widget.dart';

class ProjectCard extends StatefulWidget {
  final Project project;
  final bool forceCompactLayout;
  final bool isFavorite;
  final ValueChanged<bool>? onFavoriteToggled;
  final bool isSelected;
  final bool selectionMode;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onLongPress;
  final ProjectTaskMetrics? taskMetrics;
  final Future<Customer?>? customerFuture;
  final Future<ProjectFinancialSummary>? financialsFuture;
  final Future<List<Task>>? tasksFuture;
  final Future<List<ProjectAlert>>? alertsFuture;
  final Future<Map<String, AppUser>>? workspaceUsersFuture;

  const ProjectCard({
    super.key,
    required this.project,
    this.forceCompactLayout = false,
    this.isFavorite = false,
    this.onFavoriteToggled,
    this.isSelected = false,
    this.selectionMode = false,
    this.onSelectionChanged,
    this.onLongPress,
    this.taskMetrics,
    this.customerFuture,
    this.financialsFuture,
    this.tasksFuture,
    this.alertsFuture,
    this.workspaceUsersFuture,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  late bool _isFavorite;
  late Future<List<ProjectAlert>> _alertsFuture;
  late Future<ProjectFinancialSummary> _financialsFuture;
  late Future<List<Task>> _tasksFuture;
  late Future<_ProjectCardTaskSnapshot> _taskSnapshotFuture;
  late Future<List<AppUser>> _teamMembersFuture;
  ProjectFinancialSummary? _financials;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
    _primeAsyncData();
  }

  @override
  void didUpdateWidget(ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      _isFavorite = widget.isFavorite;
    }
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.financialsFuture != widget.financialsFuture ||
        oldWidget.tasksFuture != widget.tasksFuture ||
        oldWidget.alertsFuture != widget.alertsFuture ||
        oldWidget.workspaceUsersFuture != widget.workspaceUsersFuture) {
      _primeAsyncData();
    }
  }

  void _primeAsyncData() {
    _financialsFuture =
        widget.financialsFuture ??
        (ServiceLocator.projectService.getProjectFinancials(project.id, project)
            as Future<ProjectFinancialSummary>);
    _alertsFuture = widget.alertsFuture ?? _buildAlertsFuture();
    _tasksFuture =
        widget.tasksFuture ??
        ServiceLocator.taskService
            .getTasks(project.id, workspaceId: project.workspaceId)
            .first;
    _taskSnapshotFuture = _buildTaskSnapshot();
    _teamMembersFuture = _buildTeamMembersFuture();
    _loadExtraData();
  }

  Future<_ProjectCardTaskSnapshot> _buildTaskSnapshot() async {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      return _ProjectCardTaskSnapshot.fromMetrics(metrics);
    }

    final tasks = await _tasksFuture;
    return _ProjectCardTaskSnapshot.fromTasks(tasks);
  }

  Future<List<ProjectAlert>> _buildAlertsFuture() async {
    try {
      final financials = await _financialsFuture;
      return ProjectAlertsEngine.generateAlerts(
        project,
        financialSummary: financials,
      );
    } catch (_) {
      return ProjectAlertsEngine.generateAlerts(project);
    }
  }

  Future<void> _loadExtraData() async {
    final projectId = project.id;
    try {
      final financials = await _financialsFuture;
      if (mounted && widget.project.id == projectId) {
        setState(() {
          _financials = financials;
        });
      }
    } catch (_) {
      // Silently fail — card renders without extra data
    }
  }

  Project get project => widget.project;
  bool get forceCompactLayout => widget.forceCompactLayout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile layout: < 600px width or when forced
        final isMobile =
            forceCompactLayout || constraints.maxWidth < AppBreakpoints.mobile;

        return GestureDetector(
          onLongPress: widget.onLongPress,
          child: Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.cardRadius,
              side: BorderSide(
                color: widget.isSelected
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.cardBorder,
                width: widget.isSelected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                InkWell(
                  onTap: widget.selectionMode
                      ? () =>
                            widget.onSelectionChanged?.call(!widget.isSelected)
                      : () => context.go('/projects/${project.id}'),
                  child: isMobile
                      ? _buildMobileLayout(context)
                      : _buildDesktopLayout(context),
                ),
                if (widget.selectionMode)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Checkbox(
                        value: widget.isSelected,
                        onChanged: (val) =>
                            widget.onSelectionChanged?.call(val ?? false),
                        side: const BorderSide(color: Colors.white, width: 2),
                        checkColor: Colors.white,
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Theme.of(context).colorScheme.primary;
                          }
                          return Colors.transparent;
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Desktop: Horizontal layout with photo on left
  Widget _buildDesktopLayout(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status color stripe on the left edge
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(AppRadius.lg),
              ),
            ),
          ),

          // Photo section (left side)
          _buildPhotoSection(context, isMobile: false),

          // Right side - Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top row: Project name and badges
                  _buildTopSection(context),
                  const SizedBox(height: AppSpacing.sm),

                  // Next Best Action
                  _buildNextBestAction(),
                  const SizedBox(height: AppSpacing.sm),

                  // Details grid (3 columns)
                  _buildDetailsSection(context),
                  const SizedBox(height: AppSpacing.md),

                  // Team avatars
                  _buildTeamAvatars(context),
                  const SizedBox(height: AppSpacing.md),

                  // Progress bar and action buttons row
                  _buildProgressRow(context),
                  const SizedBox(height: AppSpacing.md),

                  // Financial row
                  _buildFinancialRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile: Vertical layout with photo on top
  Widget _buildMobileLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine if this is a narrow card (2-column mobile layout)
        // Threshold of 280px covers 2-column layouts on screens up to 600px wide
        final isNarrowCard = constraints.maxWidth < 280;
        final padding = isNarrowCard ? 8.0 : 16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full-width photo with overlay (or compact for narrow)
            isNarrowCard
                ? _buildPhotoSection(
                    context,
                    isMobile: true,
                    isNarrowCard: true,
                  )
                : _buildUnifiedHeader(context),
            if (!isNarrowCard) const SizedBox(height: 4),

            // Content below
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Next Best Action (hide on narrow)
                  if (!isNarrowCard) ...[
                    _buildNextBestAction(),
                    const SizedBox(height: 12),
                  ],

                  // Quick stats badges
                  _buildQuickStats(
                    context,
                    isNarrowCard: isNarrowCard,
                    showProgressInline: !isNarrowCard,
                  ),
                  SizedBox(height: isNarrowCard ? 4 : 8),

                  // Progress bar
                  if (isNarrowCard) ...[
                    _buildProgressBar(context, isNarrowCard: true),
                    const SizedBox(height: 6),
                  ] else
                    const SizedBox(height: 8),

                  // Details grid (simplified for narrow cards)
                  _buildDetailsSection(context, isNarrowCard: isNarrowCard),
                  SizedBox(height: isNarrowCard ? 6 : 12),

                  // Team avatars (hide on narrow cards)
                  if (!isNarrowCard) ...[
                    _buildTeamAvatars(context),
                    const SizedBox(height: 12),
                  ],

                  // Financial row (hide on narrow)
                  if (!isNarrowCard) ...[
                    _buildFinancialRow(),
                    const SizedBox(height: 12),
                    _buildBottomMetaRow(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor() {
    return ProjectStatusTheme.color(project.status);
  }

  Widget _buildPhotoSection(
    BuildContext context, {
    required bool isMobile,
    bool isNarrowCard = false,
  }) {
    final badgePadding = isNarrowCard ? 8.0 : 12.0;
    final contentPadding = isNarrowCard ? 10.0 : 16.0;
    final titleFontSize = isNarrowCard ? 14.0 : 20.0;
    final addressFontSize = isNarrowCard ? 11.0 : 13.0;

    final Widget photoContent = Stack(
      children: [
        // Photo or placeholder (camera icon as in reference)
        Positioned.fill(
          child: project.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: project.photoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      _buildPhotoPlaceholder(isNarrowCard: isNarrowCard),
                )
              : _buildPhotoPlaceholder(isNarrowCard: isNarrowCard),
        ),

        // Phase badge overlay
        Positioned(
          top: badgePadding,
          left: badgePadding,
          child: _buildPhaseBadge(context, isNarrowCard: isNarrowCard),
        ),

        // Favorite star
        Positioned(
          top: badgePadding,
          right: badgePadding,
          child: _buildOverlayActions(isNarrowCard: isNarrowCard),
        ),

        // Health badge
        if (!isNarrowCard)
          Positioned(
            bottom: isMobile ? 40 : badgePadding,
            right: badgePadding,
            child: _buildHealthBadge(),
          ),

        // Project name overlay at bottom (mobile only)
        if (isMobile)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: contentPadding,
                vertical: isNarrowCard ? 8 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.name,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 3,
                          color: Colors.black54,
                        ),
                        Shadow(
                          offset: Offset(0, 0),
                          blurRadius: 8,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                    maxLines: isNarrowCard ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (project.address.isNotEmpty && !isNarrowCard) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            AddressFormatter.condense(project.address),
                            style: TextStyle(
                              fontSize: addressFontSize,
                              color: Colors.white.withValues(alpha: 0.9),
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );

    if (isMobile) {
      // Mobile: full width, aspect ratio based height for consistency
      final photoHeight = isNarrowCard ? 100.0 : 200.0;
      return SizedBox(
        height: photoHeight,
        width: double.infinity,
        child: photoContent,
      );
    } else {
      // Desktop: fixed width
      return Container(
        width: 180,
        constraints: const BoxConstraints(minHeight: 200),
        child: photoContent,
      );
    }
  }

  Widget _buildPhotoPlaceholder({bool isNarrowCard = false}) {
    return CardPlaceholderBackground(compact: isNarrowCard);
  }

  /// Unified header: full-width photo with frosted bottom overlay
  Widget _buildUnifiedHeader(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          // Full-width photo/gradient
          Positioned.fill(
            child: project.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: project.photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        _buildPhotoPlaceholder(),
                  )
                : _buildPhotoPlaceholder(),
          ),
          // Top-left: Phase badge
          Positioned(top: 12, left: 12, child: _buildPhaseBadge(context)),
          // Top-right: overflow menu + favorite star
          Positioned(top: 12, right: 12, child: _buildOverlayActions()),
          // Bottom: Frosted overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 32, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: project.name,
                    waitDuration: const Duration(milliseconds: 150),
                    child: Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Client name
                  _buildCustomerNameText(),
                  // Address
                  if (project.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      AddressFormatter.condense(project.address),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerNameText() {
    final textStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final fallbackName = projectBusinessName(project);

    if (widget.customerFuture == null) {
      return Text(
        fallbackName.isNotEmpty ? fallbackName : 'No Customer',
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
      );
    }

    return FutureBuilder<Customer?>(
      future: widget.customerFuture,
      builder: (context, snapshot) {
        final customerName = projectBusinessName(
          project,
          customer: snapshot.data,
        );
        return Text(
          customerName.isNotEmpty ? customerName : 'No Customer',
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
        );
      },
    );
  }

  Widget _buildDesktopCustomerName() {
    final textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    final fallbackName = projectBusinessName(project);

    if (fallbackName.isEmpty && widget.customerFuture == null) {
      return const SizedBox.shrink();
    }

    if (widget.customerFuture == null) {
      return Row(
        children: [
          Icon(Icons.business, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              fallbackName,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return FutureBuilder<Customer?>(
      future: widget.customerFuture,
      builder: (context, snapshot) {
        final customerName = projectBusinessName(
          project,
          customer: snapshot.data,
        );
        if (customerName.isEmpty) return const SizedBox.shrink();
        return Row(
          children: [
            Icon(Icons.business, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                customerName,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Health score row showing status label + score number
  Widget _buildHealthScoreRow({bool onDark = false}) {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      final score = _projectHealthScore(metrics: metrics);
      if (score == null) {
        return const SizedBox.shrink();
      }

      return _buildHealthScoreRowContent(
        score: score,
        totalTasks: metrics.totalCount,
        completedTasks: metrics.completedCount,
        overdueTasks: metrics.overdueCount,
        onDark: onDark,
      );
    }

    return FutureBuilder<_ProjectCardTaskSnapshot>(
      future: _taskSnapshotFuture,
      builder: (context, snapshot) {
        final taskSnapshot = snapshot.data ?? _ProjectCardTaskSnapshot.empty;
        final score = _projectHealthScore(taskSnapshot: taskSnapshot);
        if (score == null) {
          return const SizedBox.shrink();
        }

        return _buildHealthScoreRowContent(
          score: score,
          totalTasks: taskSnapshot.total,
          completedTasks: taskSnapshot.completed,
          overdueTasks: taskSnapshot.overdue,
          onDark: onDark,
        );
      },
    );
  }

  Widget _buildHealthScoreRowContent({
    required ProjectHealthScore score,
    required int totalTasks,
    required int completedTasks,
    required int overdueTasks,
    required bool onDark,
  }) {
    final tooltipMessage = _buildHealthTooltipMessage(
      score: score,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
    );
    final label = score.overallScore >= 70
        ? 'ON TRACK'
        : score.overallScore >= 40
        ? 'AT RISK'
        : 'CRITICAL';
    final labelColor = score.overallScore >= 70
        ? AppColors.success
        : score.overallScore >= 40
        ? AppColors.warning
        : AppColors.error;

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 250),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: labelColor.withValues(alpha: onDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(
                color: labelColor.withValues(alpha: onDark ? 0.7 : 0.45),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 12,
                  color: onDark ? Colors.white : labelColor,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: onDark
                        ? Colors.white.withValues(alpha: 0.96)
                        : AppColors.textPrimary,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: score.overallScore / 100,
                      backgroundColor: onDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : labelColor.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(labelColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ProjectHealthScore? _projectHealthScore({
    ProjectTaskMetrics? metrics,
    _ProjectCardTaskSnapshot? taskSnapshot,
  }) {
    const healthService = ProjectHealthService();

    if (metrics != null) {
      if (metrics.totalCount == 0) {
        return null;
      }

      return healthService.computeScoreFromMetrics(
        project: project,
        totalTasks: metrics.totalCount,
        completedTasks: metrics.completedCount,
        overdueTasks: metrics.overdueCount,
        financials: _financials,
      );
    }

    final snapshot = taskSnapshot ?? _ProjectCardTaskSnapshot.empty;
    if (snapshot.total == 0) {
      return null;
    }

    return healthService.computeScore(
      project: project,
      tasks: snapshot.tasks,
      financials: _financials,
    );
  }

  String _buildHealthTooltipMessage({
    required ProjectHealthScore score,
    required int totalTasks,
    required int completedTasks,
    required int overdueTasks,
  }) {
    return 'AI Health Score Inputs\n'
        'Schedule: ${score.scheduleScore}/100 (30%)\n'
        'Budget: ${score.budgetScore}/100 (25%)\n'
        'Task Velocity: ${score.taskVelocityScore}/100 (25%)\n'
        'Overdue Tasks: ${score.overdueTasksScore}/100 (20%)\n'
        '\n'
        'Tasks: $completedTasks/$totalTasks complete\n'
        'Open overdue: $overdueTasks\n'
        '\n'
        'Weighted total: ${score.overallScore}/100';
  }

  /// Next Best Action driven by highest priority active alert.
  Widget _buildNextBestAction() {
    return FutureBuilder<List<ProjectAlert>>(
      future: _alertsFuture,
      builder: (context, snapshot) {
        final alerts = snapshot.data ?? const <ProjectAlert>[];
        final topAlert = _pickTopPriorityAlert(alerts);
        final hasActiveAlert = topAlert != null;
        final severityColors = AppSeverityTheme.colors(
          hasActiveAlert ? topAlert.severity : AppSeverity.neutral,
          neutralBackground: AppColors.surface,
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: severityColors.background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: severityColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(
                hasActiveAlert ? topAlert.icon : Icons.auto_awesome,
                size: 16,
                color: severityColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasActiveAlert ? 'ACTIVE ALERT' : 'NEXT BEST ACTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: severityColors.label,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _nextActionCopy(topAlert),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: severityColors.accent),
            ],
          ),
        );
      },
    );
  }

  ProjectAlert? _pickTopPriorityAlert(List<ProjectAlert> alerts) {
    if (alerts.isEmpty) return null;
    final sortedAlerts = [
      ...alerts,
    ]..sort((a, b) => _alertPriority(a.type).compareTo(_alertPriority(b.type)));
    return sortedAlerts.first;
  }

  int _alertPriority(AlertType type) {
    switch (type) {
      case AlertType.overdue:
      case AlertType.budgetOverrun:
      case AlertType.laborOverBudget:
        return 0;
      case AlertType.behindSchedule:
      case AlertType.lowBudgetRemaining:
      case AlertType.laborNearBudget:
        return 1;
      case AlertType.noBudget:
        return 2;
    }
  }

  String _nextActionCopy(ProjectAlert? alert) {
    if (alert == null) {
      return 'No active alerts. Review upcoming milestones.';
    }

    switch (alert.type) {
      case AlertType.overdue:
        return 'Resolve schedule risk: ${alert.message}';
      case AlertType.budgetOverrun:
      case AlertType.lowBudgetRemaining:
      case AlertType.noBudget:
      case AlertType.laborOverBudget:
      case AlertType.laborNearBudget:
        return 'Review budget controls: ${alert.message}';
      case AlertType.behindSchedule:
        return 'Plan timeline recovery: ${alert.message}';
    }
  }

  /// Financial row showing Approved/Estimate, Profit and Margin in separate boxes
  Widget _buildFinancialRow() {
    if (_financials == null) return const SizedBox.shrink();

    final amount = _financials!.approvedPrice;
    final margin = _financials!.projectedMargin;
    final profit = _financials!.projectedProfit;
    final marginVisual = _getMarginCardColors(margin);
    final profitVisual = _getProfitCardColors(profit);
    final formattedAmount = '\$${_formatBudget(amount)}';
    final formattedProfit =
        '${profit < 0 ? '-\$' : '\$'}${_formatBudget(profit.abs())}';

    final isPreAward =
        project.status == ProjectStatus.lead ||
        project.status == ProjectStatus.bidding ||
        project.status == ProjectStatus.proposalSent;

    return InkWell(
      onTap: _onFinancialRowTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        children: [
          // Approved / Estimate box
          Expanded(
            child: _buildFinancialBox(
              label: isPreAward ? 'ESTIMATE' : 'APPROVED',
              value: formattedAmount,
              colors: AppSeverityTheme.colors(AppSeverity.neutral),
            ),
          ),
          const SizedBox(width: 8),
          // Profit box
          Expanded(
            child: _buildFinancialBox(
              label: 'PROFIT',
              value: formattedProfit,
              colors: profitVisual,
            ),
          ),
          const SizedBox(width: 8),
          // Margin box
          Expanded(
            child: _buildFinancialBox(
              label: 'MARGIN',
              value: '${margin.toStringAsFixed(1)}%',
              colors: marginVisual,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onFinancialRowTap() async {
    try {
      final rows = await Supabase.instance.client
          .from('generated_documents')
          .select('id')
          .eq('project_id', project.id)
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;

      if (rows.isNotEmpty) {
        context.go('/documents/${rows.first['id']}');
      } else {
        context.go('/projects/${project.id}/budget');
      }
    } catch (_) {
      if (!mounted) return;
      context.go('/projects/${project.id}/budget');
    }
  }

  Widget _buildFinancialBox({
    required String label,
    required String value,
    required AppSeverityColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.label,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.value,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  AppSeverityColors _getMarginCardColors(double margin) {
    if (margin < 0) {
      return AppSeverityTheme.colors(AppSeverity.error);
    }
    if (margin < 10) {
      return AppSeverityTheme.colors(AppSeverity.warning);
    }
    return AppSeverityTheme.colors(AppSeverity.neutral);
  }

  AppSeverityColors _getProfitCardColors(double profit) {
    if (profit < 0) {
      return AppSeverityTheme.colors(AppSeverity.error);
    }
    if (profit == 0) {
      return AppSeverityTheme.colors(AppSeverity.warning);
    }
    return AppSeverityTheme.colors(AppSeverity.neutral);
  }

  Widget _buildPhaseBadge(BuildContext context, {bool isNarrowCard = false}) {
    String phaseText;
    Color backgroundColor;
    Color textColor;

    phaseText = project.status.displayName;
    backgroundColor = ProjectStatusTheme.colorDark(project.status);
    textColor = AppColors.textOnDark;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrowCard ? 6 : 10,
        vertical: isNarrowCard ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        phaseText,
        style: TextStyle(
          color: textColor,
          fontSize: isNarrowCard ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildHealthBadge() {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      final score = _projectHealthScore(metrics: metrics);
      if (score == null) {
        return const SizedBox.shrink();
      }

      return ProjectHealthBadge(score: score, size: 34);
    }

    return FutureBuilder<_ProjectCardTaskSnapshot>(
      future: _taskSnapshotFuture,
      builder: (context, snapshot) {
        final taskSnapshot = snapshot.data ?? _ProjectCardTaskSnapshot.empty;
        final score = _projectHealthScore(taskSnapshot: taskSnapshot);
        if (score == null) {
          return const SizedBox.shrink();
        }
        return ProjectHealthBadge(score: score, size: 34);
      },
    );
  }

  Widget _buildFavoriteStar({bool isNarrowCard = false}) {
    final size = isNarrowCard ? 28.0 : 32.0;
    final iconSize = isNarrowCard ? 16.0 : 20.0;
    return GestureDetector(
      onTap: () {
        setState(() => _isFavorite = !_isFavorite);
        widget.onFavoriteToggled?.call(_isFavorite);
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
          size: iconSize,
          color: _isFavorite ? Colors.amber : Colors.white,
        ),
      ),
    );
  }

  Widget _buildOverlayActions({bool isNarrowCard = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOverflowMenuButton(isNarrowCard: isNarrowCard),
        if (widget.onFavoriteToggled != null) ...[
          const SizedBox(width: 8),
          _buildFavoriteStar(isNarrowCard: isNarrowCard),
        ],
      ],
    );
  }

  Widget _buildOverflowMenuButton({bool isNarrowCard = false}) {
    final size = isNarrowCard ? 28.0 : 32.0;
    final iconSize = isNarrowCard ? 16.0 : 20.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, size: iconSize, color: Colors.white),
        padding: EdgeInsets.zero,
        tooltip: 'More actions',
        color: Colors.white,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 12),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 18, color: AppColors.error),
                SizedBox(width: 12),
                Text('Delete', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          switch (value) {
            case 'edit':
              showProjectFormPopup(context, projectId: project.id);
              break;
            case 'delete':
              _showDeleteDialog(context);
              break;
          }
        },
      ),
    );
  }

  Widget _buildInlineTaskProgress({required double completionPercent}) {
    final percentLabel = '${(completionPercent * 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Task Progress',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              percentLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value: completionPercent,
            minHeight: 6,
            backgroundColor: AppColors.cardBorder,
            valueColor: AlwaysStoppedAnimation<Color>(
              completionPercent >= 1 ? AppColors.success : AppColors.info,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomMetaRow() {
    return Row(
      children: [
        _buildProjectIdBadge(),
        const SizedBox(width: 12),
        Expanded(child: _buildHealthScoreRow()),
      ],
    );
  }

  Widget _buildProjectIdBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text(
        _projectIdLabel(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String _projectIdLabel() {
    return project.serialNumber ?? '#${project.id.substring(0, 6)}';
  }

  String _formatDateShort(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _buildTopSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project name and quick stats row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project name and address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _buildDesktopCustomerName(),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          project.address.isNotEmpty
                              ? AddressFormatter.condense(project.address)
                              : 'No Address Added',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Quick stats
            _buildQuickStats(context),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickStats(
    BuildContext context, {
    bool isNarrowCard = false,
    bool showProgressInline = false,
  }) {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      return _buildQuickStatsContent(
        openTasks: metrics.openCount,
        overdueTasks: metrics.overdueCount,
        dueTasks: metrics.dueTodayCount,
        completionPercent: metrics.progressPercent / 100,
        isNarrowCard: isNarrowCard,
        showProgressInline: showProgressInline,
      );
    }

    return FutureBuilder<_ProjectCardTaskSnapshot>(
      future: _taskSnapshotFuture,
      builder: (context, snapshot) {
        final taskSnapshot = snapshot.data ?? _ProjectCardTaskSnapshot.empty;
        return _buildQuickStatsContent(
          openTasks: taskSnapshot.open,
          overdueTasks: taskSnapshot.overdue,
          dueTasks: taskSnapshot.dueToday,
          completionPercent: taskSnapshot.completionPercent,
          isNarrowCard: isNarrowCard,
          showProgressInline: showProgressInline,
        );
      },
    );
  }

  Widget _buildQuickStatsContent({
    required int openTasks,
    required int overdueTasks,
    required int dueTasks,
    required double completionPercent,
    required bool isNarrowCard,
    required bool showProgressInline,
  }) {
    if (isNarrowCard) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _buildSoftBadge(
            label: '',
            value: '$openTasks tasks',
            backgroundColor: AppColors.errorLight,
            textColor: AppColors.error,
            dotColor: AppColors.error,
            isCompact: true,
          ),
          if (project.estimatedBudget != null || project.contractAmount != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                '\$${_formatBudget(project.contractAmount ?? project.estimatedBudget!)}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      );
    }

    final statChildren = <Widget>[
      _buildStatBox(
        value: openTasks.toString(),
        label: 'Open',
        onTap: () => _openTaskMetricView('open'),
      ),
      const SizedBox(width: 8),
      _buildStatBox(
        value: overdueTasks.toString(),
        label: 'Overdue',
        isHighlighted: overdueTasks > 0,
        highlightColor: AppColors.error,
        onTap: () => _openTaskMetricView('overdue'),
      ),
      const SizedBox(width: 8),
      _buildStatBox(
        value: dueTasks.toString(),
        label: 'Due',
        isHighlighted: dueTasks > 0,
        highlightColor: AppColors.info,
        onTap: () => _openTaskMetricView('due'),
      ),
    ];

    if (!showProgressInline) {
      return Row(mainAxisSize: MainAxisSize.min, children: statChildren);
    }

    return Row(
      children: [
        ...statChildren,
        const SizedBox(width: 12),
        Expanded(
          child: _buildInlineTaskProgress(completionPercent: completionPercent),
        ),
      ],
    );
  }

  /// Stat box showing a number and label, with optional highlight
  Widget _buildStatBox({
    required String value,
    required String label,
    bool isHighlighted = false,
    Color? highlightColor,
    VoidCallback? onTap,
  }) {
    final borderColor = isHighlighted
        ? (highlightColor ?? AppColors.info)
        : AppColors.cardBorder;
    final textColor = isHighlighted
        ? (highlightColor ?? AppColors.info)
        : AppColors.textPrimary;

    final statBox = Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlighted
            ? (highlightColor ?? AppColors.info).withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isHighlighted ? textColor : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return statBox;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: statBox,
    );
  }

  void _openTaskMetricView(String metric) {
    if (widget.selectionMode) return;
    context.go(
      '/projects/${project.id}?tab=tasks&taskView=list&taskMetric=$metric',
    );
  }

  Widget _buildSoftBadge({
    required String label,
    required String value,
    required Color backgroundColor,
    required Color textColor,
    required Color dotColor,
    bool isCompact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 10,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(isCompact ? 4 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isCompact ? 4 : 6,
            height: isCompact ? 4 : 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          SizedBox(width: isCompact ? 4 : 6),
          Text(
            label.isEmpty ? value : '$label $value',
            style: TextStyle(
              fontSize: isCompact ? 10 : 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(
    BuildContext context, {
    bool isNarrowCard = false,
  }) {
    // Simplified single row for narrow cards - just dates
    if (isNarrowCard) {
      return Row(
        children: [
          const Icon(
            Icons.calendar_today,
            size: 10,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              project.startDate != null
                  ? _formatDateShort(project.startDate!)
                  : 'No date',
              style: const TextStyle(fontSize: 9, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text(
            ' → ',
            style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
          ),
          Expanded(
            child: Text(
              project.targetCompletionDate != null
                  ? _formatDateShort(project.targetCompletionDate!)
                  : 'No date',
              style: const TextStyle(fontSize: 9, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    // Compact date range row
    return Row(
      children: [
        Icon(Icons.calendar_today, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Text(
          project.startDate != null
              ? _formatDateShort(project.startDate!)
              : 'No date',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_forward,
            size: 12,
            color: AppColors.textTertiary,
          ),
        ),
        Text(
          project.targetCompletionDate != null
              ? _formatDateShort(project.targetCompletionDate!)
              : 'No date',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
      ],
    );
  }

  // Desktop: Progress bar with action buttons in same row
  Widget _buildProgressRow(BuildContext context) {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      return _buildProgressRowContent(metrics.progressPercent);
    }

    return FutureBuilder<_ProjectCardTaskSnapshot>(
      future: _taskSnapshotFuture,
      builder: (context, snapshot) {
        final taskSnapshot = snapshot.data ?? _ProjectCardTaskSnapshot.empty;
        return _buildProgressRowContent(taskSnapshot.completionPercent * 100);
      },
    );
  }

  Widget _buildProgressRowContent(double percentage) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Task Progress',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${percentage.toStringAsFixed(0)}% Complete',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 6,
                  backgroundColor: AppColors.cardBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    percentage == 100 ? AppColors.success : AppColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Mobile: Just the progress bar
  Widget _buildProgressBar(BuildContext context, {bool isNarrowCard = false}) {
    final metrics = widget.taskMetrics;
    if (metrics != null) {
      return _buildProgressBarContent(
        metrics.progressPercent,
        isNarrowCard: isNarrowCard,
      );
    }

    return FutureBuilder<_ProjectCardTaskSnapshot>(
      future: _taskSnapshotFuture,
      builder: (context, snapshot) {
        final taskSnapshot = snapshot.data ?? _ProjectCardTaskSnapshot.empty;
        return _buildProgressBarContent(
          taskSnapshot.completionPercent * 100,
          isNarrowCard: isNarrowCard,
        );
      },
    );
  }

  Widget _buildProgressBarContent(
    double percentage, {
    required bool isNarrowCard,
  }) {
    if (isNarrowCard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 4,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                percentage == 100 ? AppColors.success : AppColors.info,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Text(
          'Task Progress',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${percentage.toStringAsFixed(0)}% Complete',
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            '${percentage.toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatBudget(double budget) {
    if (budget >= 1000000) {
      return '${(budget / 1000000).toStringAsFixed(1)}M';
    } else if (budget >= 1000) {
      return '${(budget / 1000).toStringAsFixed(0)}K';
    }
    return budget.toStringAsFixed(0);
  }

  void _showDeleteDialog(BuildContext context) async {
    final projectTerminology = context.read<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $singular'),
        content: Text(
          'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ServiceLocator.projectService.deleteProject(project.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$singular deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting project'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildTeamAvatars(BuildContext context) {
    return FutureBuilder<List<AppUser>>(
      future: _teamMembersFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final members = snapshot.data!;
        const maxVisible = 5;
        final visibleMembers = members.take(maxVisible).toList();
        final overflow = members.length - maxVisible;
        final avatarStackWidth =
            ((overflow > 0
                    ? visibleMembers.length
                    : visibleMembers.length - 1) *
                22.0) +
            32.0;

        return Row(
          children: [
            Text(
              'Team',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            // Stacked avatars
            SizedBox(
              width: avatarStackWidth,
              height: 32,
              child: Stack(
                children: [
                  for (int i = 0; i < visibleMembers.length; i++)
                    Positioned(
                      left: i * 22.0,
                      child: _buildAvatar(visibleMembers[i], i == 0),
                    ),
                  if (overflow > 0)
                    Positioned(
                      left: visibleMembers.length * 22.0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '+$overflow',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatar(AppUser user, bool isProjectManager) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isProjectManager ? AppColors.warning : AppColors.surface,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
        ],
      ),
      child: ClipOval(
        child: user.profilePictureUrl != null
            ? CachedNetworkImage(
                imageUrl: user.profilePictureUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    _buildAvatarFallback(user),
              )
            : _buildAvatarFallback(user),
      ),
    );
  }

  Widget _buildAvatarFallback(AppUser user) {
    // Generate a consistent color based on user ID
    final colors = [
      AppColors.info,
      AppColors.success,
      AppColors.secondary,
      AppColors.messageAccent,
      AppColors.financialAccent,
      AppColors.primary,
      AppColors.error,
    ];
    final colorIndex = user.id.hashCode.abs() % colors.length;

    return Container(
      color: colors[colorIndex],
      child: Center(
        child: Text(
          user.getInitials(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<List<AppUser>> _buildTeamMembersFuture() async {
    try {
      final userIds = <String>{};

      if (project.projectManagerId != null) {
        userIds.add(project.projectManagerId!);
      }

      if (project.supervisorId != null) {
        userIds.add(project.supervisorId!);
      }

      userIds.addAll(project.teamMemberIds);

      final tasks = await _tasksFuture;

      for (final task in tasks) {
        if (task.assignedTo != null) {
          userIds.add(task.assignedTo!);
        }
      }

      if (userIds.isEmpty) {
        return const <AppUser>[];
      }

      final resolvedUsers = widget.workspaceUsersFuture != null
          ? await widget.workspaceUsersFuture!
          : <String, AppUser>{};

      List<AppUser> members;
      if (resolvedUsers.isNotEmpty) {
        members = userIds
            .map((userId) => resolvedUsers[userId])
            .whereType<AppUser>()
            .toList(growable: false);
      } else {
        final userService = ServiceLocator.userService;
        final loadedUsers = await Future.wait(
          userIds.map((userId) => userService.getUserById(userId)),
        );
        members = loadedUsers.whereType<AppUser>().toList(growable: false);
      }

      final projectManagerId = project.projectManagerId;
      final supervisorId = project.supervisorId;
      members.sort((a, b) {
        if (projectManagerId != null) {
          if (a.id == projectManagerId && b.id != projectManagerId) return -1;
          if (b.id == projectManagerId && a.id != projectManagerId) return 1;
        }
        if (supervisorId != null) {
          if (a.id == supervisorId && b.id != supervisorId) return -1;
          if (b.id == supervisorId && a.id != supervisorId) return 1;
        }
        final aName = (a.displayName ?? a.email).toLowerCase();
        final bName = (b.displayName ?? b.email).toLowerCase();
        return aName.compareTo(bName);
      });

      return members;
    } catch (e) {
      return [];
    }
  }
}

class _ProjectCardTaskSnapshot {
  final List<Task> tasks;
  final int total;
  final int completed;
  final int open;
  final int overdue;
  final int dueToday;

  const _ProjectCardTaskSnapshot({
    this.tasks = const <Task>[],
    this.total = 0,
    this.completed = 0,
    this.open = 0,
    this.overdue = 0,
    this.dueToday = 0,
  });

  static const empty = _ProjectCardTaskSnapshot();

  double get completionPercent => total > 0 ? completed / total : 0.0;

  factory _ProjectCardTaskSnapshot.fromTasks(List<Task> tasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final completed = tasks.where((task) => task.isComplete).length;
    final open = tasks.where((task) => !task.isComplete).length;
    final overdue = tasks
        .where((task) => !task.isComplete && task.isOverdue())
        .length;
    final dueToday = tasks.where((task) {
      if (task.isComplete || task.dueDate == null) return false;
      return task.dueDate!.isAfter(todayStart) &&
          task.dueDate!.isBefore(todayEnd);
    }).length;

    return _ProjectCardTaskSnapshot(
      tasks: tasks,
      total: tasks.length,
      completed: completed,
      open: open,
      overdue: overdue,
      dueToday: dueToday,
    );
  }

  factory _ProjectCardTaskSnapshot.fromMetrics(ProjectTaskMetrics metrics) {
    return _ProjectCardTaskSnapshot(
      total: metrics.totalCount,
      completed: metrics.completedCount,
      open: metrics.openCount,
      overdue: metrics.overdueCount,
      dueToday: metrics.dueTodayCount,
    );
  }
}
