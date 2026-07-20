-- Enable Realtime for budget_items table
-- This allows the .stream() method to receive live updates
-- Made idempotent: only adds table if not already in publication

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'budget_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE budget_items;
  END IF;
END $$;
