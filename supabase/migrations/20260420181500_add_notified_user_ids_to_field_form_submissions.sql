alter table public.field_form_submissions
  add column if not exists notified_user_ids uuid[] not null default '{}';

comment on column public.field_form_submissions.notified_user_ids is
  'User IDs to notify when the submission transitions to submitted status. Captured at fill time, dispatched on submit.';
