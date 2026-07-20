import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../models/property.dart';
import '../models/area.dart';
import '../services/supabase/property_service.dart';
import '../services/supabase/area_service.dart';

/// A hierarchical multi-selector for choosing Properties and Areas.
/// Used to link tasks to multiple locations in restoration projects.
class PropertyAreaSelector extends StatefulWidget {
  final String projectId;
  final String workspaceId;
  final List<String> selectedPropertyIds;
  final List<String> selectedAreaIds;
  final ValueChanged<List<String>> onPropertyIdsChanged;
  final ValueChanged<List<String>> onAreaIdsChanged;
  final String? labelText;
  final bool enabled;
  final bool showAreaSelector;

  const PropertyAreaSelector({
    super.key,
    required this.projectId,
    required this.workspaceId,
    this.selectedPropertyIds = const [],
    this.selectedAreaIds = const [],
    required this.onPropertyIdsChanged,
    required this.onAreaIdsChanged,
    this.labelText,
    this.enabled = true,
    this.showAreaSelector = true,
  });

  @override
  State<PropertyAreaSelector> createState() => _PropertyAreaSelectorState();
}

class _PropertyAreaSelectorState extends State<PropertyAreaSelector> {
  final SupabasePropertyService _propertyService = SupabasePropertyService();
  final SupabaseAreaService _areaService = SupabaseAreaService();

  List<Property> _properties = [];
  Map<String, List<Area>> _areasMap = {}; // propertyId -> areas
  bool _isLoadingProperties = true;

  @override
  void initState() {
    super.initState();
    _loadProperties();
    // Load areas for all selected properties
    for (final propertyId in widget.selectedPropertyIds) {
      _loadAreas(propertyId);
    }
  }

