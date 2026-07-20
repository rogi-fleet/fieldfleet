-- Tokenized public signing links for generated documents

CREATE TABLE IF NOT EXISTS document_sign_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE,
  token TEXT UNIQUE NOT NULL,
  recipient_email TEXT,
  created_by UUID REFERENCES users(id),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  used_at TIMESTAMPTZ,
  last_accessed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_sign_links_document_id
  ON document_sign_links(document_id);

CREATE INDEX IF NOT EXISTS idx_document_sign_links_workspace_id
  ON document_sign_links(workspace_id);

CREATE INDEX IF NOT EXISTS idx_document_sign_links_token
  ON document_sign_links(token);

CREATE INDEX IF NOT EXISTS idx_document_sign_links_active_lookup
  ON document_sign_links(document_id, recipient_email, expires_at)
  WHERE revoked_at IS NULL AND used_at IS NULL;

ALTER TABLE document_sign_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_sign_links_no_direct_access ON document_sign_links;
CREATE POLICY document_sign_links_no_direct_access ON document_sign_links
  FOR ALL
  USING (FALSE)
  WITH CHECK (FALSE);

DROP TRIGGER IF EXISTS set_document_sign_links_updated_at ON document_sign_links;
CREATE TRIGGER set_document_sign_links_updated_at
  BEFORE UPDATE ON document_sign_links
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
