import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/customer.dart';
import '../../models/customer_contact.dart';
import '../../models/customer_location.dart';
import '../../models/project.dart';
import '../../providers/workspace_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';
import '../common/zero_items_action_empty_state.dart';
import '../table/table_controls_bar.dart';
import 'customer_location_form.dart';

class CustomerLocationsTab extends StatefulWidget {
  final Customer customer;
  final Customer? parentCustomer;
  final List<Customer> childCustomers;

  const CustomerLocationsTab({
    super.key,
    required this.customer,
    this.parentCustomer,
    this.childCustomers = const [],
  });

  @override
  State<CustomerLocationsTab> createState() => _CustomerLocationsTabState();
}

class _CustomerLocationsTabState extends State<CustomerLocationsTab> {
  final _locationService = ServiceLocator.customerLocationService;
  final _geocodingService = GeocodingService();
  final _geocoded = <String, LatLng>{};
  String? _selectedLocationId;
  bool _showMap = false;
  bool _geocodingStarted = false;
  List<Project>? _customerProjects;

  @override
  void initState() {
    super.initState();
    _loadCustomerProjects();
  }

  Future<void> _loadCustomerProjects() async {
    try {
      final projects = await ServiceLocator.customerService
          .getCustomerProjects(widget.customer.id)
          .first;
      if (mounted) {
        setState(() => _customerProjects = projects);
      }
    } catch (_) {
      if (mounted) setState(() => _customerProjects = const []);
    }
  }

  List<_MapEntry> _buildMapEntries(
    List<CustomerLocation> locations,
    String singularTerminology,
  ) {
    final entries = <_MapEntry>[];
    final seen = <String>{};

    void addEntry(_MapEntry entry) {
      final key = entry.address.trim().toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      entries.add(entry);
    }

    // Location addresses
    for (final loc in locations) {
      final addr = loc.fullAddress;
      if (addr != null && addr.isNotEmpty) {
        addEntry(
          _MapEntry(
            id: loc.id,
            title: loc.name,
            subtitle: 'Location',
            address: addr,
            icon: Icons.location_on_outlined,
            latitude: loc.latitude,
            longitude: loc.longitude,
          ),
        );
      }
    }

    // Customer's own address
    final customerAddr = widget.customer.fullAddress;
    if (customerAddr != null && customerAddr.isNotEmpty) {
      addEntry(
        _MapEntry(
          title: widget.customer.displayName,
          subtitle: 'Customer address',
          address: customerAddr,
          icon: Icons.business_outlined,
        ),
      );
    }

    // Project site addresses
    if (_customerProjects != null) {
      for (final project in _customerProjects!) {
        if (project.address.trim().isEmpty) continue;
        final locationSubtitle =
            project.locationDetails?.trim().isNotEmpty == true
            ? '$singularTerminology site \u2022 ${project.locationDetails!.trim()}'
            : '$singularTerminology site';
        addEntry(
          _MapEntry(
            title: project.name,
            subtitle: locationSubtitle,
            address: project.address.trim(),
            icon: Icons.work_outline,
            latitude: project.latitude,
            longitude: project.longitude,
          ),
        );
      }
    }

    return entries;
  }

  List<_MapEntry> _resolveMappable(List<_MapEntry> entries) {
    return entries
        .map((e) {
          if (e.latitude != null &&
              e.longitude != null &&
              !e.latitude!.isNaN &&
              !e.longitude!.isNaN) {
            return e;
          }
          final coords = _geocoded[e.address.trim().toLowerCase()];
          if (coords == null) return null;
          return _MapEntry(
            id: e.id,
            title: e.title,
            subtitle: e.subtitle,
            address: e.address,
            icon: e.icon,
            latitude: coords.latitude,
            longitude: coords.longitude,
          );
        })
        .whereType<_MapEntry>()
        .toList();
  }

