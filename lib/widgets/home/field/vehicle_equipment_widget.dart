import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/asset.dart';
import '../../../models/vehicle.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

/// Shows the field technician's assigned vehicle and equipment.
class VehicleEquipmentWidget extends StatelessWidget {
  final String workspaceId;
  final String userId;

  const VehicleEquipmentWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),
            _buildVehicleSection(),
            const SizedBox(height: AppSpacing.iconGap),
            _buildEquipmentSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.local_shipping,
            color: Color(0xFF0891B2),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Vehicle & Equipment',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleSection() {
    return StreamBuilder<List<Vehicle>>(
      stream: ServiceLocator.vehicleServiceFor(workspaceId).getVehicles(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final myVehicle = snapshot.data!.cast<Vehicle?>().firstWhere(
          (v) => v!.assignedToUserId == userId,
          orElse: () => null,
        );

        if (myVehicle == null) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Row(
              children: [
                Icon(Icons.directions_car, size: 18, color: AppColors.textTertiary),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'No vehicle assigned',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          );
        }

        final vehicleLabel = [
          if (myVehicle.year != 0) myVehicle.year.toString(),
          if (myVehicle.make.isNotEmpty) myVehicle.make,
          if (myVehicle.model.isNotEmpty) myVehicle.model,
        ].join(' ');

        return InkWell(
          onTap: () => context.go('/vehicles/${myVehicle.id}'),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: const Color(0xFF0891B2).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_car,
                  color: Color(0xFF0891B2),
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.iconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleLabel.isNotEmpty
                            ? vehicleLabel
                            : myVehicle.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (myVehicle.licensePlate.isNotEmpty)
                        Text(
                          myVehicle.licensePlate,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (myVehicle.currentMileage > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '${myVehicle.currentMileage} mi',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
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

  Widget _buildEquipmentSection() {
    return StreamBuilder<List<Asset>>(
      stream: ServiceLocator.assetServiceFor(workspaceId).getAssets(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final myAssets = snapshot.data!.where(
          (a) => a.assignedToUserId == userId,
        ).toList();

        if (myAssets.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Row(
              children: [
                Icon(Icons.build, size: 18, color: AppColors.textTertiary),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'No equipment assigned',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Equipment (${myAssets.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ...myAssets.take(5).map((asset) {
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.build, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        asset.name,
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (asset.serialNumber != null && asset.serialNumber!.isNotEmpty)
                      Text(
                        asset.serialNumber!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (myAssets.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${myAssets.length - 5} more',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
