-- Golden State Starlight Alliance — scheduled chat retention (spec §5)
--
-- Deliberately separate from 0001-0003 and run OUTSIDE the main transaction.
-- pg_cron has to be enabled on the project before this works, and if it isn't,
-- the failure should cost you a cron job — not the entire schema.
--
-- If this errors with "extension pg_cron is not available" or similar:
--   Supabase dashboard -> Database -> Extensions -> enable `pg_cron`,
--   then run this file again on its own. Everything else keeps working
--   meanwhile; messages simply accumulate past a year until it is scheduled.

create extension if not exists pg_cron with schema extensions;

-- Idempotent: drop any existing job before re-creating it, so re-running this
-- file does not stack duplicate schedules.
select cron.unschedule('purge-expired-messages')
  where exists (select 1 from cron.job where jobname = 'purge-expired-messages');

-- Daily at 03:15 UTC.
select cron.schedule(
  'purge-expired-messages',
  '15 3 * * *',
  $cron$ select public.purge_expired_messages(); $cron$
);

-- Confirm it registered.
select jobname, schedule, active from cron.job where jobname = 'purge-expired-messages';
