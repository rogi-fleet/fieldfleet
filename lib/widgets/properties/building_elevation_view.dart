import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/property_task_metrics.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import 'property_status_badge.dart';

enum _NamingStyle { floorBased, alpha, sequential }

/// Visual building elevation view showing properties grouped by floor
/// in a grid layout with clickable unit cells.
class BuildingElevationView extends StatefulWidget {
  final List<Property> properties;
  final Project project;
  final void Function(Property property) onPropertyTap;
  final void Function(Property property)? onPropertyEdit;
  final Map<String, PropertyTaskMetrics>? taskMetrics;

  const BuildingElevationView({
    super.key,
    required this.properties,
    required this.project,
    required this.onPropertyTap,
    this.onPropertyEdit,
    this.taskMetrics,
  });

  @override
  State<BuildingElevationView> createState() => _BuildingElevationViewState();
}

class _BuildingElevationViewState extends State<BuildingElevationView> {
  Property? _selectedProperty;
  int _unitsPerFloor = 4;
  _NamingStyle _namingStyle = _NamingStyle.floorBased;
  bool _isCreating = false;
  final _unitsController = TextEditingController(text: '4');

  @override
  void dispose() {
    _unitsController.dispose();
    super.dispose();
  }

  Map<String, List<Property>> _groupByFloor() {
    final grouped = <String, List<Property>>{};

    for (final property in widget.properties) {
      final floor = property.floor ?? 'Unassigned';
      grouped.putIfAbsent(floor, () => []).add(property);
    }

    // Sort floors numerically, then alphabetically
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Unassigned') return 1;
        if (b == 'Unassigned') return -1;
        final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
        final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return a.compareTo(b);
      });

    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  @override
  Widget build(BuildContext context) {
    // Clear selection if property was removed
    if (_selectedProperty != null &&
        !widget.properties.any((p) => p.id == _selectedProperty!.id)) {
      _selectedProperty = null;
    }
    // Update selected property data if it changed
    if (_selectedProperty != null) {
      final updated = widget.properties
          .where((p) => p.id == _selectedProperty!.id)
          .firstOrNull;
      if (updated != null) _selectedProperty = updated;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.tablet;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: _buildLeftPanel(context),
              ),
              const SizedBox(width: 20),
              Expanded(child: _buildRightPanel(context)),
            ],
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            children: [
              _buildLeftPanel(context),
              const SizedBox(height: 20),
              _buildRightPanel(context),
            ],
          ),
        );
      },
    );
  }

  // ── Left Panel ──────────────────────────────────────────────

  Widget _buildLeftPanel(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status legend
          _buildStatusLegend(context),
        ],
      ),
    );
  }

  Widget _buildManualPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add a floor',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Units per floor
          const Text(
            'Units per floor',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: TextFormField(
              controller: _unitsController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
                isDense: true,
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0 && n <= 20) {
                  _unitsPerFloor = n;
                }
              },
            ),
          ),
          const SizedBox(height: 12),

          // Naming style
          const Text(
            'Naming style',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: DropdownButtonFormField<_NamingStyle>(
              borderRadius: AppRadius.cardRadius,
              key: ValueKey(_namingStyle),
              initialValue: _namingStyle,
              isDense: true,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: _NamingStyle.floorBased,
                  child: Text('Floor-based (101, 201...)'),
                ),
                DropdownMenuItem(
                  value: _NamingStyle.alpha,
                  child: Text('Alphabetic (A1, B1...)'),
                ),
                DropdownMenuItem(
                  value: _NamingStyle.sequential,
                  child: Text('Sequential (1, 2, 3...)'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _namingStyle = v);
              },
            ),
          ),
          const SizedBox(height: 16),

          // Add floor button
          FilledButton.icon(
            onPressed: _isCreating ? null : _addFloor,
            icon: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(_isCreating ? 'Adding...' : 'Add floor'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegend(BuildContext context) {
    const legendItems = [
      (PropertyStatus.mitigation, 'Active job'),
      (PropertyStatus.completed, 'Completed'),
      (PropertyStatus.monitoring, 'Monitoring'),
      (PropertyStatus.pending, 'No active job'),
    ];

    final chrome = ChromeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unit status',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: chrome.text,
          ),
        ),
        const SizedBox(height: 10),
        ...legendItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: item.$1.color.withValues(alpha: 0.25),
                    border: Border.all(color: item.$1.color, width: 1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 11,
                    color: chrome.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Right Panel (Building Elevation) ────────────────────────

  Widget _buildRightPanel(BuildContext context) {
    final grouped = _groupByFloor();
    final totalUnits = widget.properties.length;
    final floorCount = grouped.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        children: [
          // Building container
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(AppRadius.r12),
            ),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Building elevation',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$floorCount ${floorCount == 1 ? 'floor' : 'floors'} · '
                      '$totalUnits ${totalUnits == 1 ? 'unit' : 'units'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (widget.properties.isEmpty)
                  _buildEmptyBuilding()
                else
                  _buildBuilding(context, grouped),

                // Detail card
                if (_selectedProperty != null) ...[
                  const SizedBox(height: 16),
                  _buildDetailCard(context),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
          _buildManualPanel(context),
        ],
      ),
    );
  }

  Widget _buildEmptyBuilding() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: const Column(
        children: [
          Icon(Icons.apartment, size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'No floors added yet',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Use "Build" to add floors and units',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuilding(
      BuildContext context, Map<String, List<Property>> grouped) {
    // Reverse so top floor renders first
    final floors = grouped.entries.toList().reversed.toList();

    return Column(
      children: [
        // Roof
        _buildRoof(context),

        // Building body
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.textTertiary.withValues(alpha: 0.4),
              width: 1.5,
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < floors.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.cardBorder,
                  ),
                _buildFloorRow(context, floors[i].key, floors[i].value),
              ],
            ],
          ),
        ),

        // Foundation
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.textTertiary.withValues(alpha: 0.25),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoof(BuildContext context) {
    return ClipPath(
      clipper: _RoofClipper(),
      child: Container(
        height: 36,
        color: AppColors.textTertiary.withValues(alpha: 0.2),
      ),
    );
  }

  Widget _buildFloorRow(
      BuildContext context, String floor, List<Property> units) {
    final floorLabel = floor == 'Unassigned' ? '?' : 'Fl.$floor';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          // Floor label
          SizedBox(
            width: 44,
            child: Text(
              floorLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // Unit cells — horizontal scroll to preserve building shape
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < units.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 0.5,
                        height: 42,
                        color: AppColors.cardBorder,
                      ),
                    _buildUnitCell(context, units[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitCell(BuildContext context, Property property) {
    final isSelected = _selectedProperty?.id == property.id;
    final statusColor = property.status.color;
    final metrics = widget.taskMetrics?[property.id];
    final hasTaskMetrics = metrics != null && metrics.totalCount > 0;

    return _HoverUnitCell(
      isSelected: isSelected,
      statusColor: statusColor,
      onTap: () {
        setState(() {
          _selectedProperty =
              _selectedProperty?.id == property.id ? null : property;
        });
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            property.identifier,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          if (hasTaskMetrics) ...[
            const SizedBox(height: 4),
            Text(
              '${metrics.completedCount}/${metrics.totalCount}',
              style: TextStyle(
                fontSize: 9,
                color: metrics.taskColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: LinearProgressIndicator(
                value: metrics.progressPercent / 100,
                minHeight: 3,
                backgroundColor: metrics.taskColor.withValues(alpha: 0.2),
                valueColor:
                    AlwaysStoppedAnimation<Color>(metrics.taskColor),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context) {
    final property = _selectedProperty!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      property.displayLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    PropertyStatusBadge(status: property.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (property.floor != null) 'Floor ${property.floor}',
                    '${property.areaCount} ${property.areaCount == 1 ? 'area' : 'areas'}',
                    if (property.occupant != null) property.occupant!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onPropertyEdit != null)
            IconButton(
              onPressed: () => widget.onPropertyEdit!(property),
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit structure',
              style: IconButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: () => widget.onPropertyTap(property),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            ),
            child: const Text('Open ↗',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Batch Creation ──────────────────────────────────────────

  Future<void> _addFloor() async {
    setState(() => _isCreating = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final propertyService = ServiceLocator.propertyService;
      final now = DateTime.now();

      // Determine next floor number
      final existingFloors = widget.properties
          .map((p) => int.tryParse(p.floor ?? ''))
          .whereType<int>();
      final nextFloor =
          existingFloors.isEmpty ? 1 : existingFloors.reduce(max) + 1;

      // Check for identifier conflicts before creating
      final existingIds =
          widget.properties.map((p) => p.identifier).toSet();
      for (int i = 1; i <= _unitsPerFloor; i++) {
        final id = _generateIdentifier(nextFloor, i);
        if (existingIds.contains(id)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Identifier "$id" already exists. Choose a different naming style or floor.',
                ),
                backgroundColor: AppColors.warning,
              ),
            );
          }
          return;
        }
      }

      for (int i = 1; i <= _unitsPerFloor; i++) {
        final identifier = _generateIdentifier(nextFloor, i);
        final property = Property(
          id: '',
          workspaceId: widget.project.workspaceId,
          projectId: widget.project.id,
          name: 'Unit',
          identifier: identifier,
          floor: nextFloor.toString(),
          status: PropertyStatus.pending,
          areaCount: 0,
          dryAreaCount: 0,
          contentsCount: 0,
          createdAt: now,
          updatedAt: now,
          createdBy: authProvider.appUser?.id,
        );
        await propertyService.createProperty(property);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added floor $nextFloor with $_unitsPerFloor units',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'add floor'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  String _generateIdentifier(int floor, int unitIndex) {
    switch (_namingStyle) {
      case _NamingStyle.floorBased:
        return '$floor${unitIndex.toString().padLeft(2, '0')}';
      case _NamingStyle.alpha:
        final letter = String.fromCharCode(64 + floor);
        return '$letter$unitIndex';
      case _NamingStyle.sequential:
        final total = widget.properties.length;
        return '${total + unitIndex}';
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────

/// Unit cell with hover highlight effect.
class _HoverUnitCell extends StatefulWidget {
  final bool isSelected;
  final Color statusColor;
  final VoidCallback onTap;
  final Widget child;

  const _HoverUnitCell({
    required this.isSelected,
    required this.statusColor,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverUnitCell> createState() => _HoverUnitCellState();
}

class _HoverUnitCellState extends State<_HoverUnitCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final fillAlpha = _isHovered ? 0.25 : 0.15;
    final borderColor = widget.isSelected
        ? AppColors.primary
        : _isHovered
            ? widget.statusColor.withValues(alpha: 0.7)
            : widget.statusColor.withValues(alpha: 0.4);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 72,
          height: 54,
          decoration: BoxDecoration(
            color: widget.statusColor.withValues(alpha: fillAlpha),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 2.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _RoofClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
