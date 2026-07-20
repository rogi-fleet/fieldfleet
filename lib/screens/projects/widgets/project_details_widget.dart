import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/custom_field_definition.dart';
import '../../../models/custom_field_type.dart';
import '../../../models/customer_location.dart';
import '../../../models/project.dart';
import '../../../models/vendor_subdivision.dart';
import '../../../providers/custom_field_definitions_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

class ProjectDetailsWidget extends StatefulWidget {
  final Project project;

  const ProjectDetailsWidget({super.key, required this.project});

  @override
  State<ProjectDetailsWidget> createState() => _ProjectDetailsWidgetState();
}

class _ProjectDetailsWidgetState extends State<ProjectDetailsWidget> {
  Future<CustomerLocation?>? _customerLocationFuture;
  Future<VendorSubdivision?>? _vendorSubdivisionFuture;
  late final CustomFieldDefinitionsProvider _customFieldsProvider;

  @override
  void initState() {
    super.initState();
    _syncLookupFutures();
    _customFieldsProvider = CustomFieldDefinitionsProvider();
    _customFieldsProvider.load(widget.project.workspaceId);
  }

  @override
  void dispose() {
    _customFieldsProvider.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProjectDetailsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project.customerLocationId !=
            oldWidget.project.customerLocationId ||
        widget.project.vendorSubdivisionId !=
            oldWidget.project.vendorSubdivisionId) {
      _syncLookupFutures();
    }
  }

  void _syncLookupFutures() {
    final customerLocationId = widget.project.customerLocationId;
    final vendorSubdivisionId = widget.project.vendorSubdivisionId;

    _customerLocationFuture = customerLocationId == null
        ? null
        : ServiceLocator.customerLocationService.getLocation(
            customerLocationId,
          );
    _vendorSubdivisionFuture = vendorSubdivisionId == null
        ? null
        : ServiceLocator.vendorSubdivisionService.getSubdivision(
            vendorSubdivisionId,
          );
  }

  @override
  Widget build(BuildContext context) {
    final terminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    return AnimatedBuilder(
      animation: _customFieldsProvider,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, terminology),
              const SizedBox(height: 12),
              if (widget.project.jobType != null) ...[
                _buildJobTypeChip(widget.project.jobType!),
                const SizedBox(height: 12),
              ],
              _buildDetailTiles(context, terminology),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String terminology) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$terminology Details',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildJobTypeChip(dynamic jobType) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: jobType.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: jobType.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(jobType.icon, size: 14, color: jobType.color),
          const SizedBox(width: 6),
          Text(
            jobType.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: jobType.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTiles(BuildContext context, String terminology) {
    final tiles = <Widget>[];

    if (widget.project.serialNumber != null &&
        widget.project.serialNumber!.isNotEmpty) {
      tiles.add(
        _DetailTile(
          label: '$terminology #',
          value: widget.project.serialNumber!,
        ),
      );
    }
    if (widget.project.purchaseOrderNumber != null &&
        widget.project.purchaseOrderNumber!.isNotEmpty) {
      tiles.add(
        _DetailTile(
          label: 'PO Number',
          value: widget.project.purchaseOrderNumber!,
        ),
      );
    }
    if (widget.project.locationDetails != null &&
        widget.project.locationDetails!.isNotEmpty) {
      tiles.add(
        _DetailTile(
          label: 'Location Details',
          value: widget.project.locationDetails!,
        ),
      );
    }
    if (_customerLocationFuture != null) {
      tiles.add(
        FutureBuilder<CustomerLocation?>(
          future: _customerLocationFuture,
          builder: (context, snapshot) {
            return _DetailTile(
              label: 'Customer Location',
              value: snapshot.data?.name ?? '…',
            );
          },
        ),
      );
    }
    if (_vendorSubdivisionFuture != null) {
      tiles.add(
        FutureBuilder<VendorSubdivision?>(
          future: _vendorSubdivisionFuture,
          builder: (context, snapshot) {
            return _DetailTile(
              label: 'Vendor Division',
              value: snapshot.data?.name ?? '…',
            );
          },
        ),
      );
    }

    final values = widget.project.customFields;
    final customRows = _customFieldsProvider.all
        .where((d) => values[d.key] != null)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final def in customRows) {
      tiles.add(
        _DetailTile(
          label: def.label,
          value: _formatCustomFieldValue(def, values[def.key]),
        ),
      );
    }

    if (tiles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'No additional details',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          tiles[i],
        ],
      ],
    );
  }

  String _formatCustomFieldValue(CustomFieldDefinition def, dynamic value) {
    if (value == null) return '—';
    switch (def.type) {
      case CustomFieldType.checkbox:
        return value == true ? 'Yes' : 'No';
      case CustomFieldType.multiSelect:
        if (value is List) return value.join(', ');
        return value.toString();
      default:
        return value.toString();
    }
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;

  const _DetailTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
