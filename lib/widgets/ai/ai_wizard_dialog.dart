import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shows an AI wizard dialog with a gradient header.
///
/// Provides the standard dialog boilerplate used by all AI wizards:
/// gradient header with icon+title, close button, and constrained sizing.
///
/// Pass [personaEmoji] to show the workspace persona avatar instead of [icon].
void showAiWizardDialog(
  BuildContext context, {
  required String title,
  required Widget child,
  double width = 700,
  IconData icon = Icons.auto_awesome,
  String? personaEmoji,
  String? personaAvatarAssetPath,
}) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.base),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: width,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.94,
          maxHeight: MediaQuery.of(context).size.height * 0.94,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.r16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          child: Column(
            children: [
              // Gradient header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    if (personaAvatarAssetPath != null)
                      ClipOval(
                        child: Image.asset(
                          personaAvatarAssetPath,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      )
                    else if (personaEmoji != null)
                      Text(personaEmoji, style: const TextStyle(fontSize: 20))
                    else
                      Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // Wizard content
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}
