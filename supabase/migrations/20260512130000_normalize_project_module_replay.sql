-- Normalize a migration that was partially applied manually in some local
-- databases before its replay issue was fixed: project module workspace
-- triggers must use trigger arguments via TG_ARGV, not declared
-- trigger-function parameters.

CREATE OR REPLACE FUNCTION public.project_modules_assert_ws()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  parent_table TEXT := TG_ARGV[0];
  parent_col TEXT := TG_ARGV[1];
  v_parent_id UUID;
  v_parent_ws UUID;
BEGIN
  IF TG_NARGS <> 2 THEN
    RAISE EXCEPTION 'project_modules_assert_ws requires parent table and parent column trigger args';
  END IF;

  EXECUTE format('SELECT ($1).%I', parent_col) INTO v_parent_id USING NEW;
  IF v_parent_id IS NULL THEN
    RETURN NEW;
  END IF;

  EXECUTE format('SELECT workspace_id FROM public.%I WHERE id = $1', parent_table)
    INTO v_parent_ws USING v_parent_id;
  IF v_parent_ws IS NOT NULL AND v_parent_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'workspace mismatch on %.%: parent=%, child=%',
      TG_TABLE_NAME, parent_col, v_parent_ws, NEW.workspace_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.project_warranties') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_pwarranties_ws ON public.project_warranties;
    CREATE TRIGGER trg_pwarranties_ws
      BEFORE INSERT OR UPDATE ON public.project_warranties
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('projects', 'project_id');
  END IF;

  IF to_regclass('public.project_warranty_claims') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_pwclaims_ws ON public.project_warranty_claims;
    CREATE TRIGGER trg_pwclaims_ws
      BEFORE INSERT OR UPDATE ON public.project_warranty_claims
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('project_warranties', 'warranty_id');
  END IF;

  IF to_regclass('public.project_daily_logs') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_pdaily_ws ON public.project_daily_logs;
    CREATE TRIGGER trg_pdaily_ws
      BEFORE INSERT OR UPDATE ON public.project_daily_logs
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('projects', 'project_id');
  END IF;

  IF to_regclass('public.project_inspections') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_pinsp_ws ON public.project_inspections;
    CREATE TRIGGER trg_pinsp_ws
      BEFORE INSERT OR UPDATE ON public.project_inspections
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('projects', 'project_id');
  END IF;

  IF to_regclass('public.project_inspection_items') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_pinspitems_ws ON public.project_inspection_items;
    CREATE TRIGGER trg_pinspitems_ws
      BEFORE INSERT OR UPDATE ON public.project_inspection_items
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('project_inspections', 'inspection_id');
  END IF;

  IF to_regclass('public.project_punch_lists') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_ppunch_ws ON public.project_punch_lists;
    CREATE TRIGGER trg_ppunch_ws
      BEFORE INSERT OR UPDATE ON public.project_punch_lists
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('projects', 'project_id');
  END IF;

  IF to_regclass('public.project_punch_list_items') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_ppunchitems_ws ON public.project_punch_list_items;
    CREATE TRIGGER trg_ppunchitems_ws
      BEFORE INSERT OR UPDATE ON public.project_punch_list_items
      FOR EACH ROW EXECUTE FUNCTION public.project_modules_assert_ws('project_punch_lists', 'punch_list_id');
  END IF;
END $$;
