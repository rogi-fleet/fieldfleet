import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import 'list_skeleton.dart';

/// Standard loading / error / empty / content switch for async screens.
///
/// Roughly a third of the app's async screens render no error state at all
/// (a failed load shows a spinner forever) and the rest each improvise
/// their own. Route the screen's `_isLoading` / `_error` / empty flags
/// through this widget instead:
///
/// ```dart
/// AsyncStateView(
///   isLoading: _isLoading,
///   error: _error,
///   errorAction: 'load invoices',
///   onRetry: _load,
///   isEmpty: _invoices.isEmpty,
///   emptyState: const ZeroItemsActionEmptyState(...),
///   builder: (context) => _buildList(),
/// )
/// ```
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.isLoading,
    required this.builder,
    this.error,
    this.errorAction = 'load this view',
    this.onRetry,
    this.isEmpty = false,
    this.emptyState,
    this.useSkeleton = false,
  });

  final bool isLoading;

  /// Raw error object (or message). Rendered via [UserFacingError.uiMessage]
  /// so users never see exception strings.
  final Object? error;

  /// Verb phrase for the error copy, e.g. 'load invoices'.
  final String errorAction;

  /// When set, the error state shows a Retry button wired to this callback.
  final VoidCallback? onRetry;

  final bool isEmpty;

  /// Shown when [isEmpty] is true; falls back to a plain message.
  final Widget? emptyState;

  /// Use a shimmer [ListSkeleton] instead of a spinner — prefer this on
  /// list/table screens.
  final bool useSkeleton;

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return useSkeleton
          ? const ListSkeleton()
          : const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                UserFacingError.uiMessage(error, action: errorAction),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.base),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (isEmpty) {
      return emptyState ??
          const Center(
            child: Text(
              'Nothing here yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
    }
    return builder(context);
  }
}
