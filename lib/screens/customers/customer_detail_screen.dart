import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme.dart';
import '../../models/customer.dart';
import '../../models/customer_contact.dart';
import '../../models/customer_tag.dart';
import '../../models/project.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/adaptive_navigation.dart';

import '../../utils/project_terminology.dart';
import '../../widgets/projects/embedded_project_list.dart';
import '../../widgets/customers/customer_type_badge.dart';
import '../../widgets/customers/customer_status_badge.dart';
import '../../widgets/customers/customer_tag_chip.dart';
import '../../widgets/customers/customer_messages_tab.dart';
import '../../widgets/customers/customer_documents_tab.dart';
import '../../widgets/customers/customer_files_tab.dart';
import '../../widgets/customers/customer_locations_tab.dart';
import '../../widgets/customer_form_popup.dart';
import '../../widgets/common/breadcrumb_bar.dart';
import '../../widgets/common/entity_detail_layout.dart';
import '../../widgets/notes/entity_notes_tab.dart';
import '../../widgets/common/entity_archive_actions.dart';
import '../../widgets/common/entity_archived_badge.dart';
import '../../widgets/adaptive_map_widget.dart';
import '../../services/geocoding_service.dart';

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  final bool openPortalInvite;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.openPortalInvite = false,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  dynamic get _customerService => ServiceLocator.customerService;
  final dynamic _tagService = ServiceLocator.customerTagService;
  final dynamic _portalService = ServiceLocator.clientPortalService;
  Customer? _customer;
  Customer? _parentCustomer;
  List<Customer> _childCustomers = [];
  List<CustomerTag> _customerTags = [];
  bool _isLoading = true;
  late final Stream<List<Project>> _customerProjectsStream = _customerService
      .getCustomerProjects(widget.customerId);
  bool _openedPortalInviteFromRoute = false;
  Future<List<Map<String, dynamic>>>? _portalInviteHistoryFuture;
  Set<String> _pendingPortalContactIds = const {};
  final GeocodingService _geocodingService = GeocodingService();
  Future<({double latitude, double longitude})?>? _businessLocationFuture;

  Color get _surfaceText => Theme.of(context).colorScheme.onSurface;
  Color get _surfaceMutedText => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _surfaceContainer =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _surfaceBorder => Theme.of(context).colorScheme.outlineVariant;

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  Future<void> _loadCustomer() async {
    try {
      final customer = await _customerService.getCustomer(widget.customerId);

      // Load parent if exists
      Customer? parent;
      if (customer?.parentCustomerId != null) {
        parent = await _customerService.getParentCustomer(
          customer!.parentCustomerId!,
        );
      }

      // Load children
      final children = customer != null
          ? await _customerService.getChildCustomers(
              widget.customerId,
              customer.workspaceId,
            )
          : <Customer>[];

      // Load tags
      final tags = customer != null && customer.tagIds.isNotEmpty
          ? await _tagService.getTagsByIds(
              customer.workspaceId,
              customer.tagIds,
            )
          : <CustomerTag>[];

      if (mounted) {
        setState(() {
          _customer = customer;
          _parentCustomer = parent;
          _childCustomers = children;
          _customerTags = tags;
          _isLoading = false;
          _businessLocationFuture =
              customer?.fullAddress != null &&
                  customer!.fullAddress!.trim().isNotEmpty
              ? _geocodeBusinessLocation(customer.fullAddress!)
              : null;
          _portalInviteHistoryFuture = customer != null
              ? _loadPortalInviteHistoryForCustomer(customer)
              : Future.value(const []);
        });
        if (customer != null) {
          _loadPendingPortalContactIds(customer.workspaceId);
        }
        _openPortalInviteIfRequested();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Error loading customer: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
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

    if (_customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer')),
        body: const Center(child: Text('Customer not found')),
      );
    }

    return DefaultTabController(
      length: 7,
      child: TabSwitchNotifier(
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  title: Text(_customer!.companyName ?? _customer!.name),
                  pinned: true,
                  floating: true,
                  forceElevated: innerBoxIsScrolled,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: 'Preview customer portal',
                      onPressed: () => context.push(
                        '/portal/dashboard?preview=${widget.customerId}',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.link),
                      tooltip: 'Send Portal Access',
                      onPressed: () => _showSendPortalAccessDialog(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        await showCustomerFormPopup(
                          context,
                          customerId: widget.customerId,
                        );
                        _loadCustomer();
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _customer!.isActive
                            ? Icons.archive_outlined
                            : Icons.unarchive,
                      ),
                      tooltip: _customer!.isActive
                          ? 'Archive customer'
                          : 'Restore customer',
                      onPressed: _toggleCustomerArchive,
                    ),
                  ],
                  bottom: TabBar(
                    isScrollable: true,
                    padding: EdgeInsets.zero,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      const Tab(icon: Icon(Icons.badge_outlined), text: 'Details'),
                      const Tab(icon: Icon(Icons.inbox_outlined), text: 'Inbox'),
                      const Tab(icon: Icon(Icons.description_outlined), text: 'Documents'),
                      const Tab(icon: Icon(Icons.folder_outlined), text: 'Files'),
                      const Tab(icon: Icon(Icons.sticky_note_2_outlined), text: 'Notes'),
                      const Tab(icon: Icon(Icons.place_outlined), text: 'Locations'),
                      Tab(icon: const Icon(Icons.work_outline), text: projectTerminology),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: BreadcrumbBar(
                    items: [
                      BreadcrumbItem(
                        label: 'Customers',
                        onTap: () => context.go('/customers'),
                      ),
                      BreadcrumbItem(
                        label: _customer!.companyName ?? _customer!.name,
                      ),
                    ],
                  ),
                ),
              ];
            },
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Details Tab
                _buildDetailsTab(),

                // Inbox Tab
                CustomerMessagesTab(customer: _customer!),

                // Documents Tab
                CustomerDocumentsTab(customer: _customer!),

                // Files Tab
                CustomerFilesTab(customer: _customer!),

                // Notes Tab
                EntityNotesTab(
                  workspaceId: _customer!.workspaceId,
                  entityType: 'customer',
                  entityId: _customer!.id,
                ),

                // Locations Tab
                CustomerLocationsTab(
                  customer: _customer!,
                  parentCustomer: _parentCustomer,
                  childCustomers: _childCustomers,
                ),

                // Jobs Tab
                _buildJobsTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    final contactsWithEmail = _getPortalEligibleContacts();
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;
    final activeContacts = _customer!.getActiveContacts();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        // Status and type badges
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CustomerStatusBadge(status: _customer!.status),
            CustomerTypeBadge(customerType: _customer!.customerType),
            if (!_customer!.isActive) const EntityArchivedBadge(),
          ],
        ),

        // Tags Section (Phase 1)
        if (_customerTags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _customerTags.map((tag) {
              return CustomerTagChip(tag: tag, small: false);
            }).toList(),
          ),
        ],
        const SizedBox(height: 24),
        EntityDetailResponsiveGrid(
          minCardWidth: 340,
          children: [
            _buildBusinessInformationCard(),
            _buildBusinessLocationCard(),
          ],
        ),
        const SizedBox(height: 16),
        _buildContactsSection(activeContacts),
        const SizedBox(height: 16),
        const EntityDetailSectionHeader(title: 'Customer Access'),
        const SizedBox(height: 12),
        _buildClientAccessCard(contactsWithEmail),
        const SizedBox(height: 16),
        const EntityDetailSectionHeader(title: 'Activity'),
        const SizedBox(height: 12),
        _buildActivityCard(projectTerminology),
      ],
    );
  }

  Widget _buildBusinessInformationCard() {
    return EntityDetailCard(
      title: 'Business Information',
      icon: Icons.business_center_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompactInfoItem(
            icon: Icons.account_balance,
            label: 'Tax Status',
            value: _customer!.taxExempt ? 'Tax Exempt' : 'Taxable',
          ),
          const SizedBox(height: 8),
          if (_customer!.businessPhone != null &&
              _customer!.businessPhone!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.phone_outlined,
              label: 'Business Phone',
              value: _customer!.businessPhone!,
              onTap: () => _launchUri(
                Uri(scheme: 'tel', path: _customer!.businessPhone!),
              ),
              actionIcon: Icons.call_outlined,
              actionTooltip: 'Call business phone',
            ),
          if (_customer!.businessEmail != null &&
              _customer!.businessEmail!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.email_outlined,
              label: 'Business Email',
              value: _customer!.businessEmail!,
              onTap: () => _launchUri(
                Uri(scheme: 'mailto', path: _customer!.businessEmail!),
              ),
              actionIcon: Icons.email_outlined,
              actionTooltip: 'Email business contact',
            ),
          if (_customer!.website != null &&
              _customer!.website!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.language,
              label: 'Website',
              value: _customer!.website!,
              maxLines: 1,
              onTap: () => _launchWebsite(_customer!.website!),
              actionIcon: Icons.open_in_new,
              actionTooltip: 'Open website',
            ),
          if (_customer!.source != null)
            EntityDetailInfoRow(
              icon: _customer!.source!.icon,
              label: 'Source',
              value: _customer!.source!.displayName,
            ),
          if (_customer!.referrerName != null &&
              _customer!.referrerName!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.person_outline,
              label: 'Referred By',
              value: _customer!.referrerName!,
            ),
          if (_customer!.accountOwnerId != null &&
              _customer!.accountOwnerId!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.manage_accounts_outlined,
              label: 'Account Owner',
              value: _customer!.accountOwnerId!,
            ),
          if (_parentCustomer != null)
            EntityDetailInfoRow(
              icon: Icons.account_tree_outlined,
              label: 'Parent Company',
              value: _parentCustomer!.businessDisplayName,
            ),
          if (_childCustomers.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.apartment_outlined,
              label: 'Sub-Companies',
              value: _childCustomers
                  .map((c) => c.businessDisplayName)
                  .join(', '),
            ),
          if (_customer!.notes != null && _customer!.notes!.isNotEmpty) ...[
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
              _customer!.notes!,
              style: TextStyle(fontSize: 14, color: _surfaceText, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _surfaceMutedText),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: _surfaceMutedText),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: _surfaceText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBusinessLocationCard() {
    final hasAddress =
        _customer!.fullAddress != null &&
        _customer!.fullAddress!.trim().isNotEmpty;

    return EntityDetailCard(
      title: 'Business Location',
      icon: Icons.location_on_outlined,
      trailing: IconButton(
        onPressed: () => DefaultTabController.of(context).animateTo(4),
        tooltip: 'Open Locations tab',
        icon: const Icon(Icons.place_outlined, size: 18),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAddress)
            EntityDetailInfoRow(
              icon: Icons.home_work_outlined,
              label: 'Business Address',
              value: _customer!.fullAddress!,
            )
          else
            EntityDetailInfoRow(
              icon: Icons.home_work_outlined,
              label: 'Business Address',
              value: 'No business address added',
            ),
          if (hasAddress) ...[
            const SizedBox(height: 12),
            _buildBusinessLocationMap(_customer!.fullAddress!),
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
              markerTitle: _customer!.businessDisplayName,
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactsSection(List<CustomerContact> contacts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const EntityDetailSectionHeader(title: 'Contacts'),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await showCustomerFormPopup(
                  context,
                  customerId: widget.customerId,
                  initialStep: 1,
                );
                _loadCustomer();
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Manage'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EntityDetailResponsiveGrid(
          minCardWidth: 260,
          children: contacts.isEmpty
              ? [_buildEmptyContactCard()]
              : List<Widget>.generate(
                  contacts.length,
                  (index) => _buildContactCard(contacts[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildContactCard(CustomerContact contact, int index) {
    final isLinked = contact.userId != null;
    final isInvited =
        contact.id != null && _pendingPortalContactIds.contains(contact.id);
    final canManage = context.read<AuthProvider>().canManageUsers;
    final canInviteToPortal =
        contact.id != null &&
        (contact.email ?? '').trim().isNotEmpty &&
        canManage &&
        !isLinked &&
        !isInvited;
    final canRevokePortal = canManage && isLinked && contact.id != null;
    final canCancelPendingInvite = canManage && isInvited;
    return EntityDetailCard(
      title: 'Contact ${index + 1}',
      icon: Icons.person_outline,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact.isPrimary)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Primary',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          if (isLinked) ...[
            const SizedBox(width: 6),
            _PortalStatusChip(
              icon: Icons.verified_user_outlined,
              label: 'Portal user',
              bg: AppColors.successLight,
              fg: AppColors.successDark,
              tooltip: 'Linked to a portal user — scoped to this customer',
            ),
          ] else if (isInvited) ...[
            const SizedBox(width: 6),
            _PortalStatusChip(
              icon: Icons.mark_email_read_outlined,
              label: 'Invited',
              bg: AppColors.warningLight,
              fg: AppColors.warningDark,
              tooltip:
                  'Portal invite sent — waiting for the contact to accept',
            ),
          ],
          if (canInviteToPortal) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Invite this contact to the customer portal',
              child: IconButton(
                iconSize: 18,
                icon: const Icon(Icons.send_to_mobile_outlined),
                onPressed: () => _inviteCustomerContactToPortal(contact),
              ),
            ),
          ],
          if (canRevokePortal || canCancelPendingInvite)
            PopupMenuButton<String>(
              iconSize: 18,
              tooltip: 'Portal access',
              onSelected: (value) {
                if (value == 'revoke') {
                  _revokeCustomerPortalAccess(contact);
                } else if (value == 'cancel_invite') {
                  _cancelPendingPortalInviteForContact(contact);
                }
              },
              itemBuilder: (ctx) => [
                if (canRevokePortal)
                  const PopupMenuItem(
                    value: 'revoke',
                    child: Text('Revoke portal access'),
                  ),
                if (canCancelPendingInvite)
                  const PopupMenuItem(
                    value: 'cancel_invite',
                    child: Text('Cancel pending invite'),
                  ),
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
              icon: Icons.phone_android_outlined,
              label: 'Cell Phone',
              value: contact.mobilePhone!,
              onTap: () => _launchUri(
                Uri(scheme: 'tel', path: contact.mobilePhone!),
              ),
              actionIcon: Icons.call_outlined,
              actionTooltip: 'Call contact cell',
            ),
          if (contact.email != null && contact.email!.isNotEmpty)
            EntityDetailInfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: contact.email!,
              onTap: () =>
                  _launchUri(Uri(scheme: 'mailto', path: contact.email!)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyContactCard() {
    return EntityDetailCard(
      title: 'Contact 1',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No active contacts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _surfaceText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add at least one contact so communication and customer portal access have a clear owner.',
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

  Widget _buildActivityCard(String projectTerminology) {
    return EntityDetailCard(
      title: 'Activity',
      icon: Icons.timeline_outlined,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _getCustomerActivity(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final activity = snapshot.data!;
          return Column(
            children: [
              EntityDetailInfoRow(
                icon: Icons.work_outline,
                label: 'Total $projectTerminology',
                value: '${activity['projectCount']}',
              ),
              EntityDetailInfoRow(
                icon: Icons.attach_money_outlined,
                label: 'Total Revenue',
                value: '\$${activity['revenue'].toStringAsFixed(2)}',
              ),
              EntityDetailInfoRow(
                icon: Icons.update_outlined,
                label: 'Customer Updated',
                value: timeago.format(_customer!.updatedAt),
              ),
              if (activity['lastActivity'] != null)
                EntityDetailInfoRow(
                  icon: Icons.history,
                  label: 'Last Activity',
                  value: timeago.format(activity['lastActivity'] as DateTime),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildJobsTab() {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return EmbeddedProjectList(
      projectStream: _customerProjectsStream,
      createProjectCustomerId: widget.customerId,
      createProjectLabel:
          'Create $singularTerminology for ${_customer!.businessDisplayName}',
      animatedCreateButton: true,
    );
  }

  Widget _buildClientAccessCard(List<dynamic> contactsWithEmail) {
    final hasInviteableContacts = contactsWithEmail.isNotEmpty;
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    ).toLowerCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give customer contacts secure $singularTerminology access via Customer Portal magic links.',
              style: TextStyle(color: _surfaceMutedText),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.people_outline, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Text(
                  '${contactsWithEmail.length} contact${contactsWithEmail.length == 1 ? '' : 's'} with email',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (!hasInviteableContacts) ...[
              const SizedBox(height: 8),
              Text(
                'Add an active customer contact email to enable portal invites.',
                style: TextStyle(color: _surfaceMutedText),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: hasInviteableContacts
                  ? _showSendPortalAccessDialog
                  : null,
              icon: const Icon(Icons.link),
              label: const Text('Send Portal Access'),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Invite History',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _surfaceText,
              ),
            ),
            const SizedBox(height: 8),
            _buildInviteHistoryList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteHistoryList() {
    final historyFuture = _portalInviteHistoryFuture;
    if (historyFuture == null) {
      return Text(
        'Invite history unavailable.',
        style: TextStyle(color: _surfaceMutedText),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final history = snapshot.data ?? const <Map<String, dynamic>>[];
        if (history.isEmpty) {
          return Text(
            'No portal invites sent yet.',
            style: TextStyle(color: _surfaceMutedText),
          );
        }

        return Column(
          children: history.take(10).map(_buildInviteHistoryTile).toList(),
        );
      },
    );
  }

  Widget _buildInviteHistoryTile(Map<String, dynamic> entry) {
    final email = entry['email'] as String? ?? 'Unknown email';
    final sentAt = _parseHistoryDate(entry['sentAt']);
    final sentByName = entry['sentByName'] as String?;
    final lastLoginAt = _parseHistoryDate(entry['lastLoginAt']);

    final sentAtLabel = sentAt != null
        ? timeago.format(sentAt)
        : 'unknown time';
    final sentByLabel = sentByName?.trim().isNotEmpty == true
        ? sentByName!
        : 'Unknown sender';
    final loginLabel = lastLoginAt != null
        ? 'Last login ${timeago.format(lastLoginAt)}'
        : 'Never logged in';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.mark_email_read_outlined, size: 20),
      title: Text(email),
      subtitle: Text('Sent $sentAtLabel by $sentByLabel • $loginLabel'),
    );
  }

  Future<Map<String, dynamic>> _getCustomerActivity() async {
    final projects = await _customerService
        .getCustomerProjects(widget.customerId)
        .first;
    final revenue = await _customerService.calculateCustomerRevenue(
      widget.customerId,
    );
    final lastActivity = await _customerService.getLastActivityDate(
      widget.customerId,
    );

    return {
      'projectCount': projects.length,
      'revenue': revenue,
      'lastActivity': lastActivity,
    };
  }

  Future<List<Map<String, dynamic>>> _loadPortalInviteHistoryForCustomer(
    Customer customer,
  ) async {
    try {
      final response = await _portalService.getCustomerPortalInviteHistory(
        workspaceId: customer.workspaceId,
        customerId: customer.id,
      );

      if (response is! List) {
        return const [];
      }

      return response
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<({double latitude, double longitude})?> _geocodeBusinessLocation(
    String address,
  ) {
    return _geocodingService.geocodeAddress(address);
  }

  DateTime? _parseHistoryDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);

    try {
      final converted = (raw as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Ignore invalid date formats in mixed backend payloads.
    }

    return null;
  }

  void _refreshPortalInviteHistory() {
    final customer = _customer;
    if (customer == null) return;
    setState(() {
      _portalInviteHistoryFuture = _loadPortalInviteHistoryForCustomer(
        customer,
      );
    });
  }

  List<dynamic> _getPortalEligibleContacts() {
    return _customer!.contacts
        .where((c) => c.email != null && c.email!.isNotEmpty && c.isActive)
        .toList();
  }

  void _openPortalInviteIfRequested() {
    if (_openedPortalInviteFromRoute ||
        !widget.openPortalInvite ||
        _customer == null) {
      return;
    }

    _openedPortalInviteFromRoute = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSendPortalAccessDialog();
    });
  }

  void _showSendPortalAccessDialog() {
    final contactsWithEmail = _getPortalEligibleContacts();
    final authProvider = context.read<AuthProvider>();

    if (contactsWithEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No contacts with email addresses found'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _SendPortalAccessDialog(
        contacts: contactsWithEmail,
        customerName: _customer!.name,
        workspaceId: _customer!.workspaceId,
        customerId: _customer!.id,
        sentByUserId: authProvider.appUser?.id,
        portalService: _portalService,
        onInvitesSent: _refreshPortalInviteHistory,
      ),
    );
  }

  Future<void> _toggleCustomerArchive() async {
    final customer = _customer;
    if (customer == null) return;

    return EntityArchiveActions.toggle(
      context: context,
      entityLabel: 'customer',
      isActive: customer.isActive,
      archive: () => _customerService.archiveCustomer(widget.customerId),
      restore: () => _customerService.restoreCustomer(widget.customerId),
      afterToggle: _loadCustomer,
      confirm: true,
      errorAction: 'updating customer',
    );
  }

  Future<void> _launchUri(Uri uri, {LaunchMode? mode}) async {
    await launchUrl(uri, mode: mode ?? LaunchMode.platformDefault);
  }

  Future<void> _loadPendingPortalContactIds(String workspaceId) async {
    try {
      final ids = await ServiceLocator.invitationService
          .pendingPortalCustomerContactIds(workspaceId: workspaceId);
      if (!mounted) return;
      setState(() => _pendingPortalContactIds = ids);
    } catch (e) {
      // Non-fatal — just skip the Invited badge
    }
  }

  Future<void> _cancelPendingPortalInviteForContact(
    CustomerContact contact,
  ) async {
    final contactId = contact.id;
    if (contactId == null) return;
    try {
      await ServiceLocator.invitationService
          .revokePendingPortalInvitationForCustomerContact(
            customerContactId: contactId,
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

  Future<void> _revokeCustomerPortalAccess(CustomerContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke portal access?'),
        content: Text(
          '${contact.name} will immediately lose access to the customer '
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
      await ServiceLocator.invitationService.revokeCustomerPortalAccess(
        customerContactId: contactId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal access revoked for ${contact.name}')),
        );
        await _loadCustomer();
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

  Future<void> _inviteCustomerContactToPortal(CustomerContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final invitedBy = context.read<AuthProvider>().appUser?.id;
    if (invitedBy == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite to customer portal?'),
        content: Text(
          '${contact.name} (${contact.email}) will receive an email with a '
          'link to sign up. Once they accept, they\'ll only see projects and '
          'invoices tied to this customer.',
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
      await ServiceLocator.invitationService.inviteCustomerContactToPortal(
        customerContactId: contactId,
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

  Future<void> _launchWebsite(String rawUrl) async {
    final trimmed = rawUrl.trim();
    final parsed = Uri.tryParse(trimmed);
    final uri = parsed == null
        ? Uri.parse('https://$trimmed')
        : (parsed.hasScheme ? parsed : Uri.parse('https://$trimmed'));
    await _launchUri(uri, mode: LaunchMode.externalApplication);
  }
}

/// Dialog for sending portal access links to customer contacts
class _SendPortalAccessDialog extends StatefulWidget {
  final List<dynamic> contacts;
  final String customerName;
  final String workspaceId;
  final String customerId;
  final String? sentByUserId;
  final dynamic portalService;
  final VoidCallback? onInvitesSent;

  const _SendPortalAccessDialog({
    required this.contacts,
    required this.customerName,
    required this.workspaceId,
    required this.customerId,
    this.sentByUserId,
    required this.portalService,
    this.onInvitesSent,
  });

  @override
  State<_SendPortalAccessDialog> createState() =>
      _SendPortalAccessDialogState();
}

class _SendPortalAccessDialogState extends State<_SendPortalAccessDialog> {
  final Set<String> _selectedEmails = {};
  bool _isSending = false;
  String? _error;
  final List<String> _sentEmails = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.link, color: AppColors.info),
          const SizedBox(width: 8),
          const Expanded(child: Text('Send Portal Access')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select contacts to send a portal access link to:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: AppColors.errorDark, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.errorDark,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...widget.contacts.map((contact) {
              final email = contact.email as String;
              final name = contact.name as String;
              final wasSent = _sentEmails.contains(email);

              return CheckboxListTile(
                value: wasSent ? true : _selectedEmails.contains(email),
                enabled: !_isSending && !wasSent,
                title: Text(name),
                subtitle: Row(
                  children: [
                    Text(email),
                    if (wasSent) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 16,
                      ),
                      Text(
                        ' Sent',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                onChanged: wasSent
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            _selectedEmails.add(email);
                          } else {
                            _selectedEmails.remove(email);
                          }
                        });
                      },
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _isSending || _selectedEmails.isEmpty
              ? null
              : _sendInvites,
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_isSending ? 'Sending...' : 'Send Invites'),
        ),
      ],
    );
  }

  Future<void> _sendInvites() async {
    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      for (final email in _selectedEmails) {
        await widget.portalService.requestMagicLink(
          email,
          workspaceId: widget.workspaceId,
          customerId: widget.customerId,
          sentBy: widget.sentByUserId,
        );
        setState(() {
          _sentEmails.add(email);
        });
      }

      setState(() {
        _selectedEmails.clear();
        _isSending = false;
      });

      if (mounted) {
        widget.onInvitesSent?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Portal access link(s) sent to ${_sentEmails.length} contact(s)',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to send invite: $e';
        _isSending = false;
      });
    }
  }
}

class _PortalStatusChip extends StatelessWidget {
  const _PortalStatusChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.tooltip,
  });
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
