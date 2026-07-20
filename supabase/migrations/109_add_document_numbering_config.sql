-- Workspace-level configuration for document numbering (prefix, padding, separator).
-- Separate from document_counters which holds the atomic runtime counter.

CREATE TABLE IF NOT EXISTS document_numbering_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  prefix TEXT NOT NULL,
  padding_width INTEGER NOT NULL DEFAULT 3 CHECK (padding_width BETWEEN 1 AND 8),
  separator TEXT NOT NULL DEFAULT '-',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, document_type)
);

ALTER TABLE document_numbering_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_numbering_config_select"
  ON document_numbering_config FOR SELECT
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "document_numbering_config_insert"
  ON document_numbering_config FOR INSERT
  WITH CHECK (
    is_workspace_admin(workspace_id)
  );

CREATE POLICY "document_numbering_config_update"
  ON document_numbering_config FOR UPDATE
  USING (
    is_workspace_admin(workspace_id)
  );

CREATE POLICY "document_numbering_config_delete"
  ON document_numbering_config FOR DELETE
  USING (
    is_workspace_admin(workspace_id)
  );

CREATE INDEX IF NOT EXISTS idx_document_numbering_config_workspace
  ON document_numbering_config(workspace_id, document_type);

-- Trigger to auto-update updated_at
CREATE TRIGGER set_updated_at_document_numbering_config
  BEFORE UPDATE ON document_numbering_config
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Atomically set (or create) the counter for a workspace + document type.
CREATE OR REPLACE FUNCTION set_document_counter(
  p_workspace_id UUID,
  p_document_type TEXT,
  p_value INTEGER
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO document_counters (workspace_id, document_type, current_value)
  VALUES (p_workspace_id, p_document_type, p_value)
  ON CONFLICT (workspace_id, document_type)
  DO UPDATE SET
    current_value = p_value,
    updated_at = now();
END;
$$;
