-- Collapse the legacy 'Client' system template into the new 'Customer' one
-- introduced by 20260419140000_expand_roles_and_modules.sql.
--
-- Pre-check verified zero workspace_members and zero workspace_invitations
-- reference any legacy 'Client' row; the WHERE clauses below make that
-- guarantee explicit so re-running on another environment is safe.

DELETE FROM public.workspace_role_templates
WHERE is_system = TRUE
  AND name = 'Client'
  AND role = 'client'
  AND NOT EXISTS (
    SELECT 1 FROM public.workspace_members wm
    WHERE wm.role_template_id = workspace_role_templates.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.workspace_invitations wi
    WHERE wi.role_template_id = workspace_role_templates.id
  );

-- If any environment still has 'Client' rows with references, fail loud so a
-- human makes the re-pointing decision.
DO $$
DECLARE
  remaining INTEGER;
BEGIN
  SELECT count(*) INTO remaining
  FROM public.workspace_role_templates
  WHERE is_system = TRUE AND name = 'Client' AND role = 'client';

  IF remaining > 0 THEN
    RAISE EXCEPTION
      'Legacy Client template still has referenced rows (%). Re-point members/invitations to Customer before applying.',
      remaining;
  END IF;
END $$;
