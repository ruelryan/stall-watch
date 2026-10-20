-- Nightly schedule for the stall detector (pg_cron).
--
-- WHY. The detector must run at least once a day with nobody pressing anything. pg_cron runs
-- inside Postgres as the role that scheduled the job (postgres), so the worker needs no
-- secret, no HTTP route and no service-role key. The job command names the function and two
-- literal arguments; there is nothing in it worth hiding, which is why it may live in a
-- migration (secrets never may).
--
-- WHAT.
--   1. extension pg_cron (installed in pg_catalog, which is where its control file puts it).
--   2. cron job 'stall-detector-nightly' at 09:00 UTC daily (02:00 Pacific, "overnight"),
--      running private.run_stall_detector('scheduled', null). Re-runnable: an existing job of
--      that name is unscheduled first.
--
-- NOT SELF-CONTAINED. Hosted Supabase needs pg_cron available to the project (it is, on every
-- plan; the create extension below enables it). cron.job_run_details is the raw log; the
-- app's /detector page reads builder.detector_runs, which the worker writes itself.
--
-- ROLLBACK:
--   select cron.unschedule('stall-detector-nightly');
--   -- (leave the extension installed; other jobs may use it)

create extension if not exists pg_cron;

grant usage on schema cron to postgres;

select cron.unschedule(jobid)
  from cron.job
 where jobname = 'stall-detector-nightly';

select cron.schedule(
  'stall-detector-nightly',
  '0 9 * * *',
  $$select private.run_stall_detector('scheduled', null)$$
);
