-- file_is_visible load test
-- =========================
--
-- The plan doc for the files feature called out that file_is_visible()
-- runs per-row inside the RLS SELECT policy on file_attachments, which
-- could be slow on big workspaces. This script seeds a synthetic
-- workspace with 50k files, attaches a mix of gated and ungated tags,
-- then reports query timings so we can tell whether the materialized
-- view / trigger hack mentioned in the plan is actually needed.
--
-- HOW TO RUN (against a dev project, NOT production):
--   1. Open Supabase Studio → SQL Editor
--   2. Paste this file, execute
--   3. Look for the "RESULTS" NOTICE output at the end
--   4. Delete the synthetic workspace when done:
--      DELETE FROM workspaces WHERE name = 'loadtest-file-visibility';
--
-- EXPECTED BASELINES (dev-tier Supabase, indicative only):
--   - 50k file scan under RLS:  < 400 ms
--   - 50k scan without RLS:     < 80 ms
--   If you see > 2s on the RLS case, consider materializing
--   workspace_member_role_tokens or a file_visibility cache.
--
-- SAFE TO RE-RUN: cleans up its own synthetic workspace first.

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------
-- Clean prior run
-- -----------------------------------------------------------------------
DO $$
DECLARE
  old_workspace UUID;
BEGIN
  SELECT id INTO old_workspace FROM public.workspaces
    WHERE name = 'loadtest-file-visibility';
  IF old_workspace IS NOT NULL THEN
    DELETE FROM public.workspaces WHERE id = old_workspace;
    RAISE NOTICE 'Cleaned prior load-test workspace %', old_workspace;
  END IF;
END $$;

-- -----------------------------------------------------------------------
-- Seed
-- -----------------------------------------------------------------------
DO $$
DECLARE
  v_workspace_id UUID := uuid_generate_v4();
  v_user_id UUID := uuid_generate_v4();
  v_project_id UUID := uuid_generate_v4();
  v_ungated_tag UUID := uuid_generate_v4();
  v_gated_tag UUID := uuid_generate_v4();
  v_start TIMESTAMPTZ;
  v_duration_ms NUMERIC;
  v_total_files INT;
  v_visible_files INT;
BEGIN
  -- Base records. We reuse an existing auth user if one exists to satisfy
  -- FK constraints; otherwise this test requires running with auth.users
  -- having at least one row.
  SELECT id INTO v_user_id FROM auth.users LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Need at least one auth.users row to run this test';
  END IF;

  INSERT INTO public.workspaces (id, name, owner_id)
  VALUES (v_workspace_id, 'loadtest-file-visibility', v_user_id);

  INSERT INTO public.workspace_members (workspace_id, user_id, role)
  VALUES (v_workspace_id, v_user_id, 'admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.projects (id, workspace_id, name)
  VALUES (v_project_id, v_workspace_id, 'loadtest-project');

  INSERT INTO public.file_tags (
    id, workspace_id, name, color, visible_to_roles
  ) VALUES
    (v_ungated_tag, v_workspace_id, 'ungated', '#64748B', '{}'),
    (v_gated_tag, v_workspace_id, 'gated', '#DC2626',
     ARRAY['project_manager']::text[]);

  v_start := clock_timestamp();

  -- 50k files: half untagged, a quarter with the ungated tag, a quarter
  -- with the gated tag. Matches a realistic mix where only a minority
  -- of files are role-restricted.
  INSERT INTO public.file_attachments (
    workspace_id, project_id, file_name, file_url, file_size,
    mime_type, uploaded_by, uploaded_at
  )
  SELECT
    v_workspace_id,
    v_project_id,
    'file-' || g::TEXT || '.jpg',
    'https://example.com/file-' || g::TEXT,
    1024,
    'image/jpeg',
    v_user_id,
    NOW() - (g || ' minutes')::INTERVAL
  FROM generate_series(1, 50000) g;

  v_duration_ms := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start);
  RAISE NOTICE 'Seeded 50k files in % ms', round(v_duration_ms, 1);

  v_start := clock_timestamp();
  INSERT INTO public.file_attachment_tags (file_attachment_id, file_tag_id)
  SELECT id, v_ungated_tag
  FROM public.file_attachments
  WHERE workspace_id = v_workspace_id
  ORDER BY random()
  LIMIT 12500;

  INSERT INTO public.file_attachment_tags (file_attachment_id, file_tag_id)
  SELECT id, v_gated_tag
  FROM public.file_attachments
  WHERE workspace_id = v_workspace_id
    AND NOT EXISTS (
      SELECT 1 FROM public.file_attachment_tags fat
      WHERE fat.file_attachment_id = public.file_attachments.id
    )
  ORDER BY random()
  LIMIT 12500;

  v_duration_ms := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start);
  RAISE NOTICE 'Attached 25k tags in % ms', round(v_duration_ms, 1);

  -- -----------------------------------------------------------------------
  -- Timing A: baseline scan without RLS (run as table owner)
  -- -----------------------------------------------------------------------
  v_start := clock_timestamp();
  SELECT count(*) INTO v_total_files
  FROM public.file_attachments
  WHERE workspace_id = v_workspace_id;
  v_duration_ms := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start);
  RAISE NOTICE 'A) baseline count (no RLS, no fn): % files in % ms',
    v_total_files, round(v_duration_ms, 1);

  -- -----------------------------------------------------------------------
  -- Timing B: count evaluating file_is_visible for every row
  -- -----------------------------------------------------------------------
  v_start := clock_timestamp();
  SELECT count(*) INTO v_visible_files
  FROM public.file_attachments
  WHERE workspace_id = v_workspace_id
    AND public.file_is_visible(id);
  v_duration_ms := EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start);
  RAISE NOTICE 'B) file_is_visible() scan: % visible of % in % ms',
    v_visible_files, v_total_files, round(v_duration_ms, 1);

  -- -----------------------------------------------------------------------
  -- Timing C: EXPLAIN of the RLS-equivalent query (plan inspection)
  -- -----------------------------------------------------------------------
  RAISE NOTICE '---- EXPLAIN ANALYZE (RLS-equivalent) ----';
END $$;

-- Print the EXPLAIN plan outside the DO block so its output is visible.
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT *
FROM public.file_attachments fa
WHERE fa.workspace_id = (
  SELECT id FROM public.workspaces WHERE name = 'loadtest-file-visibility'
)
AND public.file_is_visible(fa.id);

ROLLBACK; -- leave the DB clean by default. Swap to COMMIT if you want to
          -- keep the fixture around for repeated EXPLAINs.
