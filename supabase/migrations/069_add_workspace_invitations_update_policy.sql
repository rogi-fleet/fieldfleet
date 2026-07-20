-- Allow workspace admins to update invitations (resend, revoke, etc.)
DROP POLICY IF EXISTS invitations_update ON workspace_invitations;
CREATE POLICY invitations_update ON workspace_invitations
  FOR UPDATE USING (is_workspace_admin(workspace_id))
  WITH CHECK (is_workspace_admin(workspace_id));
