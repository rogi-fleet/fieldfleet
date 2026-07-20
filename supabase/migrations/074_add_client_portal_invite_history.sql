-- Track customer portal invite sends for audit/history in Customer > Client Access.

CREATE TABLE IF NOT EXISTS client_portal_invites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  sent_by UUID REFERENCES users(id) ON DELETE SET NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_client_portal_invites_customer_sent_at
  ON client_portal_invites(customer_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_portal_invites_workspace_customer
  ON client_portal_invites(workspace_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_client_portal_invites_email
  ON client_portal_invites(email);

ALTER TABLE client_portal_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS client_portal_invites_select ON client_portal_invites;
CREATE POLICY client_portal_invites_select ON client_portal_invites
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS client_portal_invites_insert ON client_portal_invites;
CREATE POLICY client_portal_invites_insert ON client_portal_invites
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id)
    AND (sent_by IS NULL OR sent_by = auth.uid())
  );
