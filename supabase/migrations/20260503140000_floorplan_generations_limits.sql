-- Defense-in-depth limits on floorplan_generations.
--
-- 1. Cap the size of `ai_plan_json` (the model's raw output we
--    persist for audit). At 256 KB this is generous for any sane
--    floorplan but stops a runaway model from filling rows. The
--    pg_column_size includes the JSONB overhead so the practical
--    text limit is roughly 200 KB.
--
-- 2. Cap the prompt length. We expect free-text descriptions, not
--    pasted manuscripts; 8 KB is more than enough for the most
--    detailed real-world prompt.
--
-- 3. Defense against rate-limit bypass: a partial unique index that
--    rejects creating a second 'generating' row for the same plan
--    when the existing one is younger than 30 seconds. The client
--    also checks before inserting (snappy UX); this index is the
--    backstop in case anyone calls the API directly.

ALTER TABLE public.floorplan_generations
  ADD CONSTRAINT floorplan_generations_ai_plan_json_size
    CHECK (
      ai_plan_json IS NULL
      OR pg_column_size(ai_plan_json) <= 262144  -- 256 KB
    );

ALTER TABLE public.floorplan_generations
  ADD CONSTRAINT floorplan_generations_prompt_size
    CHECK (length(prompt) <= 8192);

-- Partial unique index: at most one in-flight 'generating' row per
-- plan. If a stale row from a crashed client lingers in
-- 'generating' it'll need to be marked failed (or aged out by a
-- janitor job) before a new one can start — desirable behavior
-- since we don't want to spawn duplicate LLM calls.
CREATE UNIQUE INDEX IF NOT EXISTS
  floorplan_generations_one_inflight_per_plan
  ON public.floorplan_generations (plan_id)
  WHERE status = 'generating';
