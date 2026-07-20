import 'package:flutter/material.dart';

import '../theme/theme.dart';

Future<void> showImageUploadOptionsDialog({
  required BuildContext context,
  required VoidCallback onChooseFromGallery,
  VoidCallback? onRemovePhoto,
  String galleryLabel = 'Choose from gallery',
  String removeLabel = 'Remove photo',
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(galleryLabel),
              onTap: () {
                Navigator.of(dialogContext).pop();
                onChooseFromGallery();
              },
            ),
            if (onRemovePhoto != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: Text(
                  removeLabel,
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onRemovePhoto();
                },
              ),
          ],
        ),
      ),
    ),
  );
}
