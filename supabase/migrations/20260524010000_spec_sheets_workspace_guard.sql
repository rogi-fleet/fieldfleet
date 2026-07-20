-- Defence-in-depth: ensure spec_sheets.file_attachment_id always references a
-- file_attachments row in the same workspace AND project as the spec sheet.
-- Without this, a workspace member could craft a row that points at another
-- workspace's attachment UUID and exfiltrate it via the email edge function.

CREATE OR REPLACE FUNCTION public.spec_sheets_validate_attachment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_ws  UUID;
  v_pj  UUID;
BEGIN
  SELECT workspace_id, project_id
    INTO v_ws, v_pj
    FROM public.file_attachments
   WHERE id = NEW.file_attachment_id;

  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'file_attachment % not found', NEW.file_attachment_id;
  END IF;
  IF v_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'file_attachment workspace mismatch';
  END IF;
  IF v_pj IS DISTINCT FROM NEW.project_id THEN
    RAISE EXCEPTION 'file_attachment project mismatch';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_spec_sheets_validate_attachment ON public.spec_sheets;
CREATE TRIGGER trg_spec_sheets_validate_attachment
  BEFORE INSERT OR UPDATE OF file_attachment_id, workspace_id, project_id
  ON public.spec_sheets
  FOR EACH ROW EXECUTE FUNCTION public.spec_sheets_validate_attachment();
