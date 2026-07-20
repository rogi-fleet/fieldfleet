import 'package:flutter/material.dart';

/// Shows a confirmation dialog when the user has unsaved changes.
/// Returns true if the user confirms they want to discard, false otherwise.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard changes?'),
      content: const Text(
        'You have unsaved changes. Are you sure you want to leave?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Attempts to close a form popup, showing a confirmation dialog if dirty.
Future<void> maybeCloseForm(
  BuildContext context, {
  required bool isDirty,
}) async {
  if (!isDirty) {
    Navigator.of(context).pop();
    return;
  }
  final discard = await confirmDiscardChanges(context);
  if (discard && context.mounted) {
    Navigator.of(context).pop();
  }
}
