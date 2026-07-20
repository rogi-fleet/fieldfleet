import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/task.dart';
import '../../utils/safe_map_bounds.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/task_filter_engine.dart';
import '../task_form_popup.dart';

class TasksMapPanel extends StatefulWidget {
  final String workspaceId;
  final Map<String, Project> projectMap;
  final Map<String, Property> propertyMap;
  final TaskFilterOptions filterOptions;
  final VoidCallback? onClose;

  const TasksMapPanel({
    super.key,
    required this.workspaceId,
    required this.projectMap,
    required this.propertyMap,
    required this.filterOptions,
    this.onClose,
  });

  @override
  State<TasksMapPanel> createState() => _TasksMapPanelState();
}

class _TasksMapPanelState extends State<TasksMapPanel> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border(
                bottom: BorderSide(color: AppColors.cardBorder),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Task Map',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Hide map',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: ServiceLocator.taskService
                  .getAllWorkspaceTasks(widget.workspaceId),
              builder: (context, snapshot) {
                final allTasks = snapshot.data ?? const <Task>[];
                final filtered = TaskFilterEngine.apply(
                  allTasks,
                  options: widget.filterOptions,
                  context: TaskFilterContext(
                    projectMap: widget.projectMap,
                    propertyMap: widget.propertyMap,
                  ),
                );
                final pins = _buildPins(filtered);

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (pins.isEmpty) {
                  return _buildEmpty();
                }
                return _buildMap(pins);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 32,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 8),
            Text(
              'No task locations yet.\nAdd an address to a job to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_TaskPin> _buildPins(List<Task> tasks) {
    final byProject = <String, List<Task>>{};
    for (final t in tasks) {
      byProject.putIfAbsent(t.projectId, () => []).add(t);
    }

    final pins = <_TaskPin>[];
    byProject.forEach((projectId, projectTasks) {
      final project = widget.projectMap[projectId];
      if (project?.latitude == null || project?.longitude == null) return;
      pins.add(
        _TaskPin(
          project: project!,
          tasks: projectTasks,
          point: LatLng(project.latitude!, project.longitude!),
        ),
      );
    });
    return pins;
  }

  Widget _buildMap(List<_TaskPin> pins) {
    final bounds = _boundsFor(pins);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
          // Belt-and-braces with safeMapBounds: never let a tight bounds
          // resolve to an unbounded fit zoom.
          maxZoom: 17,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.taskfleet.ai',
          tileProvider: CancellableNetworkTileProvider(),
        ),
        MarkerLayer(
          markers: [
            for (final pin in pins)
              Marker(
                point: pin.point,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => _showPinSheet(pin),
                  child: _PinBadge(count: pin.tasks.length),
                ),
              ),
          ],
        ),
      ],
    );
  }

  LatLngBounds _boundsFor(List<_TaskPin> pins) =>
      // safeMapBounds pads zero-extent spans — several jobs at one street
      // address used to produce a degenerate bounds and an infinite fit
      // zoom, crashing the panel into the error boundary (F11).
      safeMapBounds([for (final pin in pins) pin.point]);

  void _showPinSheet(_TaskPin pin) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pin.project.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((pin.project.address ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 28),
                    child: Text(
                      pin.project.address ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pin.tasks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = pin.tasks[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          t.isComplete
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: t.isComplete
                              ? AppColors.success
                              : AppColors.textTertiary,
                        ),
                        title: Text(
                          t.title,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          showTaskFormPopup(
                            context,
                            projectId: t.projectId,
                            taskId: t.id,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TaskPin {
  final Project project;
  final List<Task> tasks;
  final LatLng point;

  _TaskPin({
    required this.project,
    required this.tasks,
    required this.point,
  });
}

class _PinBadge extends StatelessWidget {
  final int count;
  const _PinBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.location_pin, size: 40, color: AppColors.error),
        Positioned(
          top: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.error, width: 1),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
