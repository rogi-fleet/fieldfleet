-- Construction plans → properties: optional structure scope.
--
-- Plans are usually drawings of a specific structure (Building A 2nd-floor
-- electrical, Unit 3 mechanical), not a whole project. We add a nullable
-- property_id so callers can scope a plan to one property — NULL still
-- means project-wide (site survey, full-property elec riser).
--
-- ON DELETE SET NULL: removing a property doesn't drop its plans; they
-- fall back to project scope. ON DELETE CASCADE would be lossy.

ALTER TABLE public.construction_plans
  ADD COLUMN IF NOT EXISTS property_id UUID
    REFERENCES public.properties(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_construction_plans_property
  ON public.construction_plans (property_id)
  WHERE property_id IS NOT NULL;

COMMENT ON COLUMN public.construction_plans.property_id IS
  'Optional structure scope. NULL = project-wide drawing; '
  'set = drawing of a specific property.';

-- The "plans" view aliases construction_plans for service-layer use (see
-- migration 004 and 20260502120000). CREATE OR REPLACE VIEW only allows
-- *appending* columns, so property_id goes on the end.
CREATE OR REPLACE VIEW public.plans AS
SELECT
  id,
  workspace_id,
  project_id,
  name,
  discipline,
  sheet_number,
  version,
  is_current_version,
  drawing_date,
  file_url,
  file_name,
  file_size,
  uploaded_by,
  uploaded_at,
  notes,
  linked_task_ids,
  created_at,
  updated_at,
  storage_path,
  property_id
FROM public.construction_plans;
