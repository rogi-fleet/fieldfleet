-- Assets: add photo gallery support.
--
-- Equipment / tools / inventory benefit from photos for at-a-glance
-- identification on the assets list and detail screens. We store an
-- ordered array of public URLs (project-images bucket) directly on the
-- asset row instead of going through file_attachments — these are
-- profile-style photos tied to the asset's identity, not project files
-- that need folders, tags, or audit history.
--
-- DEFAULT '{}' so existing rows surface as "no photos" without a
-- backfill step. Column is NOT NULL since callers always read it as a
-- list and an empty array is the natural empty state.

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS photo_urls TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.assets.photo_urls IS
  'Ordered list of public photo URLs for this asset. First entry is the '
  'card hero. Files live in the project-images Storage bucket under '
  '<workspace_id>/assets/<asset_id>/.';
