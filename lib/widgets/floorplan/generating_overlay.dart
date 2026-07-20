import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Translucent overlay shown over the canvas while an AI generation is
/// in flight (or after one has failed). Decoupled from the editor so
/// the screen layout stays clean.
class GeneratingOverlay extends StatelessWidget {
  final String prompt;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const GeneratingOverlay({
    super.key,
    required this.prompt,
    this.error,
    this.onRetry,
    this.onDismiss,
  });

  bool get _isError => error != null;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(AppSpacing.lg),
            margin: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.r12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isError
                          ? Icons.error_outline
                          : Icons.auto_awesome,
                      size: 22,
                      color: _isError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isError
                          ? 'Generation failed'
                          : 'Generating floorplan…',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '"$prompt"',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                ),
                const SizedBox(height: 16),
                if (_isError) ...[
                  Text(
                    error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onDismiss != null)
                        TextButton(
                          onPressed: onDismiss,
                          child: const Text('Dismiss'),
                        ),
                      if (onRetry != null) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Typically 10–30 seconds. You can leave the editor and '
                    'come back — the result will be waiting.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
