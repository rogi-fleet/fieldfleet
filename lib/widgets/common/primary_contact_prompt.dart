import 'package:flutter/material.dart';

Future<bool> showPrimaryContactPrompt(
  BuildContext context, {
  required String contactName,
  required String ownerLabel,
}) async {
  final shouldMakePrimary = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Make Primary Contact?'),
      content: Text(
        '$contactName was added successfully.\n\n'
        'Do you want to make this the primary contact for this $ownerLabel?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not Now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Make Primary'),
        ),
      ],
    ),
  );

  return shouldMakePrimary ?? false;
}
