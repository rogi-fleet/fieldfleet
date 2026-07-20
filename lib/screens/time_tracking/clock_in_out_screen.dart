import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/theme.dart';
import '../../models/time_entry.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../models/budget_item.dart';
import '../../services/service_locator.dart';
import '../../services/location_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';

import 'package:taskfleet_ops/widgets/common/module_header.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'widgets/time_tracking_view_bar.dart';
import 'widgets/time_tracking_pickers.dart';
import 'widgets/my_week_card.dart';
import 'widgets/recent_entries_strip.dart';

class ClockInOutScreen extends StatefulWidget {
  final String? projectId;
  final ValueChanged<TimeTrackingView>? onViewChanged;
  final bool showViewBar;
  // The "Time Tracking — Clock in/out, timesheets..." ModuleHeader is
  // redundant when this screen is hosted inside the project Tasks tab's
  // Time sub-section: the user already sees "Tasks > Time" chips above.
  // Standalone (workspace-level) usage keeps the header for orientation.
  final bool showModuleHeader;

  const ClockInOutScreen({
    super.key,
    this.projectId,
    this.onViewChanged,
    this.showViewBar = true,
    this.showModuleHeader = true,
  });

  @override
  State<ClockInOutScreen> createState() => _ClockInOutScreenState();
}

class _ClockInOutScreenState extends State<ClockInOutScreen> {
  dynamic get _timeEntryService => ServiceLocator.timeEntryService;
  dynamic get _projectService => ServiceLocator.projectService;
  final _taskService = ServiceLocator.taskService;
  dynamic get _budgetService => ServiceLocator.budgetService;

  TimeEntry? _activeEntry;
  bool _isLoading = false;
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  String? _selectedProjectId;
  String? _selectedTaskId;
  String? _selectedBudgetItemId;
  int _breakDuration = 0; // Minutes

  // GPS Location state
  Position? _currentLocation;
  bool _isGettingLocation = false;
  GeofenceCheckResult? _geofenceResult;
  Project? _selectedProjectDetails;
  bool _locationPermissionGranted = false;

  // Cached streams/futures keyed by (workspaceId, userId). Re-creating these
  // on every rebuild resets their StreamBuilder/FutureBuilder children to the
  // loading state, which causes a "continuously loading" flicker whenever a
  // provider notifies or the scroll-driven SliverAppBar parent rebuilds.
  String? _streamsKey;
  Stream<List<TimeEntry>>? _weekEntriesStream;
  Stream<List<TimeEntry>>? _recentEntriesStream;
  Stream<List<TimeEntry>>? _todayEntriesStream;
  Stream<List<Project>>? _projectsStream;
  Future<List<Project>>? _projectsOnceFuture;
  late DateTime _streamsBuiltAt;
  late DateTime _weekStart;
  late DateTime _weekEnd;
  late DateTime _sevenDaysAgo;
  late DateTime _startOfDay;
  late DateTime _endOfDay;

  // Cached project lookup for the active entry.
  String? _activeProjectFutureId;
  Future<Project?>? _activeProjectFuture;

  // Cached task / budget streams for the selected project.
  String? _projectScopedKey;
  Stream<List<Task>>? _tasksStream;
  Stream<List<BudgetItem>>? _budgetItemsStream;

  String get _projectTerminology =>
      context.read<WorkspaceProvider>().projectTerminology;

  String get _singularProjectTerminology =>
      singularProjectTerminology(_projectTerminology);

  String get _projectTerminologyLower => _projectTerminology.toLowerCase();

