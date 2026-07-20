import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/vehicle.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase/vehicle_service.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/vehicle_form_popup.dart';
import 'widgets/vehicle_drivers_tab.dart';
import 'widgets/vehicle_expenses_tab.dart';
import 'widgets/vehicle_maintenance_tab.dart';
import 'widgets/vehicle_obd_tab.dart';
import 'widgets/vehicle_overview_tab.dart';

class VehicleDetailScreen extends StatefulWidget {
  final String vehicleId;

  const VehicleDetailScreen({super.key, required this.vehicleId});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    final vehicleService = SupabaseVehicleService(workspaceId: workspaceId);

    return StreamBuilder<List<Vehicle>>(
      stream: vehicleService.getVehicles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Vehicle'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vehicle')),
            body: Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error,
                    action: 'load vehicle'),
              ),
            ),
          );
        }

        final vehicles = snapshot.data ?? [];
        final vehicle = vehicles.cast<Vehicle?>().firstWhere(
          (v) => v?.id == widget.vehicleId,
          orElse: () => null,
        );

        if (vehicle == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Vehicle'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(child: Text('Vehicle not found')),
          );
        }

        return Scaffold(
          appBar: _buildAppBar(context, vehicle, vehicleService),
          body: TabBarView(
            controller: _tabController,
            children: [
              VehicleOverviewTab(
                vehicle: vehicle,
                vehicleService: vehicleService,
              ),
              VehicleMaintenanceTab(
                vehicle: vehicle,
                vehicleService: vehicleService,
              ),
              VehicleExpensesTab(
                vehicle: vehicle,
                vehicleService: vehicleService,
              ),
              VehicleDriversTab(
                vehicle: vehicle,
                vehicleService: vehicleService,
                workspaceId: workspaceId,
              ),
              VehicleObdTab(vehicle: vehicle),
            ],
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    Vehicle vehicle,
    SupabaseVehicleService vehicleService,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vehicle.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (vehicle.make.isNotEmpty || vehicle.model.isNotEmpty)
            Text(
              [
                if (vehicle.year > 0) vehicle.year.toString(),
                if (vehicle.make.isNotEmpty) vehicle.make,
                if (vehicle.model.isNotEmpty) vehicle.model,
              ].join(' '),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
      actions: [
        _buildStatusChip(vehicle.status),
        const SizedBox(width: AppSpacing.sm),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                showVehicleFormPopup(context, vehicleId: vehicle.id);
              case 'active':
              case 'maintenance':
              case 'retired':
                await vehicleService
                    .updateVehicle(vehicle.copyWith(status: value));
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit Vehicle')),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'active',
              child: Text('Set Active'),
            ),
            const PopupMenuItem(
              value: 'maintenance',
              child: Text('Set In Maintenance'),
            ),
            const PopupMenuItem(
              value: 'retired',
              child: Text('Set Retired'),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(
            icon: Icon(Icons.info_outline, size: 18),
            text: 'Overview',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.build_outlined, size: 18),
            text: 'Maintenance',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.receipt_long_outlined, size: 18),
            text: 'Expenses',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.person_outlined, size: 18),
            text: 'Drivers',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
          Tab(
            icon: Icon(Icons.sensors_outlined, size: 18),
            text: 'Live Data',
            iconMargin: EdgeInsets.only(bottom: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    final label = status.isEmpty
        ? 'Unknown'
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'maintenance':
        return AppColors.warning;
      case 'retired':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }
}
