import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// Supabase service for submitting in-app user feedback.
class SupabaseFeedbackService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Submit feedback from a user and send email notification.
  Future<void> submitFeedback({
    required String workspaceId,
    required String userId,
    required String category,
    required String message,
  }) async {
    try {
      await _supabase.from('feedback').insert({
        'workspace_id': workspaceId,
        'user_id': userId,
        'category': category,
        'message': message,
      });
      AppLogger.info('Feedback submitted (category=$category)');

      // Fire-and-forget email notification — don't block the user on it.
      _sendNotification(
        workspaceId: workspaceId,
        category: category,
        message: message,
      );
    } catch (e) {
      AppLogger.error('Failed to submit feedback', error: e);
      rethrow;
    }
  }

  Future<void> _sendNotification({
    required String workspaceId,
    required String category,
    required String message,
  }) async {
    try {
      await _supabase.functions.invoke(
        'send-feedback-notification',
        body: {
          'workspaceId': workspaceId,
          'category': category,
          'message': message,
        },
      );
    } catch (e) {
      // Log but don't throw — feedback was already saved.
      AppLogger.error('Failed to send feedback notification email', error: e);
    }
  }
}
