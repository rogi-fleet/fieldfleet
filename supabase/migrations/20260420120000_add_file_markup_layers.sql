-- Phase 4: non-destructive markup layer per file.
--
-- The layer is a single JSONB blob of vector shapes stored alongside the
-- file — the file's underlying bytes are never touched. One row per file
-- (UNIQUE on file_attachment_id): the viewer renders the latest shapes
-- over the image, and "Revert to Original" in the editor is modeled as a
-- DELETE on this row. Shape history / multi-version is out of scope per
-- product direction — a revert wipes the layer.
--
-- Shape schema (documented here for cross-reference; Dart side has the
-- typed model in lib/models/file_markup.dart):
--
-- [
--   { "id", "type": "free_draw", "points": [[x,y]...], "color", "width" },
--   { "id", "type": "arrow",     "from": [x,y], "to": [x,y], "color", "width" },
--   { "id", "type": "callout",   "anchor": [x,y], "tails": [[x,y]...], "text", "color", "fontSize" },
--   { "id", "type": "polyline",  "points": [[x,y]...], "color", "width" },
--   { "id", "type": "text",      "at": [x,y], "text", "color", "fontSize" },
--   { "id", "type": "timestamp", "at": [x,y], "captured_at", "color" }
-- ]
--
-- All coordinates are normalized 0..1 so markup survives rotation and
-- renders to any viewport size.

CREATE TABLE IF NOT EXISTS public.file_markup_layers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  file_attachment_id UUID NOT NULL UNIQUE
    REFERENCES public.file_attachments(id) ON DELETE CASCADE,
  shapes JSONB NOT NULL DEFAULT '[]'::jsonb,
  author_id UUID REFERENCES public.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_file_markup_layers_workspace
  ON public.file_markup_layers (workspace_id);

CREATE OR REPLACE TRIGGER update_file_markup_layers_updated_at
  BEFORE UPDATE ON public.file_markup_layers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.file_markup_layers IS
  'Non-destructive vector markup layer attached to a file_attachment. '
  'One row per file; original bytes are untouched. Delete == revert.';
COMMENT ON COLUMN public.file_markup_layers.shapes IS
  'Ordered JSONB array of vector shapes with normalized (0..1) coordinates.';

-- ---------------------------------------------------------------------------
-- RLS — inherit visibility from the parent file
-- ---------------------------------------------------------------------------
ALTER TABLE public.file_markup_layers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_markup_layers_select ON public.file_markup_layers;
CREATE POLICY file_markup_layers_select ON public.file_markup_layers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'read'
        )
        AND public.file_is_visible(fa.id)
    )
  );

DROP POLICY IF EXISTS file_markup_layers_insert ON public.file_markup_layers;
CREATE POLICY file_markup_layers_insert ON public.file_markup_layers
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'write'
        )
    )
  );

DROP POLICY IF EXISTS file_markup_layers_update ON public.file_markup_layers;
CREATE POLICY file_markup_layers_update ON public.file_markup_layers
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'write'
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'write'
        )
    )
  );

DROP POLICY IF EXISTS file_markup_layers_delete ON public.file_markup_layers;
CREATE POLICY file_markup_layers_delete ON public.file_markup_layers
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'write'
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'file_markup_layers'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE file_markup_layers';
  END IF;
END $$;
