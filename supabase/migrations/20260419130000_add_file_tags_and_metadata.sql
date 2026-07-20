-- File tag system + title/description on file_attachments.
--
-- Promotes the loose TEXT[] `tags` column on `file_attachments` into a proper
-- workspace-scoped tag table with color + reusable semantics (mirrors the
-- customer_tags / customer_tag_assignments pair).
--
-- The existing `file_attachments.tags` column is retained for one release as
-- a read-only fallback; a follow-up migration will drop it after the backfill
-- has stabilised.

-- ---------------------------------------------------------------------------
-- file_tags
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS file_tags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#64748B',
  description TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Case-insensitive uniqueness per workspace so "Photo" and "photo" collapse.
CREATE UNIQUE INDEX IF NOT EXISTS idx_file_tags_workspace_name_ci
  ON file_tags (workspace_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_file_tags_workspace
  ON file_tags (workspace_id);

CREATE OR REPLACE TRIGGER update_file_tags_updated_at
  BEFORE UPDATE ON file_tags
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE file_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_tags_select ON file_tags;
CREATE POLICY file_tags_select ON file_tags
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS file_tags_insert ON file_tags;
CREATE POLICY file_tags_insert ON file_tags
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS file_tags_update ON file_tags;
CREATE POLICY file_tags_update ON file_tags
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS file_tags_delete ON file_tags;
CREATE POLICY file_tags_delete ON file_tags
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- file_attachment_tags (join)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS file_attachment_tags (
  file_attachment_id UUID NOT NULL REFERENCES file_attachments(id) ON DELETE CASCADE,
  file_tag_id UUID NOT NULL REFERENCES file_tags(id) ON DELETE CASCADE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (file_attachment_id, file_tag_id)
);

CREATE INDEX IF NOT EXISTS idx_file_attachment_tags_tag
  ON file_attachment_tags (file_tag_id);

ALTER TABLE file_attachment_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_attachment_tags_select ON file_attachment_tags;
CREATE POLICY file_attachment_tags_select ON file_attachment_tags
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM file_attachments fa
      WHERE fa.id = file_attachment_id
        AND is_workspace_member(fa.workspace_id)
    )
  );

DROP POLICY IF EXISTS file_attachment_tags_insert ON file_attachment_tags;
CREATE POLICY file_attachment_tags_insert ON file_attachment_tags
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM file_attachments fa
      WHERE fa.id = file_attachment_id
        AND is_workspace_member(fa.workspace_id)
    )
  );

DROP POLICY IF EXISTS file_attachment_tags_delete ON file_attachment_tags;
CREATE POLICY file_attachment_tags_delete ON file_attachment_tags
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM file_attachments fa
      WHERE fa.id = file_attachment_id
        AND is_workspace_member(fa.workspace_id)
    )
  );

-- ---------------------------------------------------------------------------
-- title / description on file_attachments
-- ---------------------------------------------------------------------------
ALTER TABLE file_attachments
  ADD COLUMN IF NOT EXISTS title TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON COLUMN file_attachments.title IS
  'Optional human-readable title, separate from the stored filename. Editable from the file detail panel.';
COMMENT ON COLUMN file_attachments.description IS
  'Optional long-form description shown in the file detail panel.';

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  tables_to_add text[] := ARRAY['file_tags', 'file_attachment_tags'];
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY tables_to_add LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', tbl);
    END IF;
  END LOOP;
END $$;
