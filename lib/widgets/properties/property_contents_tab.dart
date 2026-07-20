import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:intl/intl.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/area.dart';
import '../../models/property_contents.dart';
import '../../models/contents_status.dart';


import 'contents_form_popup.dart';

/// Contents tab showing items tracked within a property.
class PropertyContentsTab extends StatefulWidget {
  final Property property;
  final Project project;

  const PropertyContentsTab({
    super.key,
    required this.property,
    required this.project,
  });

  @override
  State<PropertyContentsTab> createState() => _PropertyContentsTabState();
}

class _PropertyContentsTabState extends State<PropertyContentsTab> {
  final dynamic _contentsService = ServiceLocator.propertyContentsService;
  final dynamic _areaService = ServiceLocator.areaService;

  String? _selectedAreaId;
  ContentsStatus? _selectedStatus;
  List<Area> _areas = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with filters and add button
        _buildHeader(context),
        const Divider(height: 1),
        // Contents list
        Expanded(child: _buildContentsList(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: [
          // Area filter
          StreamBuilder<List<Area>>(
            stream: _areaService.getAreas(
              widget.property.id,
              workspaceId: widget.property.workspaceId,
            ),
            builder: (context, snapshot) {
              _areas = snapshot.data ?? [];
              return DropdownButton<String?>(
                borderRadius: AppRadius.cardRadius,
                value: _selectedAreaId,
                hint: const Text('All Areas'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Areas')),
                  ...(_areas).map(
                    (area) => DropdownMenuItem(
                      value: area.id,
                      child: Text(area.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedAreaId = value;
                  });
                },
              );
            },
          ),
          const SizedBox(width: 16),
          // Status filter
          DropdownButton<ContentsStatus?>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedStatus,
            hint: const Text('All Status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Status')),
              ...ContentsStatus.values.map(
                (status) => DropdownMenuItem(
                  value: status,
                  child: Row(
                    children: [
                      Icon(status.icon, size: 16, color: status.color),
                      const SizedBox(width: 8),
                      Text(status.displayName),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedStatus = value;
              });
            },
          ),
          const Spacer(),
          // Add item button
          ElevatedButton.icon(
            onPressed: () => _showContentsForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Add Item'),
          ),
        ],
      ),
    );
  }

  Widget _buildContentsList(BuildContext context) {
    return StreamBuilder<List<PropertyContents>>(
      stream: _contentsService.getContentsByProperty(
        widget.property.id,
        workspaceId: widget.property.workspaceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allContents = snapshot.data ?? [];

        // Apply filters
        var contents = allContents;
        if (_selectedAreaId != null) {
          contents = contents
              .where((c) => c.areaId == _selectedAreaId)
              .toList();
        }
        if (_selectedStatus != null) {
          contents = contents
              .where((c) => c.status == _selectedStatus)
              .toList();
        }

        if (contents.isEmpty) {
          return _buildEmptyState(context, allContents.isEmpty);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Card(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Area')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Photo')),
                DataColumn(label: Text('Barcode')),
                DataColumn(label: Text('Actions')),
              ],
              rows: contents.map((item) {
                final area = _areas
                    .where((a) => a.id == item.areaId)
                    .firstOrNull;
                return DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.itemName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (item.description != null &&
                              item.description!.isNotEmpty)
                            Text(
                              item.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    DataCell(Text(area?.name ?? '-')),
                    DataCell(_buildStatusChip(item.status)),
                    DataCell(Text('${item.quantity}')),
                    DataCell(_buildPhotoCell(item)),
                    DataCell(Text(item.barcode ?? '-')),
                    DataCell(_buildRowActions(context, item)),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool noContents) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              noContents
                  ? 'No contents items tracked yet'
                  : 'No items match your filters',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              noContents
                  ? 'Add items to track personal property and contents'
                  : 'Try adjusting your filters',
              style: TextStyle(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            if (noContents) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showContentsForm(context, null),
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ContentsStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: status.color.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: status.color.withAlpha(75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(
              color: status.color,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCell(PropertyContents item) {
    if (!item.hasPhoto) {
      return Icon(
        Icons.image_not_supported,
        color: AppColors.textTertiary,
        size: 20,
      );
    }

    return InkWell(
      onTap: () => _showPhotoDialog(context, item),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          image: DecorationImage(
            image: CachedNetworkImageProvider(item.photoUrl!),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildRowActions(BuildContext context, PropertyContents item) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (action) => _handleItemAction(context, item, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 12),
              Text('Edit'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility, size: 20),
              SizedBox(width: 12),
              Text('View Details'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Status update options
        ...ContentsStatus.values
            .where((s) => s != item.status)
            .take(4)
            .map(
              (status) => PopupMenuItem(
                value: 'status_${status.name}',
                child: Row(
                  children: [
                    Icon(status.icon, size: 20, color: status.color),
                    const SizedBox(width: 12),
                    Text('Set ${status.displayName}'),
                  ],
                ),
              ),
            ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: AppColors.errorDark),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: AppColors.errorDark)),
            ],
          ),
        ),
      ],
    );
  }

  void _showContentsForm(BuildContext context, PropertyContents? item) {
    showContentsFormPopup(
      context,
      property: widget.property,
      areas: _areas,
      existingItem: item,
    );
  }

  void _showPhotoDialog(BuildContext context, PropertyContents item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.itemName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Photo
            if (item.hasPhoto)
              CachedNetworkImage(
                imageUrl: item.photoUrl!,
                width: 400,
                height: 300,
                fit: BoxFit.contain,
              ),
          ],
        ),
      ),
    );
  }

  void _handleItemAction(
    BuildContext context,
    PropertyContents item,
    String action,
  ) {
    if (action == 'edit') {
      _showContentsForm(context, item);
    } else if (action == 'view') {
      _showItemDetails(context, item);
    } else if (action == 'delete') {
      _confirmDeleteItem(context, item);
    } else if (action.startsWith('status_')) {
      final statusName = action.substring(7);
      final newStatus = ContentsStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => item.status,
      );
      _updateStatus(context, item, newStatus);
    }
  }

  void _showItemDetails(BuildContext context, PropertyContents item) {
    final area = _areas.where((a) => a.id == item.areaId).firstOrNull;
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.itemName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.hasPhoto) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: CachedNetworkImage(
                    imageUrl: item.photoUrl!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildDetailRow('Status', item.status.displayName),
              _buildDetailRow('Area', area?.name ?? '-'),
              _buildDetailRow('Quantity', '${item.quantity}'),
              if (item.description != null)
                _buildDetailRow('Description', item.description!),
              if (item.barcode != null)
                _buildDetailRow('Barcode', item.barcode!),
              if (item.notes != null) _buildDetailRow('Notes', item.notes!),
              _buildDetailRow('Created', dateFormat.format(item.createdAt)),
              _buildDetailRow('Updated', dateFormat.format(item.updatedAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showContentsForm(context, item);
            },
            child: const Text('Edit'),
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

  Future<void> _updateStatus(
    BuildContext context,
    PropertyContents item,
    ContentsStatus newStatus,
  ) async {
    try {
      await _contentsService.updateStatus(item.id, newStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${newStatus.displayName}')),
        );
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

  Future<void> _confirmDeleteItem(
    BuildContext context,
    PropertyContents item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.itemName}"?'),
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
        await _contentsService.deleteContents(item.id, widget.property.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Item deleted')));
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