  String get _singularProjectTerminologyLower =>
      _singularProjectTerminology.toLowerCase();

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null) {
      _selectedProjectId = widget.projectId;
    }
    _loadActiveEntry();
    _initializeLocation();
  }

  void _ensureUserStreams(String workspaceId, String userId) {
    final key = '$workspaceId|$userId';
    final now = DateTime.now();
    final sameDay = _streamsKey != null &&
        _streamsBuiltAt.year == now.year &&
        _streamsBuiltAt.month == now.month &&
        _streamsBuiltAt.day == now.day;
    if (_streamsKey == key && sameDay) return;

    _streamsKey = key;
    _streamsBuiltAt = now;
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _weekEnd = _weekStart.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );
    _sevenDaysAgo = now.subtract(const Duration(days: 7));
    _startOfDay = DateTime(now.year, now.month, now.day);
    _endOfDay = _startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    _weekEntriesStream = _timeEntryService.getTimeEntriesForDateRange(
      userId,
      _weekStart,
      _weekEnd,
      workspaceId: workspaceId,
    ) as Stream<List<TimeEntry>>;
    _recentEntriesStream = _timeEntryService.getTimeEntriesForDateRange(
      userId,
      _sevenDaysAgo,
      now,
      workspaceId: workspaceId,
    ) as Stream<List<TimeEntry>>;
    _todayEntriesStream = _timeEntryService.getTimeEntriesForDateRange(
      userId,
      _startOfDay,
      _endOfDay,
      workspaceId: workspaceId,
    ) as Stream<List<TimeEntry>>;
    _projectsStream = _projectService.getProjects(workspaceId)
        as Stream<List<Project>>;
    _projectsOnceFuture = _projectService.getProjectsOnce(workspaceId)
        as Future<List<Project>>;
  }

  void _ensureProjectScopedStreams(String workspaceId, String projectId) {
    final key = '$workspaceId|$projectId';
    if (_projectScopedKey == key) return;
    _projectScopedKey = key;
    _tasksStream = _taskService.getTasks(projectId, workspaceId: workspaceId)
        as Stream<List<Task>>;
    _budgetItemsStream = _budgetService.getBudgetItems(
      projectId,
      workspaceId: workspaceId,
    ) as Stream<List<BudgetItem>>;
  }

  Future<Project?> _activeEntryProjectFuture(String projectId) {
    if (_activeProjectFutureId != projectId) {
      _activeProjectFutureId = projectId;
      _activeProjectFuture =
          _projectService.getProject(projectId) as Future<Project?>;
    }
    return _activeProjectFuture!;
  }

  Future<void> _initializeLocation() async {
    final locationService = LocationService();
    _locationPermissionGranted = await locationService.hasPermission();
    if (_locationPermissionGranted) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = position;
          _isGettingLocation = false;
        });
        if (_selectedProjectId != null) {
          _validateGeofence();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }

  Future<void> _validateGeofence() async {
    if (_selectedProjectId == null || _currentLocation == null) return;

    try {
      final project = await _projectService.getProject(_selectedProjectId!);
      if (project != null && mounted) {
        setState(() {
          _selectedProjectDetails = project;
        });

        final locationService = LocationService();
        final result = locationService.validateGeofence(
          workerPosition: _currentLocation!,
          project: project,
        );

        if (mounted) {
          setState(() {
            _geofenceResult = GeofenceCheckResult(
              canProceed:
                  result.isWithinGeofence ||
                  project.allowClockInOutsideGeofence,
              requiresValidation: project.requireGeofenceValidation,
              validationResult: result,
              warningMessage: result.isWithinGeofence ? null : result.message,
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error validating geofence: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveEntry() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id;
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (userId != null && workspaceId != null) {
        final activeEntry = await _timeEntryService.getActiveEntry(
          userId,
          workspaceId,
        );
        if (mounted) {
          setState(() {
            _activeEntry = activeEntry;
            _isLoading = false;
          });

          if (_activeEntry != null) {
            _startTimer();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Error loading active entry: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeEntry != null) {
        setState(() {
          _elapsedTime = DateTime.now().difference(_activeEntry!.clockIn);
        });
      }
    });
  }

  Future<void> _clockIn() async {
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a $_singularProjectTerminologyLower'),
        ),
      );
      return;
    }

    // Check geofence validation
    if (_geofenceResult?.canProceed == false) {
      _showGeofenceWarning();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id;
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      final workspaceProvider = context.read<WorkspaceProvider>();
      final activeWorkspace = workspaceProvider.activeWorkspace;
      final hourlyRate =
          activeWorkspace?.hourlyRate ??
          activeWorkspace?.defaultHourlyRate ??
          authProvider.appUser?.hourlyRate;

      if (userId == null || workspaceId == null) {
        throw Exception('User not authenticated');
      }

      if (hourlyRate == null || hourlyRate <= 0) {
        throw Exception(
          'Hourly rate not set. Please update your profile with an hourly rate before clocking in.',
        );
      }

      // Get fresh location before clocking in
      Position? location;
      if (_locationPermissionGranted) {
        location = await LocationService().getCurrentPosition();
      }

      final entry = await _timeEntryService.clockIn(
        workspaceId: workspaceId,
        workerId: userId,
        projectId: _selectedProjectId!,
        taskId: _selectedTaskId,
        budgetItemId: _selectedBudgetItemId,
        hourlyRate: hourlyRate,
        location: location,
      );

      if (mounted) {
        setState(() {
          _activeEntry = entry;
          _isLoading = false;
        });
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clocked in successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'clocking in')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showGeofenceWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_off, color: AppColors.warning),
            const SizedBox(width: 8),
            Text('Outside $_singularProjectTerminology Area'),
          ],
        ),
        content: Text(
          _geofenceResult?.warningMessage ??
              'You are outside the designated $_singularProjectTerminologyLower area. Clocking in from this location will be recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clockIn();
            },
            child: const Text('Clock In Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _clockOut() async {
    if (_activeEntry == null) return;

    setState(() => _isLoading = true);

    try {
      // Get fresh location before clocking out
      Position? location;
      if (_locationPermissionGranted) {
        location = await LocationService().getCurrentPosition();
      }

      await _timeEntryService.clockOut(
        _activeEntry!.id,
        breakDuration: _breakDuration,
        location: location,
      );

      if (mounted) {
        _timer?.cancel();
        setState(() {
          _activeEntry = null;
          _isLoading = false;
          _breakDuration = 0;
          _elapsedTime = Duration.zero;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clocked out successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'clocking out')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;

    final workspaceProvider = context.watch<WorkspaceProvider>();
    final activeWorkspace = workspaceProvider.activeWorkspace;
    final hourlyRate =
        activeWorkspace?.hourlyRate ??
        activeWorkspace?.defaultHourlyRate ??
        authProvider.appUser?.hourlyRate;
    final isAdmin = authProvider.canManageUsers;

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    if (userId != null) {
      _ensureUserStreams(workspaceId, userId);
    }

    return Scaffold(
      body: Column(
        children: [
          if (widget.showModuleHeader && widget.showViewBar)
            const ModuleHeader(
              icon: Icons.schedule_outlined,
              title: 'Time Tracking',
              description:
                  'Clock in/out, timesheets and labor cost capture for every job.',
            ),
          if (widget.showViewBar)
            TimeTrackingViewBar(
              currentView: TimeTrackingView.clock,
              onViewChanged: widget.onViewChanged,
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
                      final hPad = constraints.maxWidth >= 720 ? 24.0 : 16.0;
                      final isMobile = constraints.maxWidth < 720;
                      final platformBottomPad =
                          Theme.of(context).platform == TargetPlatform.iOS
                              ? 16.0
                              : 8.0;
                      final bottomPad = isMobile
                          ? MediaQuery.paddingOf(context).bottom +
                              platformBottomPad +
                              70 +
                              12
                          : 24.0;

                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(hPad, 16, hPad, bottomPad),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Clock card + My Week card ─────────────────
                            if (userId != null)
                              StreamBuilder<List<TimeEntry>>(
                                stream: _weekEntriesStream,
                                builder: (context, weekSnap) {
                                  final weekEntries = weekSnap.data ?? [];
                                  final weekLoading = weekSnap.connectionState ==
                                      ConnectionState.waiting;

                                  if (isWide) {
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _buildClockColumn(
                                            hourlyRate: hourlyRate,
                                            isAdmin: isAdmin,
                                            workspaceId: workspaceId,
                                            userId: userId,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: MyWeekCard(
                                            weekEntries: weekEntries,
                                            isLoading: weekLoading,
                                            isClockedIn: _activeEntry != null,
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  // Mobile: stacked
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 560,
                                          ),
                                          child: _buildClockColumn(
                                            hourlyRate: hourlyRate,
                                            isAdmin: isAdmin,
                                            workspaceId: workspaceId,
                                            userId: userId,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      MyWeekCard(
                                        weekEntries: weekEntries,
                                        isLoading: weekLoading,
                                        isClockedIn: _activeEntry != null,
                                      ),
                                    ],
                                  );
                                },
                              )
                            else
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 560),
                                  child: _buildClockColumn(
                                    hourlyRate: hourlyRate,
                                    isAdmin: isAdmin,
                                    workspaceId: workspaceId,
                                    userId: null,
                                  ),
                                ),
                              ),

                            // ── Recent entries strip ──────────────────────
                            if (userId != null) ...[
                              const SizedBox(height: 16),
                              FutureBuilder<List<Project>>(
                                future: _projectsOnceFuture,
                                builder: (context, projSnap) {
                                  final projectNames = {
                                    for (final p in projSnap.data ?? <Project>[])
                                      p.id: p.name,
                                  };
                                  return StreamBuilder<List<TimeEntry>>(
                                    stream: _recentEntriesStream,
                                    builder: (context, recentSnap) {
                                      return RecentEntriesStrip(
                                        entries: recentSnap.data ?? [],
                                        isLoading:
                                            recentSnap.connectionState ==
                                            ConnectionState.waiting,
                                        projectNames: projectNames,
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Clock-in UI column: the status hero + break input or job selection form.
  /// Extracted so it can be placed in either a one-column or two-column layout.
  Widget _buildClockColumn({
    required double? hourlyRate,
    required bool isAdmin,
    required String workspaceId,
    required String? userId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusHero(
          hourlyRateReady: hourlyRate != null && hourlyRate > 0,
        ),
        if (_activeEntry != null) ...[
          const SizedBox(height: 16),
          _buildBreakDurationInput(),
        ] else ...[
          if (hourlyRate == null || hourlyRate <= 0) ...[
            const SizedBox(height: 16),
            _buildMissingRateCard(isAdmin),
          ] else ...[
            const SizedBox(height: 16),
            _buildJobDetailsCard(workspaceId),
            const SizedBox(height: 16),
            _buildTodaySummaryCard(workspaceId, userId),
          ],
        ],
      ],
    );
  }

  Future<void> _showTodayLogDialog() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id;
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (userId == null || workspaceId == null) {
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Today's Log"),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<Project>>(
            future: _projectService.getProjectsOnce(workspaceId),
            builder: (context, projectSnapshot) {
              if (projectSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (projectSnapshot.hasError) {
                return Text(
                  UserFacingError.uiMessage(
                    projectSnapshot.error,
                    action: 'load projects',
                  ),
                );
              }

              final projects = projectSnapshot.data ?? [];
              final assignedProjectIds = projects
                  .where((project) => project.teamMemberIds.contains(userId))
                  .map((project) => project.id)
                  .toSet();

              if (assignedProjectIds.isEmpty) {
                return Text(
                  'No assigned $_projectTerminologyLower found for you.',
                );
              }

              return StreamBuilder<List<TimeEntry>>(
                stream: _timeEntryService.getTimeEntriesForDateRange(
                  userId,
                  startOfDay,
                  endOfDay,
                  workspaceId: workspaceId,
                ),
                builder: (context, entrySnapshot) {
                  if (entrySnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (entrySnapshot.hasError) {
                    return Text(
                      UserFacingError.uiMessage(
                        entrySnapshot.error,
                        action: 'load log',
                      ),
                    );
                  }

                  final entries = (entrySnapshot.data ?? [])
                      .where(
                        (entry) => assignedProjectIds.contains(entry.projectId),
                      )
                      .toList();

                  if (entries.isEmpty) {
                    return const Text('No entries yet today.');
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _buildLogRow(entry);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(TimeEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<Project?>(
                  future: _projectService.getProject(entry.projectId),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?.name ?? 'Loading...',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(entry.clockIn)} - ${entry.clockOut != null ? _formatTime(entry.clockOut!) : 'Active'}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.formattedDuration,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHero({required bool hourlyRateReady}) {
    if (_activeEntry != null) {
      return FutureBuilder<Project?>(
        future: _activeEntryProjectFuture(_activeEntry!.projectId),
        builder: (context, snapshot) {
          final projectName =
              snapshot.data?.name ?? 'Active $_singularProjectTerminologyLower';
          return Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroBadge(
                  icon: Icons.play_circle_fill,
                  label: 'Clocked in now',
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.successDark,
                ),
                const SizedBox(height: 16),
                Text(
                  _formatDuration(_elapsedTime),
                  style: TextStyle(
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successDark,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  projectName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Started at ${_formatTime(_activeEntry!.clockIn)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeroBadge(
                      icon: Icons.work_outline,
                      label: projectName,
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textPrimary,
                    ),
                    _buildHeroBadge(
                      icon: Icons.coffee_outlined,
                      label: 'Break $_breakDuration min',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildClockOutButton(),
              ],
            ),
          );
        },
      );
    }

    final selectedProjectName =
        _selectedProjectDetails?.name ??
        (widget.projectId != null && _selectedProjectId == widget.projectId
            ? '$_singularProjectTerminology preselected'
            : null);
    final helperText = _clockInHelperText(hourlyRateReady);
    final warningText = _clockInWarningText();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroBadge(
            icon: hourlyRateReady
                ? Icons.schedule
                : Icons.warning_amber_rounded,
            label: hourlyRateReady ? 'Ready to clock in' : 'Setup needed',
            backgroundColor: Colors.white,
            foregroundColor: hourlyRateReady
                ? AppColors.primaryDark
                : AppColors.warningDark,
          ),
          const SizedBox(height: 16),
          const Text(
            'Clock in fast from your phone',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selectedProjectName == null
                ? 'Choose a $_singularProjectTerminologyLower below, confirm your location, and start time tracking.'
                : 'You are about to clock into $selectedProjectName.',
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroBadge(
                icon: Icons.folder_outlined,
                label:
                    selectedProjectName ??
                    '$_singularProjectTerminology required',
                backgroundColor: Colors.white,
                foregroundColor: selectedProjectName == null
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
              // Only show the location badge here when no project is selected.
              // When a project is selected, the job details card already shows
              // a detailed location status card — showing the badge here too
              // would be redundant.
              if (_selectedProjectId == null)
                _buildHeroBadge(
                  icon: _locationStatusIcon(),
                  label: _locationStatusLabel(),
                  backgroundColor: Colors.white,
                  foregroundColor: _locationStatusColor(),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildClockInButton(),
          if (helperText != null) ...[
            const SizedBox(height: 10),
            Text(
              helperText,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (warningText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warningDark,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warningText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakDurationInput() {
    // A break can't exceed the time clocked so far. Cap the slider at the
    // elapsed minutes (rounded down, min 1 so the Slider stays valid) when
    // clocked in, and keep the recorded break within that bound.
    final elapsedMinutes = _activeEntry != null
        ? _elapsedTime.inMinutes
        : 120;
    final maxBreak = elapsedMinutes < 1 ? 1.0 : elapsedMinutes.toDouble();
    final cappedBreak = _breakDuration.toDouble().clamp(0.0, maxBreak);
    if (cappedBreak.toInt() != _breakDuration) {
      // Elapsed shrank below the set break (shouldn't normally happen) — pull
      // it back in on the next frame to avoid a Slider assertion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _breakDuration = cappedBreak.toInt());
      });
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Break Duration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: cappedBreak,
                    min: 0,
                    max: maxBreak,
                    divisions: maxBreak >= 1 ? maxBreak.toInt() : 1,
                    label: '${cappedBreak.toInt()} min',
                    onChanged: (value) {
                      setState(() {
                        _breakDuration = value.toInt();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: Text(
                    '$_breakDuration min',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingRateCard(bool isAdmin) {
    return Card(
      color: AppColors.secondarySurface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            Icon(Icons.warning, color: AppColors.warningDark, size: 48),
            const SizedBox(height: 12),
            Text(
              'Hourly Rate Not Set',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.warningDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Set a default wage in Workspace Settings or set a member wage in Team.'
                  : 'Ask a workspace admin to set your hourly wage or a workspace default.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (isAdmin)
                  ElevatedButton.icon(
                    onPressed: () {
                      context.go('/workspaces/settings');
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Workspace Settings'),
                  ),
                ElevatedButton.icon(
                  onPressed: () {
                    context.go('/team');
                  },
                  icon: const Icon(Icons.group),
                  label: Text(isAdmin ? 'Set Team Wage' : 'View Team'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobDetailsCard(String workspaceId) {
    return StreamBuilder<List<Project>>(
      stream: _projectsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Text(
                UserFacingError.uiMessage(
                  snapshot.error,
                  action: 'load $_projectTerminologyLower',
                ),
              ),
            ),
          );
        }

        final projects = snapshot.data ?? [];
        final activeProjects = projects
            .where((p) => !p.status.isClosed)
            .toList();
        final selectedProject = activeProjects.where((project) {
          return project.id == _selectedProjectId;
        }).firstOrNull;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_singularProjectTerminology details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.projectId != null
                      ? '$_singularProjectTerminology context is prefilled from where you opened this screen.'
                      : 'Pick the $_singularProjectTerminologyLower you are working on before you clock in.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: '$_singularProjectTerminology *',
                  child: Builder(
                    builder: (buttonContext) {
                      return TimeTrackingPickers.selectionButton(
                        icon: Icons.folder_outlined,
                        title:
                            selectedProject?.name ??
                            'Choose $_singularProjectTerminologyLower',
                        subtitle: activeProjects.isEmpty
                            ? 'No active $_projectTerminologyLower available'
                            : '${activeProjects.length} active ${projectTerminologyForCount(activeProjects.length, _projectTerminology).toLowerCase()}',
                        onTap: activeProjects.isEmpty
                            ? null
                            : () => _showProjectPicker(
                                  activeProjects,
                                  anchorContext: buttonContext,
                                ),
                      );
                    },
                  ),
                ),
                if (_selectedProjectId != null) ...[
                  const SizedBox(height: 16),
                  _buildLocationStatus(),
                  const SizedBox(height: 16),
                  _buildBudgetItemSelector(workspaceId),
                  const SizedBox(height: 16),
                  _buildTaskSelector(workspaceId),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskSelector(String workspaceId) {
    _ensureProjectScopedStreams(workspaceId, _selectedProjectId!);
    return TimeTrackingPickers.taskField(
      stream: _tasksStream!,
      selectedTaskId: _selectedTaskId,
      singularTermLower: _singularProjectTerminologyLower,
      onSelected: (task) {
        setState(() => _selectedTaskId = task?.id);
      },
    );
  }

  Widget _buildBudgetItemSelector(String workspaceId) {
    _ensureProjectScopedStreams(workspaceId, _selectedProjectId!);
    return TimeTrackingPickers.budgetItemField(
      stream: _budgetItemsStream!,
      selectedBudgetItemId: _selectedBudgetItemId,
      singularTermLower: _singularProjectTerminologyLower,
      onSelected: (item) {
        setState(() => _selectedBudgetItemId = item?.id);
      },
    );
  }


  Widget _buildClockInButton() {
    final isEnabled = _selectedProjectId != null;
    return FilledButton.icon(
      onPressed: isEnabled ? _clockIn : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 28),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Clock In',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (_selectedProjectDetails?.name != null)
            Text(
              _selectedProjectDetails!.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: AppSpacing.lg),
        backgroundColor: AppColors.success,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.72),
        disabledForegroundColor: AppColors.textSecondary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _buildClockOutButton() {
    return FilledButton.icon(
      onPressed: _clockOut,
      icon: const Icon(Icons.stop_circle_outlined, size: 26),
      label: const Text(
        'Clock Out',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: AppSpacing.lg),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _buildLocationStatus() {
    if (!_locationPermissionGranted) {
      return _buildInlineStatusCard(
        icon: Icons.location_off_outlined,
        iconColor: AppColors.warningDark,
        title: 'Location is off',
        subtitle:
            'Enable location so this clock-in can be verified at the job site.',
        backgroundColor: AppColors.warningLight,
        actionLabel: 'Enable',
        onAction: () async {
          final granted = await LocationService().requestLocationPermission();
          if (granted) {
            setState(() => _locationPermissionGranted = true);
            _getCurrentLocation();
          }
        },
      );
    }

    if (_isGettingLocation) {
      return _buildInlineStatusCard(
        icon: Icons.my_location,
        iconColor: AppColors.infoDark,
        title: 'Checking location',
        subtitle:
            'Confirming whether you are at the selected $_singularProjectTerminologyLower.',
        backgroundColor: AppColors.infoLight,
        leading: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_geofenceResult == null || _currentLocation == null) {
      return _buildInlineStatusCard(
        icon: Icons.location_searching,
        iconColor: AppColors.textSecondary,
        title: 'Location pending',
        subtitle:
            'Refresh to check your current distance from the $_singularProjectTerminologyLower.',
        backgroundColor: AppColors.surfaceAlt,
        actionLabel: 'Refresh',
        onAction: _getCurrentLocation,
      );
    }

    final isWithin = _geofenceResult!.isWithinGeofence;
    final distance = _geofenceResult?.validationResult?.distanceMeters;

    return _buildInlineStatusCard(
      icon: isWithin
          ? Icons.verified_user_outlined
          : Icons.warning_amber_rounded,
      iconColor: isWithin ? AppColors.successDark : AppColors.warningDark,
      title: isWithin
          ? 'On site'
          : 'Outside $_singularProjectTerminologyLower area',
      subtitle: distance == null
          ? 'Location confirmed.'
          : '${LocationService.formatDistance(distance)} from the $_singularProjectTerminologyLower',
      backgroundColor: isWithin
          ? AppColors.successLight
          : AppColors.warningLight,
      detailText: _geofenceResult!.hasWarning
          ? _geofenceResult!.warningMessage
          : null,
      actionLabel: 'Refresh',
      onAction: _getCurrentLocation,
    );
  }

  Widget _buildTodaySummaryCard(String workspaceId, String? userId) {
    if (userId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<Project>>(
      future: _projectsOnceFuture,
      builder: (context, projectSnapshot) {
        final projectLookup = {
          for (final project in projectSnapshot.data ?? <Project>[])
            project.id: project.name,
        };

        return StreamBuilder<List<TimeEntry>>(
          stream: _todayEntriesStream,
          builder: (context, entrySnapshot) {
            if (projectSnapshot.connectionState == ConnectionState.waiting ||
                entrySnapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (projectSnapshot.hasError || entrySnapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Text(
                    UserFacingError.uiMessage(
                      projectSnapshot.error ?? entrySnapshot.error,
                      action: 'load today\'s time',
                    ),
                  ),
                ),
              );
            }

            final entries = [...(entrySnapshot.data ?? <TimeEntry>[])];
            entries.sort((a, b) => a.clockIn.compareTo(b.clockIn));
            final summary = _TodaySummary.fromEntries(entries, projectLookup);

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showTodayLogDialog,
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: const Text('View log'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryMetric(
                            icon: Icons.timelapse,
                            label: 'Logged',
                            value: _formatHours(summary.totalHours),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryMetric(
                            icon: Icons.layers_outlined,
                            label: 'Entries',
                            value: '${summary.entryCount}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _buildSummaryMetric(
                        icon: Icons.work_outline,
                        label: 'Last job',
                        value: summary.lastProjectName,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildInlineStatusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color backgroundColor,
    String? detailText,
    String? actionLabel,
    VoidCallback? onAction,
    Widget? leading,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading ?? Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
          if (detailText != null) ...[
            const SizedBox(height: 10),
            Text(
              detailText,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryDark),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProjectPicker(
    List<Project> projects, {
    BuildContext? anchorContext,
  }) async {
    final selectedProject = await TimeTrackingPickers.showProjectPicker(
      context: context,
      projects: projects,
      currentProjectId: _selectedProjectId,
      singularTermLower: _singularProjectTerminologyLower,
      anchorContext: anchorContext,
    );

    if (selectedProject == null) return;

    setState(() {
      _selectedProjectId = selectedProject.id;
      _selectedTaskId = null;
      _selectedBudgetItemId = null;
      _selectedProjectDetails = selectedProject;
      _geofenceResult = null;
    });
    await _validateGeofence();
  }


  String? _clockInHelperText(bool hourlyRateReady) {
    if (!hourlyRateReady) {
      return 'Set a wage before clocking in.';
    }
    if (_selectedProjectId == null) {
      return 'Select a $_singularProjectTerminologyLower to enable clock in.';
    }
    if (_locationPermissionGranted && _geofenceResult == null) {
      return 'We are still checking your location.';
    }
    return null;
  }

  String? _clockInWarningText() {
    if (_geofenceResult?.canProceed == false) {
      return _geofenceResult?.warningMessage ??
          'You are outside the designated $_singularProjectTerminologyLower area.';
    }
    if (_geofenceResult?.hasWarning == true) {
      return _geofenceResult?.warningMessage;
    }
    return null;
  }

  IconData _locationStatusIcon() {
    if (!_locationPermissionGranted) {
      return Icons.location_off_outlined;
    }
    if (_isGettingLocation) {
      return Icons.my_location;
    }
    if (_geofenceResult == null || _currentLocation == null) {
      return Icons.location_searching;
    }
    return _geofenceResult!.isWithinGeofence
        ? Icons.verified_user_outlined
        : Icons.warning_amber_rounded;
  }

  Color _locationStatusColor() {
    if (!_locationPermissionGranted) {
      return AppColors.warningDark;
    }
    if (_isGettingLocation) {
      return AppColors.infoDark;
    }
    if (_geofenceResult == null || _currentLocation == null) {
      return AppColors.textSecondary;
    }
    return _geofenceResult!.isWithinGeofence
        ? AppColors.successDark
        : AppColors.warningDark;
  }

  String _locationStatusLabel() {
    if (!_locationPermissionGranted) {
      return 'Location off';
    }
    if (_isGettingLocation) {
      return 'Checking site';
    }
    if (_geofenceResult == null || _currentLocation == null) {
      return 'Location pending';
    }
    return _geofenceResult!.isWithinGeofence ? 'On site' : 'Outside site';
  }

  String _formatHours(double hours) {
    final rounded = hours.toStringAsFixed(
      hours.truncateToDouble() == hours ? 0 : 1,
    );
    return '$rounded h';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _TodaySummary {
  const _TodaySummary({
    required this.entryCount,
    required this.totalHours,
    required this.lastProjectName,
    required this.subtitle,
  });

  final int entryCount;
  final double totalHours;
  final String lastProjectName;
  final String subtitle;

  factory _TodaySummary.fromEntries(
    List<TimeEntry> entries,
    Map<String, String> projectLookup,
  ) {
    if (entries.isEmpty) {
      return const _TodaySummary(
        entryCount: 0,
        totalHours: 0,
        lastProjectName: 'None',
        subtitle: 'No time logged today yet.',
      );
    }

    final totalHours = entries.fold<double>(0, (sum, entry) {
      return sum +
          entry.regularHours +
          entry.overtimeHours +
          entry.doubleTimeHours;
    });
    final lastEntry = entries.last;
    final activeEntries = entries
        .where((entry) => entry.clockOut == null)
        .length;

    return _TodaySummary(
      entryCount: entries.length,
      totalHours: totalHours,
      lastProjectName: projectLookup[lastEntry.projectId] ?? 'Unknown',
      subtitle: activeEntries > 0
          ? '$activeEntries active session${activeEntries == 1 ? '' : 's'} right now.'
          : 'Last clock-in was at ${_formatStaticTime(lastEntry.clockIn)}.',
    );
  }

  static String _formatStaticTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

