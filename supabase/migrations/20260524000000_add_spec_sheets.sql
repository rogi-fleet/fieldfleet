-- Spec sheets: lightweight saved PDFs generated from the budget-item picker on
-- the Specifications tab. Each row references a file_attachments row that
-- holds the actual PDF in Supabase Storage, so existing storage quota,
-- audit-event and download plumbing all apply.

CREATE TABLE IF NOT EXISTS public.spec_sheets (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  file_attachment_id  UUID NOT NULL REFERENCES public.file_attachments(id) ON DELETE CASCADE,
  item_ids            TEXT[] NOT NULL DEFAULT '{}',
  item_count          INT NOT NULL DEFAULT 0,
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spec_sheets_project   ON public.spec_sheets(project_id);
CREATE INDEX IF NOT EXISTS idx_spec_sheets_workspace ON public.spec_sheets(workspace_id);
CREATE INDEX IF NOT EXISTS idx_spec_sheets_file      ON public.spec_sheets(file_attachment_id);

ALTER TABLE public.spec_sheets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spec_sheets_all ON public.spec_sheets;
CREATE POLICY spec_sheets_all ON public.spec_sheets
  FOR ALL USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));
