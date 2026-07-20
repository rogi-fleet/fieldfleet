ALTER TABLE public.notes
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE public.notes
SET updated_at = COALESCE(updated_at, created_at, now());

DROP TRIGGER IF EXISTS set_notes_updated_at ON public.notes;
CREATE TRIGGER set_notes_updated_at
  BEFORE UPDATE ON public.notes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS notes_update ON public.notes;
CREATE POLICY notes_update ON public.notes
  FOR UPDATE
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

ALTER TABLE public.property_notes
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE public.property_notes
SET updated_at = COALESCE(updated_at, created_at, now());

DROP TRIGGER IF EXISTS set_property_notes_updated_at ON public.property_notes;
CREATE TRIGGER set_property_notes_updated_at
  BEFORE UPDATE ON public.property_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS property_notes_update ON public.property_notes;
CREATE POLICY property_notes_update ON public.property_notes
  FOR UPDATE
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());
