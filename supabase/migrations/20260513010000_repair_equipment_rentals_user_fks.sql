-- Repair the auth.users → public.users FK drift on equipment_rentals tables.
--
-- PostgREST embeds (e.g. `users!created_by(display_name, email)`) target
-- the *public* `users` mirror table. The original module migrations
-- referenced `auth.users(id)` directly, so PostgREST refused to resolve any
-- embed of `users` from these tables with PGRST200.
--
-- public.users.id mirrors auth.users.id one-to-one (created by a sync
-- trigger), so swapping the target is safe and preserves the previous
-- ON DELETE semantics. We verified beforehand that every referenced id in
-- these tables also exists in public.users (zero orphan references), so the
-- DROP + ADD pattern below is safe without a backfill.
--
-- Each step is idempotent: if a constraint already references public.users
-- (perhaps because the migration is being replayed), the DROP/ADD is
-- skipped.

CREATE OR REPLACE FUNCTION public._repoint_fk_to_public_users(
  p_table text,
  p_column text,
  p_on_delete text
) RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_conname text;
BEGIN
  SELECT c.conname INTO v_conname
  FROM pg_constraint c
  WHERE c.conrelid = format('public.%I', p_table)::regclass
    AND c.contype = 'f'
    AND pg_get_constraintdef(c.oid) LIKE '%REFERENCES auth.users%'
    AND EXISTS (
      SELECT 1
      FROM unnest(c.conkey) AS k(attnum)
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid AND a.attnum = k.attnum
      WHERE a.attname = p_column
    );

  IF v_conname IS NULL THEN
    RETURN;  -- already repointed (or no such FK)
  END IF;

  EXECUTE format(
    'ALTER TABLE public.%I DROP CONSTRAINT %I',
    p_table, v_conname
  );

  EXECUTE format(
    'ALTER TABLE public.%I ADD CONSTRAINT %I '
    'FOREIGN KEY (%I) REFERENCES public.users(id) ON DELETE %s',
    p_table, v_conname, p_column, p_on_delete
  );
END;
$fn$;

SELECT public._repoint_fk_to_public_users('equipment_rentals',   'created_by',     'SET NULL');

-- Clean up the one-shot helper so it doesn't linger as a public function.
DROP FUNCTION public._repoint_fk_to_public_users(text, text, text);

-- Make PostgREST pick up the new FK targets immediately.
NOTIFY pgrst, 'reload schema';
