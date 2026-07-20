-- =============================================================================
-- Pin search_path on the remaining 39 non-finance Postgres functions.
--
-- Supabase security advisor flagged these as `function_search_path_mutable`.
-- Mutable search_path lets a caller's earlier-on-search_path schema shadow
-- a relation/operator the function uses, intercepting the call. Pinning
-- to public + pg_temp eliminates that without changing behavior.
--
-- Includes RLS helpers (is_workspace_member, is_within_project_geofence),
-- timestamp triggers (update_*_updated_at), recalcs (project_*_recalc,
-- inventory guards, and
-- the workspace consistency checks across the project_modules / hr /
-- punch list / inspections subsystems.
--
-- Applied to the live DB via supabase MCP apply_migration.
-- =============================================================================

DO $$
DECLARE
  function_signature text;
  target_function regprocedure;
BEGIN
  FOREACH function_signature IN ARRAY ARRAY[
    'public.calculate_distance_meters(numeric,numeric,numeric,numeric)',
    'public.fn_messages_thread_rollup()',
    'public.get_or_create_uncategorized_labor_item(uuid,uuid)',
    'public.get_user_workspace_ids()',
    'public.get_workspace_from_storage_path(text)',
    'public.get_workspace_storage_usage(uuid)',
    'public.inventory_apply_stock_movement()',
    'public.is_within_project_geofence(numeric,numeric,uuid)',
    'public.is_workspace_member(uuid)',
    'public.normalize_task_status_progress()',
    'public.permission_level_rank(text)',
    'public.project_daily_logs_ws_check()',
    'public.project_inspection_items_ws_check()',
    'public.project_inspection_recalc()',
    'public.project_inspections_ws_check()',
    'public.project_modules_assert_ws()',
    'public.project_punch_list_items_ws_check()',
    'public.project_punch_list_recalc()',
    'public.project_punch_lists_ws_check()',
    'public.project_warranties_ws_check()',
    'public.project_warranty_claim_recalc()',
    'public.project_warranty_claims_ws_check()',
    'public.rename_customer_type(uuid,uuid,text,text)',
    'public.rename_vendor_category(uuid,uuid,text,text)',
    'public.rename_vendor_type(uuid,uuid,text,text)',
    'public.search_messages(text,text,text,text,timestamp with time zone,timestamp with time zone,boolean,integer)',
    'public.seed_customer_types_for_workspace(uuid)',
    'public.seed_default_workspace_role_templates(uuid,uuid)',
    'public.seed_vendor_categories_for_workspace(uuid)',
    'public.seed_vendor_types_for_workspace(uuid)',
    'public.set_daily_ai_summaries_updated_at()',
    'public.sync_tasks_property_area_legacy()',
    'public.touch_bid_packages_updated_at()',
    'public.update_time_entry_distance()',
    'public.update_updated_at_column()'
  ] LOOP
    target_function := to_regprocedure(function_signature);
    IF target_function IS NOT NULL THEN
      EXECUTE format(
        'ALTER FUNCTION %s SET search_path = public, pg_temp',
        target_function
      );
    END IF;
  END LOOP;
END $$;
