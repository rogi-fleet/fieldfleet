-- Keep project team membership permissions aligned with project create/update.
-- The app allows workspace members to create and edit projects, and both flows
-- write to project_team_members when team assignments are present. Requiring
-- PM/admin here causes the project row insert to succeed and the follow-up team
-- member write to fail, which surfaces as a misleading "create project" error.

DROP POLICY IF EXISTS project_team_insert ON public.project_team_members;
CREATE POLICY project_team_insert ON public.project_team_members
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.projects p
      WHERE p.id = project_team_members.project_id
        AND is_workspace_member(p.workspace_id)
    )
  );

DROP POLICY IF EXISTS project_team_delete ON public.project_team_members;
CREATE POLICY project_team_delete ON public.project_team_members
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.projects p
      WHERE p.id = project_team_members.project_id
        AND is_workspace_member(p.workspace_id)
    )
  );
