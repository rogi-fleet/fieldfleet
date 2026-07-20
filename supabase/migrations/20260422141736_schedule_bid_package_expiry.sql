-- Enable pg_cron and schedule the bid-package expiry sweeper to run
-- daily. Replaces the "needs external scheduling" TODO from the Phase D
-- migration.
--
-- The extension is created in the default 'pg_catalog' schema (Supabase
-- convention). Jobs are stored in cron.job.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Unschedule any prior job with the same name (idempotent re-runs).
DO $$
DECLARE
  existing_jobid bigint;
BEGIN
  SELECT jobid INTO existing_jobid
  FROM cron.job
  WHERE jobname = 'expire_stale_bid_packages_daily';
  IF existing_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(existing_jobid);
  END IF;
END $$;

-- Daily at 06:00 UTC. Short on-disk impact: one function call, no-op if
-- nothing is stale.
SELECT cron.schedule(
  'expire_stale_bid_packages_daily',
  '0 6 * * *',
  $cron$SELECT public.expire_stale_bid_packages();$cron$
);
