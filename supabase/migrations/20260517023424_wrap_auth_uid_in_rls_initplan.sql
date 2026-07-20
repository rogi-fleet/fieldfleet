-- =============================================================================
-- Wrap auth.uid() / auth.jwt() / auth.role() / auth.email() in (SELECT ...)
-- inside row-level security policies.
--
-- Surfaced by the Supabase performance advisor (auth_rls_initplan). Bare
-- auth.X() calls get re-evaluated for every row scanned; wrapping them in
-- (SELECT auth.X()) hoists the call into an initplan that runs once per
-- query. On large tables (tasks, projects, files, time_entries, etc.) this
-- can be the difference between a few-ms list view and a multi-second
-- spinner. Behavior is identical.
--
-- DROP + CREATE per policy because Postgres has no in-place ALTER POLICY
-- expression change. Applied via supabase MCP apply_migration.
-- =============================================================================

DROP POLICY IF EXISTS ai_copilot_events_insert ON public.ai_copilot_events;
CREATE POLICY ai_copilot_events_insert ON public.ai_copilot_events AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (user_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS "Users can insert own AI plans" ON public.ai_generated_plans;
CREATE POLICY "Users can insert own AI plans" ON public.ai_generated_plans AS PERMISSIVE FOR INSERT WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Users can update own AI plans" ON public.ai_generated_plans;
CREATE POLICY "Users can update own AI plans" ON public.ai_generated_plans AS PERMISSIVE FOR UPDATE USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Users can view own AI plans" ON public.ai_generated_plans;
CREATE POLICY "Users can view own AI plans" ON public.ai_generated_plans AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Admins can view analytics" ON public.analytics_events;
CREATE POLICY "Admins can view analytics" ON public.analytics_events AS PERMISSIVE FOR SELECT USING (((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))) OR ((SELECT auth.role()) = 'service_role'::text)));
DROP POLICY IF EXISTS "Users can insert analytics events" ON public.analytics_events;
CREATE POLICY "Users can insert analytics events" ON public.analytics_events AS PERMISSIVE FOR INSERT WITH CHECK (((user_id = (SELECT auth.uid())) OR (user_id IS NULL)));
DROP POLICY IF EXISTS automation_rules_insert ON public.automation_rules;
CREATE POLICY automation_rules_insert ON public.automation_rules AS PERMISSIVE FOR INSERT WITH CHECK ((is_pm_or_admin(workspace_id) AND (created_by = (SELECT auth.uid()))));
DROP POLICY IF EXISTS catalog_bundle_components_member ON public.catalog_bundle_components;
CREATE POLICY catalog_bundle_components_member ON public.catalog_bundle_components AS PERMISSIVE FOR ALL USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid()))))) WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS "Admins and managers can insert catalog items" ON public.catalog_items;
CREATE POLICY "Admins and managers can insert catalog items" ON public.catalog_items AS PERMISSIVE FOR INSERT WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins and managers can update catalog items" ON public.catalog_items;
CREATE POLICY "Admins and managers can update catalog items" ON public.catalog_items AS PERMISSIVE FOR UPDATE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins can delete catalog items" ON public.catalog_items;
CREATE POLICY "Admins can delete catalog items" ON public.catalog_items AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Users can view catalog items in their workspace" ON public.catalog_items;
CREATE POLICY "Users can view catalog items in their workspace" ON public.catalog_items AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS catalog_price_tiers_member ON public.catalog_price_tiers;
CREATE POLICY catalog_price_tiers_member ON public.catalog_price_tiers AS PERMISSIVE FOR ALL USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid()))))) WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS client_portal_invites_insert ON public.client_portal_invites;
CREATE POLICY client_portal_invites_insert ON public.client_portal_invites AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND ((sent_by IS NULL) OR (sent_by = (SELECT auth.uid())))));
DROP POLICY IF EXISTS "Admins and managers can insert plans" ON public.construction_plans;
CREATE POLICY "Admins and managers can insert plans" ON public.construction_plans AS PERMISSIVE FOR INSERT WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins and managers can update plans" ON public.construction_plans;
CREATE POLICY "Admins and managers can update plans" ON public.construction_plans AS PERMISSIVE FOR UPDATE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins can delete plans" ON public.construction_plans;
CREATE POLICY "Admins can delete plans" ON public.construction_plans AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Users can view plans in their workspace" ON public.construction_plans;
CREATE POLICY "Users can view plans in their workspace" ON public.construction_plans AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS conversations_insert ON public.conversations;
CREATE POLICY conversations_insert ON public.conversations AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND ((SELECT auth.uid()) = ANY (participant_ids))));
DROP POLICY IF EXISTS conversations_select ON public.conversations;
CREATE POLICY conversations_select ON public.conversations AS PERMISSIVE FOR SELECT USING ((is_workspace_member(workspace_id) AND ((SELECT auth.uid()) = ANY (participant_ids))));
DROP POLICY IF EXISTS conversations_update ON public.conversations;
CREATE POLICY conversations_update ON public.conversations AS PERMISSIVE FOR UPDATE USING ((is_workspace_member(workspace_id) AND ((SELECT auth.uid()) = ANY (participant_ids))));
DROP POLICY IF EXISTS customer_types_select ON public.customer_types;
CREATE POLICY customer_types_select ON public.customer_types AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS "Service role can write daily summaries" ON public.daily_ai_summaries;
CREATE POLICY "Service role can write daily summaries" ON public.daily_ai_summaries AS PERMISSIVE FOR ALL USING (((SELECT auth.role()) = 'service_role'::text)) WITH CHECK (((SELECT auth.role()) = 'service_role'::text));
DROP POLICY IF EXISTS "Users can read their own daily summaries" ON public.daily_ai_summaries;
CREATE POLICY "Users can read their own daily summaries" ON public.daily_ai_summaries AS PERMISSIVE FOR SELECT USING ((user_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS document_activity_log_insert_workspace_member ON public.document_activity_log;
CREATE POLICY document_activity_log_insert_workspace_member ON public.document_activity_log AS PERMISSIVE FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM workspace_members wm
  WHERE ((wm.workspace_id = document_activity_log.workspace_id) AND (wm.user_id = (SELECT auth.uid()))))));
