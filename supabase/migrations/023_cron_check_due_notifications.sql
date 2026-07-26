-- Run in the SQL Editor. First replace both placeholders below:
--   EURE-PROJEKT-ID                  → your Supabase project ID
--   HIER_DEIN_CRON_SECRET_EINTRAGEN  → exactly the value you entered as
--                                      the CRON_SECRET secret on
--                                      "check-due-notifications"

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'check-due-notifications-hourly',
  '0 * * * *',  -- every full hour; syntax: minute hour day month weekday
  $$
  select net.http_post(
    url := 'https://EURE-PROJEKT-ID.supabase.co/functions/v1/check-due-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', 'HIER_DEIN_CRON_SECRET_EINTRAGEN'
    )
  ) as request_id;
  $$
);

-- To check whether it's set up:
select * from cron.job;

-- To check whether the last runs succeeded:
select * from cron.job_run_details order by start_time desc limit 10;
