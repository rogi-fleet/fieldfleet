-- Feedback table for in-app user feedback
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('bug', 'feature_request', 'improvement', 'general')),
  message text not null check (char_length(message) >= 10),
  created_at timestamptz not null default now()
);

-- Index for workspace-level queries
create index if not exists idx_feedback_workspace
  on public.feedback(workspace_id, created_at desc);

-- RLS
alter table public.feedback enable row level security;

-- Users can insert their own feedback
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'feedback'
      and policyname = 'Users can insert own feedback'
  ) then
    create policy "Users can insert own feedback"
      on public.feedback for insert
      with check (auth.uid() = user_id);
  end if;
end
$$;

-- Users can read their own feedback
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'feedback'
      and policyname = 'Users can read own feedback'
  ) then
    create policy "Users can read own feedback"
      on public.feedback for select
      using (auth.uid() = user_id);
  end if;
end
$$;