  Future<void> _geocodeEntries(List<_MapEntry> entries) async {
    final toGeocode = entries
        .where((e) => e.latitude == null || e.longitude == null)
        .map((e) => e.address.trim())
        .toSet();

    for (final address in toGeocode) {
      final key = address.toLowerCase();
      if (_geocoded.containsKey(key)) continue;
      final result = await _geocodingService.geocodeAddress(address);
      if (result != null && mounted) {
        setState(() {
          _geocoded[key] = LatLng(result.latitude, result.longitude);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.customer.workspaceId;
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return StreamBuilder<List<CustomerLocation>>(
      stream: _locationService.getLocations(widget.customer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final locations = snapshot.data ?? [];

        if (locations.isEmpty) {
          return _buildEmptyState(workspaceId);
        }

        // Build map entries from locations + customer address + projects
        final mapEntries = _buildMapEntries(locations, singularTerminology);

        if (!_geocodingStarted && mapEntries.isNotEmpty) {
          _geocodingStarted = true;
          _geocodeEntries(mapEntries);
        }

        final resolvedEntries = _resolveMappable(mapEntries);

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= AppBreakpoints.compact;

            final listContent = _buildLocationList(
              locations,
              workspaceId,
              singularTerminology,
              wide,
            );

            if (wide && resolvedEntries.isNotEmpty) {
              return Row(
                children: [
                  SizedBox(
                    width: constraints.maxWidth * 0.48,
                    child: listContent,
                  ),
                  Expanded(
                    child: _LocationsMap(
                      entries: resolvedEntries,
                      focusEntry: _selectedLocationId == null
                          ? null
                          : resolvedEntries
                                .where((e) => e.id == _selectedLocationId)
                                .firstOrNull,
                    ),
                  ),
                ],
              );
            }

            // Mobile: toggle map view
            if (_showMap && resolvedEntries.isNotEmpty) {
              return Column(
                children: [
                  _buildHeader(
                    locations.length,
                    workspaceId,
                    resolvedEntries.isNotEmpty,
                  ),
                  Expanded(
                    child: _LocationsMap(
                      entries: resolvedEntries,
                      focusEntry: null,
                    ),
                  ),
                ],
              );
            }

            return listContent;
          },
        );
      },
    );
  }

  Widget _buildHeader(int count, String workspaceId, bool hasMap) {
    final chrome = ChromeColors.of(context);
    final activeControlColor = chrome.isDark
        ? AppColors.secondaryLight
        : AppColors.secondary;

    return TableControlsBar(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      children: [
        Text(
          '$count location${count == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: chrome.text,
          ),
        ),
        const Spacer(),
        if (hasMap)
          IconButton(
            icon: Icon(
              _showMap ? Icons.list : Icons.map_outlined,
              size: 20,
              color: _showMap ? activeControlColor : chrome.text,
            ),
            tooltip: _showMap ? 'List view' : 'Map view',
            onPressed: () => setState(() => _showMap = !_showMap),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        IconButton(
          icon: Icon(Icons.add, size: 20, color: chrome.text),
          tooltip: 'Create Location',
          onPressed: () => _showLocationForm(workspaceId),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildLocationList(
    List<CustomerLocation> locations,
    String workspaceId,
    String singularTerminology,
    bool wide,
  ) {
    final mapEntries = _buildMapEntries(locations, singularTerminology);
    final resolvedEntries = _resolveMappable(mapEntries);
    final hasMap =
        resolvedEntries.isNotEmpty ||
        mapEntries.any((e) => e.latitude != null && e.longitude != null);

    return Column(
      children: [
        _buildHeader(locations.length, workspaceId, hasMap),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: locations.length,
            itemBuilder: (context, index) {
              final location = locations[index];
              final contacts = _findContacts(location.contactIds);
              return _LocationCard(
                location: location,
                contacts: contacts,
                selected: _selectedLocationId == location.id,
                singularTerminology: singularTerminology,
                onTap: wide
                    ? () => setState(() => _selectedLocationId = location.id)
                    : null,
                onEdit: () =>
                    _showLocationForm(workspaceId, location: location),
                onArchive: () => _archiveLocation(location),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String workspaceId) {
    return ZeroItemsActionEmptyState(
      icon: Icons.location_off_outlined,
      title: 'No locations yet',
      subtitle:
          'Add locations to track multiple service sites for this customer.',
      ctaLabel: 'Create Location',
      onTap: () => _showLocationForm(workspaceId),
    );
  }

  List<CustomerContact> _findContacts(List<String> contactIds) {
    if (contactIds.isEmpty) return [];
    return widget.customer.contacts
        .where((c) => c.isActive && contactIds.contains(c.id))
        .toList();
  }

  void _showLocationForm(String workspaceId, {CustomerLocation? location}) {
    showDialog(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: workspaceId,
        customerId: widget.customer.id,
        location: location,
        contacts: widget.customer.contacts.where((c) => c.isActive).toList(),
        onSave: (loc) async {
          if (location != null) {
            await _locationService.updateLocation(loc);
          } else {
            await _locationService.createLocation(loc);
          }
        },
      ),
    );
  }

  void _archiveLocation(CustomerLocation location) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Location'),
        content: Text(
          'Are you sure you want to archive "${location.name}"? '
          'Existing jobs linked to this location will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _locationService.deleteLocation(location.id);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location Card
// ---------------------------------------------------------------------------

class _LocationCard extends StatefulWidget {
  final CustomerLocation location;
  final List<CustomerContact> contacts;
  final bool selected;
  final String singularTerminology;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const _LocationCard({
    required this.location,
    this.contacts = const [],
    this.selected = false,
    required this.singularTerminology,
    this.onTap,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  bool _expanded = false;
  List<Map<String, dynamic>>? _linkedProjects;

  Future<void> _loadLinkedProjects() async {
    if (_linkedProjects != null) return;
    final results = await ServiceLocator.customerLocationService
        .getProjectsForLocation(widget.location.id);
    if (mounted) {
      setState(() => _linkedProjects = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.location.fullAddress;
    final contacts = widget.contacts;
    final location = widget.location;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: widget.selected ? AppColors.surfaceAlt : null,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (v) {
                      if (v == 'edit') widget.onEdit();
                      if (v == 'archive') widget.onArchive();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'archive', child: Text('Archive')),
                    ],
                  ),
                ],
              ),
              if (address != null && address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  AddressFormatter.condense(address),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        contacts.map((c) => c.name).join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (location.accessDetails != null &&
                  location.accessDetails!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.key_outlined,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location.accessDetails!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (address != null && address.isNotEmpty)
                    _CompactButton(
                      icon: Icons.map_outlined,
                      label: 'Map',
                      onTap: () => _openMap(address),
                    ),
                  const SizedBox(width: 4),
                  _CompactButton(
                    icon: _expanded ? Icons.expand_less : Icons.work_outline,
                    label: _expanded ? 'Hide' : widget.singularTerminology,
                    onTap: () {
                      setState(() => _expanded = !_expanded);
                      if (_expanded) _loadLinkedProjects();
                    },
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (_linkedProjects == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_linkedProjects!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(
                      'No ${widget.singularTerminology.toLowerCase()}s linked to this location.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                else
                  ..._linkedProjects!.map(
                    (p) => InkWell(
                      onTap: () => context.go('/projects/${p['id']}'),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                          horizontal: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.work_outline,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                p['name'] as String? ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              (p['status'] as String? ?? '').replaceAll(
                                '_',
                                ' ',
                              ),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMap(String address) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ---------------------------------------------------------------------------
// Map Entry
// ---------------------------------------------------------------------------

class _MapEntry {
  final String? id;
  final String title;
  final String subtitle;
  final String address;
  final IconData icon;
  final double? latitude;
  final double? longitude;

  const _MapEntry({
    this.id,
    required this.title,
    required this.subtitle,
    required this.address,
    required this.icon,
    this.latitude,
    this.longitude,
  });
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

class _LocationsMap extends StatelessWidget {
  final List<_MapEntry> entries;
  final _MapEntry? focusEntry;

  const _LocationsMap({required this.entries, this.focusEntry});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final coords = entries
        .map((e) => LatLng(e.latitude!, e.longitude!))
        .toList();
    final uniqueCoords = coords.toSet().toList();

    final CameraFit cameraFit;
    if (focusEntry != null) {
      cameraFit = CameraFit.coordinates(
        coordinates: [LatLng(focusEntry!.latitude!, focusEntry!.longitude!)],
        maxZoom: 15,
      );
    } else if (uniqueCoords.length <= 1) {
      cameraFit = CameraFit.coordinates(
        coordinates: [coords.first],
        maxZoom: 14,
      );
    } else {
      cameraFit = CameraFit.coordinates(
        coordinates: uniqueCoords,
        padding: const EdgeInsets.all(50),
        maxZoom: 18,
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        key: ValueKey(focusEntry?.id),
        options: MapOptions(initialCameraFit: cameraFit),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.com',
            tileProvider: CancellableNetworkTileProvider(),
          ),
          MarkerLayer(
            markers: entries
                .map(
                  (e) => Marker(
                    point: LatLng(e.latitude!, e.longitude!),
                    width: 200,
                    height: 80,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(e.icon, size: 36, color: AppColors.error),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            e.title,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact button
// ---------------------------------------------------------------------------

class _CompactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CompactButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
