ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'ai_plan_ready',
      'ai_plan_failed',
      'automation',
      'capacity_alert',
      'priority_alert',
      'workspace_member_joined',
      'time_entry_submitted',
      'time_entry_approved',
      'time_entry_rejected'
    )
  );

