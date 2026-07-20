-- Add per-file rotation to the markup layer.
--
-- Rotation is a view transform (0 / 90 / 180 / 270 degrees) stored on the
-- markup layer, not on the file_attachments row. That keeps the feature
-- non-destructive: the underlying image bytes are never rotated, so
-- reverting the markup also clears the rotation. Any other consumer of
-- file_attachments still sees the image in its original orientation.
--
-- Values are constrained to 0/90/180/270 so the viewer can branch cleanly.

ALTER TABLE public.file_markup_layers
  ADD COLUMN IF NOT EXISTS rotation INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.file_markup_layers
  DROP CONSTRAINT IF EXISTS file_markup_layers_rotation_check;

ALTER TABLE public.file_markup_layers
  ADD CONSTRAINT file_markup_layers_rotation_check
  CHECK (rotation IN (0, 90, 180, 270));

COMMENT ON COLUMN public.file_markup_layers.rotation IS
  'Quarter-turn display rotation applied by the viewer on top of the '
  'original bytes. 0/90/180/270 only. Reverting the layer resets to 0.';
