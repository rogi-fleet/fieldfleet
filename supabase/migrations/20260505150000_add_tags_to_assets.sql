-- Assets: free-form tag labels.
--
-- Tags cover the cross-cutting attributes that don't fit categories or
-- status: 'rental', 'favorite', 'needs-charge', 'outdoor', 'fragile'.
-- Multi-value, free-form, lowercase by convention. We intentionally
-- store them as TEXT[] on the asset row instead of a normalized
-- asset_tags table — most workspaces will keep this list small and the
-- file_attachments TEXT[] precedent (see migration 20260419130000)
-- shows the simpler shape works well at this scale.
--
-- GIN index on the column makes `tags @> ARRAY['x']` filter scans cheap
-- regardless of fleet size.

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_assets_tags
  ON public.assets USING GIN (tags);

COMMENT ON COLUMN public.assets.tags IS
  'Free-form lowercase labels. Use for cross-cutting attributes that '
  'don''t fit category or status (rental, favorite, outdoor, etc.). '
  'Empty array = no tags.';
