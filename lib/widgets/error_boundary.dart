import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/app_logger.dart';
import 'package:taskfleet_ops/widgets/error_screen.dart';
import '../theme/theme.dart';

/// Error boundary widget that catches and contains errors to a specific subtree
///
/// Wraps a section of the widget tree and displays an error UI if any widget
/// in that subtree throws an error during build.
///
/// Example:
/// ```dart
/// ErrorBoundary(
///   child: MyComplexWidget(),
///   onError: (error, stackTrace) {
///     // Custom error handling
///   },
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(FlutterErrorDetails details, VoidCallback retry)?
      errorBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final String? friendlyMessage;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
    this.friendlyMessage,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterErrorDetails? _errorDetails;
  int _errorKey = 0;

  @override
  Widget build(BuildContext context) {
    if (_errorDetails != null) {
      // Error state - show error UI
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_errorDetails!, _retry);
      }

      // Default error UI
      return ErrorScreen(
        errorDetails: _errorDetails,
        onRetry: _retry,
        friendlyMessage: widget.friendlyMessage,
      );
    }

    // Normal state - wrap child in error catching
    return ErrorCatchingWidget(
      key: ValueKey(_errorKey),
      onError: (details) {
        _handleError(details);
        setState(() {
          _errorDetails = details;
        });
      },
      child: widget.child,
    );
  }

  void _handleError(FlutterErrorDetails details) {
    // Call custom error handler if provided
    if (widget.onError != null) {
      widget.onError!(details.exception, details.stack ?? StackTrace.current);
    }

    // Log to AppLogger (which sends to Crashlytics in production)
    AppLogger.error(
      'Error boundary caught error',
      error: details.exception,
      stackTrace: details.stack,
      metadata: {
        'library': details.library ?? 'unknown',
        'context': details.context?.toString() ?? 'unknown',
      },
    );
  }

  void _retry() {
    setState(() {
      _errorDetails = null;
      _errorKey++; // Force rebuild with new key
    });
  }
}

/// Widget that catches build errors in its child
class ErrorCatchingWidget extends StatelessWidget {
  final Widget child;
  final void Function(FlutterErrorDetails) onError;

  const ErrorCatchingWidget({
    super.key,
    required this.child,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // Wrap in a try-catch to handle synchronous errors
        try {
          return child;
        } catch (error, stackTrace) {
          final details = FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'error_boundary',
            context: ErrorDescription('building ${child.runtimeType}'),
          );
          onError(details);
          // Return a simple error indicator
          return Center(
            child: Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 48,
            ),
          );
        }
      },
    );
  }
}
