import 'package:flutter/material.dart';
import '../../models/field_form_submission.dart';
import '../../models/field_form_template.dart';
import '../../theme/theme.dart';

/// Returns an icon for a field form category.
IconData fieldFormCategoryIcon(FieldFormCategory cat) {
  switch (cat) {
    case FieldFormCategory.inspection:
      return Icons.search;
    case FieldFormCategory.completion:
      return Icons.check_circle_outline;
    case FieldFormCategory.safety:
      return Icons.shield_outlined;
    case FieldFormCategory.assessment:
      return Icons.assignment_outlined;
    case FieldFormCategory.custom:
      return Icons.description_outlined;
  }
}

/// A card widget displaying a field form submission in a list.
class FieldFormSubmissionCard extends StatelessWidget {
  const FieldFormSubmissionCard({
    super.key,
    required this.submission,
    required this.onTap,
  });

  final FieldFormSubmission submission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = submission.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 6),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: status.color.withOpacity(0.12),
          child: Icon(
            _statusIcon(status),
            size: 18,
            color: status.color,
          ),
        ),
        title: Text(
          submission.templateName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: status.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    status.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: status.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (submission.filledByName != null)
                  Text(
                    submission.filledByName!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              submission.formattedCreatedAt,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  IconData _statusIcon(FieldFormStatus status) {
    switch (status) {
      case FieldFormStatus.draft:
        return Icons.edit_note;
      case FieldFormStatus.submitted:
        return Icons.send;
      case FieldFormStatus.approved:
        return Icons.check_circle;
      case FieldFormStatus.rejected:
        return Icons.cancel;
    }
  }
}
