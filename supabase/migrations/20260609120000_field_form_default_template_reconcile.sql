-- Field Form default-template reconciliation support.
--
-- Adds the tracking columns the client uses to keep each workspace's built-in
-- field form templates in sync with the canonical definitions in Dart, while
-- never clobbering edits a workspace made to its own copy.
--
--   default_key       stable identity for a built-in template (rename-safe).
--   default_version   the definition version currently materialized in the row.
--   default_seed_hash  content fingerprint at last seed/overwrite; the client
--                     compares it against the row's live content to detect a
--                     workspace edit ("overwrite unless edited").
--
-- Reconciliation itself (insert new defaults, push version bumps to unedited
-- copies) runs client-side and reuses the per-template content defined in Dart,
-- so there is intentionally no SQL copy of the template bodies here.

ALTER TABLE field_form_templates
  ADD COLUMN IF NOT EXISTS default_key       TEXT,
  ADD COLUMN IF NOT EXISTS default_version   INT,
  ADD COLUMN IF NOT EXISTS default_seed_hash TEXT;

-- Backfill default_key for templates already seeded into existing workspaces by
-- matching their original names. default_version / default_seed_hash are left
-- NULL on purpose: the client's first reconcile "adopts" these rows as-is
-- (records their current content as the baseline) so nothing is overwritten on
-- rollout. Keys here MUST match the 'key' values in the Dart definitions.
UPDATE field_form_templates
SET default_key = CASE name
    WHEN 'Generic Work Order'                                  THEN 'generic_work_order'
    WHEN 'Installation Service Work Order'                     THEN 'installation_service_work_order'
    WHEN '12-Hour Mitigation Report — Residential'             THEN 'twelve_hour_mitigation_residential'
    WHEN 'Initial Inspection — Residential'                    THEN 'initial_inspection_residential'
    WHEN 'Employee Clock-Out Questionnaire'                    THEN 'employee_clock_out_questionnaire'
    WHEN 'Daily Job Site Log'                                  THEN 'daily_job_site_log'
    WHEN '12-Hour Mitigation Report — Multi-Res / Commercial'  THEN 'twelve_hour_mitigation_commercial'
    WHEN 'Initial Inspection — Multi-Res / Commercial'         THEN 'initial_inspection_commercial'
    WHEN 'Site Inspection'                                     THEN 'site_inspection'
    WHEN 'Work Completion Report'                              THEN 'work_completion_report'
    WHEN 'Safety Checklist'                                    THEN 'safety_checklist'
    WHEN 'Equipment Inspection'                                THEN 'equipment_inspection'
    WHEN 'Room / Area Completion'                              THEN 'room_area_completion'
    ELSE default_key
  END
WHERE is_default = TRUE
  AND default_key IS NULL;

-- A workspace may hold at most one row per built-in template key. Created after
-- the backfill so it validates against the final state.
CREATE UNIQUE INDEX IF NOT EXISTS idx_fft_default_key
  ON field_form_templates(workspace_id, default_key)
  WHERE default_key IS NOT NULL;
