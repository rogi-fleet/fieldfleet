import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../models/insurance_info.dart';
import '../../models/license_info.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../models/vendor_contact.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/project_terminology.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/adaptive_map_widget.dart';
import '../../widgets/adaptive_navigation.dart';
import '../../widgets/common/breadcrumb_bar.dart';
import '../../widgets/common/entity_archive_actions.dart';
import '../../widgets/common/entity_archived_badge.dart';
import '../../widgets/common/entity_detail_layout.dart';
import '../../widgets/common/primary_contact_prompt.dart';
import '../../widgets/projects/embedded_project_list.dart';
import '../../widgets/project_form_popup.dart';
import '../../widgets/vendor_form_popup.dart';
import '../../widgets/vendors/vendor_bills_tab.dart';
import '../../widgets/vendors/vendor_contact_form_dialog.dart';
import '../../widgets/vendors/vendor_documents_tab.dart';
import '../../widgets/vendors/vendor_files_tab.dart';
import '../../widgets/vendors/vendor_locations_tab.dart';
import '../../widgets/notes/entity_notes_tab.dart';
import '../../widgets/vendors/vendor_messages_tab.dart';
import '../../widgets/vendors/vendor_products_services_tab.dart';
import '../../widgets/vendors/vendor_related_project_scope.dart';

class VendorDetailScreen extends StatefulWidget {
  final String vendorId;

  const VendorDetailScreen({super.key, required this.vendorId});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  final _vendorService = ServiceLocator.vendorService;
  final GeocodingService _geocodingService = GeocodingService();

  Vendor? _vendor;
  bool _isLoading = true;
  String? _error;
  bool _showInactiveContacts = false;
  Set<String> _pendingPortalContactIds = const {};
  late final Future<List<Project>> _vendorProjectsFuture = _vendorService
      .getVendorProjects(widget.vendorId);
  Future<Map<String, dynamic>>? _activityFuture;
  Future<
    ({
      int openProjects,
      int pipelineProjects,
      int relatedDocuments,
      int unpaidBills,
      bool complianceAtRisk,
    })
  >?
  _openWorkFuture;
  Future<({double latitude, double longitude})?>? _businessLocationFuture;

  Color get _surfaceText => Theme.of(context).colorScheme.onSurface;
  Color get _surfaceMutedText => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _surfaceContainer =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _surfaceBorder => Theme.of(context).colorScheme.outlineVariant;

  @override
  void initState() {
    super.initState();
    _loadVendor();
  }

  Future<void> _loadVendor() async {
    try {
      final vendor = await _vendorService.getVendor(widget.vendorId);
      if (!mounted) return;

      setState(() {
        _vendor = vendor;
        _isLoading = false;
        _activityFuture = _getVendorActivity();
        _openWorkFuture = vendor != null ? _loadOpenWorkSummary(vendor) : null;
        _businessLocationFuture =
            vendor?.fullAddress != null &&
                vendor!.fullAddress!.trim().isNotEmpty
            ? _geocodeBusinessLocation(vendor.fullAddress!)
            : null;
      });
      if (vendor != null) {
        _loadPendingPortalContactIds(vendor.workspaceId);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = UserFacingError.uiMessage(e, action: 'load this vendor');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendor Details')),
        body: Center(
          child: Text(_error ?? 'Unable to load this vendor right now.'),
        ),
      );
    }

    if (_vendor == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendor Details')),
        body: const Center(child: Text('Vendor not found')),
      );
    }

