-- =============================================================================
-- Drop legacy overlapping permissive policies flagged by the Supabase
-- performance advisor (multiple_permissive_policies).
--
-- Every entry below has a `<table>_<cmd>` counterpart that uses the
-- `is_workspace_member()` / `is_pm_or_admin()` helper functions for the
-- same (or broader) access. With both policies permissive, Postgres
-- evaluates BOTH per row even though one passing is enough — pure
-- overhead.
--
-- daily_ai_summaries also drops the "Service role can write daily
-- summaries" entry. The service_role JWT has BYPASSRLS, so writes still
-- succeed; the policy was decorative.
--
-- Note: the user-read policy on daily_ai_summaries was accidentally
-- caught by the name-with-space filter; the next migration (restore
-- _daily_ai_summaries_user_read) recreates it under a snake_case name.
--
-- Idempotent (DROP POLICY IF EXISTS). Applied via supabase MCP.
-- =============================================================================

DROP POLICY IF EXISTS "Admins and managers can insert catalog items" ON public.catalog_items;
DROP POLICY IF EXISTS "Admins and managers can update catalog items" ON public.catalog_items;
DROP POLICY IF EXISTS "Admins can delete catalog items" ON public.catalog_items;
DROP POLICY IF EXISTS "Users can view catalog items in their workspace" ON public.catalog_items;
DROP POLICY IF EXISTS "Admins and managers can insert plans" ON public.construction_plans;
DROP POLICY IF EXISTS "Admins and managers can update plans" ON public.construction_plans;
DROP POLICY IF EXISTS "Admins can delete plans" ON public.construction_plans;
DROP POLICY IF EXISTS "Users can view plans in their workspace" ON public.construction_plans;
DROP POLICY IF EXISTS "Service role can write daily summaries" ON public.daily_ai_summaries;
DROP POLICY IF EXISTS "Users can read their own daily summaries" ON public.daily_ai_summaries;
DROP POLICY IF EXISTS "Admins and managers can insert forms" ON public.forms;
DROP POLICY IF EXISTS "Admins and managers can update forms" ON public.forms;
DROP POLICY IF EXISTS "Admins can delete forms" ON public.forms;
DROP POLICY IF EXISTS "Users can view forms in their workspace" ON public.forms;
DROP POLICY IF EXISTS "Admins and managers can insert maintenance logs" ON public.maintenance_logs;
DROP POLICY IF EXISTS "Admins and managers can update maintenance logs" ON public.maintenance_logs;
DROP POLICY IF EXISTS "Admins can delete maintenance logs" ON public.maintenance_logs;
DROP POLICY IF EXISTS "Users can view maintenance logs in their workspace" ON public.maintenance_logs;
DROP POLICY IF EXISTS "Admins and managers can insert vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Admins and managers can update vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Admins can delete vehicles" ON public.vehicles;
DROP POLICY IF EXISTS "Users can view vehicles in their workspace" ON public.vehicles;
