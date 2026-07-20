import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/file_attachment.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/property_task_metrics.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import 'package:intl/intl.dart';
import '../file_upload_widget.dart';




/// Summary tab showing property overview and quick stats.
class PropertySummaryTab extends StatelessWidget {
  final Property property;
  final Project project;

  const PropertySummaryTab({
    super.key,
    required this.property,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Timeline
          _buildStatusTimeline(context),
          const SizedBox(height: 24),

          // Task summary card
          StreamBuilder<List<Task>>(
            stream: ServiceLocator.taskService.getTasksByProperty(property.id),
            builder: (context, snapshot) {
              final tasks = snapshot.data ?? [];
              if (tasks.isEmpty) return const SizedBox.shrink();
              final m = PropertyTaskMetrics.fromTasks(property.id, tasks);
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _buildTaskSummaryCard(context, m),
              );
            },
          ),

          // Two-column layout for wider screens
          LayoutBuilder(
            builder: (context, constraints) {
              return _buildContentsSummary(context);
            },
          ),
          const SizedBox(height: 24),

          // Unit Plan widget
          _buildUnitPlanCard(context),
          const SizedBox(height: 24),

          // Notes section (if any)
          if (property.notes != null && property.notes!.isNotEmpty)
            _buildNotesCard(context),

          const SizedBox(height: 24),

          // Property Details
          _buildDetailsCard(context),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status Timeline',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: PropertyStatus.values.map((status) {
                final isActive = status == property.status;
                final isPast =
                    PropertyStatus.values.indexOf(status) <
                    PropertyStatus.values.indexOf(property.status);

                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (status != PropertyStatus.values.first)
                            Expanded(
                              child: Container(
                                height: 2,
                                color: isPast || isActive
                                    ? status.color
                                    : AppColors.cardBorder,
                              ),
                            ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? status.color
                                  : (isPast
                                      ? status.color.withAlpha(150)
                                      : AppColors.cardBorder),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              status.icon,
                              size: 16,
                              color: isActive || isPast
                                  ? Colors.white
                                  : AppColors.textTertiary,
                            ),
                          ),
                          if (status != PropertyStatus.values.last)
                            Expanded(
                              child: Container(
                                height: 2,
                                color: isPast
                                    ? PropertyStatus
                                        .values[PropertyStatus.values
                                                .indexOf(status) +
                                            1]
                                        .color
                                    : AppColors.cardBorder,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? status.color : ChromeColors.of(context).text,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatItem(String label, String value, Color color) {
    return Builder(
      builder: (context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ChromeColors.of(context).text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentsSummary(BuildContext context) {
    final contentsService = ServiceLocator.propertyContentsService;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, color: AppColors.messageAccentDark),
                const SizedBox(width: 8),
                Text(
                  'Contents Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            FutureBuilder<Map<String, int>>(
              future: contentsService.getContentsStats(
                property.id,
                workspaceId: property.workspaceId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final stats = snapshot.data ?? {'total': 0, 'totalQuantity': 0};
                final total = stats['total'] ?? 0;
                final quantity = stats['totalQuantity'] ?? 0;

                if (total == 0) {
                  final chrome = ChromeColors.of(context);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2,
                              size: 48, color: chrome.text),
                          const SizedBox(height: 8),
                          Text(
                            'No contents items tracked',
                            style: TextStyle(color: chrome.text),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final identified = stats['identified'] ?? 0;
                final packed = stats['packed'] ?? 0;
                final stored = stats['stored'] ?? 0;
                final returned = stats['returned'] ?? 0;
                final disposed = stats['disposed'] ?? 0;

                return Column(
                  children: [
                    // Total items
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text(
                              '$total',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Items',
                              style: TextStyle(color: ChromeColors.of(context).text),
                            ),
                          ],
                        ),
                        const SizedBox(width: 32),
                        Column(
                          children: [
                            Text(
                              '$quantity',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Total Qty',
                              style: TextStyle(color: ChromeColors.of(context).text),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Status breakdown
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildContentsBadge('Identified', identified, AppColors.textTertiary),
                        _buildContentsBadge('Packed', packed, AppColors.messageAccent),
                        _buildContentsBadge('Stored', stored, Colors.indigo),
                        _buildContentsBadge('Returned', returned, AppColors.success),
                        _buildContentsBadge('Disposed', disposed, Colors.brown),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentsBadge(String label, int count, Color color) {
    if (count == 0) return const SizedBox.shrink();

    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 10,
        child: Text(
          '$count',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
      label: Text(label),
      backgroundColor: color.withAlpha(25),
      labelStyle: TextStyle(color: color, fontSize: 12),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTaskSummaryCard(BuildContext context, PropertyTaskMetrics m) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.task_alt, size: 18, color: m.taskColor),
                const SizedBox(width: 8),
                Text(
                  'Tasks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${m.completedCount} of ${m.totalCount} complete',
                  style: TextStyle(
                    fontSize: 13,
                    color: m.taskColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: m.progressPercent / 100,
              minHeight: 6,
              backgroundColor: m.taskColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(m.taskColor),
              borderRadius: BorderRadius.circular(3),
            ),
            if (m.hasOverdue || m.stuckCount > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (m.hasOverdue) ...[
                    Icon(Icons.schedule, size: 14, color: AppColors.error),
                    const SizedBox(width: 4),
                    Text(
                      '${m.overdueCount} overdue',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                    if (m.stuckCount > 0) const SizedBox(width: 16),
                  ],
                  if (m.stuckCount > 0) ...[
                    Icon(Icons.block, size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${m.stuckCount} stuck',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note, color: AppColors.warningDark),
                const SizedBox(width: 8),
                Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            Text(property.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitPlanCard(BuildContext context) {
    return UnitPlanCard(property: property, project: project);
  }

  Widget _buildDetailsCard(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Property Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(),
            _buildDetailRow('Name', property.name),
            _buildDetailRow('Number', property.identifier),
            if (property.floor != null)
              _buildDetailRow('Floor', property.floor!),
            if (property.occupant != null)
              _buildDetailRow('Occupant', property.occupant!),
            _buildDetailRow('Status', property.status.displayName),
            _buildDetailRow('Created', dateFormat.format(property.createdAt)),
            _buildDetailRow('Updated', dateFormat.format(property.updatedAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: TextStyle(
                  color: ChromeColors.of(context).text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      ),
    );
  }
}

class UnitPlanCard extends StatelessWidget {
  final Property property;
  final Project project;

  const UnitPlanCard({super.key, required this.property, required this.project});

  String get _tag => 'property:${property.id}:floorplan';

  void _showUploadSheet(BuildContext context) {
    final userId = context.read<AuthProvider>().appUser?.id ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload Unit Plan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            FileUploadWidget(
              workspaceId: project.workspaceId,
              projectId: project.id,
              tags: [_tag],
              uploadedBy: userId,
              onUploadComplete: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFile(BuildContext context, FileAttachment file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove unit plan?'),
        content: Text(file.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ServiceLocator.storageService.deleteFile(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageService = ServiceLocator.storageService;

    return StreamBuilder<List<FileAttachment>>(
      stream: storageService.getProjectFiles(
        project.workspaceId,
        project.id,
      ),
      builder: (context, snapshot) {
        final plans = (snapshot.data ?? [])
            .where((f) => f.tags.contains(_tag))
            .toList()
          ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));

        final plan = plans.isNotEmpty ? plans.first : null;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top-level Wrap so the title cluster and action cluster
                // can reflow onto separate lines on narrow widths or with
                // large text scaling instead of overflowing the row.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.architecture,
                            color: AppColors.financialAccent),
                        const SizedBox(width: 8),
                        Text(
                          'Unit Plan (Sketch)',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        // Jumps to the project's Plans tab pre-scoped to
                        // this property so the user lands on the existing
                        // "+ New Floorplan" editor flow without wading
                        // through other structures' plans.
                        TextButton.icon(
                          onPressed: () => context.push(
                            '/projects/${project.id}/plans?property=${property.id}',
                          ),
                          icon: const Icon(Icons.draw_outlined, size: 18),
                          label: const Text('Draw sketch'),
                        ),
                        TextButton.icon(
                          onPressed: () => _showUploadSheet(context),
                          icon: const Icon(Icons.upload, size: 18),
                          label: Text(plan == null ? 'Upload' : 'Replace'),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                if (plan == null)
                  Builder(
                    builder: (context) {
                      final chrome = ChromeColors.of(context);
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            children: [
                              Icon(Icons.architecture,
                                  size: 48, color: chrome.text),
                              const SizedBox(height: 8),
                              Text('No unit plan uploaded',
                                  style: TextStyle(color: chrome.text)),
                              const SizedBox(height: 4),
                              Text('Upload a floor plan or sketch',
                                  style: TextStyle(
                                      color: chrome.sectionLabel,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                else
                  _PlanPreview(
                    file: plan,
                    onDelete: () => _deleteFile(context, plan),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlanPreview extends StatelessWidget {
  final FileAttachment file;
  final VoidCallback onDelete;

  const _PlanPreview({required this.file, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (file.isImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CachedNetworkImage(
              imageUrl: file.fileUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _iconBox(context),
            ),
          )
        else
          _iconBox(context),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(file.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                'Uploaded ${DateFormat('MMM d, y').format(file.uploadedAt)}',
                style: TextStyle(
                    fontSize: 12, color: chrome.text),
              ),
              Text(
                file.formattedSize,
                style: TextStyle(
                    fontSize: 12, color: chrome.sectionLabel),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          color: chrome.text,
          onPressed: onDelete,
          tooltip: 'Remove',
        ),
      ],
    );
  }

  Widget _iconBox(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        file.isPDF ? Icons.picture_as_pdf : Icons.insert_drive_file,
        size: 36,
        color: ChromeColors.of(context).text,
      ),
    );
  }
}
