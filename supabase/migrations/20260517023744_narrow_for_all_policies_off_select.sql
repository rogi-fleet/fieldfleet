-- =============================================================================
-- Consolidate the last few multiple_permissive_policies warnings.
--
-- push_delivery_logs_service_role_all was FOR ALL, overlapping with
-- _select_own on SELECT. service_role has BYPASSRLS so the SELECT half
-- of that policy was decorative — narrow it to mutating commands only.
--
-- workspace_feature_flags_upsert was FOR ALL, overlapping with _select
-- on SELECT. Members already read via _select; admins (the _upsert
-- audience) also pass _select. Narrow _upsert to mutating commands.
-- =============================================================================

DROP POLICY IF EXISTS push_delivery_logs_service_role_all ON public.push_delivery_logs;
CREATE POLICY push_delivery_logs_service_role_write ON public.push_delivery_logs
  AS PERMISSIVE FOR INSERT
  WITH CHECK ((SELECT auth.role()) = 'service_role');
CREATE POLICY push_delivery_logs_service_role_update ON public.push_delivery_logs
  AS PERMISSIVE FOR UPDATE
  USING ((SELECT auth.role()) = 'service_role')
  WITH CHECK ((SELECT auth.role()) = 'service_role');
CREATE POLICY push_delivery_logs_service_role_delete ON public.push_delivery_logs
  AS PERMISSIVE FOR DELETE
  USING ((SELECT auth.role()) = 'service_role');

DROP POLICY IF EXISTS workspace_feature_flags_upsert ON public.workspace_feature_flags;
CREATE POLICY workspace_feature_flags_insert ON public.workspace_feature_flags
  AS PERMISSIVE FOR INSERT
  WITH CHECK (is_workspace_admin(workspace_id));
CREATE POLICY workspace_feature_flags_update ON public.workspace_feature_flags
  AS PERMISSIVE FOR UPDATE
  USING (is_workspace_admin(workspace_id))
  WITH CHECK (is_workspace_admin(workspace_id));
CREATE POLICY workspace_feature_flags_delete ON public.workspace_feature_flags
  AS PERMISSIVE FOR DELETE
  USING (is_workspace_admin(workspace_id));
