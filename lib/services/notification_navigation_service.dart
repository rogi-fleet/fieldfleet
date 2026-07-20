import '../models/app_notification.dart';

/// Resolves app navigation routes from notification metadata/payload fields.
class NotificationNavigationService {
  static String routeForNotification(AppNotification notification) {
    return routeFromMetadata(notification.metadata) ?? '/notifications';
  }

  static String? routeFromMetadata(Map<String, dynamic> metadata) {
    final explicitRoute = _firstNonEmpty(metadata, const [
      'deeplink_path',
      'deep_link',
      'route',
      'target_path',
    ]);
    if (explicitRoute != null) {
      final normalized = explicitRoute.startsWith('/')
          ? explicitRoute
          : '/$explicitRoute';
      return _normalizeRoute(normalized);
    }

    final projectId = _firstNonEmpty(metadata, const [
      'project_id',
      'projectId',
    ]);
    final taskId = _firstNonEmpty(metadata, const ['task_id', 'taskId']);
    final conversationId = _firstNonEmpty(metadata, const [
      'conversation_id',
      'conversationId',
    ]);
    final documentId = _firstNonEmpty(metadata, const [
      'document_id',
      'documentId',
    ]);
    final aiPlanId = _firstNonEmpty(metadata, const ['ai_plan_id', 'aiPlanId']);
    final planId = _firstNonEmpty(metadata, const ['plan_id', 'planId']);
    final tab = _firstNonEmpty(metadata, const ['tab']);
    final targetType = _firstNonEmpty(metadata, const [
      'target_type',
      'targetType',
    ]);

    // When the producer set `target_type` explicitly, honor it. Project
    // status-change notifications (e.g. "Kitchen renovation is now Awarded")
    // carry both project_id and document_id — without this branch the
    // document_id check wins and the user lands on the triggering quotation
    // instead of the project the notification headlines.
    if (targetType == 'project' && projectId != null) {
      if (taskId != null) {
        return '/projects/$projectId?tab=tasks&taskId=$taskId';
      }
      if (aiPlanId != null) {
        return '/projects/$projectId/ai-plan/$aiPlanId';
      }
      if (planId != null) {
        return '/projects/$projectId/plans/$planId';
      }
      if (tab != null) {
        return '/projects/$projectId?tab=$tab';
      }
      return '/projects/$projectId';
    }

    if (projectId != null && taskId != null) {
      return '/projects/$projectId?tab=tasks&taskId=$taskId';
    }
    if (conversationId != null) {
      return _normalizeRoute('/messages/$conversationId');
    }
    if (documentId != null) {
      return _normalizeRoute('/documents/$documentId');
    }
    if (projectId != null && aiPlanId != null) {
      return '/projects/$projectId/ai-plan/$aiPlanId';
    }
    if (projectId != null && planId != null) {
      return '/projects/$projectId/plans/$planId';
    }
    if (projectId != null && tab != null) {
      return '/projects/$projectId?tab=$tab';
    }
    if (projectId != null) {
      return '/projects/$projectId';
    }

    return null;
  }

  static String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String _normalizeRoute(String route) {
    // Legacy path support: `/messages/conversation/:id` -> `/messages/:id`.
    if (route.startsWith('/messages/conversation/')) {
      return route.replaceFirst('/messages/conversation/', '/messages/');
    }
    return route;
  }
}
