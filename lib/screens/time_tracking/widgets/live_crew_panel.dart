import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../utils/safe_map_bounds.dart';
import '../../../models/time_entry.dart';
import '../../../models/user.dart';
import '../../../models/project.dart';
import 'package:intl/intl.dart';
import '../../../theme/theme.dart';

const double _kOtRiskHours = 38.0;
const double _kOtHours = 40.0;

/// Shows who is currently clocked in, with elapsed time and OT risk indicators,
/// and a flutter_map showing their GPS clock-in locations.
class LiveCrewPanel extends StatefulWidget {
  final List<TimeEntry> activeEntries;
  /// All workspace entries for today (for "off the clock" section).
  final List<TimeEntry> todayEntries;
  final Map<String, AppUser> usersMap;
  final Map<String, Project> projectsMap;
  /// Pre-aggregated week hours per worker (for OT risk color).
  final Map<String, double> weekHoursMap;

  const LiveCrewPanel({
    super.key,
    required this.activeEntries,
    required this.todayEntries,
    required this.usersMap,
    required this.projectsMap,
    required this.weekHoursMap,
  });

  @override
  State<LiveCrewPanel> createState() => _LiveCrewPanelState();
}

class _LiveCrewPanelState extends State<LiveCrewPanel> {
  final MapController _mapController = MapController();
  String? _focusedWorkerId;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    // Refresh elapsed times every 30 seconds so crew rows stay live.
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // Workers who clocked out today (not currently active), deduplicated per worker.
  List<TimeEntry> get _offClockToday {
    final activeIds = widget.activeEntries.map((e) => e.workerId).toSet();
    // Keep only the most recent completed entry per worker.
    final byWorker = <String, TimeEntry>{};
    for (final e in widget.todayEntries) {
      if (activeIds.contains(e.workerId) || e.clockOut == null) continue;
      final existing = byWorker[e.workerId];
      if (existing == null || e.clockOut!.isAfter(existing.clockOut!)) {
        byWorker[e.workerId] = e;
      }
    }
    return byWorker.values.toList()
      ..sort((a, b) => b.clockOut!.compareTo(a.clockOut!));
  }

  // Active entries with GPS coords.
  List<TimeEntry> get _mappableActive => widget.activeEntries
      .where((e) => e.clockInLatitude != null && e.clockInLongitude != null)
      .toList();

  // Off-clock entries with GPS coords (most recent per worker, already deduped by _offClockToday).
  List<TimeEntry> get _mappableOff => _offClockToday
      .where((e) => e.clockInLatitude != null && e.clockInLongitude != null)
      .toList();

