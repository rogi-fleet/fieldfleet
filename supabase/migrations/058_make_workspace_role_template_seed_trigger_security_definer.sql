-- Fix signup bootstrap RLS timing issue.
-- The AFTER INSERT trigger on workspaces seeds role templates in the same
-- statement snapshot; owner-based policy checks that query workspaces can fail
-- because the new workspace row is not visible yet.
-- Run trigger seeding as SECURITY DEFINER instead.

CREATE OR REPLACE FUNCTION trigger_seed_default_workspace_role_templates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM seed_default_workspace_role_templates(NEW.id, NEW.owner_id);
  RETURN NEW;
END;
$$;
