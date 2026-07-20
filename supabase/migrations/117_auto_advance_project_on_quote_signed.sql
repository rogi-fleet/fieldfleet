-- Auto-advance project status based on quotation document lifecycle.
--
-- Two transitions are handled:
--   1. Quotation SENT  → project advances from lead/bidding to "proposal_sent"
--   2. Quotation SIGNED → project advances from any pipeline stage to "awarded"
--
-- A notification is created for workspace members on each transition.

-- ============================================================================
-- 1. Advance project to "proposal_sent" when a quotation is sent
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_advance_project_on_quote_sent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  project_row RECORD;
  old_status TEXT;
BEGIN
  -- Only act when status just changed to 'sent'
  IF NEW.status <> 'sent' OR OLD.status = 'sent' THEN
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

  -- Only advance from early pipeline stages (not if already proposal_sent+)
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
      || ' to Proposal Sent after the quotation was sent.',
    jsonb_build_object(
      'target_type', 'project',
      'project_id', NEW.project_id,
      'old_status', old_status,
      'new_status', 'proposal_sent',
      'trigger', 'quote_sent',
      'document_id', NEW.id
    )
  FROM workspace_members wm
  WHERE wm.workspace_id = project_row.workspace_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_advance_project_on_quote_sent ON generated_documents;
CREATE TRIGGER trg_auto_advance_project_on_quote_sent
  AFTER UPDATE ON generated_documents
  FOR EACH ROW
  WHEN (NEW.status = 'sent' AND OLD.status IS DISTINCT FROM 'sent')
  EXECUTE FUNCTION auto_advance_project_on_quote_sent();

-- ============================================================================
-- 2. Advance project to "awarded" when a quotation is signed
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_advance_project_on_quote_signed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  project_row RECORD;
  old_status TEXT;
BEGIN
  -- Only act when status just changed to 'signed'
  IF NEW.status <> 'signed' OR OLD.status = 'signed' THEN
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

  -- Only advance if project is in a pipeline stage
  IF old_status NOT IN ('lead', 'bidding', 'proposal_sent') THEN
    RETURN NEW;
  END IF;

  UPDATE projects
  SET status = 'awarded',
      updated_at = NOW()
  WHERE id = NEW.project_id;

  INSERT INTO notifications (user_id, workspace_id, type, title, body, metadata)
  SELECT DISTINCT
    wm.user_id,
    project_row.workspace_id,
    'project_update',
    project_row.name || ' is now Awarded',
    'Project status automatically changed from '
      || INITCAP(REPLACE(old_status, '_', ' '))
      || ' to Awarded after the quotation was signed by '
      || COALESCE(NULLIF(TRIM(NEW.signed_by_name), ''), 'the client')
      || '.',
    jsonb_build_object(
      'target_type', 'project',
      'project_id', NEW.project_id,
      'old_status', old_status,
      'new_status', 'awarded',
      'trigger', 'quote_signed',
      'document_id', NEW.id
    )
  FROM workspace_members wm
  WHERE wm.workspace_id = project_row.workspace_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_advance_project_on_quote_signed ON generated_documents;
CREATE TRIGGER trg_auto_advance_project_on_quote_signed
  AFTER UPDATE ON generated_documents
  FOR EACH ROW
  WHEN (NEW.status = 'signed' AND OLD.status IS DISTINCT FROM 'signed')
  EXECUTE FUNCTION auto_advance_project_on_quote_signed();
