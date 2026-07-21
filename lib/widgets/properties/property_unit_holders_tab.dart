import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/customer_contact.dart';
import '../../models/project.dart';
import '../../models/property.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Staff-side tab for managing "unit holders" — customer_contacts rows
/// restricted to exactly this property, who can log into the client portal
/// and see just this property's scoped view and report issues against it.
class PropertyUnitHoldersTab extends StatefulWidget {
  final Project project;
  final Property property;

  const PropertyUnitHoldersTab({
    super.key,
    required this.project,
    required this.property,
  });

  @override
  State<PropertyUnitHoldersTab> createState() =>
      _PropertyUnitHoldersTabState();
}

class _PropertyUnitHoldersTabState extends State<PropertyUnitHoldersTab> {
  final _customerService = ServiceLocator.customerService;
  final _invitationService = ServiceLocator.invitationService;

  List<CustomerContact> _contacts = const [];
  Set<String> _pendingInviteIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final contacts =
          await _customerService.getUnitHolders(widget.property.id)
              as List<CustomerContact>;
      Set<String> pending = {};
      try {
        pending = await _invitationService.pendingPortalCustomerContactIds(
          workspaceId: widget.property.workspaceId,
        ) as Set<String>;
      } catch (_) {
        // Non-fatal — just skip the Invited badge.
      }
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _pendingInviteIds = pending;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load unit holders: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add unit holder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: 'Required to send a portal invite',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true || nameCtrl.text.trim().isEmpty) return;

    final customerId = widget.project.clientId;
    if (customerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This project has no customer assigned yet — assign one before adding unit holders.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    try {
      await _customerService.createUnitHolderContact(
        customerId: customerId,
        restrictedPropertyId: widget.property.id,
        name: nameCtrl.text.trim(),
        title: titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not add unit holder: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _invite(CustomerContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final invitedBy = context.read<AuthProvider>().appUser?.id;
    if (invitedBy == null) return;
    try {
      await _invitationService.inviteCustomerContactToPortal(
        customerContactId: contactId,
        invitedBy: invitedBy,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal invite sent to ${contact.email}')),
        );
      }
      await _loadData();
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

  Future<void> _cancelInvite(CustomerContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    try {
      await _invitationService.revokePendingPortalInvitationForCustomerContact(
        customerContactId: contactId,
      );
      if (mounted) {
        setState(() {
          _pendingInviteIds = {..._pendingInviteIds}..remove(contactId);
        });
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

  Future<void> _revokeAccess(CustomerContact contact) async {
    final contactId = contact.id;
    if (contactId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke portal access?'),
        content: Text(
          '${contact.name} will immediately lose access to this property\'s '
          'portal view.',
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
      await _invitationService.revokeCustomerPortalAccess(
        customerContactId: contactId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal access revoked for ${contact.name}')),
        );
      }
      await _loadData();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Scaffold(
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.badge_outlined,
                      size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  const Text(
                    'No unit holders yet',
                    style:
                        TextStyle(fontSize: 18, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Add someone to give them portal access to just this property.',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.base),
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final isLinked = contact.userId != null;
                final isPending = _pendingInviteIds.contains(contact.id);
                final hasEmail = (contact.email ?? '').trim().isNotEmpty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.badge),
                    title: Text(contact.name),
                    subtitle: Text([
                      if (contact.title != null) contact.title!,
                      if (contact.email != null) contact.email!,
                    ].join(' · ')),
                    trailing: isLinked
                        ? Chip(
                            label: const Text('Active'),
                            backgroundColor:
                                AppColors.success.withValues(alpha: 0.15),
                            labelStyle:
                                const TextStyle(color: AppColors.success),
                          )
                        : isPending
                            ? TextButton(
                                onPressed: () => _cancelInvite(contact),
                                child: const Text('Cancel invite'),
                              )
                            : TextButton(
                                onPressed:
                                    hasEmail ? () => _invite(contact) : null,
                                child: const Text('Invite'),
                              ),
                    onTap: isLinked ? () => _revokeAccess(contact) : null,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Unit Holder'),
      ),
    );
  }
}
