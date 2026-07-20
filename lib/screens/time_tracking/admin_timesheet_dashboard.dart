import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/time_entry.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';

import 'widgets/time_tracking_view_bar.dart';
import 'widgets/timesheet_kpi_strip.dart';
import 'widgets/live_crew_panel.dart';
import 'widgets/inline_approval_card.dart';
import 'widgets/week_summary_bars.dart';
import '../../theme/theme.dart';

const double _kOtRiskHours = 38.0;

class AdminTimesheetDashboard extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;

  final bool showViewBar;

  const AdminTimesheetDashboard({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
  });

  @override
  State<AdminTimesheetDashboard> createState() =>
      _AdminTimesheetDashboardState();
}

class _AdminTimesheetDashboardState extends State<AdminTimesheetDashboard> {
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _userService => ServiceLocator.userService;
  dynamic get _projectService => ServiceLocator.projectService;

  // Data caches from streams
  List<TimeEntry> _activeEntries = [];
  List<TimeEntry> _weekEntries = [];
  List<TimeEntry> _pendingEntries = [];

  // Look-up maps
  Map<String, AppUser> _usersMap = {};
  Map<String, Project> _projectsMap = {};

  bool _otBannerDismissed = false;
  bool _isProcessingApproval = false;
  bool _activeLoaded = false;
  bool _weekLoaded = false;
  bool _pendingLoaded = false;

  bool get _isLoading => !_activeLoaded || !_weekLoaded || !_pendingLoaded;

  StreamSubscription? _activeSub;
  StreamSubscription? _weekSub;
  StreamSubscription? _pendingSub;

  late String _workspaceId;
  late String _userId;

  // Pre-computed week hours per worker (for OT coloring)
  Map<String, double> get _weekHoursMap {
    final map = <String, double>{};
    for (final entry in _weekEntries) {
      final hours = entry.totalDuration / 60.0;
      map[entry.workerId] = (map[entry.workerId] ?? 0.0) + hours;
    }
    return map;
  }

  double get _totalWeekHours =>
      _weekHoursMap.values.fold(0.0, (a, b) => a + b);

  int get _otAlertCount =>
      _weekHoursMap.values.where((h) => h >= _kOtRiskHours).length;

