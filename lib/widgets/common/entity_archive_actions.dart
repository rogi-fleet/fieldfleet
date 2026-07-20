import 'package:flutter/material.dart';

import '../../utils/user_facing_error.dart';

class EntityArchiveActions {
  const EntityArchiveActions._();

  static Future<void> toggle({
    required BuildContext context,
    required String entityLabel,
    required bool isActive,
    required Future<void> Function() archive,
    required Future<void> Function() restore,
    Future<void> Function()? afterToggle,
    bool confirm = false,
    String? errorAction,
  }) async {
    if (confirm) {
      final confirmed = await _confirmToggle(
        context: context,
        entityLabel: entityLabel,
        isActive: isActive,
      );
      if (confirmed != true) return;
    }

    try {
      if (isActive) {
        await archive();
      } else {
        await restore();
      }

      if (afterToggle != null) {
        await afterToggle();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage(entityLabel, isActive))),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(
              error,
              action: errorAction ?? 'update $entityLabel',
            ),
          ),
        ),
      );
    }
  }

  static String successMessage(String entityLabel, bool isActive) {
    final title = _capitalize(entityLabel);
    return isActive ? '$title archived' : '$title restored';
  }

  static Future<bool?> _confirmToggle({
    required BuildContext context,
    required String entityLabel,
    required bool isActive,
  }) {
    final title = _capitalize(entityLabel);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isActive ? 'Archive $title' : 'Restore $title'),
        content: Text(
          isActive
              ? 'Archive this $entityLabel? You can restore it later.'
              : 'Restore this $entityLabel to make it active again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: isActive
                  ? Theme.of(dialogContext).colorScheme.error
                  : Theme.of(dialogContext).colorScheme.primary,
            ),
            child: Text(isActive ? 'Archive' : 'Restore'),
          ),
        ],
      ),
    );
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
