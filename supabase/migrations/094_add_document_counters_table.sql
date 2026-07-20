-- Sequential document number counters per workspace and document type.
CREATE TABLE IF NOT EXISTS document_counters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  current_value INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, document_type)
);

-- RLS
ALTER TABLE document_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage counters in their workspace"
  ON document_counters
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_document_counters_workspace
  ON document_counters(workspace_id, document_type);

-- Atomic increment-and-return for document counters.
-- Uses INSERT ... ON CONFLICT with RETURNING to avoid race conditions.
CREATE OR REPLACE FUNCTION next_document_number(
  p_workspace_id UUID,
  p_document_type TEXT
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_next INTEGER;
BEGIN
  INSERT INTO document_counters (workspace_id, document_type, current_value)
  VALUES (p_workspace_id, p_document_type, 1)
  ON CONFLICT (workspace_id, document_type)
  DO UPDATE SET
    current_value = document_counters.current_value + 1,
    updated_at = now()
  RETURNING current_value INTO v_next;

  RETURN v_next;
END;
$$;
