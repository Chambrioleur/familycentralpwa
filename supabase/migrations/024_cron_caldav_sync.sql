-- Run in the SQL Editor. Uses the same CRON_SECRET as the
-- check-due-notifications cron job — if you've already set that up,
-- just reuse the same value here. If not: first set a CRON_SECRET
-- secret on caldav-sync (Dashboard -> Edge Functions -> caldav-sync ->
-- Secrets), then use that same value here.

select cron.schedule(
  'caldav-sync-every-15-min',
  '*/15 * * * *',  -- every 15 minutes
  $$
  select net.http_post(
    url := 'https://EURE-PROJEKT-ID.supabase.co/functions/v1/caldav-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', 'HIER_DEIN_CRON_SECRET_EINTRAGEN'
    )
  ) as request_id;
  $$
);

-- To check:
select * from cron.job;
select * from cron.job_run_details order by start_time desc limit 10;
