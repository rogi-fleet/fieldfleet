import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/mobile_app/app_download_section.dart';

/// Permanent /apps route. Hosts a single AppDownloadSection plus a few
/// "what mobile gets you" callouts. Public — a marketing email or
/// social link can drop visitors here without forcing signup first.
///
/// The app bar adapts: signed-in users see "Back to portal"; signed-out
/// users see "Sign in" / "Sign up" so they have a path forward after
/// reading the page.
class GetTheAppScreen extends StatelessWidget {
  const GetTheAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final isSignedIn = auth.appUser != null;
    return Scaffold(
      // Content surface — without this the headings (which use default text
      // colors) render dark-on-dark over the chrome background.
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('FieldFleet mobile'),
        leading: isSignedIn
            ? IconButton(
                tooltip: 'Back to portal',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/');
                  }
                },
              )
            : null,
        automaticallyImplyLeading: isSignedIn,
        actions: isSignedIn
            ? null
            : [
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Sign in'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: FilledButton(
                    onPressed: () => context.go('/signup'),
                    child: const Text('Sign up'),
                  ),
                ),
              ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'FieldFleet, on the job site.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The web portal is your back-office command centre — '
                  'the mobile app is what you and your crews use in the '
                  'field. Same account, same projects, same data.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                const AppDownloadSection(
                  eyebrow: 'INSTALL',
                  title: 'Get the FieldFleet mobile app',
                  body: 'Room scanning, on-site photo capture, time clock '
                      'with GPS, and offline forms — all in your pocket.',
                ),
                const SizedBox(height: 32),
                Text(
                  'Mobile-only features',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _FeatureRow(
                  icon: Icons.view_in_ar_outlined,
                  title: 'Scan a room',
                  body: 'Walk through a room with your phone camera and '
                      'FieldFleet generates a 2D floor plan you can edit '
                      'on either the phone or the web portal.',
                ),
                _FeatureRow(
                  icon: Icons.camera_alt_outlined,
                  title: 'Job-site photo capture',
                  body: 'Snap photos, tag them to a project or task, and '
                      'they sync to the portal automatically.',
                ),
                _FeatureRow(
                  icon: Icons.timer_outlined,
                  title: 'GPS time clock',
                  body: 'Crew members clock in / out with location stamps '
                      'so payroll matches what actually happened on site.',
                ),
                _FeatureRow(
                  icon: Icons.cloud_off_outlined,
                  title: 'Works offline',
                  body: 'Field forms and photos queue locally when you '
                      'lose signal, then sync when you\'re back online.',
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
