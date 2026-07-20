import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/catalog_item.dart';
import '../../../models/project.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Log materials used on-site, linked to the catalog and budget system.
class MaterialUsageWidget extends StatefulWidget {
  final String workspaceId;
  final String userId;
  final List<Project>? allProjects;
  final Map<String, String> projectNamesById;

  const MaterialUsageWidget({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.allProjects,
    this.projectNamesById = const <String, String>{},
  });

  @override
  State<MaterialUsageWidget> createState() => _MaterialUsageWidgetState();
}

class _MaterialUsageWidgetState extends State<MaterialUsageWidget> {
  final List<_MaterialLogEntry> _recentLogs = [];

  @override
  Widget build(BuildContext context) {
    context.watch<WorkspaceProvider>().projectTerminology;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.base),

            // Quick log button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showLogMaterialSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log Material Used'),
              ),
            ),

            if (_recentLogs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.iconGap),
              const Text(
                'Recent Usage',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._recentLogs.take(5).map((log) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2,
                        size: 16,
                        color: Color(0xFFE8973A),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${log.quantity} ${log.unit} • ${log.projectName}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        DateFormat.jm().format(log.loggedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sectionGap),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.inventory,
                        size: 48,
                        color: AppColors.cardBorder,
                      ),
                      const SizedBox(height: AppSpacing.iconGap),
                      const Text(
                        'No materials logged today',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        kIsWeb ? 'Click above to log material usage' : 'Tap above to log material usage',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
            color: const Color(0xFFE8973A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.inventory,
            color: Color(0xFFE8973A),
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.iconGap),
        const Expanded(
          child: Text(
            'Material Usage',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/catalog'),
          child: const Text('Catalog'),
        ),
      ],
    );
  }

  void _showLogMaterialSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return _LogMaterialSheet(
          workspaceId: widget.workspaceId,
          allProjects: widget.allProjects,
          projectNamesById: widget.projectNamesById,
          onLogged: (entry) {
            setState(() => _recentLogs.insert(0, entry));
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }
}

class _LogMaterialSheet extends StatefulWidget {
  final String workspaceId;
  final List<Project>? allProjects;
  final Map<String, String> projectNamesById;
  final ValueChanged<_MaterialLogEntry> onLogged;

  const _LogMaterialSheet({
    required this.workspaceId,
    required this.allProjects,
    required this.projectNamesById,
    required this.onLogged,
  });

  @override
  State<_LogMaterialSheet> createState() => _LogMaterialSheetState();
}

class _LogMaterialSheetState extends State<_LogMaterialSheet> {
  CatalogItem? _selectedItem;
  String? _selectedProjectId;
  final _quantityController = TextEditingController(text: '1');

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Log Material',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Catalog item selector
          StreamBuilder<List<CatalogItem>>(
            stream: ServiceLocator.catalogService.getCatalogItems(
              widget.workspaceId,
            ),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              final leafItems = items
                  .where((i) => i.itemType == CatalogItemType.item)
                  .toList();

              return DropdownButtonFormField<CatalogItem>(
                borderRadius: AppRadius.cardRadius,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: leafItems.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (item) =>
                    setState(() => _selectedItem = item),
              );
            },
          ),
          const SizedBox(height: 12),

          // Project selector
          DropdownButtonFormField<String>(
            borderRadius: AppRadius.cardRadius,
            decoration: InputDecoration(
              labelText: singularTerminology,
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: (widget.allProjects ?? <Project>[])
                .where((p) => p.status == ProjectStatus.active)
                .map((project) {
              return DropdownMenuItem(
                value: project.id,
                child: Text(
                  project.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (id) =>
                setState(() => _selectedProjectId = id),
          ),
          const SizedBox(height: 12),

          // Quantity
          TextFormField(
            controller: _quantityController,
            decoration: InputDecoration(
              labelText: 'Quantity',
              border: const OutlineInputBorder(),
              suffixText: _selectedItem?.unit ?? '',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Submit
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedItem != null && _selectedProjectId != null
                  ? _submit
                  : null,
              child: const Text('Log Usage'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text) ?? 1;
    widget.onLogged(
      _MaterialLogEntry(
        itemName: _selectedItem!.name,
        quantity: quantity,
        unit: _selectedItem!.unit ?? 'ea',
        projectName: widget.projectNamesById[_selectedProjectId!] ?? 'Unknown',
        loggedAt: DateTime.now(),
      ),
    );
  }
}

class _MaterialLogEntry {
  final String itemName;
  final double quantity;
  final String unit;
  final String projectName;
  final DateTime loggedAt;

  _MaterialLogEntry({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.projectName,
    required this.loggedAt,
  });
}
