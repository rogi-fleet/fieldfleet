import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/capacity_planning.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

class CapacityAlertsWidget extends StatefulWidget {
  final String workspaceId;

  const CapacityAlertsWidget({super.key, required this.workspaceId});

  @override
  State<CapacityAlertsWidget> createState() => _CapacityAlertsWidgetState();
}

class _CapacityAlertsWidgetState extends State<CapacityAlertsWidget> {
  late Future<CapacitySnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshotAndSync();
  }

  @override
  void didUpdateWidget(covariant CapacityAlertsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _snapshotFuture = _loadSnapshotAndSync();
    }
  }

  Future<CapacitySnapshot> _loadSnapshotAndSync() async {
    final start = DateTime.now();
    final end = start.add(const Duration(days: 13));
    final snapshot = await ServiceLocator.capacityPlanningService
        .getCapacitySnapshot(
          workspaceId: widget.workspaceId,
          start: start,
          end: end,
        );
    await ServiceLocator.capacityPlanningService.syncCapacityAlertsFromSnapshot(
      workspaceId: widget.workspaceId,
      snapshot: snapshot,
    );
    return snapshot;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CapacitySnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        final issues = snapshot.data?.issues ?? const <CapacityIssue>[];
        final overCapacity = issues
            .where((i) => i.issueType == 'over_capacity')
            .length;
        final highRisk = issues.where((i) => i.issueType == 'high_risk').length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.balance, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Capacity Alerts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator(minHeight: 4)
                else if (snapshot.hasError)
                  const Text(
                    'Unable to load capacity alerts.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else if (issues.isEmpty)
                  const Text(
                    'No overload or high-risk alerts in the next 2 weeks.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Over capacity: $overCapacity'),
                      Text('High risk: $highRisk'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          context.push('/team?tab=capacity');
                        },
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open capacity planner'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
