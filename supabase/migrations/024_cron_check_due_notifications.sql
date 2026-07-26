-- Im SQL Editor ausführen. Vorher beide Platzhalter unten ersetzen:
--   EURE-PROJEKT-ID                  → eure Supabase-Projekt-ID
--   HIER_DEIN_CRON_SECRET_EINTRAGEN  → genau der Wert, den ihr als
--                                      CRON_SECRET-Secret bei
--                                      "check-due-notifications" eingetragen habt

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'check-due-notifications-hourly',
  '0 * * * *',  -- jede volle Stunde; Syntax: Minute Stunde Tag Monat Wochentag
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

-- Zum Prüfen, ob's eingerichtet ist:
select * from cron.job;

-- Zum Nachschauen, ob die letzten Läufe geklappt haben:
select * from cron.job_run_details order by start_time desc limit 10;
