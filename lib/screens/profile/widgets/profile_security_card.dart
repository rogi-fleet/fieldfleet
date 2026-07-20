import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../theme/theme.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/profile/change_password_dialog.dart';

/// Profile card grouping account-security actions: change password
/// and sign out of every device.
class ProfileSecurityCard extends StatefulWidget {
  const ProfileSecurityCard({super.key});

  @override
  State<ProfileSecurityCard> createState() => _ProfileSecurityCardState();
}

class _ProfileSecurityCardState extends State<ProfileSecurityCard> {
  bool _signingOutEverywhere = false;

  Future<void> _confirmSignOutEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out everywhere?'),
        content: const Text(
          'This signs you out on every browser and device. You will need to '
          'sign in again on each one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _signingOutEverywhere = true);
    try {
      await context.read<AuthProvider>().signOutEverywhere();
      // Auth state change will redirect to login; nothing else to do.
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOutEverywhere = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'sign out everywhere'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final hasPassword = authProvider.hasPasswordIdentity;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage how you sign in to your account.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            if (hasPassword)
              _SecurityActionRow(
                icon: Icons.lock_outline,
                title: 'Change password',
                subtitle: 'Update the password used to sign in with email.',
                buttonLabel: 'Change',
                onPressed: () => ChangePasswordDialog.show(context),
              )
            else
              const _SecurityActionRow(
                icon: Icons.shield_outlined,
                title: 'Password',
                subtitle:
                    'Your account signs in with a federated provider — '
                    'manage your password there.',
              ),
            const Divider(height: 32),
            _SecurityActionRow(
              icon: Icons.logout,
              iconColor: AppColors.error,
              title: 'Sign out everywhere',
              subtitle: 'Revoke active sessions on all browsers and devices.',
              buttonLabel: 'Sign out',
              destructive: true,
              busy: _signingOutEverywhere,
              onPressed: _confirmSignOutEverywhere,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityActionRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool busy;

  const _SecurityActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.buttonLabel,
    this.onPressed,
    this.destructive = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedIconColor = iconColor ?? AppColors.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: resolvedIconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, size: 20, color: resolvedIconColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (buttonLabel != null) ...[
          const SizedBox(width: 12),
          if (destructive)
            OutlinedButton(
              onPressed: busy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel!),
            )
          else
            FilledButton.tonal(
              onPressed: busy ? null : onPressed,
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel!),
            ),
        ],
      ],
    );
  }
}