DROP POLICY IF EXISTS document_activity_log_select_workspace_member ON public.document_activity_log;
CREATE POLICY document_activity_log_select_workspace_member ON public.document_activity_log AS PERMISSIVE FOR SELECT USING ((EXISTS ( SELECT 1
   FROM workspace_members wm
  WHERE ((wm.workspace_id = document_activity_log.workspace_id) AND (wm.user_id = (SELECT auth.uid()))))));
DROP POLICY IF EXISTS "Users can manage counters in their workspace" ON public.document_counters;
CREATE POLICY "Users can manage counters in their workspace" ON public.document_counters AS PERMISSIVE FOR ALL USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS document_numbering_config_select ON public.document_numbering_config;
CREATE POLICY document_numbering_config_select ON public.document_numbering_config AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS email_queue_select_own ON public.email_notification_queue;
CREATE POLICY email_queue_select_own ON public.email_notification_queue AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Users can insert own feedback" ON public.feedback;
CREATE POLICY "Users can insert own feedback" ON public.feedback AS PERMISSIVE FOR INSERT WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Users can read own feedback" ON public.feedback;
CREATE POLICY "Users can read own feedback" ON public.feedback AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS field_form_submissions_workspace_access ON public.field_form_submissions;
CREATE POLICY field_form_submissions_workspace_access ON public.field_form_submissions AS PERMISSIVE FOR ALL USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid()))))) WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS field_form_templates_workspace_access ON public.field_form_templates;
CREATE POLICY field_form_templates_workspace_access ON public.field_form_templates AS PERMISSIVE FOR ALL USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid()))))) WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS file_attachments_delete ON public.file_attachments;
CREATE POLICY file_attachments_delete ON public.file_attachments AS PERMISSIVE FOR DELETE USING (((uploaded_by = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'documents'::text, 'write'::text)));
DROP POLICY IF EXISTS file_attachments_update ON public.file_attachments;
CREATE POLICY file_attachments_update ON public.file_attachments AS PERMISSIVE FOR UPDATE USING (((uploaded_by = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'documents'::text, 'write'::text))) WITH CHECK (((uploaded_by = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'documents'::text, 'write'::text)));
DROP POLICY IF EXISTS file_comments_delete ON public.file_comments;
CREATE POLICY file_comments_delete ON public.file_comments AS PERMISSIVE FOR DELETE USING (((author_id = (SELECT auth.uid())) OR (EXISTS ( SELECT 1
   FROM file_attachments fa
  WHERE ((fa.id = file_comments.file_attachment_id) AND has_workspace_module_permission(fa.workspace_id, 'documents'::text, 'write'::text))))));
