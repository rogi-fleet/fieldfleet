-- Allow authenticated workspace members to insert activity log entries directly.
-- The previous deny-all policy blocked internal app writes; portal-user actions
-- already bypass RLS via SECURITY DEFINER RPCs and are unaffected by this change.
DROP POLICY IF EXISTS document_activity_log_deny_all ON public.document_activity_log;

CREATE POLICY document_activity_log_insert_workspace_member ON public.document_activity_log
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM workspace_members wm
      WHERE wm.workspace_id = document_activity_log.workspace_id
        AND wm.user_id = auth.uid()
    )
  );
