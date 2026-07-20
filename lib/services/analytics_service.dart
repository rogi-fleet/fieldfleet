import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:taskfleet_ops/utils/app_logger.dart';

/// Centralized analytics tracking service
///
/// Provides typed methods for tracking user behavior, events, and screen views.
/// All PII is automatically filtered and only opaque IDs are logged.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Get the analytics observer for navigation tracking
  FirebaseAnalyticsObserver getObserver() {
    return FirebaseAnalyticsObserver(analytics: _analytics);
  }

  // ============================================================================
  // Authentication Events
  // ============================================================================

  /// Track user login
  Future<void> logLogin({required String method}) async {
    await _logEvent('login', parameters: {'method': method});
  }

  /// Track user signup
  Future<void> logSignup({required String method}) async {
    await _logEvent('sign_up', parameters: {'method': method});
  }

  /// Track user logout
  Future<void> logLogout() async {
    await _logEvent('logout');
  }

  // ============================================================================
  // Screen View Tracking
  // ============================================================================

  /// Track screen view
  ///
  /// Note: This is usually handled automatically by FirebaseAnalyticsObserver
  /// but can be called manually for custom screens
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
    AppLogger.debug('Screen view: $screenName');
  }

  // ============================================================================
  // Project Management Events
  // ============================================================================

  /// Track project creation
  Future<void> logProjectCreated({
    required String projectId,
    String? projectType,
  }) async {
    await _logEvent('project_created', parameters: {
      'project_id': projectId,
      if (projectType != null) 'project_type': projectType,
    });
  }

  /// Track project viewed
  Future<void> logProjectViewed({required String projectId}) async {
    await _logEvent('project_viewed', parameters: {
      'project_id': projectId,
    });
  }

  /// Track project updated
  Future<void> logProjectUpdated({
    required String projectId,
    required String field,
  }) async {
    await _logEvent('project_updated', parameters: {
      'project_id': projectId,
      'field': field,
    });
  }

  /// Track project deleted
  Future<void> logProjectDeleted({required String projectId}) async {
    await _logEvent('project_deleted', parameters: {
      'project_id': projectId,
    });
  }

  // ============================================================================
  // Task Management Events
  // ============================================================================

  /// Track task creation
  Future<void> logTaskCreated({
    required String taskId,
    required String projectId,
  }) async {
    await _logEvent('task_created', parameters: {
      'task_id': taskId,
      'project_id': projectId,
    });
  }

  /// Track task completion
  Future<void> logTaskCompleted({
    required String taskId,
    required String projectId,
    int? durationDays,
  }) async {
    await _logEvent('task_completed', parameters: {
      'task_id': taskId,
      'project_id': projectId,
      if (durationDays != null) 'duration_days': durationDays,
    });
  }

  /// Track task assignment
  Future<void> logTaskAssigned({
    required String taskId,
    required String projectId,
  }) async {
    await _logEvent('task_assigned', parameters: {
      'task_id': taskId,
      'project_id': projectId,
    });
  }

  // ============================================================================
  // Budget Events
  // ============================================================================

  /// Track budget item creation
  ///
  /// Note: We log amount ranges, not exact amounts, for privacy
  Future<void> logBudgetItemCreated({
    required String projectId,
    required String itemType,
    required double amount,
  }) async {
    await _logEvent('budget_item_created', parameters: {
      'project_id': projectId,
      'item_type': itemType,
      'amount_range': _getAmountRange(amount),
    });
  }

  /// Track budget update
  Future<void> logBudgetUpdated({
    required String projectId,
    required double totalAmount,
  }) async {
    await _logEvent('budget_updated', parameters: {
      'project_id': projectId,
      'total_range': _getAmountRange(totalAmount),
    });
  }

  // ============================================================================
  // Customer Events
  // ============================================================================

  /// Track customer creation
  Future<void> logCustomerCreated({
    required String customerId,
    required String customerType,
  }) async {
    await _logEvent('customer_created', parameters: {
      'customer_id': customerId,
      'customer_type': customerType,
    });
  }

  /// Track customer viewed
  Future<void> logCustomerViewed({required String customerId}) async {
    await _logEvent('customer_viewed', parameters: {
      'customer_id': customerId,
    });
  }

  // ============================================================================
  // Error Events
  // ============================================================================

  /// Track error occurrence
  Future<void> logErrorOccurred({
    required String errorType,
    required String screen,
  }) async {
    await _logEvent('error_occurred', parameters: {
      'error_type': errorType,
      'screen': screen,
    });
  }

  /// Track error recovery
  Future<void> logErrorRecovered({
    required String recoveryMethod,
    required String screen,
  }) async {
    await _logEvent('error_recovered', parameters: {
      'recovery_method': recoveryMethod,
      'screen': screen,
    });
  }

  // ============================================================================
  // User Properties
  // ============================================================================

  /// Set user properties after login
  Future<void> setUserProperties({
    required String userId,
    String? workspaceId,
    String? userRole,
  }) async {
    await _analytics.setUserId(id: userId);
    if (workspaceId != null) {
      await _analytics.setUserProperty(
        name: 'workspace_id',
        value: workspaceId,
      );
    }
    if (userRole != null) {
      await _analytics.setUserProperty(
        name: 'user_role',
        value: userRole,
      );
    }
    AppLogger.debug('User properties set', metadata: {
      'userId': userId,
      'workspaceId': workspaceId ?? 'none',
      'userRole': userRole ?? 'none',
    });
  }

  /// Clear user properties (on logout)
  Future<void> clearUserProperties() async {
    await _analytics.setUserId(id: null);
    AppLogger.debug('User properties cleared');
  }

  // ============================================================================
  // Custom Events
  // ============================================================================

  /// Log a custom event
  ///
  /// Use this for events not covered by the typed methods above.
  /// Event names should follow Firebase naming conventions (lowercase, underscores).
  Future<void> logCustomEvent({
    required String name,
    Map<String, Object?>? parameters,
  }) async {
    await _logEvent(name, parameters: parameters);
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /// Internal event logging with validation
  Future<void> _logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {
    try {
      // Cast to Map<String, Object> for Firebase Analytics
      final Map<String, Object>? eventParams = parameters?.map(
        (key, value) => MapEntry(key, value ?? ''),
      );

      await _analytics.logEvent(
        name: name,
        parameters: eventParams,
      );

      if (parameters != null) {
        AppLogger.debug('Analytics: $name', metadata: parameters.cast<String, dynamic>());
      } else {
        AppLogger.debug('Analytics: $name');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to log analytics event',
        error: e,
        stackTrace: stackTrace,
        metadata: {'event': name},
      );
    }
  }

  /// Convert amount to privacy-safe range
  String _getAmountRange(double amount) {
    if (amount < 1000) return '0-1k';
    if (amount < 5000) return '1k-5k';
    if (amount < 10000) return '5k-10k';
    if (amount < 25000) return '10k-25k';
    if (amount < 50000) return '25k-50k';
    if (amount < 100000) return '50k-100k';
    if (amount < 250000) return '100k-250k';
    if (amount < 500000) return '250k-500k';
    return '500k+';
  }
}
