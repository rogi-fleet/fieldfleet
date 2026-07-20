import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/user.dart';
import '../../../models/vehicle.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../services/supabase/user_service.dart';
import '../../../services/supabase/vehicle_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../../../widgets/project_selector_dialog.dart';
import '../../../widgets/user_avatar.dart';

class VehicleDriversTab extends StatelessWidget {
  final Vehicle vehicle;
  final SupabaseVehicleService vehicleService;
  final String workspaceId;

  const VehicleDriversTab({
    super.key,
    required this.vehicle,
    required this.vehicleService,
    required this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Primary Driver'),
          const SizedBox(height: AppSpacing.sm),
          _buildPrimaryDriverCard(context),
          const SizedBox(height: AppSpacing.base),
          _buildSectionTitle('Currently Driving'),
          const SizedBox(height: AppSpacing.sm),
          _buildCurrentDriverCard(context),
          const SizedBox(height: AppSpacing.base),
          _buildSectionTitle('Project Assignment'),
          const SizedBox(height: AppSpacing.sm),
          _buildProjectCard(context),
          const SizedBox(height: AppSpacing.base),
          _buildSectionTitle('Vehicle Status'),
          const SizedBox(height: AppSpacing.sm),
          _buildStatusCard(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildPrimaryDriverCard(BuildContext context) {
    final hasUser = (vehicle.assignedToUserId ?? '').isNotEmpty;
    return _DriverCard(
      icon: Icons.person_outlined,
      title: 'Primary Driver',
      subtitle: 'Long-term assignment — the team member this vehicle belongs to',
      content: hasUser
          ? FutureBuilder<AppUser?>(
              future: SupabaseUserService().getUserById(vehicle.assignedToUserId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingRow();
                }
                final user = snapshot.data;
                return _UserRow(
                  user: user,
                  onReassign: () => _pickPrimaryDriver(context),
                  onClear: () => vehicleService.unassignVehicle(vehicle.id),
                  reassignLabel: 'Reassign',
                  clearLabel: 'Unassign',
                );
              },
            )
          : _AssignButton(
              label: 'Assign Primary Driver',
              icon: Icons.person_add_outlined,
              onTap: () => _pickPrimaryDriver(context),
            ),
    );
  }

  Widget _buildCurrentDriverCard(BuildContext context) {
    final hasDriver = (vehicle.currentDriverId ?? '').isNotEmpty;
    return _DriverCard(
      icon: Icons.vpn_key_outlined,
      title: 'Current Driver',
      subtitle: 'Who has the keys right now — updated on check-out / check-in',
      content: hasDriver
          ? FutureBuilder<AppUser?>(
              future: SupabaseUserService().getUserById(vehicle.currentDriverId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingRow();
                }
                final user = snapshot.data;
                return _UserRow(
                  user: user,
                  onReassign: () => _pickCurrentDriver(context),
                  onClear: () => vehicleService.checkInVehicle(vehicle.id),
                  reassignLabel: 'Hand Off',
                  clearLabel: 'Check In',
                  clearColor: AppColors.success,
                );
              },
            )
          : _AssignButton(
              label: 'Check Out Vehicle',
              icon: Icons.login_outlined,
              onTap: () => _pickCurrentDriver(context),
            ),
    );
  }

  Widget _buildProjectCard(BuildContext context) {
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final hasProject = (vehicle.assignedToProjectId ?? '').isNotEmpty;

    return _DriverCard(
      icon: Icons.work_outline,
      title: singular,
      subtitle: 'The job this vehicle is committed to for cost tracking',
      content: hasProject
          ? FutureBuilder<Project?>(
              future: ServiceLocator.projectService
                  .getProject(vehicle.assignedToProjectId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingRow();
                }
                final project = snapshot.data;
                if (project == null) {
                  return _AssignButton(
                    label: 'Assign to ${singular.toLowerCase()}',
                    icon: Icons.add_circle_outline,
                    onTap: () => _pickProject(context),
                  );
                }
                return _ProjectRow(
                  project: project,
                  onTap: () => context.push('/projects/${project.id}'),
                  onReassign: () => _pickProject(context),
                  onClear: () =>
                      vehicleService.unassignVehicleFromProject(vehicle.id),
                );
              },
            )
          : _AssignButton(
              label: 'Assign to ${singular.toLowerCase()}',
              icon: Icons.work_outline,
              onTap: () => _pickProject(context),
            ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final statusOptions = [
      ('active', 'Active', Icons.check_circle_outline, AppColors.success),
      ('maintenance', 'In Maintenance', Icons.build_circle_outlined,
          AppColors.warning),
      ('retired', 'Retired', Icons.archive_outlined, AppColors.error),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: statusOptions.asMap().entries.map((entry) {
          final i = entry.key;
          final opt = entry.value;
          final isSelected = vehicle.status == opt.$1;
          return Column(
            children: [
              InkWell(
                onTap: isSelected
                    ? null
                    : () => vehicleService.updateVehicle(
                          vehicle.copyWith(status: opt.$1),
                        ),
                borderRadius: i == 0
                    ? AppRadius.cardRadius.copyWith(
                        bottomLeft: Radius.zero,
                        bottomRight: Radius.zero,
                      )
                    : i == statusOptions.length - 1
                    ? AppRadius.cardRadius.copyWith(
                        topLeft: Radius.zero,
                        topRight: Radius.zero,
                      )
                    : BorderRadius.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: opt.$4.withValues(
                              alpha: isSelected ? 0.15 : 0.06),
                          borderRadius: AppRadius.badgeRadius,
                        ),
                        child: Icon(opt.$3,
                            size: 18,
                            color: opt.$4
                                .withValues(alpha: isSelected ? 1.0 : 0.5)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          opt.$2,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle,
                            color: opt.$4, size: 20),
                    ],
                  ),
                ),
              ),
              if (i < statusOptions.length - 1)
                const Divider(height: 1, color: AppColors.cardBorder),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _pickPrimaryDriver(BuildContext context) async {
    final picked = await _showMemberPicker(context,
        title: 'Assign Primary Driver',
        currentUserId: vehicle.assignedToUserId);
    if (picked == null) return;
    await vehicleService.assignVehicleToUser(vehicle.id, picked.id);
  }

  Future<void> _pickCurrentDriver(BuildContext context) async {
    final picked = await _showMemberPicker(context,
        title: 'Check Out To',
        currentUserId: vehicle.currentDriverId);
    if (picked == null) return;
    await vehicleService.checkOutVehicle(vehicle.id, picked.id);
  }

  Future<void> _pickProject(BuildContext context) async {
    final project = await showDialog<Project>(
      context: context,
      builder: (_) => ProjectSelectorDialog(
        workspaceId: workspaceId,
        currentProjectId: vehicle.assignedToProjectId,
      ),
    );
    if (project == null || !context.mounted) return;
    await vehicleService.assignVehicleToProject(vehicle.id, project.id);
  }

  Future<AppUser?> _showMemberPicker(
    BuildContext context, {
    required String title,
    String? currentUserId,
  }) async {
    final users =
        await ServiceLocator.userService.getWorkspaceUsers(workspaceId);

    if (!context.mounted) return null;

    return showDialog<AppUser>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (_, i) {
              final u = users[i];
              final isCurrent = u.id == currentUserId;
              return ListTile(
                leading: UserAvatar(user: u, size: AvatarSize.small),
                title: Text(u.displayName ?? u.email),
                subtitle: isCurrent ? const Text('Current') : null,
                trailing: isCurrent
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(ctx, u),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget content;

  const _DriverCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, 0),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.xs, AppSpacing.base, AppSpacing.sm),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: content,
          ),
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text('Loading...', style: TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  final AppUser? user;
  final VoidCallback onReassign;
  final VoidCallback onClear;
  final String reassignLabel;
  final String clearLabel;
  final Color? clearColor;

  const _UserRow({
    required this.user,
    required this.onReassign,
    required this.onClear,
    required this.reassignLabel,
    required this.clearLabel,
    this.clearColor,
  });

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : user?.email ?? 'Team member';

    return Row(
      children: [
        if (user != null) UserAvatar(user: user, size: AvatarSize.small),
        if (user == null)
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceAlt,
            child: Icon(Icons.person, size: 16, color: AppColors.textTertiary),
          ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (user?.email != null && user?.displayName?.isNotEmpty == true)
                Text(
                  user!.email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          onPressed: onReassign,
          child: Text(reassignLabel),
        ),
        OutlinedButton(
          onPressed: onClear,
          style: OutlinedButton.styleFrom(
            foregroundColor: clearColor ?? AppColors.error,
            side: BorderSide(
                color: (clearColor ?? AppColors.error).withValues(alpha: 0.4)),
          ),
          child: Text(clearLabel),
        ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onReassign;
  final VoidCallback onClear;

  const _ProjectRow({
    required this.project,
    required this.onTap,
    required this.onReassign,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.projectAccentLight,
            borderRadius: AppRadius.badgeRadius,
          ),
          child: const Icon(Icons.work_outline,
              size: 16, color: AppColors.projectAccent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Text(
              project.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
        TextButton(onPressed: onReassign, child: const Text('Change')),
        OutlinedButton(
          onPressed: onClear,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
          ),
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

class _AssignButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AssignButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 44),
        side: const BorderSide(color: AppColors.cardBorder),
        foregroundColor: AppColors.primary,
      ),
    );
  }
}
