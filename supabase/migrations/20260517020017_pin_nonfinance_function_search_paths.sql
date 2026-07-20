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

ALTER FUNCTION public.calculate_distance_meters(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric) SET search_path = public, pg_temp;
ALTER FUNCTION public.fn_messages_thread_rollup() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_or_create_uncategorized_labor_item(p_project_id uuid, p_workspace_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_user_workspace_ids() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_workspace_from_storage_path(path text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_workspace_storage_usage(p_workspace_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.inventory_apply_stock_movement() SET search_path = public, pg_temp;
ALTER FUNCTION public.is_within_project_geofence(worker_lat numeric, worker_lon numeric, project_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_workspace_member(workspace_uuid uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_task_status_progress() SET search_path = public, pg_temp;
ALTER FUNCTION public.permission_level_rank(level text) SET search_path = public, pg_temp;
ALTER FUNCTION public.project_daily_logs_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_inspection_items_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_inspection_recalc() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_inspections_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_modules_assert_ws() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_punch_list_items_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_punch_list_recalc() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_punch_lists_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_warranties_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_warranty_claim_recalc() SET search_path = public, pg_temp;
ALTER FUNCTION public.project_warranty_claims_ws_check() SET search_path = public, pg_temp;
ALTER FUNCTION public.rename_customer_type(p_workspace_id uuid, p_type_id uuid, p_old_name text, p_new_name text) SET search_path = public, pg_temp;
ALTER FUNCTION public.rename_vendor_category(p_workspace_id uuid, p_category_id uuid, p_old_name text, p_new_name text) SET search_path = public, pg_temp;
ALTER FUNCTION public.rename_vendor_type(p_workspace_id uuid, p_type_id uuid, p_old_name text, p_new_name text) SET search_path = public, pg_temp;
ALTER FUNCTION public.search_messages(p_workspace_id text, p_user_id text, p_query text, p_sender_id text, p_date_from timestamp with time zone, p_date_to timestamp with time zone, p_has_attachment boolean, p_limit integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_customer_types_for_workspace(p_workspace_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_default_workspace_role_templates(p_workspace_id uuid, p_created_by uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_vendor_categories_for_workspace(p_workspace_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_vendor_types_for_workspace(p_workspace_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.set_daily_ai_summaries_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.sync_tasks_property_area_legacy() SET search_path = public, pg_temp;
ALTER FUNCTION public.touch_bid_packages_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_time_entry_distance() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_updated_at_column() SET search_path = public, pg_temp;