  // Today's entries for the "off the clock" section
  List<TimeEntry> get _todayEntries {
    final today = DateTime.now();
    return _weekEntries.where((e) {
      return e.date.year == today.year &&
          e.date.month == today.month &&
          e.date.day == today.day;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // initState can't use context; subscribe after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final auth = context.read<AuthProvider>();
    _workspaceId = auth.appUser?.currentWorkspaceId ?? '';
    _userId = auth.appUser?.id ?? '';
    if (_workspaceId.isEmpty) return;

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    _activeSub = (_timeEntryService.getActiveTimeEntries(
      _workspaceId,
    ) as Stream<List<TimeEntry>>)
        .listen(_onActiveEntries, onError: _onStreamError);

    _weekSub = (_timeEntryService.getWorkspaceTimeEntriesForDateRange(
      _workspaceId,
      weekStart,
      weekEnd,
    ) as Stream<List<TimeEntry>>)
        .listen(_onWeekEntries, onError: _onStreamError);

    _pendingSub = (_timeEntryService.getPendingTimeEntries(
      _workspaceId,
    ) as Stream<List<TimeEntry>>)
        .listen(_onPendingEntries, onError: _onStreamError);
  }

  List<TimeEntry> _scope(List<TimeEntry> entries) {
    final pid = widget.projectId;
    if (pid == null) return entries;
    return entries.where((e) => e.projectId == pid).toList();
  }

  void _onActiveEntries(List<TimeEntry> entries) {
    if (!mounted) return;
    final scoped = _scope(entries);
    setState(() {
      _activeEntries = scoped;
      _activeLoaded = true;
    });
    _loadUsersAndProjects(scoped);
  }

  void _onWeekEntries(List<TimeEntry> entries) {
    if (!mounted) return;
    final scoped = _scope(entries);
    setState(() {
      _weekEntries = scoped;
      _weekLoaded = true;
    });
    _loadUsersAndProjects(scoped);
  }

  void _onPendingEntries(List<TimeEntry> entries) {
    if (!mounted) return;
    final scoped = _scope(entries);
    setState(() {
      _pendingEntries = scoped;
      _pendingLoaded = true;
    });
    _loadUsersAndProjects(scoped);
  }

  void _onStreamError(Object error) {
    if (!mounted) return;
    // Mark all as loaded so the loading state resolves
    setState(() {
      _activeLoaded = true;
      _weekLoaded = true;
      _pendingLoaded = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Failed to load timesheet data. Pull to retry.'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  Future<void> _loadUsersAndProjects(List<TimeEntry> entries) async {
    final missingUserIds = entries
        .map((e) => e.workerId)
        .where((id) => !_usersMap.containsKey(id))
        .toSet();

    final missingProjectIds = entries
        .map((e) => e.projectId)
        .where((id) => !_projectsMap.containsKey(id))
        .toSet();

    if (missingUserIds.isEmpty && missingProjectIds.isEmpty) return;

    final futures = <Future>[
      for (final uid in missingUserIds)
        (_userService.getUserById(uid) as Future<AppUser?>)
            .then((u) {
          if (u != null && mounted) {
            setState(() => _usersMap = {..._usersMap, uid: u});
          }
        }),
      for (final pid in missingProjectIds)
        (_projectService.getProject(pid) as Future<Project?>)
            .then((p) {
          if (p != null && mounted) {
            setState(() => _projectsMap = {..._projectsMap, pid: p});
          }
        }),
    ];

    await Future.wait(futures);
  }

  @override
  void dispose() {
    _activeSub?.cancel();
    _weekSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  Future<void> _approve(TimeEntry entry) async {
    setState(() => _isProcessingApproval = true);
    try {
      await _timeEntryService.approveTimeEntry(entry.id, _userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingApproval = false);
    }
  }

  Future<void> _approveAll(List<TimeEntry> entries) async {
    setState(() => _isProcessingApproval = true);
    try {
      await Future.wait(
        entries.map((e) => _timeEntryService.approveTimeEntry(e.id, _userId) as Future),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve all: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingApproval = false);
    }
  }

  Future<void> _reject(TimeEntry entry) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provide a reason so the worker knows what to fix.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Missing project assignment…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();

    setState(() => _isProcessingApproval = true);
    try {
      await _timeEntryService.rejectTimeEntry(entry.id, _userId, reason);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingApproval = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final dateRangeLabel =
        '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekEnd)}';
    final hasOtAlerts = _otAlertCount > 0 && !_otBannerDismissed;

    return Scaffold(
      body: Column(
        children: [
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.dashboard,
              onViewChanged: widget.onViewChanged,
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Page header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Time Tracking',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Week of $dateRangeLabel',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // My timesheet shortcut
                            OutlinedButton.icon(
                              onPressed: () => context.go('/time-tracking'),
                              icon: const Icon(Icons.timer_outlined, size: 16),
                              label: const Text('My Timesheet'),
                              style: OutlinedButton.styleFrom(
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // OT alert banner
                        if (hasOtAlerts)
                          _OtAlertBanner(
                            count: _otAlertCount,
                            onDismiss: () =>
                                setState(() => _otBannerDismissed = true),
                            onReview: () =>
                                context.go('/time-tracking/employees'),
                          ),
                        if (hasOtAlerts) const SizedBox(height: 14),
                        // KPI strip
                        TimesheetKpiStrip(
                          activeWorkers: _activeEntries.length,
                          totalWorkers: _weekHoursMap.length,
                          weekTotalHours: _totalWeekHours,
                          pendingApprovals: _pendingEntries.length,
                          otAlerts: _otAlertCount,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                // Responsive body
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 820;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left column: live crew
                              Expanded(
                                flex: 6,
                                child: LiveCrewPanel(
                                  activeEntries: _activeEntries,
                                  todayEntries: _todayEntries,
                                  usersMap: _usersMap,
                                  projectsMap: _projectsMap,
                                  weekHoursMap: _weekHoursMap,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Right column: approvals + week summary
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    InlineApprovalPanel(
                                      pendingEntries: _pendingEntries,
                                      usersMap: _usersMap,
                                      projectsMap: _projectsMap,
                                      onApprove: _approve,
                                      onReject: _reject,
                                      onApproveAll: _approveAll,
                                      isProcessing: _isProcessingApproval,
                                    ),
                                    const SizedBox(height: 16),
                                    WeekSummaryBars(
                                      weekEntries: _weekEntries,
                                      usersMap: _usersMap,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        // Mobile: stacked
                        return Column(
                          children: [
                            LiveCrewPanel(
                              activeEntries: _activeEntries,
                              todayEntries: _todayEntries,
                              usersMap: _usersMap,
                              projectsMap: _projectsMap,
                              weekHoursMap: _weekHoursMap,
                            ),
                            const SizedBox(height: 14),
                            InlineApprovalPanel(
                              pendingEntries: _pendingEntries,
                              usersMap: _usersMap,
                              projectsMap: _projectsMap,
                              onApprove: _approve,
                              onReject: _reject,
                              isProcessing: _isProcessingApproval,
                            ),
                            const SizedBox(height: 14),
                            WeekSummaryBars(
                              weekEntries: _weekEntries,
                              usersMap: _usersMap,
                            ),
                          ],
                        );
                      },
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
}

class _OtAlertBanner extends StatelessWidget {
  final int count;
  final VoidCallback onDismiss;
  final VoidCallback onReview;

  const _OtAlertBanner({
    required this.count,
    required this.onDismiss,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF92400E),
                ),
                children: [
                  TextSpan(
                    text: '$count worker${count == 1 ? '' : 's'} ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text:
                        'approaching or over overtime this week. Review before the period closes.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onReview,
            child: const Text(
              'Review →',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.warningDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              size: 14,
              color: const Color(0xFF92400E).withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
