-- Vehicles: model assignment more like real fleets.
--
-- Today `assigned_to_user_id` represents the primary driver — the person a
-- truck is "registered" to long-term. That's the right anchor, but it
-- conflates two things real operators track separately:
--
--   * who has the keys *right now* (current driver — flips on check-out)
--   * which job the truck is on this week (project assignment — drives
--     budget rollups and "what's on site" views)
--
-- Adding both as nullable columns keeps the existing column meaning
-- intact (primary driver) and avoids a backfill: rows surface as
-- "no current driver / no project" until someone checks one out or
-- pins a project.
--
-- ON DELETE behaviour:
--   * current_driver_id → SET NULL when the user is removed (vehicle
--     remains, just becomes un-checked-out).
--   * assigned_to_project_id → SET NULL when the project is deleted
--     (matches assets.assigned_to_project_id semantics).

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS current_driver_id UUID
    REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_to_project_id UUID
    REFERENCES public.projects(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_vehicles_current_driver
  ON public.vehicles(current_driver_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_assigned_project
  ON public.vehicles(assigned_to_project_id);

COMMENT ON COLUMN public.vehicles.assigned_to_user_id IS
  'Primary driver — the team member this vehicle is regularly assigned to. '
  'Long-lived; survives day-to-day check-out / check-in.';
COMMENT ON COLUMN public.vehicles.current_driver_id IS
  'Team member currently in possession of the vehicle. Set on check-out, '
  'cleared on check-in. NULL means the vehicle is parked / in the yard.';
COMMENT ON COLUMN public.vehicles.assigned_to_project_id IS
  'Project this vehicle is currently committed to. Used for project-level '
  'utilisation views and to roll fuel / maintenance costs into a budget.';
