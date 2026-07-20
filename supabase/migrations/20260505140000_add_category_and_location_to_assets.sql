-- Assets: classify by category and pin to a physical location.
--
-- Today the asset table is flat — every ladder, drill, generator, and
-- chair sits in one bucket distinguished only by free-text name. As
-- fleets grow past ~20 items, owners want to slice by *what kind of
-- thing* this is (power tool, ladder, safety gear) and *where it
-- physically lives* (yard, truck #3, site B tool crib).
--
-- `category` is a soft enum: client validates against a fixed list, but
-- the column stays TEXT so we can extend without a migration. Default
-- 'other' keeps existing rows valid without backfill.
--
-- `location` is intentionally free-form. Real-world locations don't
-- normalize cleanly (a truck has a number, a yard doesn't, a site has
-- both a name and an address) and forcing a foreign key here would just
-- push pain into the form UX.

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS location TEXT;

CREATE INDEX IF NOT EXISTS idx_assets_category
  ON public.assets (workspace_id, category);

COMMENT ON COLUMN public.assets.category IS
  'Soft enum: power_tool, hand_tool, heavy_equipment, ladder, safety, '
  'electronics, furniture, vehicle_attachment, other. Client validates; '
  'TEXT chosen so the list can grow without a migration.';

COMMENT ON COLUMN public.assets.location IS
  'Free-form physical location label (e.g. "Truck #3", "Yard", '
  '"Site B - tool crib"). NULL = unspecified.';
