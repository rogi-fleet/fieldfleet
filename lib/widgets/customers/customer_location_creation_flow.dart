import 'package:flutter/material.dart';

import '../../models/customer.dart';
import '../../models/customer_location.dart';
import '../../services/service_locator.dart';
import 'customer_location_form.dart';

CustomerLocation buildSuggestedCustomerLocation({
  required Customer customer,
  required String workspaceId,
}) {
  final now = DateTime.now();
  final primaryContact = customer.contacts
      .where((contact) => contact.isPrimary && contact.isActive)
      .firstOrNull;

  return CustomerLocation(
    id: '',
    workspaceId: workspaceId,
    customerId: customer.id,
    name: 'Headquarters',
    address: customer.address,
    city: customer.city,
    state: customer.state,
    zipCode: customer.zipCode,
    country: customer.country,
    contactIds: primaryContact?.id != null ? [primaryContact!.id!] : const [],
    createdAt: now,
    updatedAt: now,
  );
}

Future<bool> promptForCustomerLocationCreation(
  BuildContext context, {
  required bool isEditMode,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create Location Now?'),
      content: Text(
        isEditMode
            ? 'You can add a new customer location now without going back to the Locations tab.'
            : 'Do you want to create the first customer location now? We will prefill it from the customer details.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not Now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Create Location'),
        ),
      ],
    ),
  );

  return result ?? false;
}

Future<bool> showCreateCustomerLocationDialog(
  BuildContext context, {
  required Customer customer,
  required String workspaceId,
}) async {
  var created = false;

  await showDialog<void>(
    context: context,
    builder: (context) => CustomerLocationForm(
      workspaceId: workspaceId,
      customerId: customer.id,
      initialLocation: buildSuggestedCustomerLocation(
        customer: customer,
        workspaceId: workspaceId,
      ),
      contacts: customer.contacts.where((contact) => contact.isActive).toList(),
      onSave: (location) async {
        await ServiceLocator.customerLocationService.createLocation(location);
        created = true;
      },
    ),
  );

  return created;
}
