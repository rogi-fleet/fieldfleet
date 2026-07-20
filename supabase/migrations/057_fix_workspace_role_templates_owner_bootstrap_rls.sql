-- Fix signup bootstrap failure:
-- workspace_role_templates are seeded by a trigger on workspaces insert,
-- before the creator is inserted into workspace_members.
-- Allow workspace owners to insert role templates during this window.

DO $$
BEGIN
  IF to_regclass('public.workspace_role_templates') IS NULL THEN
    RAISE NOTICE
      'Skipping workspace_role_templates policy patch: table does not exist.';
    RETURN;
  END IF;

  EXECUTE
    'DROP POLICY IF EXISTS workspace_role_templates_insert ON public.workspace_role_templates';

  EXECUTE $policy$
    CREATE POLICY workspace_role_templates_insert
    ON public.workspace_role_templates
    FOR INSERT
    WITH CHECK (
      is_workspace_admin(workspace_id)
      OR EXISTS (
        SELECT 1
        FROM public.workspaces w
        WHERE w.id = workspace_role_templates.workspace_id
          AND w.owner_id = auth.uid()
      )
    )
  $policy$;
END $$;
