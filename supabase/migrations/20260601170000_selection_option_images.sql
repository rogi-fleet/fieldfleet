-- =============================================================================
-- Multiple photos per selection option (JobTread parity).
--
-- selection_options.image_url holds a single photo. JobTread allows several
-- images per option (the right-panel cards show a stacked-images badge). Add an
-- image_urls TEXT[] for the full set; image_url stays as the primary/first image
-- for back-compat with existing portal + card rendering.
--
-- Backfill: seed image_urls from any existing single image_url. Additive, safe.
-- =============================================================================

ALTER TABLE selection_options
  ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN selection_options.image_urls IS
  'All photos for this option. image_url mirrors the first (primary) entry.';

UPDATE selection_options
   SET image_urls = ARRAY[image_url]
 WHERE image_url IS NOT NULL
   AND image_url <> ''
   AND (image_urls IS NULL OR array_length(image_urls, 1) IS NULL);