  @override
  void didUpdateWidget(PropertyAreaSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _loadProperties();
    }
  }

  Future<void> _loadProperties() async {
    try {
      _propertyService
          .getProperties(widget.projectId, workspaceId: widget.workspaceId)
          .listen((properties) {
        if (mounted) {
          setState(() {
            _properties = properties;
            _isLoadingProperties = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProperties = false);
      }
    }
  }

  Future<void> _loadAreas(String propertyId) async {
    try {
      _areaService
          .getAreas(propertyId, workspaceId: widget.workspaceId)
          .listen((areas) {
        if (mounted) {
          setState(() {
            _areasMap[propertyId] = areas;
          });
        }
      });
    } catch (e) {
      // silently fail
    }
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _MultiLocationPickerSheet(
        properties: _properties,
        areasMap: _areasMap,
        selectedPropertyIds: List.from(widget.selectedPropertyIds),
        selectedAreaIds: List.from(widget.selectedAreaIds),
        showAreaSelector: widget.showAreaSelector,
        onDone: (propertyIds, areaIds) {
          widget.onPropertyIdsChanged(propertyIds);
          widget.onAreaIdsChanged(areaIds);
          // Load areas for any newly selected properties
          for (final pid in propertyIds) {
            if (!_areasMap.containsKey(pid)) {
              _loadAreas(pid);
            }
          }
        },
        areaService: _areaService,
        workspaceId: widget.workspaceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProperties) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final hasSelections = widget.selectedPropertyIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                widget.labelText!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected locations as chips
              if (hasSelections)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Property chips
                      for (final propertyId in widget.selectedPropertyIds)
                        _buildLocationChip(propertyId),
                    ],
                  ),
                ),
              // Add/change button
              if (widget.enabled)
                InkWell(
                  onTap: _properties.isEmpty ? null : _showLocationPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasSelections ? Icons.edit : Icons.add,
                          size: 18,
                          color: _properties.isEmpty
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _properties.isEmpty
                              ? 'No properties available'
                              : hasSelections
                                  ? 'Change locations...'
                                  : 'Link to property/area...',
                          style: TextStyle(
                            color: _properties.isEmpty
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationChip(String propertyId) {
    final property = _properties.where((p) => p.id == propertyId).firstOrNull;
    if (property == null) return const SizedBox.shrink();

    // Find areas selected for this property
    final propertyAreas = _areasMap[propertyId] ?? [];
    final selectedAreas = propertyAreas
        .where((a) => widget.selectedAreaIds.contains(a.id))
        .toList();

    final label = selectedAreas.isNotEmpty
        ? '${property.displayLabel} (${selectedAreas.map((a) => a.name).join(', ')})'
        : property.displayLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.home_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.enabled) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                final newPropertyIds = List<String>.from(widget.selectedPropertyIds)
                  ..remove(propertyId);
                // Also remove any areas belonging to this property
                final areasForProperty = propertyAreas.map((a) => a.id).toSet();
                final newAreaIds = widget.selectedAreaIds
                    .where((id) => !areasForProperty.contains(id))
                    .toList();
                widget.onPropertyIdsChanged(newPropertyIds);
                widget.onAreaIdsChanged(newAreaIds);
              },
              child: Icon(
                Icons.close,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MultiLocationPickerSheet extends StatefulWidget {
  final List<Property> properties;
  final Map<String, List<Area>> areasMap;
  final List<String> selectedPropertyIds;
  final List<String> selectedAreaIds;
  final bool showAreaSelector;
  final void Function(List<String> propertyIds, List<String> areaIds) onDone;
  final SupabaseAreaService areaService;
  final String workspaceId;

  const _MultiLocationPickerSheet({
    required this.properties,
    required this.areasMap,
    required this.selectedPropertyIds,
    required this.selectedAreaIds,
    required this.showAreaSelector,
    required this.onDone,
    required this.areaService,
    required this.workspaceId,
  });

  @override
  State<_MultiLocationPickerSheet> createState() =>
      _MultiLocationPickerSheetState();
}

class _MultiLocationPickerSheetState
    extends State<_MultiLocationPickerSheet> {
  late List<String> _selectedPropertyIds;
  late List<String> _selectedAreaIds;
  late Map<String, List<Area>> _areasMap;
  final Set<String> _loadingAreas = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedPropertyIds = List.from(widget.selectedPropertyIds);
    _selectedAreaIds = List.from(widget.selectedAreaIds);
    _areasMap = Map.from(widget.areasMap);
  }

  Future<void> _loadAreasForProperty(String propertyId) async {
    if (_areasMap.containsKey(propertyId)) return;
    setState(() => _loadingAreas.add(propertyId));
    try {
      final areas = await widget.areaService
          .getAreas(propertyId, workspaceId: widget.workspaceId)
          .first;
      if (mounted) {
        setState(() {
          _areasMap[propertyId] = areas;
          _loadingAreas.remove(propertyId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _areasMap[propertyId] = [];
          _loadingAreas.remove(propertyId);
        });
      }
    }
  }

  void _toggleProperty(String propertyId) {
    setState(() {
      if (_selectedPropertyIds.contains(propertyId)) {
        _selectedPropertyIds.remove(propertyId);
        // Remove areas belonging to this property
        final areasForProperty =
            (_areasMap[propertyId] ?? []).map((a) => a.id).toSet();
        _selectedAreaIds.removeWhere((id) => areasForProperty.contains(id));
      } else {
        _selectedPropertyIds.add(propertyId);
        _loadAreasForProperty(propertyId);
      }
    });
  }

  void _toggleArea(String areaId) {
    setState(() {
      if (_selectedAreaIds.contains(areaId)) {
        _selectedAreaIds.remove(areaId);
      } else {
        _selectedAreaIds.add(areaId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredProperties = widget.properties.where((property) {
      if (_searchQuery.isEmpty) return true;
      return property.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          property.identifier
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.location_on, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Locations',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onDone(_selectedPropertyIds, _selectedAreaIds);
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search properties...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          // Clear selection option
          if (_selectedPropertyIds.isNotEmpty)
            ListTile(
              leading: Icon(Icons.clear, color: AppColors.error),
              title: const Text('Clear all selections'),
              dense: true,
              onTap: () {
                setState(() {
                  _selectedPropertyIds.clear();
                  _selectedAreaIds.clear();
                });
              },
            ),
          const Divider(),
          // Property and Area list
          Expanded(
            child: filteredProperties.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'No properties available'
                          : 'No matching properties',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredProperties.length,
                    itemBuilder: (context, index) {
                      final property = filteredProperties[index];
                      final isSelected =
                          _selectedPropertyIds.contains(property.id);
                      final areas = _areasMap[property.id] ?? [];
                      final isLoadingPropertyAreas =
                          _loadingAreas.contains(property.id);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Property tile with checkbox
                          CheckboxListTile(
                            value: isSelected,
                            onChanged: (_) => _toggleProperty(property.id),
                            secondary: Icon(
                              Icons.home,
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : AppColors.textSecondary,
                            ),
                            title: Text(
                              property.displayLabel,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : null,
                              ),
                            ),
                            subtitle: property.floor != null
                                ? Text('Floor: ${property.floor}')
                                : null,
                            controlAffinity: ListTileControlAffinity.trailing,
                          ),
                          // Areas for selected property
                          if (isSelected &&
                              widget.showAreaSelector &&
                              areas.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 56),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                    child: Text(
                                      'Areas (optional):',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  ...areas.map((area) {
                                    final isAreaSelected =
                                        _selectedAreaIds.contains(area.id);
                                    return CheckboxListTile(
                                      value: isAreaSelected,
                                      onChanged: (_) => _toggleArea(area.id),
                                      secondary: Icon(
                                        Icons.room_outlined,
                                        size: 20,
                                        color: isAreaSelected
                                            ? Theme.of(context).primaryColor
                                            : AppColors.textTertiary,
                                      ),
                                      title: Text(
                                        area.name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isAreaSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isAreaSelected
                                              ? Theme.of(context).primaryColor
                                              : null,
                                        ),
                                      ),
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      controlAffinity:
                                          ListTileControlAffinity.trailing,
                                    );
                                  }),
                                ],
                              ),
                            ),
                          if (isSelected &&
                              widget.showAreaSelector &&
                              isLoadingPropertyAreas)
                            const Padding(
                              padding: EdgeInsets.only(left: 72, top: 8),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          if (isSelected &&
                              widget.showAreaSelector &&
                              !isLoadingPropertyAreas &&
                              areas.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 72, top: 4, bottom: 8),
                              child: Text(
                                'No areas defined for this property',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
