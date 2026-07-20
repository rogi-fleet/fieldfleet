-- Non-destructive crop for the markup layer.
--
-- Stored as four normalized (0..1) floats on file_markup_layers. Defaults
-- of (0, 0, 1, 1) mean "show the whole image" — the viewer interprets
-- these the same as an empty crop. Like rotation and flip, this is a
-- view transform applied on top of the original bytes; reverting the
-- layer clears it. Shapes continue to be drawn in image-native
-- coordinates and are simply clipped by the viewer when outside the
-- crop region.

ALTER TABLE public.file_markup_layers
  ADD COLUMN IF NOT EXISTS crop_x REAL NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS crop_y REAL NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS crop_width REAL NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS crop_height REAL NOT NULL DEFAULT 1;

ALTER TABLE public.file_markup_layers
  DROP CONSTRAINT IF EXISTS file_markup_layers_crop_bounds_check;

ALTER TABLE public.file_markup_layers
  ADD CONSTRAINT file_markup_layers_crop_bounds_check
  CHECK (
    crop_x >= 0 AND crop_x <= 1
    AND crop_y >= 0 AND crop_y <= 1
    AND crop_width > 0 AND crop_width <= 1
    AND crop_height > 0 AND crop_height <= 1
    AND crop_x + crop_width <= 1
    AND crop_y + crop_height <= 1
  );

COMMENT ON COLUMN public.file_markup_layers.crop_width IS
  'Width of the visible crop region as a fraction of the original image. '
  '1.0 = no crop. Combined with crop_x/y/height to define the rect.';
