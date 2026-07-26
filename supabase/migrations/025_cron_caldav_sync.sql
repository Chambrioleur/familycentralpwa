-- Im SQL Editor ausführen. Nutzt dasselbe CRON_SECRET wie beim
-- check-due-notifications-Cron-Job — falls du das schon eingerichtet hast,
-- einfach denselben Wert wieder einsetzen. Falls nicht: erst bei
-- caldav-sync ein CRON_SECRET-Secret eintragen (Dashboard -> Edge
-- Functions -> caldav-sync -> Secrets), dann hier denselben Wert nutzen.

select cron.schedule(
  'caldav-sync-every-15-min',
  '*/15 * * * *',  -- alle 15 Minuten
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

-- Zum Prüfen:
select * from cron.job;
select * from cron.job_run_details order by start_time desc limit 10;
