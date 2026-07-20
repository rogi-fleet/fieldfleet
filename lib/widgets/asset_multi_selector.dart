import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../models/asset.dart';
import '../services/supabase/asset_service.dart';
import '../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// Multi-select dialog for choosing required assets for a task
class AssetMultiSelector extends StatefulWidget {
  final String workspaceId;
  final String projectId;
  final List<String> selectedAssetIds;
  final bool useSheetPresentation;

  const AssetMultiSelector({
    super.key,
    required this.workspaceId,
    required this.projectId,
    required this.selectedAssetIds,
    this.useSheetPresentation = false,
  });

  @override
  State<AssetMultiSelector> createState() => _AssetMultiSelectorState();
}

class _AssetMultiSelectorState extends State<AssetMultiSelector> {
  final Set<String> _selectedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.selectedAssetIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetService = SupabaseAssetService(workspaceId: widget.workspaceId);
    final content = SizedBox(
      width: 500,
      height: 600,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Required Equipment',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Search equipment',
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<Asset>>(
                stream: assetService.getAssets(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: SelectableText(
                        UserFacingError.uiMessage(
                          snapshot.error,
                          action: 'load data',
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No equipment found'));
                  }

                  final assets = snapshot.data!
                      .where(
                        (a) =>
                            _searchQuery.isEmpty ||
                            a.name.toLowerCase().contains(_searchQuery) ||
                            (a.description?.toLowerCase().contains(
                                  _searchQuery,
                                ) ??
                                false),
                      )
                      .toList();

                  if (assets.isEmpty) {
                    return const Center(child: Text('No matching equipment'));
                  }

                  return ListView.builder(
                    itemCount: assets.length,
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      final isSelected = _selectedIds.contains(asset.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedIds.add(asset.id);
                            } else {
                              _selectedIds.remove(asset.id);
                            }
                          });
                        },
                        title: Text(asset.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (asset.description != null)
                              Text(asset.description!),
                            Row(
                              children: [
                                Chip(
                                  label: Text(asset.status),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (asset.assignedToProjectId != null &&
                                    asset.assignedToProjectId !=
                                        widget.projectId)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Chip(
                                      label: const Text('Assigned elsewhere'),
                                      backgroundColor: AppColors.warning,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        secondary: Icon(
                          Icons.inventory_2,
                          color: _getAssetStatusColor(asset.status),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, _selectedIds.toList());
                    },
                    child: Text('Select (${_selectedIds.length})'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (widget.useSheetPresentation) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: content,
        ),
      );
    }

    return Dialog(child: content);
  }

  Color _getAssetStatusColor(String status) {
    switch (status) {
      case 'available':
        return AppColors.success;
      case 'assigned':
        return AppColors.info;
      case 'maintenance':
        return AppColors.warning;
      case 'retired':
        return AppColors.textTertiary;
      default:
        return AppColors.textTertiary;
    }
  }
}
