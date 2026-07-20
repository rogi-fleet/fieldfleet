-- Enforce workspace/project consistency for budget_document_links.

CREATE OR REPLACE FUNCTION public.enforce_budget_document_link_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  document_workspace_id UUID;
  document_project_id UUID;
  budget_workspace_id UUID;
  budget_project_id UUID;
BEGIN
  SELECT workspace_id, project_id
  INTO document_workspace_id, document_project_id
  FROM public.generated_documents
  WHERE id = NEW.generated_document_id;

  IF document_workspace_id IS NULL THEN
    RAISE EXCEPTION 'generated_document_id % does not exist', NEW.generated_document_id;
  END IF;

  SELECT workspace_id, project_id
  INTO budget_workspace_id, budget_project_id
  FROM public.budget_items
  WHERE id = NEW.budget_item_id;

  IF budget_workspace_id IS NULL THEN
    RAISE EXCEPTION 'budget_item_id % does not exist', NEW.budget_item_id;
  END IF;

  IF document_workspace_id IS DISTINCT FROM budget_workspace_id THEN
    RAISE EXCEPTION
      'budget_document_links workspace mismatch for document % and budget item %',
      NEW.generated_document_id,
      NEW.budget_item_id;
  END IF;

  IF document_project_id IS NOT NULL
     AND document_project_id IS DISTINCT FROM budget_project_id THEN
    RAISE EXCEPTION
      'budget_document_links project mismatch for document % and budget item %',
      NEW.generated_document_id,
      NEW.budget_item_id;
  END IF;

  NEW.workspace_id := document_workspace_id;
  NEW.project_id := COALESCE(document_project_id, budget_project_id);

  IF NEW.project_id IS NULL THEN
    RAISE EXCEPTION
      'budget_document_links requires a project for document % and budget item %',
      NEW.generated_document_id,
      NEW.budget_item_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_budget_document_link_integrity
ON public.budget_document_links;

CREATE TRIGGER enforce_budget_document_link_integrity
BEFORE INSERT OR UPDATE ON public.budget_document_links
FOR EACH ROW
EXECUTE FUNCTION public.enforce_budget_document_link_integrity();

UPDATE public.budget_document_links bdl
SET
  workspace_id = gd.workspace_id,
  project_id = COALESCE(gd.project_id, bi.project_id)
FROM public.generated_documents gd,
     public.budget_items bi
WHERE gd.id = bdl.generated_document_id
  AND bi.id = bdl.budget_item_id
  AND gd.workspace_id = bi.workspace_id
  AND (gd.project_id IS NULL OR gd.project_id = bi.project_id)
  AND (
    bdl.workspace_id IS DISTINCT FROM gd.workspace_id
    OR bdl.project_id IS DISTINCT FROM COALESCE(gd.project_id, bi.project_id)
  );
