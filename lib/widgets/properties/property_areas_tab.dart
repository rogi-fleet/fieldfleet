import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/area.dart';
import '../../models/area_status.dart';
import '../../services/service_locator.dart';
import 'area_form_popup.dart';
import 'room_sketch.dart';

/// Areas tab showing all areas within a property.
class PropertyAreasTab extends StatefulWidget {
  final Property property;
  final Project project;

  const PropertyAreasTab({
    super.key,
    required this.property,
    required this.project,
  });

  @override
  State<PropertyAreasTab> createState() => _PropertyAreasTabState();
}

class _PropertyAreasTabState extends State<PropertyAreasTab> {
  final dynamic _areaService = ServiceLocator.areaService;
  Area? _selectedArea;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Area>>(
      stream: _areaService.getAreas(
        widget.property.id,
        workspaceId: widget.property.workspaceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final areas = snapshot.data ?? [];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;

            if (areas.isEmpty) {
              return _buildEmptyState(context);
            }

            if (isWide) {
              // Side-by-side layout
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Area list
                  SizedBox(width: 350, child: _buildAreaList(context, areas)),
                  const VerticalDivider(width: 1),
                  // Detail panel
                  Expanded(
                    child: _selectedArea != null
                        ? _buildAreaDetailPanel(context, _selectedArea!)
                        : _buildSelectAreaPrompt(context),
                  ),
                ],
              );
            } else {
              // Stacked layout for mobile
              return _buildAreaList(context, areas);
            }
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.room_outlined, size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No rooms added yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add rooms to track drying progress room by room',
              style: TextStyle(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAreaForm(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add Room'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaList(BuildContext context, List<Area> areas) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${areas.length} Rooms',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => _showAreaForm(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Room'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Area cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: areas.length,
            itemBuilder: (context, index) {
              final area = areas[index];
              return _buildAreaCard(context, area);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAreaCard(BuildContext context, Area area) {
    final isSelected = _selectedArea?.id == area.id;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedArea = area;
          });
        },
        child: SizedBox(
          height: 110,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left column — existing content (compact)
                Expanded(
                  flex: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: area.status.color.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          area.status.icon,
                          color: area.status.color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              area.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            _buildStatusChip(area.status),
                            if (area.isAffected) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.water_drop,
                                    size: 12,
                                    color: AppColors.infoDark,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Affected',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.infoDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (action) =>
                                  _handleAreaAction(context, area, action),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 18),
                                      SizedBox(width: 12),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                if (area.status != AreaStatus.dry)
                                  const PopupMenuItem(
                                    value: 'mark_dry',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.wb_sunny,
                                          size: 18,
                                          color: AppColors.success,
                                        ),
                                        SizedBox(width: 12),
                                        Text('Mark as Dry'),
                                      ],
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: AppColors.errorDark,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Delete',
                                        style: TextStyle(
                                            color: AppColors.errorDark),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (area.trend != null)
                            _buildTrendIndicator(area.trend!),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Right column — sketch preview / add / edit
                Expanded(
                  flex: 2,
                  child: _buildSketchColumn(context, area),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSketchColumn(BuildContext context, Area area) {
    final hasSketch = area.hasSketch;
    return Stack(
      children: [
        Positioned.fill(
          child: hasSketch
              ? RoomSketchView(strokes: area.sketchStrokes)
              : Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    border: Border.all(
                      color: AppColors.cardBorder,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 22,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add sketch',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _openSketchEditor(context, area),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (hasSketch)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(220),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.edit,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openSketchEditor(BuildContext context, Area area) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => RoomSketchEditor(
        roomName: area.name,
        initialStrokes: area.sketchStrokes,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      final updated = area.copyWith(
        sketchStrokes: result,
        updatedAt: DateTime.now(),
      );
      await _areaService.updateArea(updated, previousArea: area);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sketch saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'save the sketch'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildStatusChip(AreaStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: status.color.withAlpha(75)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          color: status.color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTrendIndicator(String trend) {
    IconData icon;
    Color color;

    switch (trend) {
      case 'improving':
        icon = Icons.trending_down;
        color = AppColors.success;
        break;
      case 'worsening':
        icon = Icons.trending_up;
        color = AppColors.error;
        break;
      default:
        icon = Icons.trending_flat;
        color = AppColors.textTertiary;
    }

    return Tooltip(
      message: 'Trend: $trend',
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildSelectAreaPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Select a room to view details',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaDetailPanel(BuildContext context, Area area) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: area.status.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Icon(
                  area.status.icon,
                  color: area.status.color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      area.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildStatusChip(area.status),
                        if (area.isAffected) ...[
                          const SizedBox(width: 8),
                          Chip(
                            avatar: const Icon(
                              Icons.water_drop,
                              size: 14,
                              color: AppColors.info,
                            ),
                            label: const Text('Affected'),
                            backgroundColor: AppColors.infoLight,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: AppColors.infoDark,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _buildDetailRow('Status', area.status.displayName),
                  _buildDetailRow('Affected', area.isAffected ? 'Yes' : 'No'),
                  if (area.trend != null)
                    _buildDetailRow(
                      'Trend',
                      area.trend!.substring(0, 1).toUpperCase() +
                          area.trend!.substring(1),
                    ),
                  if (area.notes != null && area.notes!.isNotEmpty)
                    _buildDetailRow('Notes', area.notes!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showAreaForm(context, area),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit Room'),
                      ),
                      if (area.status != AreaStatus.dry)
                        ElevatedButton.icon(
                          onPressed: () => _markAreaDry(context, area),
                          icon: const Icon(Icons.wb_sunny, size: 18),
                          label: const Text('Mark as Dry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showAreaForm(BuildContext context, Area? area) {
    showAreaFormPopup(context, property: widget.property, existingArea: area);
  }

  void _handleAreaAction(BuildContext context, Area area, String action) {
    switch (action) {
      case 'edit':
        _showAreaForm(context, area);
        break;
      case 'mark_dry':
        _markAreaDry(context, area);
        break;
      case 'delete':
        _confirmDeleteArea(context, area);
        break;
    }
  }

  Future<void> _markAreaDry(BuildContext context, Area area) async {
    try {
      await _areaService.markAreaDry(area.id, widget.property.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Room marked as dry')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteArea(BuildContext context, Area area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete "${area.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await _areaService.deleteArea(area);
        setState(() {
          if (_selectedArea?.id == area.id) {
            _selectedArea = null;
          }
        });
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Room deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
