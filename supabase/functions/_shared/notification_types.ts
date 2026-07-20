// Shared notification type registry for edge functions. Keep in sync
// with lib/models/app_notification.dart (Dart class AppNotificationTypes)
// and the seed in migration 20260503160000_unify_notifications_foundation.
//
// To add a new type: append here, in app_notification.dart, and INSERT a
// row into public.notification_types via a migration. The DB FK enforces
// agreement at insert time.

export const NOTIFICATION_TYPES = {
  mention: "mention",
  taskAssignment: "task_assignment",
  taskCompletion: "task_completion",
  messageReceived: "message_received",
  workspaceMemberJoined: "workspace_member_joined",
  timeEntrySubmitted: "time_entry_submitted",
  timeEntryApproved: "time_entry_approved",
  timeEntryRejected: "time_entry_rejected",
  documentSigned: "document_signed",
  documentDenied: "document_denied",
  documentChangesRequested: "document_changes_requested",
  documentPaymentCompleted: "document_payment_completed",
  documentBidReceived: "document_bid_received",
  documentBidApplied: "document_bid_applied",
  agreementSigned: "agreement_signed",
  projectUpdate: "project_update",
  priorityAlert: "priority_alert",
  capacityAlert: "capacity_alert",
  automation: "automation",
  aiPlanReady: "ai_plan_ready",
  aiPlanFailed: "ai_plan_failed",
  formSubmission: "form_submission",
} as const;

export type NotificationType =
  typeof NOTIFICATION_TYPES[keyof typeof NOTIFICATION_TYPES];

// Map of type → preference key in users.notification_preferences.
// Mirrors the seed in notification_types(email_pref_key, push_pref_key).
export const PUSH_PREF_KEY: Record<string, string> = {
  [NOTIFICATION_TYPES.mention]: "mentionsPush",
  [NOTIFICATION_TYPES.taskAssignment]: "taskAssignmentsPush",
  [NOTIFICATION_TYPES.taskCompletion]: "taskCompletionsPush",
  [NOTIFICATION_TYPES.messageReceived]: "messagesPush",
};

export const EMAIL_PREF_KEY: Record<string, string> = {
  [NOTIFICATION_TYPES.mention]: "mentionsEmail",
  [NOTIFICATION_TYPES.taskAssignment]: "taskAssignmentsEmail",
  [NOTIFICATION_TYPES.taskCompletion]: "taskCompletionsEmail",
};

// Catch-all fallback for any type that doesn't have an explicit pref key.
export const FALLBACK_PUSH_PREF_KEY = "projectUpdatesPush";
export const FALLBACK_EMAIL_PREF_KEY = "projectUpdatesEmail";

export function pushPrefKeyFor(type: string): string {
  return PUSH_PREF_KEY[type] ?? FALLBACK_PUSH_PREF_KEY;
}

export function emailPrefKeyFor(type: string): string {
  return EMAIL_PREF_KEY[type] ?? FALLBACK_EMAIL_PREF_KEY;
}
