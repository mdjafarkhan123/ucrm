-- Keep a week of background-job history (Supabase's pg_cron guide: "delete old job run details").
--
-- pg_cron writes one cron.job_run_details row per run and never removes them. Our one-minute workers add about
-- 13,000 rows a day; by 2026-10-24 the table held 500,000 rows (152 MB) and pushed the database past its plan
-- limit. A nightly delete keeps the last seven days for diagnosing a failed run. The table is small after the
-- trim, so the nightly scan is cheap and freed space is reused instead of growing the file.

select cron.schedule(
  'cron-run-history-trim-nightly',
  '47 4 * * *',
  $job$delete from cron.job_run_details where end_time < now() - interval '7 days';$job$
);
