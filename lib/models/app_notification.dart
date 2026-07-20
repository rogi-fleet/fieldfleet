/// Notification type constants. Keep in sync with:
///   * `supabase/functions/_shared/notification_types.ts`
///   * the seed in `20260503160000_unify_notifications_foundation.sql`
///
/// Adding a new type requires an INSERT into public.notification_types
/// (the FK in the notifications table will reject unknown values).
class AppNotificationTypes {
  static const mention = 'mention';
  static const taskAssignment = 'task_assignment';
  static const taskCompletion = 'task_completion';
  static const messageReceived = 'message_received';
  static const workspaceMemberJoined = 'workspace_member_joined';
  static const timeEntrySubmitted = 'time_entry_submitted';
  static const timeEntryApproved = 'time_entry_approved';
  static const timeEntryRejected = 'time_entry_rejected';
  static const documentSigned = 'document_signed';
  static const documentDenied = 'document_denied';
  static const documentChangesRequested = 'document_changes_requested';
  static const documentPaymentCompleted = 'document_payment_completed';
  static const documentBidReceived = 'document_bid_received';
  static const documentBidApplied = 'document_bid_applied';
  static const agreementSigned = 'agreement_signed';
  static const projectUpdate = 'project_update';
  static const priorityAlert = 'priority_alert';
  static const capacityAlert = 'capacity_alert';
  static const automation = 'automation';
  static const aiPlanReady = 'ai_plan_ready';
  static const aiPlanFailed = 'ai_plan_failed';
  static const formSubmission = 'form_submission';
}

/// Represents an in-app notification
class AppNotification {
  final String id;
  final String userId;
  final String workspaceId;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.workspaceId,
    required this.type,
    required this.title,
    this.body,
    this.isRead = false,
    this.metadata = const {},
    required this.createdAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      workspaceId: row['workspace_id'] as String,
      type: row['type'] as String,
      title: row['title'] as String,
      body: row['body'] as String?,
      isRead: row['is_read'] as bool? ?? false,
      metadata: row['metadata'] != null
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : {},
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
