import 'package:flutter/material.dart';
import '../../models/customer_contact.dart';
import '../../theme/theme.dart';
import '../../utils/confirm_dialog.dart';
import '../common/primary_contact_prompt.dart';
import 'contact_card.dart';
import 'contact_form_dialog.dart';

class ContactsList extends StatefulWidget {
  final List<CustomerContact> contacts;
  final Function(List<CustomerContact>) onContactsChanged;
  final bool readOnly;

  const ContactsList({
    super.key,
    required this.contacts,
    required this.onContactsChanged,
    this.readOnly = false,
  });

  @override
  State<ContactsList> createState() => _ContactsListState();
}

class _ContactsListState extends State<ContactsList> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final displayContacts = _showInactive
        ? widget.contacts
        : widget.contacts.where((c) => c.isActive).toList();

    // Sort with primary first
    displayContacts.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return 0;
    });

    final inactiveCount = widget.contacts.where((c) => !c.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Contacts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ChromeColors.of(context).scaffoldText,
              ),
            ),
            if (!widget.readOnly)
              ElevatedButton.icon(
                onPressed: _addContact,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Contact'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Show inactive toggle (if there are inactive contacts)
        if (inactiveCount > 0 && !widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Switch(
                  value: _showInactive,
                  onChanged: (value) {
                    setState(() {
                      _showInactive = value;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Show inactive contacts ($inactiveCount)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

        // Contacts list
        if (displayContacts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: [
                  const Icon(
                    Icons.contacts,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.contacts.isEmpty
                        ? 'No contacts yet'
                        : 'No active contacts',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (widget.contacts.isEmpty && !widget.readOnly) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Add a contact to get started',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayContacts.length,
            itemBuilder: (context, index) {
              final contact = displayContacts[index];
              return ContactCard(
                contact: contact,
                onTap: widget.readOnly
                    ? null
                    : () => _editContact(contact, index),
                onDelete: widget.readOnly ? null : () => _deleteContact(index),
                showPrimaryBadge: true,
              );
            },
          ),
      ],
    );
  }

  void _addContact() async {
    final result = await showContactFormDialog(
      context,
      canSetPrimary: false,
      defaultPrimary: false,
    );

    if (result != null) {
      if (!mounted) return;
      final updatedContacts = List<CustomerContact>.from(widget.contacts);
      final shouldMakePrimary = await showPrimaryContactPrompt(
        context,
        contactName: result.name,
        ownerLabel: 'customer',
      );
      if (!mounted) return;
      final contactToAdd = result.copyWith(isPrimary: shouldMakePrimary);

      if (shouldMakePrimary) {
        for (int i = 0; i < updatedContacts.length; i++) {
          if (updatedContacts[i].isPrimary) {
            updatedContacts[i] = updatedContacts[i].copyWith(isPrimary: false);
          }
        }
      }

      updatedContacts.add(contactToAdd);
      widget.onContactsChanged(updatedContacts);
    }
  }

  void _editContact(CustomerContact contact, int index) async {
    // Find the actual index in the full contacts list
    final actualIndex = widget.contacts.indexOf(contact);
    if (actualIndex == -1) return;

    final hasPrimary = widget.contacts.any((c) => c.isPrimary && c != contact);

    final result = await showContactFormDialog(
      context,
      existingContact: contact,
      canSetPrimary: !hasPrimary || contact.isPrimary,
    );

    if (result != null) {
      final updatedContacts = List<CustomerContact>.from(widget.contacts);

      // If this is being set as primary, unset others
      if (result.isPrimary && !contact.isPrimary) {
        for (int i = 0; i < updatedContacts.length; i++) {
          if (updatedContacts[i].isPrimary) {
            updatedContacts[i] = updatedContacts[i].copyWith(isPrimary: false);
          }
        }
      }

      updatedContacts[actualIndex] = result;
      widget.onContactsChanged(updatedContacts);
    }
  }

  void _deleteContact(int displayIndex) async {
    final displayContacts = _showInactive
        ? widget.contacts
        : widget.contacts.where((c) => c.isActive).toList();

    // Sort with primary first (same as build)
    displayContacts.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return 0;
    });

    final contact = displayContacts[displayIndex];

    // Find the actual index in the full contacts list
    final actualIndex = widget.contacts.indexOf(contact);
    if (actualIndex == -1) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete Contact',
      message: 'Are you sure you want to delete ${contact.name}?\n\n'
          'This will mark the contact as inactive.',
    );

    if (confirmed) {
      final updatedContacts = List<CustomerContact>.from(widget.contacts);
      updatedContacts[actualIndex] = contact.copyWith(isActive: false);
      widget.onContactsChanged(updatedContacts);
    }
  }
}
