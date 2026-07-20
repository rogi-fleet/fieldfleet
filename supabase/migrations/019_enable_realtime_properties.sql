-- Enable realtime for properties and related tables
-- Made idempotent: only adds if not already in publication

DO $$
DECLARE
  tbl text;
  tables_to_add text[] := ARRAY[
    'properties',
    'areas',
    'property_contents',
    'property_notes'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables_to_add LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime' AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', tbl);
    END IF;
  END LOOP;
END $$;