DROP POLICY IF EXISTS file_comments_insert ON public.file_comments;
CREATE POLICY file_comments_insert ON public.file_comments AS PERMISSIVE FOR INSERT WITH CHECK (((author_id = (SELECT auth.uid())) AND (EXISTS ( SELECT 1
   FROM file_attachments fa
  WHERE ((fa.id = file_comments.file_attachment_id) AND has_workspace_module_permission(fa.workspace_id, 'documents'::text, 'read'::text) AND file_is_visible(fa.id))))));
DROP POLICY IF EXISTS file_comments_update ON public.file_comments;
CREATE POLICY file_comments_update ON public.file_comments AS PERMISSIVE FOR UPDATE USING ((author_id = (SELECT auth.uid()))) WITH CHECK ((author_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS "Admins can delete submissions" ON public.form_submissions;
CREATE POLICY "Admins can delete submissions" ON public.form_submissions AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Anyone can submit to public forms" ON public.form_submissions;
CREATE POLICY "Anyone can submit to public forms" ON public.form_submissions AS PERMISSIVE FOR INSERT WITH CHECK (((form_template_id IN ( SELECT forms.id
   FROM forms
  WHERE (forms.is_public = true))) OR (workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid()))))));
DROP POLICY IF EXISTS "Users can view submissions in their workspace" ON public.form_submissions;
CREATE POLICY "Users can view submissions in their workspace" ON public.form_submissions AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS "Admins and managers can insert forms" ON public.forms;
CREATE POLICY "Admins and managers can insert forms" ON public.forms AS PERMISSIVE FOR INSERT WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins and managers can update forms" ON public.forms;
CREATE POLICY "Admins and managers can update forms" ON public.forms AS PERMISSIVE FOR UPDATE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins can delete forms" ON public.forms;
CREATE POLICY "Admins can delete forms" ON public.forms AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Users can view forms in their workspace" ON public.forms;
CREATE POLICY "Users can view forms in their workspace" ON public.forms AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS "Admins and managers can insert maintenance logs" ON public.maintenance_logs;
CREATE POLICY "Admins and managers can insert maintenance logs" ON public.maintenance_logs AS PERMISSIVE FOR INSERT WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins and managers can update maintenance logs" ON public.maintenance_logs;
CREATE POLICY "Admins and managers can update maintenance logs" ON public.maintenance_logs AS PERMISSIVE FOR UPDATE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins can delete maintenance logs" ON public.maintenance_logs;
CREATE POLICY "Admins can delete maintenance logs" ON public.maintenance_logs AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Users can view maintenance logs in their workspace" ON public.maintenance_logs;
CREATE POLICY "Users can view maintenance logs in their workspace" ON public.maintenance_logs AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS message_bookmarks_owner ON public.message_bookmarks;
CREATE POLICY message_bookmarks_owner ON public.message_bookmarks AS PERMISSIVE FOR ALL USING ((user_id = (SELECT auth.uid()))) WITH CHECK ((user_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS messages_delete ON public.messages;
CREATE POLICY messages_delete ON public.messages AS PERMISSIVE FOR DELETE USING ((sender_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS messages_insert ON public.messages;
CREATE POLICY messages_insert ON public.messages AS PERMISSIVE FOR INSERT WITH CHECK (((sender_id = (SELECT auth.uid())) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((SELECT auth.uid()) = ANY (c.participant_ids)))))));
DROP POLICY IF EXISTS messages_select ON public.messages;
CREATE POLICY messages_select ON public.messages AS PERMISSIVE FOR SELECT USING ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((SELECT auth.uid()) = ANY (c.participant_ids))))));
DROP POLICY IF EXISTS messages_update ON public.messages;
CREATE POLICY messages_update ON public.messages AS PERMISSIVE FOR UPDATE USING ((sender_id = (SELECT auth.uid())));
DO $$
BEGIN
  IF to_regclass('public.notes') IS NOT NULL THEN
    EXECUTE 'DROP POLICY IF EXISTS notes_delete ON public.notes';
    EXECUTE 'CREATE POLICY notes_delete ON public.notes AS PERMISSIVE FOR DELETE USING ((author_id = (SELECT auth.uid())))';
    EXECUTE 'DROP POLICY IF EXISTS notes_insert ON public.notes';
    EXECUTE 'CREATE POLICY notes_insert ON public.notes AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (author_id = (SELECT auth.uid()))))';
    EXECUTE 'DROP POLICY IF EXISTS notes_update ON public.notes';
    EXECUTE 'CREATE POLICY notes_update ON public.notes AS PERMISSIVE FOR UPDATE USING ((author_id = (SELECT auth.uid()))) WITH CHECK ((author_id = (SELECT auth.uid())))';
  END IF;
