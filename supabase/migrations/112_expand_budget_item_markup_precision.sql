-- Budget item markup is derived from unit cost and unit price.
-- Real-world values can exceed 999.99%, which overflows NUMERIC(5,2)
-- and causes inserts/updates to fail with a generic 400.
ALTER TABLE public.budget_items
  ALTER COLUMN markup TYPE numeric(10,2);
