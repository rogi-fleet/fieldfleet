import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../models/vendor_contact.dart';
import '../../models/vendor_subdivision.dart';
import '../../providers/workspace_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';
import '../table/table_controls_bar.dart';
import 'vendor_subdivision_form.dart';

class VendorLocationsTab extends StatefulWidget {
  final Vendor vendor;

  const VendorLocationsTab({super.key, required this.vendor});

  @override
  State<VendorLocationsTab> createState() => _VendorLocationsTabState();
}

class _VendorLocationsTabState extends State<VendorLocationsTab> {
  final _subdivisionService = ServiceLocator.vendorSubdivisionService;
  final _geocodingService = GeocodingService();
  final _geocoded = <String, LatLng>{};
  String? _selectedSubdivisionId;
  bool _showMap = false;
  bool _geocodingStarted = false;
  List<Project>? _vendorProjects;

  @override
  void initState() {
    super.initState();
    _loadVendorProjects();
  }

  Future<void> _loadVendorProjects() async {
    try {
      final projects = await ServiceLocator.vendorService.getVendorProjects(
        widget.vendor.id,
      );
      if (mounted) {
        setState(() => _vendorProjects = projects);
      }
    } catch (_) {
      if (mounted) setState(() => _vendorProjects = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.vendor.workspaceId;
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return StreamBuilder<List<VendorSubdivision>>(
      stream: _subdivisionService.getSubdivisions(widget.vendor.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final subdivisions = snapshot.data ?? [];

        if (subdivisions.isEmpty) {
          return _buildEmptyState(workspaceId);
        }

        // Build map entries from subdivisions + vendor address + projects
        final mapEntries = _buildMapEntries(subdivisions, singularTerminology);

        if (!_geocodingStarted && mapEntries.isNotEmpty) {
          _geocodingStarted = true;
          _geocodeEntries(mapEntries);
        }

        final resolvedEntries = _resolveMappable(mapEntries);

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= AppBreakpoints.compact;

            final listContent = _buildSubdivisionList(
              subdivisions,
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
                      focusEntry: _selectedSubdivisionId == null
                          ? null
                          : resolvedEntries
                                .where((e) => e.id == _selectedSubdivisionId)
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
                    subdivisions.length,
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

  List<_MapEntry> _buildMapEntries(
    List<VendorSubdivision> subdivisions,
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

    // Subdivision addresses
    for (final sub in subdivisions) {
      final addr = sub.fullAddress;
      if (addr != null && addr.isNotEmpty) {
        addEntry(
          _MapEntry(
            id: sub.id,
            title: sub.name,
            subtitle: 'Subdivision',
            address: addr,
            icon: Icons.business_outlined,
            latitude: sub.latitude,
            longitude: sub.longitude,
          ),
        );
      }
    }

    // Vendor's own address
    final vendorAddr = widget.vendor.fullAddress;
    if (vendorAddr != null && vendorAddr.isNotEmpty) {
      addEntry(
        _MapEntry(
          title: widget.vendor.companyName,
          subtitle: 'Vendor address',
          address: vendorAddr,
          icon: Icons.store_outlined,
        ),
      );
    }

    // Project site addresses
    if (_vendorProjects != null) {
      for (final project in _vendorProjects!) {
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

  Widget _buildHeader(int count, String workspaceId, bool hasMap) {
    final chrome = ChromeColors.of(context);
    final activeControlColor = chrome.isDark
        ? AppColors.secondaryLight
        : AppColors.secondary;

    return TableControlsBar(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      children: [
        Text(
          '$count subdivision${count == 1 ? '' : 's'}',
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
          tooltip: 'Create Subdivision',
          onPressed: () => _showSubdivisionForm(workspaceId),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildSubdivisionList(
    List<VendorSubdivision> subdivisions,
    String workspaceId,
    String singularTerminology,
    bool wide,
  ) {
    // Check if we have any mappable entries (from subs, vendor address, or projects)
    final mapEntries = _buildMapEntries(subdivisions, singularTerminology);
    final resolvedEntries = _resolveMappable(mapEntries);
    final hasMap =
        resolvedEntries.isNotEmpty ||
        mapEntries.any((e) => e.latitude != null && e.longitude != null);

    return Column(
      children: [
        _buildHeader(subdivisions.length, workspaceId, hasMap),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: subdivisions.length,
            itemBuilder: (context, index) {
              final subdivision = subdivisions[index];
              final contact = _findContact(subdivision.contactId);
              return _SubdivisionCard(
                subdivision: subdivision,
                contact: contact,
                selected: _selectedSubdivisionId == subdivision.id,
                singularTerminology: singularTerminology,
                onTap: wide
                    ? () => setState(
                        () => _selectedSubdivisionId = subdivision.id,
                      )
                    : null,
                onEdit: () =>
                    _showSubdivisionForm(workspaceId, subdivision: subdivision),
                onArchive: () => _archiveSubdivision(subdivision),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String workspaceId) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No subdivisions yet',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Add subdivisions to track departments or units for this vendor.',
              style: TextStyle(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _showSubdivisionForm(workspaceId),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Subdivision'),
            ),
          ],
        ),
      ),
    );
  }

  VendorContact? _findContact(String? contactId) {
    if (contactId == null) return null;
    try {
      return widget.vendor.contacts.firstWhere(
        (c) => c.id == contactId && c.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  void _showSubdivisionForm(
    String workspaceId, {
    VendorSubdivision? subdivision,
  }) {
    showDialog(
      context: context,
      builder: (context) => VendorSubdivisionForm(
        workspaceId: workspaceId,
        vendorId: widget.vendor.id,
        subdivision: subdivision,
        contacts: widget.vendor.contacts.where((c) => c.isActive).toList(),
        onSave: (sub) async {
          if (subdivision != null) {
            await _subdivisionService.updateSubdivision(sub);
          } else {
            await _subdivisionService.createSubdivision(sub);
          }
        },
      ),
    );
  }

  void _archiveSubdivision(VendorSubdivision subdivision) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Subdivision'),
        content: Text(
          'Are you sure you want to archive "${subdivision.name}"? '
          'Existing jobs linked to this subdivision will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _subdivisionService.deleteSubdivision(subdivision.id);
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
// Subdivision Card
// ---------------------------------------------------------------------------

class _SubdivisionCard extends StatefulWidget {
  final VendorSubdivision subdivision;
  final VendorContact? contact;
  final bool selected;
  final String singularTerminology;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const _SubdivisionCard({
    required this.subdivision,
    this.contact,
    this.selected = false,
    required this.singularTerminology,
    this.onTap,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  State<_SubdivisionCard> createState() => _SubdivisionCardState();
}

class _SubdivisionCardState extends State<_SubdivisionCard> {
  bool _expanded = false;
  List<Map<String, dynamic>>? _linkedProjects;

  Future<void> _loadLinkedProjects() async {
    if (_linkedProjects != null) return;
    final results = await ServiceLocator.vendorSubdivisionService
        .getProjectsForSubdivision(widget.subdivision.id);
    if (mounted) {
      setState(() => _linkedProjects = results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.subdivision.fullAddress;
    final contact = widget.contact;
    final subdivision = widget.subdivision;

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
                  const Icon(Icons.business_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subdivision.name,
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
              if (contact != null) ...[
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
                        contact.name,
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
              if (subdivision.accessDetails != null &&
                  subdivision.accessDetails!.isNotEmpty) ...[
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
                        subdivision.accessDetails!,
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
                      'No ${widget.singularTerminology.toLowerCase()}s linked to this subdivision.',
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
// Map (shows subdivisions + vendor address + project sites)
// ---------------------------------------------------------------------------

class _LocationsMap extends StatelessWidget {
  final List<_MapEntry> entries;
  final _MapEntry? focusEntry;

  const _LocationsMap({required this.entries, this.focusEntry});

  @override
  Widget build(BuildContext context) {
    final points = entries
        .where(
          (e) =>
              e.latitude != null &&
              e.longitude != null &&
              !e.latitude!.isNaN &&
              !e.longitude!.isNaN,
        )
        .toList();

    if (points.isEmpty) return const SizedBox.shrink();

    final coords = points
        .map((e) => LatLng(e.latitude!, e.longitude!))
        .toList();
    final uniqueCoords = coords.toSet().toList();

    final CameraFit cameraFit;
    if (focusEntry != null &&
        focusEntry!.latitude != null &&
        focusEntry!.longitude != null) {
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
        key: ValueKey(focusEntry?.id ?? focusEntry?.address),
        options: MapOptions(initialCameraFit: cameraFit),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.com',
            tileProvider: CancellableNetworkTileProvider(),
          ),
          MarkerLayer(
            markers: points
                .map(
                  (e) => Marker(
                    point: LatLng(e.latitude!, e.longitude!),
                    width: 200,
                    height: 80,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_pin,
                          size: 36,
                          color: AppColors.error,
                        ),
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
// Map entry (generic point for subdivisions, vendor address, projects)
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
