import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/asset.dart';
import '../../models/project.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/asset_service.dart';
import '../../services/supabase/user_service.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/project_selector_dialog.dart';
import 'widgets/asset_activity_section.dart';
import 'widgets/asset_maintenance_section.dart';

class AssetDetailScreen extends StatelessWidget {
  final String assetId;

  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    final assetService = SupabaseAssetService(workspaceId: workspaceId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              context.push('/equipment/$assetId/edit');
            },
          ),
        ],
      ),
      body: StreamBuilder<Asset?>(
        stream: assetService.streamAsset(assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          final asset = snapshot.data;
          if (asset == null) {
            return const Center(child: Text('Equipment not found'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (asset.photoUrls.isNotEmpty) ...[
                  _PhotoGallery(photoUrls: asset.photoUrls),
                  const SizedBox(height: 16),
                ],
                if (asset.qrCode != null) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: asset.qrCode!,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                _buildInfoCard(context, 'Basic Information', [
                  _InfoRow('Name', asset.name),
                  if (asset.description != null)
                    _InfoRow('Description', asset.description!),
                  if (asset.serialNumber != null)
                    _InfoRow('Serial Number', asset.serialNumber!),
                  _InfoRow(
                    'Status',
                    asset.status.isEmpty
                        ? 'Unknown'
                        : asset.status[0].toUpperCase() +
                            asset.status.substring(1),
                  ),
                  _InfoRow('Category', asset.category),
                  if ((asset.location ?? '').isNotEmpty)
                    _InfoRow('Location', asset.location!),
                ]),
                const SizedBox(height: 16),

                if (asset.tags.isNotEmpty) ...[
                  _buildTagsCard(context, asset.tags),
                  const SizedBox(height: 16),
                ],

                if (asset.purchaseDate != null || asset.purchasePrice != null)
                  _buildInfoCard(context, 'Purchase Information', [
                    if (asset.purchaseDate != null)
                      _InfoRow(
                        'Purchase Date',
                        '${asset.purchaseDate!.year}-${asset.purchaseDate!.month.toString().padLeft(2, '0')}-${asset.purchaseDate!.day.toString().padLeft(2, '0')}',
                      ),
                    if (asset.purchasePrice != null)
                      _InfoRow(
                        'Purchase Cost',
                        CurrencyUtils.formatCurrency(
                          asset.purchasePrice!,
                          context.read<WorkspaceProvider>().currencyCode,
                        ),
                      ),
                  ]),
                const SizedBox(height: 16),

                _buildAssignmentCard(
                  context,
                  asset,
                  assetService,
                  workspaceId,
                ),
                const SizedBox(height: 16),

                AssetMaintenanceSection(
                  assetId: asset.id,
                  workspaceId: workspaceId,
                ),
                const SizedBox(height: 16),

                AssetActivitySection(assetId: asset.id),

                if (asset.notes != null) ...[
                  const SizedBox(height: 16),
                  _buildInfoCard(context, 'Notes', [
                    _InfoRow('', asset.notes!),
                  ]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagsCard(BuildContext context, List<String> tags) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tags',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      labelStyle: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                        fontSize: 13,
                      ),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    String title,
    List<_InfoRow> rows,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: row.label.isEmpty
                    ? Text(row.value)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              row.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(child: Text(row.value)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(
    BuildContext context,
    Asset asset,
    SupabaseAssetService assetService,
    String workspaceId,
  ) {
    final projectService = ServiceLocator.projectService;
    final projectTerminology =
        context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final hasProject = (asset.assignedToProjectId ?? '').isNotEmpty;
    final hasUser = (asset.assignedToUserId ?? '').isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assignment',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            if (hasProject)
              FutureBuilder<Project?>(
                future: projectService.getProject(asset.assignedToProjectId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: LinearProgressIndicator(),
                    );
                  }
                  final project = snapshot.data;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            'Assigned to $singular',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: project == null
                              ? const Text('Unknown')
                              : InkWell(
                                  onTap: () =>
                                      context.push('/projects/${project.id}'),
                                  child: Text(
                                    project.name,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (hasUser)
              FutureBuilder<AppUser?>(
                future: SupabaseUserService().getUserById(
                  asset.assignedToUserId!,
                ),
                builder: (context, snapshot) {
                  final name = snapshot.data?.displayName?.isNotEmpty == true
                      ? snapshot.data!.displayName!
                      : snapshot.data?.email ?? 'Team member';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 140,
                          child: Text(
                            'Assigned to user',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(child: Text(name)),
                      ],
                    ),
                  );
                },
              ),
            if (!hasProject && !hasUser)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('Not assigned to any ${singular.toLowerCase()}'),
              ),
            const SizedBox(height: 8),
            if (hasProject || hasUser)
              ElevatedButton.icon(
                onPressed: () async {
                  await assetService.unassignAsset(asset.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Equipment unassigned')),
                    );
                  }
                },
                icon: const Icon(Icons.close),
                label: const Text('Unassign'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: () async {
                  final project = await showDialog<Project>(
                    context: context,
                    builder: (context) => ProjectSelectorDialog(
                      workspaceId: workspaceId,
                      currentProjectId: asset.assignedToProjectId,
                    ),
                  );

                  if (project != null && context.mounted) {
                    await assetService.assignAssetToProject(
                      asset.id,
                      project.id,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Equipment assigned to ${project.name}'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: Text('Assign to $singular'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
}

class _PhotoGallery extends StatefulWidget {
  final List<String> photoUrls;

  const _PhotoGallery({required this.photoUrls});

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  int _index = 0;

  @override
  void didUpdateWidget(_PhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.photoUrls.length) {
      _index = widget.photoUrls.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.photoUrls;
    if (urls.isEmpty) return const SizedBox.shrink();
    final activeUrl = urls[_index.clamp(0, urls.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: GestureDetector(
              onTap: () => _showFullScreen(context, activeUrl),
              child: CachedNetworkImage(
                imageUrl: activeUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(
                  color: AppColors.cardBorder,
                ),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: AppColors.cardBorder,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: AppColors.textTertiary,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final isActive = i == _index;
                return GestureDetector(
                  onTap: () => setState(() => _index = i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: isActive ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: urls[i],
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: AppColors.cardBorder,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _showFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: url),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