    return DefaultTabController(
      length: 9,
      child: TabSwitchNotifier(
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final singularTerminology = singularProjectTerminology(
                projectTerminology,
              );

              return [
                SliverAppBar(
                  title: Text(_vendor!.companyName),
                  pinned: true,
                  floating: true,
                  forceElevated: innerBoxIsScrolled,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_task_outlined),
                      tooltip: 'New $singularTerminology',
                      onPressed: _openNewProject,
                    ),
                    IconButton(
                      icon: const Icon(Icons.description_outlined),
                      tooltip: 'New Document',
                      onPressed: _openNewDocument,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        await showVendorFormPopup(
                          context,
                          vendorId: widget.vendorId,
                        );
                        await _loadVendor();
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _vendor!.isActive
                            ? Icons.archive_outlined
                            : Icons.unarchive,
                      ),
                      tooltip: _vendor!.isActive
                          ? 'Archive vendor'
                          : 'Restore vendor',
                      onPressed: _toggleVendorArchive,
                    ),
                  ],
                  bottom: TabBar(
                    isScrollable: true,
                    padding: EdgeInsets.zero,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      const Tab(icon: Icon(Icons.badge_outlined), text: 'Details'),
                      Tab(icon: const Icon(Icons.work_outline), text: projectTerminology),
                      const Tab(icon: Icon(Icons.place_outlined), text: 'Locations'),
                      const Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Products/Services'),
                      const Tab(icon: Icon(Icons.receipt_outlined), text: 'Invoices'),
                      const Tab(icon: Icon(Icons.description_outlined), text: 'Documents'),
                      const Tab(icon: Icon(Icons.folder_outlined), text: 'Files'),
                      const Tab(icon: Icon(Icons.sticky_note_2_outlined), text: 'Notes'),
                      const Tab(icon: Icon(Icons.forum_outlined), text: 'Messages'),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: BreadcrumbBar(
                    items: [
                      BreadcrumbItem(
                        label: 'Vendors',
                        onTap: () => context.go('/vendors'),
                      ),
                      BreadcrumbItem(label: _vendor!.companyName),
                    ],
                  ),
                ),
              ];
            },
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildDetailsTab(_vendor!),
                _buildJobsTab(),
                VendorLocationsTab(vendor: _vendor!),
                VendorProductsServicesTab(vendor: _vendor!),
                VendorBillsTab(vendor: _vendor!),
                VendorDocumentsTab(vendor: _vendor!),
                VendorFilesTab(vendor: _vendor!),
                EntityNotesTab(
                  workspaceId: _vendor!.workspaceId,
                  entityType: 'vendor',
                  entityId: _vendor!.id,
                ),
                VendorMessagesTab(vendor: _vendor!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJobsTab() {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return EmbeddedProjectList(
      projectFuture: _vendorProjectsFuture,
      createProjectVendorId: widget.vendorId,
      createProjectLabel:
          'Create $singularTerminology for ${_vendor!.companyName}',
      animatedCreateButton: true,
    );
  }

  Widget _buildDetailsTab(Vendor vendor) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    final displayContacts = _displayContacts(vendor);
    final inactiveCount = vendor.contacts.where((c) => !c.isActive).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        _buildHeader(vendor),
        if (vendor.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vendor.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        _buildPrimaryActionsCard(singularTerminology),
        const SizedBox(height: 16),
        EntityDetailResponsiveGrid(
          minCardWidth: 320,
          children: [
            if (_openWorkFuture != null)
              _buildOpenWorkCard(singularTerminology),
            _buildBusinessInformationCard(vendor),
            _buildAccountingCard(vendor),
            _buildBusinessLocationCard(vendor),
          ],
        ),
        const SizedBox(height: 16),
        _buildContactsSection(
          vendor,
          displayContacts,
          inactiveCount: inactiveCount,
        ),
        if (vendor.insurance != null) ...[
          const SizedBox(height: 16),
          const EntityDetailSectionHeader(title: 'Insurance'),
          const SizedBox(height: 12),
          _buildInsuranceCard(vendor.insurance!),
        ],
        if (vendor.licenses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const EntityDetailSectionHeader(title: 'Licenses & Certifications'),
          const SizedBox(height: 12),
          EntityDetailResponsiveGrid(
            minCardWidth: 280,
            children: vendor.licenses
                .map((license) => _buildLicenseCard(license))
                .toList(),
          ),
        ],
        if (vendor.notes != null && vendor.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          const EntityDetailSectionHeader(title: 'Notes'),
          const SizedBox(height: 12),
          EntityDetailCard(
            title: 'Notes',
            icon: Icons.sticky_note_2_outlined,
            child: Text(
              vendor.notes!,
              style: TextStyle(fontSize: 14, color: _surfaceText, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const EntityDetailSectionHeader(title: 'Activity'),
        const SizedBox(height: 12),
        _buildActivityCard(),
      ],
    );
  }

  Widget _buildPrimaryActionsCard(String singularTerminology) {
    return EntityDetailCard(
      title: 'Quick Actions',
      icon: Icons.flash_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start work or create paperwork without leaving this vendor profile.',
            style: TextStyle(fontSize: 14, color: _surfaceMutedText),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _openNewProject,
                icon: const Icon(Icons.add_task_outlined),
                label: Text('New $singularTerminology'),
              ),
              OutlinedButton.icon(
                onPressed: _openNewDocument,
                icon: const Icon(Icons.description_outlined),
                label: const Text('New Document'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpenWorkCard(String singularTerminology) {
    return EntityDetailCard(
      title: 'Open Work',
      icon: Icons.dashboard_outlined,
      child:
          FutureBuilder<
            ({
              int openProjects,
              int pipelineProjects,
              int relatedDocuments,
              int unpaidBills,
              bool complianceAtRisk,
            })
          >(
            future: _openWorkFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final summary = snapshot.data!;

              return Column(
                children: [
                  EntityDetailInfoRow(
                    icon: Icons.work_outline,
                    label: 'Open $singularTerminology',
                    value: '${summary.openProjects}',
                  ),
                  EntityDetailInfoRow(
                    icon: Icons.track_changes_outlined,
                    label: 'Pipeline $singularTerminology',
                    value: '${summary.pipelineProjects}',
                  ),
                  EntityDetailInfoRow(
                    icon: Icons.description_outlined,
                    label: 'Related Documents',
                    value: '${summary.relatedDocuments}',
                  ),
                  EntityDetailInfoRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Unpaid Bills',
                    value: '${summary.unpaidBills}',
                  ),
                  EntityDetailInfoRow(
                    icon: summary.complianceAtRisk
                        ? Icons.warning_amber_rounded
                        : Icons.verified_outlined,
                    label: 'Compliance',
                    value: summary.complianceAtRisk
                        ? 'Needs attention'
                        : 'Healthy',
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<Map<String, dynamic>> _getVendorActivity() async {
    final projects = await _vendorProjectsFuture;
    final spending =
        await _vendorService.calculateVendorSpending(widget.vendorId) as double;
    final lastActivity =
        await _vendorService.getVendorLastActivityDate(widget.vendorId)
            as DateTime?;

    return {
      'projectCount': projects.length,
      'spending': spending,
      'lastActivity': lastActivity,
    };
  }

  Future<
    ({
      int openProjects,
      int pipelineProjects,
      int relatedDocuments,
      int unpaidBills,
      bool complianceAtRisk,
    })
  >
  _loadOpenWorkSummary(Vendor vendor) async {
    final projects = await _vendorProjectsFuture;
    final scope = await loadVendorRelatedProjectScope(vendor);

    return (
      openProjects: projects.where((project) => project.status.isOpen).length,
      pipelineProjects: projects
          .where((project) => project.status.isPipeline)
          .length,
      relatedDocuments:
          scope.purchaseOrders.length +
          scope.bidRequests.length +
          scope.bills.length,
      unpaidBills: scope.bills.where((bill) => bill.paidDate == null).length,
      complianceAtRisk:
          vendor.hasExpiredLicenses ||
          vendor.hasExpiringSoonInsuranceOrLicenses,
    );
  }

  Widget _buildActivityCard() {
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    return EntityDetailCard(
      title: 'Activity',
      icon: Icons.timeline_outlined,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _activityFuture,
        builder: (context, snapshot) {
          if (_activityFuture == null) return const SizedBox.shrink();
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final activity = snapshot.data!;
          final lastActivity = activity['lastActivity'] as DateTime?;

          return Column(
            children: [
              EntityDetailInfoRow(
                icon: Icons.work_outline,
                label: 'Total $projectTerminology',
                value: '${activity['projectCount']}',
              ),
              EntityDetailInfoRow(
                icon: Icons.attach_money_outlined,
                label: 'Total Spending',
                value:
                    '\$${(activity['spending'] as double).toStringAsFixed(2)}',
              ),
              EntityDetailInfoRow(
                icon: Icons.update_outlined,
                label: 'Vendor Updated',
                value: timeago.format(_vendor!.updatedAt),
              ),
              if (lastActivity != null)
                EntityDetailInfoRow(
                  icon: Icons.history,
                  label: 'Last Activity',
                  value: timeago.format(lastActivity),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(Vendor vendor) {
    final chrome = ChromeColors.of(context);
    final badges = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildHeaderBadge(
          label: vendor.category,
          icon: Icons.inventory_2_outlined,
        ),
        _buildHeaderBadge(label: vendor.vendorType, icon: Icons.sell_outlined),
        if (vendor.isPreferred)
          _buildHeaderBadge(
            label: 'Preferred',
            icon: Icons.star_outline,
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        if (!vendor.isActive) const EntityArchivedBadge(),
      ],
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          vendor.companyName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: chrome.scaffoldText,
          ),
        ),
        if (vendor.dba != null && vendor.dba!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'DBA: ${vendor.dba!}',
            style: TextStyle(fontSize: 15, color: _surfaceMutedText),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: 12), badges],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            Flexible(
              child: Align(alignment: Alignment.topRight, child: badges),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBusinessInformationCard(Vendor vendor) {
    return EntityDetailCard(
      title: 'Business Information',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntityDetailInfoRow(
            icon: Icons.inventory_2_outlined,
            label: 'Category',
            value: vendor.category,
          ),
          EntityDetailInfoRow(
            icon: Icons.sell_outlined,
            label: 'Vendor Type',
            value: vendor.vendorType,
          ),
          EntityDetailInfoRow(
            icon: Icons.star_outline,
            label: 'Relationship',
            value: vendor.isPreferred ? 'Preferred vendor' : 'Standard vendor',
          ),
          if (vendor.businessPhone != null && vendor.businessPhone!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.phone_outlined,
              label: 'Business Phone',
              value: vendor.businessPhone!,
              onTap: () =>
                  _launchUri(Uri(scheme: 'tel', path: vendor.businessPhone!)),
              actionIcon: Icons.call_outlined,
              actionTooltip: 'Call business phone',
            ),
          if (vendor.businessEmail != null && vendor.businessEmail!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.email_outlined,
              label: 'Business Email',
              value: vendor.businessEmail!,
              onTap: () => _launchUri(
                Uri(scheme: 'mailto', path: vendor.businessEmail!),
              ),
              actionIcon: Icons.email_outlined,
              actionTooltip: 'Email business contact',
            ),
          if (vendor.website != null && vendor.website!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.language_outlined,
              label: 'Website',
              value: vendor.website!,
              onTap: () => _launchWebsite(vendor.website!),
              actionIcon: Icons.open_in_new_outlined,
              actionTooltip: 'Open website',
            ),
        ],
      ),
    );
  }

  Widget _buildAccountingCard(Vendor vendor) {
    final hasAccountingData =
        (vendor.taxId != null && vendor.taxId!.isNotEmpty) ||
        (vendor.accountNumber != null && vendor.accountNumber!.isNotEmpty) ||
        vendor.paymentTerms != null ||
        vendor.discountRate != null;

    return EntityDetailCard(
      title: 'Accounting & Terms',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vendor.taxId != null && vendor.taxId!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.badge_outlined,
              label: 'Tax ID',
              value: vendor.taxId!,
            ),
          if (vendor.accountNumber != null && vendor.accountNumber!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Account Number',
              value: vendor.accountNumber!,
            ),
          if (vendor.paymentTerms != null)
            EntityDetailInfoRow(
              icon: Icons.payment_outlined,
              label: 'Payment Terms',
              value: vendor.paymentTerms!.displayName,
            ),
          if (vendor.discountRate != null)
            EntityDetailInfoRow(
              icon: Icons.percent_outlined,
              label: 'Discount Rate',
              value: '${(vendor.discountRate! * 100).toStringAsFixed(1)}%',
            ),
          if (!hasAccountingData)
            Text(
              'No accounting terms configured yet.',
              style: TextStyle(fontSize: 14, color: _surfaceMutedText),
            ),
        ],
      ),
    );
  }

  Widget _buildBusinessLocationCard(Vendor vendor) {
    final hasAddress =
        vendor.fullAddress != null && vendor.fullAddress!.trim().isNotEmpty;

    return EntityDetailCard(
      title: 'Business Location',
      icon: Icons.location_on_outlined,
      trailing: IconButton(
        onPressed: () => DefaultTabController.of(context).animateTo(2),
        tooltip: 'Open Locations tab',
        icon: const Icon(Icons.place_outlined, size: 18),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntityDetailInfoRow(
            icon: Icons.home_work_outlined,
            label: 'Business Address',
            value: hasAddress
                ? vendor.fullAddress!
                : 'No business address added',
          ),
          if (hasAddress) ...[
            const SizedBox(height: 12),
            _buildBusinessLocationMap(vendor.fullAddress!),
          ],
        ],
      ),
    );
  }

  Widget _buildBusinessLocationMap(String address) {
    final mapFuture =
        _businessLocationFuture ?? _geocodeBusinessLocation(address);

    return FutureBuilder<({double latitude, double longitude})?>(
      future: mapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 160,
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: _surfaceBorder),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final coordinates = snapshot.data;
        if (coordinates == null) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: _surfaceBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.map_outlined, size: 18, color: _surfaceMutedText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Map preview unavailable for this address.',
                    style: TextStyle(fontSize: 13, color: _surfaceMutedText),
                  ),
                ),
              ],
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 160,
            child: AdaptiveMapWidget(
              address: address,
              latitude: coordinates.latitude,
              longitude: coordinates.longitude,
              height: 160,
              zoom: 14,
              markerTitle: _vendor!.companyName,
            ),
          ),
        );
      },
    );
  }

  List<VendorContact> _displayContacts(Vendor vendor) {
    final contacts = _showInactiveContacts
        ? List<VendorContact>.from(vendor.contacts)
        : vendor.contacts.where((c) => c.isActive).toList();

    contacts.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return contacts;
  }

  Widget _buildContactsSection(
    Vendor vendor,
    List<VendorContact> contacts, {
    required int inactiveCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const EntityDetailSectionHeader(title: 'Contacts'),
            const Spacer(),
            TextButton.icon(
              onPressed: _addVendorContact,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        if (inactiveCount > 0) ...[
          const SizedBox(height: 12),
          FilterChip(
            selected: _showInactiveContacts,
            onSelected: (value) =>
                setState(() => _showInactiveContacts = value),
            label: Text('Show inactive contacts ($inactiveCount)'),
          ),
        ],
        const SizedBox(height: 12),
        EntityDetailResponsiveGrid(
          minCardWidth: 260,
          children: contacts.isEmpty
              ? [_buildEmptyContactCard(vendor.contacts.isEmpty)]
              : List<Widget>.generate(
                  contacts.length,
                  (index) => _buildVendorContactCard(contacts[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildVendorContactCard(VendorContact contact, int index) {
    final isLinked = contact.userId != null;
    final isInvited =
        contact.id != null && _pendingPortalContactIds.contains(contact.id);
    final canManage = context.read<AuthProvider>().canManageUsers;
    return EntityDetailCard(
      title: contact.isPrimary ? 'Primary Contact' : 'Contact ${index + 1}',
      icon: contact.isPrimary ? Icons.star_outline : Icons.person_outline,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!contact.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (!contact.isActive) const SizedBox(width: 8),
          if (isLinked) ...[
            Tooltip(
              message: 'Linked to a portal user — scoped to this vendor',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 12,
                      color: AppColors.successDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Portal user',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.successDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ] else if (isInvited) ...[
            Tooltip(
              message: 'Portal invite sent — waiting for accept',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 12,
                      color: AppColors.warningDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Invited',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          PopupMenuButton<String>(
            iconSize: 18,
            onSelected: (value) {
              if (value == 'edit') _editVendorContact(contact);
              if (value == 'delete') _deleteVendorContact(contact);
              if (value == 'invite_portal') {
                _inviteVendorContactToPortal(contact);
              }
              if (value == 'revoke_portal') {
                _revokeVendorPortalAccess(contact);
              }
              if (value == 'cancel_invite') {
                _cancelPendingPortalInviteForVendorContact(contact);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if ((contact.email ?? '').trim().isNotEmpty &&
                  contact.id != null &&
                  canManage &&
                  !isLinked &&
                  !isInvited)
                const PopupMenuItem(
                  value: 'invite_portal',
                  child: Text('Invite to vendor portal'),
                ),
              if (canManage && isInvited && contact.id != null)
                const PopupMenuItem(
                  value: 'cancel_invite',
                  child: Text('Cancel pending invite'),
                ),
              if (canManage && isLinked && contact.id != null)
                const PopupMenuItem(
                  value: 'revoke_portal',
                  child: Text('Revoke portal access'),
                ),
              if (contact.isActive && !contact.isPrimary)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contact.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _surfaceText,
            ),
          ),
          if (contact.title != null && contact.title!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              contact.title!,
              style: TextStyle(fontSize: 14, color: _surfaceMutedText),
            ),
          ],
          const SizedBox(height: 12),
          if (contact.phone != null && contact.phone!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: contact.phone!,
              onTap: () => _launchUri(Uri(scheme: 'tel', path: contact.phone!)),
              actionIcon: Icons.call_outlined,
              actionTooltip: 'Call contact',
            ),
          if (contact.mobilePhone != null && contact.mobilePhone!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.smartphone_outlined,
              label: 'Mobile',
              value: contact.mobilePhone!,
              onTap: () =>
                  _launchUri(Uri(scheme: 'tel', path: contact.mobilePhone!)),
              actionIcon: Icons.call_outlined,
              actionTooltip: 'Call mobile',
            ),
          if (contact.email != null && contact.email!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: contact.email!,
              onTap: () =>
                  _launchUri(Uri(scheme: 'mailto', path: contact.email!)),
              actionIcon: Icons.email_outlined,
              actionTooltip: 'Email contact',
            ),
          if (contact.notes != null && contact.notes!.trim().isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Notes',
              style: TextStyle(
                fontSize: 12,
                color: _surfaceMutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              contact.notes!,
              style: TextStyle(fontSize: 14, color: _surfaceText, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyContactCard(bool hasNoContacts) {
    return EntityDetailCard(
      title: 'Contact 1',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasNoContacts ? 'No contacts yet' : 'No active contacts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _surfaceText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasNoContacts
                ? 'Add a contact so orders, invoices, and documents have a clear owner.'
                : 'Turn on inactive contacts to review older vendor contacts, or add a new primary contact.',
            style: TextStyle(
              fontSize: 14,
              color: _surfaceMutedText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _addVendorContact() async {
    final result = await showVendorContactFormDialog(context);

    if (result != null && mounted) {
      final shouldMakePrimary = await showPrimaryContactPrompt(
        context,
        contactName: result.name,
        ownerLabel: 'vendor',
      );
      if (!mounted) return;

      final contactToAdd = result.copyWith(isPrimary: shouldMakePrimary);
      final updatedContacts = List<VendorContact>.from(_vendor!.contacts);

      if (shouldMakePrimary) {
        for (var i = 0; i < updatedContacts.length; i++) {
          if (updatedContacts[i].isPrimary) {
            updatedContacts[i] = updatedContacts[i].copyWith(isPrimary: false);
          }
        }
      }

      updatedContacts.add(contactToAdd);
      await _saveVendorContacts(updatedContacts);
    }
  }

  void _editVendorContact(VendorContact contact) async {
    final result = await showVendorContactFormDialog(
      context,
      existingContact: contact,
    );

    if (result != null && mounted) {
      final updatedContacts = List<VendorContact>.from(_vendor!.contacts);
      final index = updatedContacts.indexOf(contact);
      if (index == -1) return;

      updatedContacts[index] = result.copyWith(isPrimary: contact.isPrimary);
      await _saveVendorContacts(updatedContacts);
    }
  }

  Future<void> _loadPendingPortalContactIds(String workspaceId) async {
    try {
      final ids = await ServiceLocator.invitationService
          .pendingPortalVendorContactIds(workspaceId: workspaceId);
      if (!mounted) return;
      setState(() => _pendingPortalContactIds = ids);
    } catch (_) {
      // Non-fatal
    }
  }

  Future<void> _cancelPendingPortalInviteForVendorContact(
    VendorContact contact,
  ) async {
    final contactId = contact.id;
    if (contactId == null) return;
    try {
      await ServiceLocator.invitationService
          .revokePendingPortalInvitationForVendorContact(
            vendorContactId: contactId,
          );
      if (mounted) {
        setState(() {
          _pendingPortalContactIds = {..._pendingPortalContactIds}
            ..remove(contactId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Portal invite cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not cancel invite: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _revokeVendorPortalAccess(VendorContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke portal access?'),
        content: Text(
          '${contact.name} will immediately lose access to the vendor '
          'portal. They can be re-invited later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ServiceLocator.invitationService.revokeVendorPortalAccess(
        vendorContactId: contactId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal access revoked for ${contact.name}')),
        );
        await _loadVendor();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not revoke access: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _inviteVendorContactToPortal(VendorContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final invitedBy = context.read<AuthProvider>().appUser?.id;
    if (invitedBy == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite to vendor portal?'),
        content: Text(
          '${contact.name} (${contact.email}) will receive an email with a '
          'link to sign up. Once they accept, they\'ll only see bid requests, '
          'bills, and purchase orders tied to this vendor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send invite'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ServiceLocator.invitationService.inviteVendorContactToPortal(
        vendorContactId: contactId,
        invitedBy: invitedBy,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal invite sent to ${contact.email}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send invite: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _deleteVendorContact(VendorContact contact) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete Contact',
      message: 'Are you sure you want to delete ${contact.name}?\n\n'
          'This will mark the contact as inactive.',
    );

    if (confirmed && mounted) {
      final updatedContacts = List<VendorContact>.from(_vendor!.contacts);
      final index = updatedContacts.indexOf(contact);
      if (index == -1) return;

      updatedContacts[index] = contact.copyWith(isActive: false);
      await _saveVendorContacts(updatedContacts);
    }
  }

  Future<void> _saveVendorContacts(List<VendorContact> contacts) async {
    try {
      await _vendorService.updateVendor(_vendor!.copyWith(contacts: contacts));
      await _loadVendor();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update contacts: $e')));
    }
  }

  Widget _buildInsuranceCard(InsuranceInfo insurance) {
    final isExpired = insurance.isExpired;
    final isExpiringSoon = insurance.isExpiringSoon;

    return EntityDetailCard(
      title: 'Coverage',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isExpired || isExpiringSoon)
            _buildAlertBanner(
              label: isExpired
                  ? 'Insurance Expired'
                  : 'Insurance Expiring Soon',
              color: isExpired
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
              backgroundColor: isExpired
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
            ),
          if (insurance.provider != null && insurance.provider!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.business_outlined,
              label: 'Provider',
              value: insurance.provider!,
            ),
          if (insurance.policyNumber != null &&
              insurance.policyNumber!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Policy Number',
              value: insurance.policyNumber!,
            ),
          if (insurance.liabilityCoverage != null)
            EntityDetailInfoRow(
              icon: Icons.attach_money_outlined,
              label: 'Liability Coverage',
              value: NumberFormat.currency(
                symbol: '\$',
              ).format(insurance.liabilityCoverage),
            ),
          if (insurance.expirationDate != null)
            EntityDetailInfoRow(
              icon: Icons.event_outlined,
              label: 'Expiration Date',
              value: DateFormat(
                'MMM dd, yyyy',
              ).format(insurance.expirationDate!),
            ),
        ],
      ),
    );
  }

  Widget _buildLicenseCard(LicenseInfo license) {
    final isExpired = license.isExpired;
    final isExpiringSoon = license.isExpiringSoon;

    return EntityDetailCard(
      title: license.licenseType,
      icon: Icons.workspace_premium_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isExpired || isExpiringSoon)
            _buildAlertBanner(
              label: isExpired ? 'Expired' : 'Expiring Soon',
              color: isExpired
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
              backgroundColor: isExpired
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
            ),
          EntityDetailInfoRow(
            icon: Icons.badge_outlined,
            label: 'License Number',
            value: license.licenseNumber,
          ),
          if (license.issuingState != null && license.issuingState!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.map_outlined,
              label: 'Issuing State',
              value: license.issuingState!,
            ),
          if (license.expirationDate != null)
            EntityDetailInfoRow(
              icon: Icons.event_outlined,
              label: 'Expiration Date',
              value: DateFormat('MMM dd, yyyy').format(license.expirationDate!),
            ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner({
    required String label,
    required Color color,
    required Color backgroundColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge({
    required String label,
    required IconData icon,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: foregroundColor ?? scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foregroundColor ?? scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<({double latitude, double longitude})?> _geocodeBusinessLocation(
    String address,
  ) async {
    final result = await _geocodingService.geocodeAddress(address);
    if (result == null) return null;
    return (latitude: result.latitude, longitude: result.longitude);
  }

  Future<void> _launchUri(Uri uri, {LaunchMode? mode}) async {
    await launchUrl(uri, mode: mode ?? LaunchMode.platformDefault);
  }

  Future<void> _launchWebsite(String rawUrl) async {
    final trimmed = rawUrl.trim();
    final parsed = Uri.tryParse(trimmed);
    final uri = parsed == null
        ? Uri.parse('https://$trimmed')
        : (parsed.hasScheme ? parsed : Uri.parse('https://$trimmed'));
    await _launchUri(uri, mode: LaunchMode.externalApplication);
  }

  void _openNewProject() {
    showProjectFormPopup(context, initialVendorId: widget.vendorId);
  }

  void _openNewDocument() {
    context.push(
      '/documents/create',
      extra: <String, dynamic>{'vendorId': widget.vendorId},
    );
  }

  Future<void> _toggleVendorArchive() async {
    final vendor = _vendor;
    if (vendor == null) return;

    return EntityArchiveActions.toggle(
      context: context,
      entityLabel: 'vendor',
      isActive: vendor.isActive,
      archive: () => _vendorService.archiveVendor(widget.vendorId),
      restore: () => _vendorService.restoreVendor(widget.vendorId),
      afterToggle: _loadVendor,
      confirm: true,
      errorAction: 'updating vendor',
    );
  }
}