  bool get _hasMapData => _mappableActive.isNotEmpty || _mappableOff.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                _PulseDot(color: const Color(0xFF4ADE80)),
                const SizedBox(width: 8),
                Text(
                  'Live Crew — On the Clock',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.activeEntries.length} active',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => context.go('/time-tracking/employees'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Full schedule', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          // Active workers
          if (widget.activeEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'No one is clocked in right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.activeEntries.length,
              itemBuilder: (_, i) {
                final entry = widget.activeEntries[i];
                final weekHours = widget.weekHoursMap[entry.workerId] ?? 0.0;
                final hasGps = entry.clockInLatitude != null &&
                    entry.clockInLongitude != null;
                return _CrewRow(
                  entry: entry,
                  user: widget.usersMap[entry.workerId],
                  project: widget.projectsMap[entry.projectId],
                  weekHours: weekHours,
                  isSelected: _focusedWorkerId == entry.workerId,
                  onTap: hasGps ? () => _focusMarker(entry) : null,
                );
              },
            ),
          // Off the clock section
          if (_offClockToday.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Off the clock today',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _offClockToday.length,
              itemBuilder: (_, i) {
                final entry = _offClockToday[i];
                final weekHours = widget.weekHoursMap[entry.workerId] ?? 0.0;
                final hasGps = entry.clockInLatitude != null &&
                    entry.clockInLongitude != null;
                return Opacity(
                  opacity: 0.55,
                  child: _CrewRow(
                    entry: entry,
                    user: widget.usersMap[entry.workerId],
                    project: widget.projectsMap[entry.projectId],
                    weekHours: weekHours,
                    isOff: true,
                    onTap: hasGps ? () => _focusMarker(entry) : null,
                  ),
                );
              },
            ),
          ],
          // Map
          if (_hasMapData) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            SizedBox(
              height: 300,
              child: _CrewMap(
                activeEntries: _mappableActive,
                offEntries: _mappableOff,
                usersMap: widget.usersMap,
                projectsMap: widget.projectsMap,
                weekHoursMap: widget.weekHoursMap,
                controller: _mapController,
                focusedWorkerId: _focusedWorkerId,
              ),
            ),
            // Map legend
            Container(
              color: theme.colorScheme.surfaceContainerLowest,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Clock-in locations',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  _LegendDot(color: AppColors.success, label: 'Active'),
                  const SizedBox(width: 10),
                  _LegendDot(color: AppColors.error, label: 'OT Risk'),
                  const SizedBox(width: 10),
                  _LegendDot(color: AppColors.textTertiary, label: 'Off Clock'),
                  const Spacer(),
                  Text(
                    kIsWeb ? 'Click row to zoom' : 'Tap row to zoom',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  void _focusMarker(TimeEntry entry) {
    if (entry.clockInLatitude == null || entry.clockInLongitude == null) return;
    setState(() => _focusedWorkerId = entry.workerId);
    _mapController.move(
      LatLng(entry.clockInLatitude!, entry.clockInLongitude!),
      15.5,
    );
  }
}

// ---------------------------------------------------------------------------
// Crew row
// ---------------------------------------------------------------------------

class _CrewRow extends StatelessWidget {
  final TimeEntry entry;
  final AppUser? user;
  final Project? project;
  final double weekHours;
  final bool isOff;
  final bool isSelected;
  final VoidCallback? onTap;

  const _CrewRow({
    required this.entry,
    required this.user,
    required this.project,
    required this.weekHours,
    this.isOff = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOtRisk = weekHours >= _kOtHours;
    final isApproaching = weekHours >= _kOtRiskHours && !isOtRisk;
    final name = user?.displayName ?? user?.email ?? 'Unknown';
    final initials = _initials(name);
    final projectName = project?.name ?? 'Unknown project';
    final elapsed = isOff
        ? _fmtHours(entry.totalDuration / 60.0)
        : _elapsed(entry.clockIn);
    final clockIn = entry.clockOut == null
        ? 'Since ${DateFormat('h:mm a').format(entry.clockIn)}'
        : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          border: isOtRisk && !isOff
              ? Border(
                  left: BorderSide(
                    color: theme.colorScheme.error,
                    width: 3,
                  ),
                )
              : isApproaching && !isOff
                  ? const Border(
                      left: BorderSide(
                        color: Color(0xFFF97316),
                        width: 3,
                      ),
                    )
                  : null,
        ),
        child: Row(
          children: [
            _Avatar(
              initials: initials,
              userId: entry.workerId,
              isOff: isOff,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((isOtRisk || isApproaching) && !isOff) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isOtRisk
                                ? AppColors.errorLight
                                : AppColors.warningLight,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            isOtRisk ? 'OT' : 'OT RISK',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: isOtRisk
                                  ? AppColors.error
                                  : AppColors.warningDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    projectName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!isOff)
              _PulseDot(
                color: isOtRisk
                    ? const Color(0xFFF97316)
                    : const Color(0xFF4ADE80),
              ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  elapsed,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isOtRisk && !isOff
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
                Text(
                  clockIn,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _elapsed(DateTime start) {
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  String _fmtHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

// ---------------------------------------------------------------------------
// flutter_map
// ---------------------------------------------------------------------------

class _CrewMap extends StatelessWidget {
  final List<TimeEntry> activeEntries;
  final List<TimeEntry> offEntries;
  final Map<String, AppUser> usersMap;
  final Map<String, Project> projectsMap;
  final Map<String, double> weekHoursMap;
  final MapController controller;
  final String? focusedWorkerId;

  const _CrewMap({
    required this.activeEntries,
    required this.offEntries,
    required this.usersMap,
    required this.projectsMap,
    required this.weekHoursMap,
    required this.controller,
    required this.focusedWorkerId,
  });

  List<TimeEntry> get _allEntries => [...activeEntries, ...offEntries];

  @override
  Widget build(BuildContext context) {
    final allPoints = _allEntries
        .map((e) => LatLng(e.clockInLatitude!, e.clockInLongitude!))
        .toList();

    final initialCenter = allPoints.isNotEmpty
        ? _centroid(allPoints)
        : const LatLng(43.65, -79.38);

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 13,
        onMapReady: () {
          if (allPoints.length > 1) {
            // safeMapBounds: two workers clocked in at the same job site
            // produce identical points — a raw fromPoints bounds has zero
            // extent and the camera fit zooms to infinity (same failure
            // class as F11 on the task map).
            controller.fitCamera(
              CameraFit.bounds(
                bounds: safeMapBounds(allPoints),
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                maxZoom: 17,
              ),
            );
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          tileProvider: CancellableNetworkTileProvider(),
          userAgentPackageName: 'com.example.com',
        ),
        // Dashed radius rings for active workers only
        CircleLayer(
          circles: activeEntries.map((entry) {
            final weekHours = weekHoursMap[entry.workerId] ?? 0.0;
            final isOtRisk = weekHours >= _kOtHours;
            final isApproaching = weekHours >= _kOtRiskHours && !isOtRisk;
            final color = isOtRisk
                ? AppColors.error
                : isApproaching
                    ? AppColors.warning
                    : AppColors.success;
            final isFocused = focusedWorkerId == entry.workerId;
            return CircleMarker(
              point: LatLng(entry.clockInLatitude!, entry.clockInLongitude!),
              radius: isFocused ? 16 : 12,
              color: color.withOpacity(0.15),
              borderColor: color,
              borderStrokeWidth: isFocused ? 3 : 1.5,
            );
          }).toList(),
        ),
        // Markers — active workers full opacity, off-clock at 50%
        MarkerLayer(
          markers: _allEntries.map((entry) {
            final isOff = offEntries.contains(entry);
            final user = usersMap[entry.workerId];
            final name = user?.displayName ?? user?.email ?? '?';
            final initials = _initials(name);
            final weekHours = weekHoursMap[entry.workerId] ?? 0.0;
            final isOtRisk = weekHours >= _kOtHours;
            final isApproaching = weekHours >= _kOtRiskHours && !isOtRisk;
            final color = isOff
                ? AppColors.textTertiary
                : isOtRisk
                    ? AppColors.error
                    : isApproaching
                        ? AppColors.warning
                        : AppColors.success;

            return Marker(
              point: LatLng(entry.clockInLatitude!, entry.clockInLongitude!),
              width: 34,
              height: 34,
              child: Opacity(
                opacity: isOff ? 0.5 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  LatLng _centroid(List<LatLng> points) {
    final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) /
        points.length;
    final lng = points.map((p) => p.longitude).reduce((a, b) => a + b) /
        points.length;
    return LatLng(lat, lng);
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.5),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final String userId;
  final bool isOff;

  const _Avatar({
    required this.initials,
    required this.userId,
    this.isOff = false,
  });

  static const _gradients = [
    [Color(0xFF2563EB), Color(0xFF7C3AED)],
    [Color(0xFF16A34A), Color(0xFF0891B2)],
    [AppColors.error, Color(0xFFF97316)],
    [Color(0xFF7C3AED), Color(0xFFDB2777)],
    [Color(0xFF0891B2), Color(0xFF2563EB)],
  ];

  @override
  Widget build(BuildContext context) {
    final pair = isOff
        ? [AppColors.textTertiary, AppColors.textTertiary]
        : _gradients[userId.hashCode.abs() % _gradients.length];

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
