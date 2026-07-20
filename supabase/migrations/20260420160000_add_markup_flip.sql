-- Add horizontal / vertical flip transforms to the markup layer.
--
-- Same philosophy as rotation (20260420150000): the underlying file bytes
-- stay untouched. Flip is a view transform applied by the viewer on top
-- of the original image, stored per markup layer. Reverting the layer
-- clears the flip alongside rotation and shapes.

ALTER TABLE public.file_markup_layers
  ADD COLUMN IF NOT EXISTS flip_horizontal BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS flip_vertical BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.file_markup_layers.flip_horizontal IS
  'Non-destructive horizontal mirror applied by the viewer.';
COMMENT ON COLUMN public.file_markup_layers.flip_vertical IS
  'Non-destructive vertical mirror applied by the viewer.';
