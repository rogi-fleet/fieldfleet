import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../services/service_locator.dart';
import '../../utils/pdf_export_io.dart'
    if (dart.library.html) '../../utils/pdf_export_web.dart' as pdf_export;

import '../../models/property_status.dart';
import 'property_status_badge.dart';
import 'property_form_popup.dart';
import 'property_summary_tab.dart';
import 'property_contents_tab.dart';
import 'property_media_tab.dart';
import '../notes/entity_notes_tab.dart';
import 'property_tasks_tab.dart';
import '../adaptive_navigation.dart';
import '../common/view_icon_button.dart';

/// Detail view for viewing and managing a single property.
/// Can be used as a standalone screen or embedded in a tab.
class PropertyDetailView extends StatefulWidget {
  final Project project;
  final String propertyId;
  final VoidCallback? onBack;
  final ValueChanged<String>? onPropertySelected;

  const PropertyDetailView({
    super.key,
    required this.project,
    required this.propertyId,
    this.onBack,
    this.onPropertySelected,
  });

  @override
  State<PropertyDetailView> createState() => _PropertyDetailViewState();
}

class _PropertyDetailViewState extends State<PropertyDetailView> {
  final _propertyService = ServiceLocator.propertyService;
  String _selectedTab = 'summary';

  static const List<(String, IconData, String)> _tabs = [
    ('summary', Icons.dashboard, 'Summary'),
    ('tasks', Icons.task_alt, 'Tasks'),
    ('contents', Icons.inventory_2, 'Contents'),
    ('media', Icons.photo_library, 'Media'),
    ('notes', Icons.note, 'Notes'),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Property?>(
      stream: _propertyService.watchProperty(widget.propertyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final property = snapshot.data;
        if (property == null) {
          return Center(child: Text('Property not found'));
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: _buildPropertySwitcherTitle(context, property),
            actions: [
              if (MediaQuery.sizeOf(context).width <= AppBreakpoints.tablet &&
                  property.floor != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildInfoChip(
                    Icons.layers,
                    'Floor: ${property.floor}',
                  ),
                ),
              _buildStatusButton(context, property),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditForm(context, property),
                tooltip: 'Edit Structure',
              ),
            ],
          ),
          body: Column(
            children: [
              // Property header (stats)
              _buildPropertyHeader(context, property),
              // Icon toolbar
              Builder(
                builder: (context) {
                  final chrome = ChromeColors.of(context);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: chrome.background,
                      border: Border(
                        bottom: BorderSide(color: chrome.divider),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final (id, icon, label) in _tabs)
                          ViewIconButton(
                            icon: icon,
                            tooltip: label,
                            isSelected: _selectedTab == id,
                            onTap: () {
                              setState(() => _selectedTab = id);
                              TabSwitchNotification().dispatch(context);
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
              // Tab content
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: IndexedStack(
                    index: _tabs.indexWhere((t) => t.$1 == _selectedTab),
                    children: [
                      PropertySummaryTab(
                        property: property,
                        project: widget.project,
                      ),
                      PropertyTasksTab(
                        property: property,
                        project: widget.project,
                      ),
                      PropertyContentsTab(
                        property: property,
                        project: widget.project,
                      ),
                      PropertyMediaTab(
                        property: property,
                        project: widget.project,
                      ),
                      EntityNotesTab(
                        workspaceId: property.workspaceId,
                        entityType: 'property',
                        entityId: property.id,
                        projectId: property.projectId,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPropertyHeader(BuildContext context, Property property) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(50),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > AppBreakpoints.mobile;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: status and metadata (identifier/name are shown in AppBar title)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PropertyStatusBadge(status: property.status),
                      if (property.floor != null || property.occupant != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 16,
                            children: [
                              if (property.floor != null)
                                _buildInfoChip(
                                  Icons.layers,
                                  'Floor: ${property.floor}',
                                ),
                              if (property.occupant != null)
                                _buildInfoChip(
                                  Icons.person,
                                  property.occupant!,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Right: Stats
                _buildStatsSection(context, property),
              ],
            );
          } else {
            // Mobile view: stats strip + status in one row
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildAppBarStatsStrip(context, property),
                PropertyStatusBadge(status: property.status),
                if (property.occupant != null)
                  _buildInfoChip(Icons.person, property.occupant!),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    final chrome = ChromeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: chrome.text),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: chrome.text)),
      ],
    );
  }

  Widget _buildStatsSection(BuildContext context, Property property) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatCard(
            context,
            Icons.room,
            '${property.areaCount}',
            'Rooms',
            AppColors.info,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            context,
            Icons.air,
            '${property.dryAreaCount}/${property.areaCount}',
            'Dry',
            property.isDryingComplete ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            context,
            Icons.inventory_2,
            '${property.contentsCount}',
            'Contents',
            AppColors.messageAccent,
          ),
          const SizedBox(width: 16),
          // Drying progress
          Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: property.areaCount > 0
                          ? property.dryingProgress / 100
                          : 0,
                      backgroundColor: AppColors.cardBorder,
                      valueColor: AlwaysStoppedAnimation(
                        property.isDryingComplete
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      strokeWidth: 3,
                    ),
                    Text(
                      '${property.dryingProgress.toInt()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Progress',
                style: TextStyle(fontSize: 10, color: ChromeColors.of(context).text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Builder(
          builder: (context) => Text(
            label,
            style: TextStyle(fontSize: 10, color: ChromeColors.of(context).text),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBarStatsStrip(BuildContext context, Property property) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: ChromeColors.of(context).text,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    Widget stat(String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withAlpha(70),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(width: 3),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stat('R', '${property.areaCount}'),
          const SizedBox(width: 4),
          stat('D', '${property.dryAreaCount}/${property.areaCount}'),
          const SizedBox(width: 4),
          stat('C', '${property.contentsCount}'),
          const SizedBox(width: 4),
          stat('P', '${property.dryingProgress.toInt()}%'),
        ],
      ),
    );
  }

  Widget _buildPropertySwitcherTitle(BuildContext context, Property property) {
    return StreamBuilder<List<Property>>(
      stream: _propertyService.getProperties(
        widget.project.id,
        workspaceId: widget.project.workspaceId,
      ),
      builder: (context, snapshot) {
        final properties = snapshot.data ?? const <Property>[];
        final sortedProperties = List<Property>.from(properties)
          ..sort(
            (a, b) => a.identifier.toLowerCase().compareTo(
              b.identifier.toLowerCase(),
            ),
          );

        if (sortedProperties.length < 2) {
          return Text(property.displayLabel, overflow: TextOverflow.ellipsis);
        }

        final selectedId = sortedProperties.any((p) => p.id == property.id)
            ? property.id
            : sortedProperties.first.id;

        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedId,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppRadius.r12),
            icon: const Icon(Icons.keyboard_arrow_down),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onChanged: (value) {
              if (value == null || value == property.id) return;
              _handlePropertySelection(context, value);
            },
            items: sortedProperties
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.id,
                    child: Text(
                      item.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  void _handlePropertySelection(BuildContext context, String propertyId) {
    if (widget.onPropertySelected != null) {
      widget.onPropertySelected!(propertyId);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PropertyDetailView(
          project: widget.project,
          propertyId: propertyId,
          onBack: widget.onBack,
        ),
      ),
    );
  }

  Widget _buildStatusButton(BuildContext context, Property property) {
    return PopupMenuButton<PropertyStatus>(
      tooltip: 'Change status',
      icon: Icon(property.status.icon, color: property.status.color),
      onSelected: (newStatus) {
        _propertyService.updateProperty(property.copyWith(status: newStatus));
      },
      itemBuilder: (context) => PropertyStatus.values
          .map(
            (status) => PopupMenuItem<PropertyStatus>(
              value: status,
              child: Row(
                children: [
                  Icon(status.icon, size: 18, color: status.color),
                  const SizedBox(width: 10),
                  Text(
                    status.displayName,
                    style: TextStyle(
                      color: status.color,
                      fontWeight: status == property.status
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (status == property.status) ...[
                    const Spacer(),
                    Icon(Icons.check, size: 16, color: status.color),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  void _showEditForm(BuildContext context, Property property) {
    showPropertyFormPopup(
      context,
      project: widget.project,
      existingProperty: property,
    );
  }
}

