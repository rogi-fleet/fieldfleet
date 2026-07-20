-- Align file_tags / file_attachment_tags RLS with the module-permission model
-- introduced for file_attachments in 20260415110000. Selecting tags still
-- requires workspace membership, but mutations now require the 'documents'
-- module with 'write'. This matches how file_attachments.update / .delete
-- are gated and keeps the tag vocabulary behind the same admin/manager
-- control as the files themselves.

-- ---------------------------------------------------------------------------
-- file_tags
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS file_tags_select ON public.file_tags;
CREATE POLICY file_tags_select ON public.file_tags
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'read')
  );

DROP POLICY IF EXISTS file_tags_insert ON public.file_tags;
CREATE POLICY file_tags_insert ON public.file_tags
  FOR INSERT WITH CHECK (
    public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  );

DROP POLICY IF EXISTS file_tags_update ON public.file_tags;
CREATE POLICY file_tags_update ON public.file_tags
  FOR UPDATE
  USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  )
  WITH CHECK (
    public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  );

DROP POLICY IF EXISTS file_tags_delete ON public.file_tags;
CREATE POLICY file_tags_delete ON public.file_tags
  FOR DELETE USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  );

-- ---------------------------------------------------------------------------
-- file_attachment_tags (join)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS file_attachment_tags_select ON public.file_attachment_tags;
CREATE POLICY file_attachment_tags_select ON public.file_attachment_tags
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(fa.workspace_id, 'documents', 'read')
    )
  );

DROP POLICY IF EXISTS file_attachment_tags_insert ON public.file_attachment_tags;
CREATE POLICY file_attachment_tags_insert ON public.file_attachment_tags
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(fa.workspace_id, 'documents', 'write')
    )
  );

DROP POLICY IF EXISTS file_attachment_tags_delete ON public.file_attachment_tags;
CREATE POLICY file_attachment_tags_delete ON public.file_attachment_tags
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(fa.workspace_id, 'documents', 'write')
    )
  );