END $$;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications AS PERMISSIVE FOR UPDATE USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS property_notes_delete ON public.property_notes;
CREATE POLICY property_notes_delete ON public.property_notes AS PERMISSIVE FOR DELETE USING ((author_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS property_notes_insert ON public.property_notes;
CREATE POLICY property_notes_insert ON public.property_notes AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (author_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS property_notes_update ON public.property_notes;
CREATE POLICY property_notes_update ON public.property_notes AS PERMISSIVE FOR UPDATE USING ((author_id = (SELECT auth.uid()))) WITH CHECK ((author_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS push_delivery_logs_select_own ON public.push_delivery_logs;
CREATE POLICY push_delivery_logs_select_own ON public.push_delivery_logs AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS push_delivery_logs_service_role_all ON public.push_delivery_logs;
CREATE POLICY push_delivery_logs_service_role_all ON public.push_delivery_logs AS PERMISSIVE FOR ALL USING (((SELECT auth.role()) = 'service_role'::text)) WITH CHECK (((SELECT auth.role()) = 'service_role'::text));
DROP POLICY IF EXISTS push_devices_delete_own ON public.push_devices;
CREATE POLICY push_devices_delete_own ON public.push_devices AS PERMISSIVE FOR DELETE USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS push_devices_insert_own ON public.push_devices;
CREATE POLICY push_devices_insert_own ON public.push_devices AS PERMISSIVE FOR INSERT WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS push_devices_select_own ON public.push_devices;
CREATE POLICY push_devices_select_own ON public.push_devices AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS push_devices_update_own ON public.push_devices;
CREATE POLICY push_devices_update_own ON public.push_devices AS PERMISSIVE FOR UPDATE USING (((SELECT auth.uid()) = user_id)) WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS settings_audit_events_insert ON public.settings_audit_events;
CREATE POLICY settings_audit_events_insert ON public.settings_audit_events AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (actor_user_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS task_comments_delete ON public.task_comments;
CREATE POLICY task_comments_delete ON public.task_comments AS PERMISSIVE FOR DELETE USING (((sender_id = (SELECT auth.uid())) OR is_workspace_admin(workspace_id)));
DROP POLICY IF EXISTS task_comments_insert ON public.task_comments;
CREATE POLICY task_comments_insert ON public.task_comments AS PERMISSIVE FOR INSERT WITH CHECK ((has_workspace_module_permission(workspace_id, 'tasks'::text, 'read'::text) AND (sender_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS task_comments_update ON public.task_comments;
CREATE POLICY task_comments_update ON public.task_comments AS PERMISSIVE FOR UPDATE USING (((sender_id = (SELECT auth.uid())) AND has_workspace_module_permission(workspace_id, 'tasks'::text, 'read'::text)));
DROP POLICY IF EXISTS task_required_forms_workspace_access ON public.task_required_forms;
CREATE POLICY task_required_forms_workspace_access ON public.task_required_forms AS PERMISSIVE FOR ALL USING ((task_id IN ( SELECT t.id
   FROM (tasks t
     JOIN workspace_members wm ON ((wm.workspace_id = t.workspace_id)))
  WHERE (wm.user_id = (SELECT auth.uid()))))) WITH CHECK ((task_id IN ( SELECT t.id
   FROM (tasks t
     JOIN workspace_members wm ON ((wm.workspace_id = t.workspace_id)))
  WHERE (wm.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS time_entries_delete ON public.time_entries;
CREATE POLICY time_entries_delete ON public.time_entries AS PERMISSIVE FOR DELETE USING ((((worker_id = (SELECT auth.uid())) AND (status = 'draft'::time_entry_status)) OR has_workspace_module_permission(workspace_id, 'time_tracking'::text, 'write'::text)));
DROP POLICY IF EXISTS time_entries_insert ON public.time_entries;
CREATE POLICY time_entries_insert ON public.time_entries AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND ((worker_id = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'time_tracking'::text, 'write'::text))));
DROP POLICY IF EXISTS time_entries_select ON public.time_entries;
CREATE POLICY time_entries_select ON public.time_entries AS PERMISSIVE FOR SELECT USING (((worker_id = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'time_tracking'::text, 'read'::text)));
DROP POLICY IF EXISTS time_entries_update ON public.time_entries;
CREATE POLICY time_entries_update ON public.time_entries AS PERMISSIVE FOR UPDATE USING ((((worker_id = (SELECT auth.uid())) AND (status = 'draft'::time_entry_status)) OR has_workspace_module_permission(workspace_id, 'time_tracking'::text, 'write'::text)));
DROP POLICY IF EXISTS time_entry_location_audits_insert ON public.time_entry_location_audits;
CREATE POLICY time_entry_location_audits_insert ON public.time_entry_location_audits AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (worker_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS time_entry_location_audits_select ON public.time_entry_location_audits;
CREATE POLICY time_entry_location_audits_select ON public.time_entry_location_audits AS PERMISSIVE FOR SELECT USING (((worker_id = (SELECT auth.uid())) OR is_pm_or_admin(workspace_id)));
DROP POLICY IF EXISTS time_entry_templates_delete ON public.time_entry_templates;
CREATE POLICY time_entry_templates_delete ON public.time_entry_templates AS PERMISSIVE FOR DELETE USING ((is_workspace_member(workspace_id) AND (((user_id IS NULL) AND is_pm_or_admin(workspace_id)) OR (user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS time_entry_templates_insert ON public.time_entry_templates;
CREATE POLICY time_entry_templates_insert ON public.time_entry_templates AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (((user_id IS NULL) AND is_pm_or_admin(workspace_id)) OR (user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS time_entry_templates_update ON public.time_entry_templates;
CREATE POLICY time_entry_templates_update ON public.time_entry_templates AS PERMISSIVE FOR UPDATE USING ((is_workspace_member(workspace_id) AND (((user_id IS NULL) AND is_pm_or_admin(workspace_id)) OR (user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS user_preferences_insert ON public.user_preferences;
CREATE POLICY user_preferences_insert ON public.user_preferences AS PERMISSIVE FOR INSERT WITH CHECK ((user_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS user_preferences_select ON public.user_preferences;
CREATE POLICY user_preferences_select ON public.user_preferences AS PERMISSIVE FOR SELECT USING ((user_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS user_preferences_update ON public.user_preferences;
CREATE POLICY user_preferences_update ON public.user_preferences AS PERMISSIVE FOR UPDATE USING ((user_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS "Users can manage own expansion prefs" ON public.user_task_expansion_prefs;
CREATE POLICY "Users can manage own expansion prefs" ON public.user_task_expansion_prefs AS PERMISSIVE FOR ALL USING (((SELECT auth.uid()) = user_id)) WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS users_insert ON public.users;
CREATE POLICY users_insert ON public.users AS PERMISSIVE FOR INSERT WITH CHECK ((id = (SELECT auth.uid())));
DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users AS PERMISSIVE FOR SELECT USING (((id = (SELECT auth.uid())) OR (id IN ( SELECT wm.user_id
   FROM workspace_members wm
  WHERE (wm.workspace_id = ANY (get_user_workspace_ids()))))));
DROP POLICY IF EXISTS users_update ON public.users;
CREATE POLICY users_update ON public.users AS PERMISSIVE FOR UPDATE USING ((id = (SELECT auth.uid())));
DROP POLICY IF EXISTS "Admins and managers can insert vehicles" ON public.vehicles;
CREATE POLICY "Admins and managers can insert vehicles" ON public.vehicles AS PERMISSIVE FOR INSERT WITH CHECK ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins and managers can update vehicles" ON public.vehicles;
CREATE POLICY "Admins and managers can update vehicles" ON public.vehicles AS PERMISSIVE FOR UPDATE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = ANY (ARRAY['admin'::workspace_member_role, 'project_manager'::workspace_member_role]))))));
DROP POLICY IF EXISTS "Admins can delete vehicles" ON public.vehicles;
CREATE POLICY "Admins can delete vehicles" ON public.vehicles AS PERMISSIVE FOR DELETE USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE ((workspace_members.user_id = (SELECT auth.uid())) AND (workspace_members.role = 'admin'::workspace_member_role)))));
DROP POLICY IF EXISTS "Users can view vehicles in their workspace" ON public.vehicles;
CREATE POLICY "Users can view vehicles in their workspace" ON public.vehicles AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS vendor_categories_select ON public.vendor_categories;
CREATE POLICY vendor_categories_select ON public.vendor_categories AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS vendor_types_select ON public.vendor_types;
CREATE POLICY vendor_types_select ON public.vendor_types AS PERMISSIVE FOR SELECT USING ((workspace_id IN ( SELECT workspace_members.workspace_id
   FROM workspace_members
  WHERE (workspace_members.user_id = (SELECT auth.uid())))));
DROP POLICY IF EXISTS weekly_ai_project_digests_insert ON public.weekly_ai_project_digests;
CREATE POLICY weekly_ai_project_digests_insert ON public.weekly_ai_project_digests AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_member(workspace_id) AND (user_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS weekly_ai_project_digests_update ON public.weekly_ai_project_digests;
CREATE POLICY weekly_ai_project_digests_update ON public.weekly_ai_project_digests AS PERMISSIVE FOR UPDATE USING ((is_workspace_member(workspace_id) AND (user_id = (SELECT auth.uid())))) WITH CHECK ((is_workspace_member(workspace_id) AND (user_id = (SELECT auth.uid()))));
DROP POLICY IF EXISTS workspace_members_insert ON public.workspace_members;
CREATE POLICY workspace_members_insert ON public.workspace_members AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_admin(workspace_id) OR ((user_id = (SELECT auth.uid())) AND (role = 'admin'::workspace_member_role))));
DROP POLICY IF EXISTS workspace_members_select ON public.workspace_members;
CREATE POLICY workspace_members_select ON public.workspace_members AS PERMISSIVE FOR SELECT USING (((user_id = (SELECT auth.uid())) OR has_workspace_module_permission(workspace_id, 'team'::text, 'read'::text)));
DROP POLICY IF EXISTS wnp_delete_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_delete_own ON public.workspace_notification_preferences AS PERMISSIVE FOR DELETE USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS wnp_insert_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_insert_own ON public.workspace_notification_preferences AS PERMISSIVE FOR INSERT WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS wnp_select_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_select_own ON public.workspace_notification_preferences AS PERMISSIVE FOR SELECT USING (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS wnp_update_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_update_own ON public.workspace_notification_preferences AS PERMISSIVE FOR UPDATE USING (((SELECT auth.uid()) = user_id)) WITH CHECK (((SELECT auth.uid()) = user_id));
DROP POLICY IF EXISTS workspace_role_templates_insert ON public.workspace_role_templates;
CREATE POLICY workspace_role_templates_insert ON public.workspace_role_templates AS PERMISSIVE FOR INSERT WITH CHECK ((is_workspace_admin(workspace_id) OR (EXISTS ( SELECT 1
   FROM workspaces w
  WHERE ((w.id = workspace_role_templates.workspace_id) AND (w.owner_id = (SELECT auth.uid())))))));
DROP POLICY IF EXISTS workspaces_delete ON public.workspaces;
CREATE POLICY workspaces_delete ON public.workspaces AS PERMISSIVE FOR DELETE USING ((owner_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS workspaces_insert ON public.workspaces;
CREATE POLICY workspaces_insert ON public.workspaces AS PERMISSIVE FOR INSERT WITH CHECK (((SELECT auth.uid()) IS NOT NULL));
DROP POLICY IF EXISTS workspaces_select ON public.workspaces;
CREATE POLICY workspaces_select ON public.workspaces AS PERMISSIVE FOR SELECT USING ((is_workspace_member(id) OR (owner_id = (SELECT auth.uid()))));
