-- Persist raw room-scan metadata alongside the converted scene.
--
-- When a scene is born from a native room scan (RoomPlan on iOS LiDAR
-- devices, ARCore on Android), the conversion to the editor's
-- vector model is lossy on purpose — we project 3D walls down to a 2D
-- polygon, drop per-vertex elevations, and pick a single ceiling
-- height. The raw FloorPlanScanResult JSON has the data we threw
-- away (per-wall heights, confidence per surface, RoomPlan's
-- furniture inventory, the captureId for telemetry correlation).
--
-- Keeping it next to the scene lets us re-process old scans with a
-- better algorithm later without going back to the user for another
-- capture. We never *read* this column at runtime today — it's archival.
ALTER TABLE public.floorplan_scenes
  ADD COLUMN IF NOT EXISTS scan_metadata JSONB;

COMMENT ON COLUMN public.floorplan_scenes.scan_metadata IS
  'Raw FloorPlanScanResult JSON from the native room scanner that produced '
  'this scene. NULL for scenes that did not originate from a scan '
  '(blank/preset/AI/upload). See '
  'lib/models/floorplan/scan/floor_plan_scan_result.dart for the shape.';
