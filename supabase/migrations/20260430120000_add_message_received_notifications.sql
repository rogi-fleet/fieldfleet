-- Add 'message_received' to the notifications type CHECK constraint so
-- new-message notifications can be inserted.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'message_received',
      'ai_plan_ready',
      'ai_plan_failed',
      'automation',
      'capacity_alert',
      'priority_alert',
      'workspace_member_joined',
      'time_entry_submitted',
      'time_entry_approved',
      'time_entry_rejected',
      'document_signed',
      'agreement_signed',
      'project_update',
      'document_denied',
      'document_changes_requested',
      'document_payment_completed'
    )
  );
