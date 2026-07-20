-- Auto-advance project status when a quotation is approved internally.
--
-- When a quotation document transitions to 'approved', advance the project
-- from early pipeline stages (lead, bidding) to "proposal_sent" so the
-- summary dashboard label changes from "Estimated" to "Approved".

CREATE OR REPLACE FUNCTION public.auto_advance_project_on_quote_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  project_row RECORD;
  old_status TEXT;
BEGIN
  -- Only act when status just changed to 'approved'
  IF NEW.status <> 'approved' OR OLD.status = 'approved' THEN
    RETURN NEW;
  END IF;

  -- Only for quotation documents linked to a project
  IF NEW.document_type IS NULL
     OR NEW.document_type::TEXT <> 'quotation'
     OR NEW.project_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id, status::TEXT AS status, workspace_id, name
  INTO project_row
  FROM projects
  WHERE id = NEW.project_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  old_status := project_row.status;

  -- Only advance from early pipeline stages
  IF old_status NOT IN ('lead', 'bidding') THEN
    RETURN NEW;
  END IF;

  UPDATE projects
  SET status = 'proposal_sent',
      updated_at = NOW()
  WHERE id = NEW.project_id;

  INSERT INTO notifications (user_id, workspace_id, type, title, body, metadata)
  SELECT DISTINCT
    wm.user_id,
    project_row.workspace_id,
    'project_update',
    project_row.name || ' is now Proposal Sent',
    'Project status automatically changed from '
      || INITCAP(REPLACE(old_status, '_', ' '))
      || ' to Proposal Sent after the estimate was approved.',
    jsonb_build_object(
      'target_type', 'project',
      'project_id', NEW.project_id,
      'old_status', old_status,
      'new_status', 'proposal_sent',
      'trigger', 'quote_approved',
      'document_id', NEW.id
    )
  FROM workspace_members wm
  WHERE wm.workspace_id = project_row.workspace_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_advance_project_on_quote_approved ON generated_documents;
CREATE TRIGGER trg_auto_advance_project_on_quote_approved
  AFTER UPDATE ON generated_documents
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION auto_advance_project_on_quote_approved();
