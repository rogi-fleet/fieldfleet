import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Status of contents items in a property.
enum ContentsStatus {
  identified,
  clean,
  store,
  dispose,
  packed,
  stored,
  returned,
  disposed;

  String get displayName {
    switch (this) {
      case ContentsStatus.identified:
        return 'Identified';
      case ContentsStatus.clean:
        return 'Clean';
      case ContentsStatus.store:
        return 'To Store';
      case ContentsStatus.dispose:
        return 'To Dispose';
      case ContentsStatus.packed:
        return 'Packed';
      case ContentsStatus.stored:
        return 'Stored';
      case ContentsStatus.returned:
        return 'Returned';
      case ContentsStatus.disposed:
        return 'Disposed';
    }
  }

  Color get color {
    switch (this) {
      case ContentsStatus.identified:
        return AppColors.textTertiary;
      case ContentsStatus.clean:
        return AppColors.info;
      case ContentsStatus.store:
        return AppColors.warning;
      case ContentsStatus.dispose:
        return AppColors.error;
      case ContentsStatus.packed:
        return AppColors.messageAccent;
      case ContentsStatus.stored:
        return AppColors.planAccent;
      case ContentsStatus.returned:
        return AppColors.success;
      case ContentsStatus.disposed:
        return AppColors.textSecondary;
    }
  }

  IconData get icon {
    switch (this) {
      case ContentsStatus.identified:
        return Icons.assignment;
      case ContentsStatus.clean:
        return Icons.cleaning_services;
      case ContentsStatus.store:
        return Icons.inventory;
      case ContentsStatus.dispose:
        return Icons.delete;
      case ContentsStatus.packed:
        return Icons.inventory_2;
      case ContentsStatus.stored:
        return Icons.warehouse;
      case ContentsStatus.returned:
        return Icons.assignment_return;
      case ContentsStatus.disposed:
        return Icons.delete_forever;
    }
  }

  static ContentsStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'identified':
        return ContentsStatus.identified;
      case 'clean':
        return ContentsStatus.clean;
      case 'store':
        return ContentsStatus.store;
      case 'dispose':
        return ContentsStatus.dispose;
      case 'packed':
        return ContentsStatus.packed;
      case 'stored':
        return ContentsStatus.stored;
      case 'returned':
        return ContentsStatus.returned;
      case 'disposed':
        return ContentsStatus.disposed;
      default:
        return ContentsStatus.identified;
    }
  }
}
