import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Centralized logging system for the app
///
/// Provides structured logging with 5 levels:
/// - debug: Development-only verbose logging
/// - info: General informational messages
/// - warning: Warning conditions that should be investigated
/// - error: Error conditions (non-fatal)
/// - fatal: Fatal errors that crashed or nearly crashed the app
///
/// Logs are written locally using package:logger.
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: kDebugMode ? Level.debug : Level.warning,
  );

  /// Log debug message (development only)
  ///
  /// Example:
  /// ```dart
  /// AppLogger.debug('User tapped button', metadata: {'screen': 'home'});
  /// ```
  static void debug(String message, {Map<String, dynamic>? metadata}) {
    if (kDebugMode) {
      _logger.d(message, error: metadata);
    }
  }

  /// Log informational message
  ///
  /// Example:
  /// ```dart
  /// AppLogger.info('Project loaded successfully', metadata: {'projectId': id});
  /// ```
  static void info(String message, {Map<String, dynamic>? metadata}) {
    if (kDebugMode) {
      _logger.i(message, error: metadata);
    }
    // Info logs don't go to Crashlytics in production
  }

  /// Log warning message
  ///
  /// Example:
  /// ```dart
  /// AppLogger.warning('API call took longer than expected', metadata: {'duration': '5s'});
  /// ```
  static void warning(String message, {Map<String, dynamic>? metadata}) {
    _logger.w(message, error: metadata);
  }

  /// Log error message (non-fatal)
  /// Example:
  /// ```dart
  /// AppLogger.error('Failed to load project',
  ///   error: exception,
  ///   stackTrace: stackTrace,
  ///   metadata: {'projectId': id}
  /// );
  /// ```
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    if (metadata != null) {
      _logger.d('Metadata: $metadata');
    }
  }

  /// Log fatal error
  /// Example:
  /// ```dart
  /// AppLogger.fatal('Unrecoverable database error',
  ///   error: exception,
  ///   stackTrace: stackTrace
  /// );
  /// ```
  static void fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    if (metadata != null) {
      _logger.d('Metadata: $metadata');
    }
  }

  /// Set user context metadata.
  /// Call this after user logs in.
  static Future<void> setUserContext({
    required String userId,
    String? workspaceId,
  }) async {
    debug(
      'User context set',
      metadata: {'userId': userId, 'workspaceId': workspaceId ?? 'none'},
    );
  }

  /// Clear user context (on logout)
  static Future<void> clearUserContext() async {
    debug('User context cleared');
  }

  /// Log a breadcrumb (navigation, user action, etc.)
  static void breadcrumb(String message, {Map<String, dynamic>? metadata}) {
    _logger.d('🍞 $message', error: metadata);
  }
}
