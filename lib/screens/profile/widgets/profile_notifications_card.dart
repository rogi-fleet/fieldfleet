import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user.dart' show NotificationPreferences, EmailDigestMode;
import '../../../providers/workspace_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

/// Profile card for per-channel notification preferences.
///
/// Stateless — preference state is owned by the parent screen so the
/// existing save-bar flow keeps working unchanged.
class ProfileNotificationsCard extends StatelessWidget {
  final NotificationPreferences preferences;
  final ValueChanged<NotificationPreferences> onChanged;

  const ProfileNotificationsCard({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final projectTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Preferences',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose which notifications you want to receive',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _NotificationRow(
              title: 'Task Assignments',
              icon: Icons.assignment,
              emailEnabled: preferences.taskAssignmentsEmail,
              pushEnabled: preferences.taskAssignmentsPush,
              onChanged: (email, push) => onChanged(
                preferences.copyWith(
                  taskAssignmentsEmail: email,
                  taskAssignmentsPush: push,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _NotificationRow(
              title: 'Task Completions',
              icon: Icons.check_circle,
              emailEnabled: preferences.taskCompletionsEmail,
              pushEnabled: preferences.taskCompletionsPush,
              onChanged: (email, push) => onChanged(
                preferences.copyWith(
                  taskCompletionsEmail: email,
                  taskCompletionsPush: push,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _NotificationRow(
              title: '$projectTerminology Updates',
              icon: Icons.folder,
              emailEnabled: preferences.projectUpdatesEmail,
              pushEnabled: preferences.projectUpdatesPush,
              onChanged: (email, push) => onChanged(
                preferences.copyWith(
                  projectUpdatesEmail: email,
                  projectUpdatesPush: push,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _NotificationRow(
              title: 'Mentions',
              icon: Icons.alternate_email,
              emailEnabled: preferences.mentionsEmail,
              pushEnabled: preferences.mentionsPush,
              onChanged: (email, push) => onChanged(
                preferences.copyWith(mentionsEmail: email, mentionsPush: push),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Email Cadence',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How often we email you. Push notifications are unaffected.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            // Icons omitted: with them, "Immediate" wraps to two lines on
            // narrow (mobile) widths.
            SegmentedButton<EmailDigestMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: EmailDigestMode.immediate,
                  label: Text('Immediate'),
                ),
                ButtonSegment(
                  value: EmailDigestMode.hourly,
                  label: Text('Hourly'),
                ),
                ButtonSegment(
                  value: EmailDigestMode.daily,
                  label: Text('Daily'),
                ),
              ],
              selected: {preferences.digestMode},
              onSelectionChanged: (set) {
                if (set.isEmpty) return;
                onChanged(preferences.copyWith(digestMode: set.first));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool emailEnabled;
  final bool pushEnabled;
  final void Function(bool email, bool push) onChanged;

  const _NotificationRow({
    required this.title,
    required this.icon,
    required this.emailEnabled,
    required this.pushEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textPrimary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Email', style: TextStyle(fontSize: 14)),
                    value: emailEnabled,
                    onChanged: (value) =>
                        onChanged(value ?? false, pushEnabled),
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Push', style: TextStyle(fontSize: 14)),
                    value: pushEnabled,
                    onChanged: (value) =>
                        onChanged(emailEnabled, value ?? false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
