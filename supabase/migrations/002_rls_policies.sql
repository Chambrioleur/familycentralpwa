-- ═══════════════════════════════════════════════════════════════
-- Echte Rechte-Trennung: jede Person bekommt einen eigenen Login,
-- die Datenbank unterscheidet ab jetzt wirklich zwischen den Personen
-- statt nur zwischen "angemeldet" und "nicht angemeldet".
-- Im SQL Editor komplett ausführen.
-- ═══════════════════════════════════════════════════════════════

-- 1. Neue Felder auf members
alter table members add column if not exists user_id uuid references auth.users(id);
alter table members add column if not exists login_email text unique;
alter table members add column if not exists ist_master boolean not null default false;

-- 2. Hilfsfunktionen (security definer, damit sie members selbst lesen
--    dürfen ohne in eine RLS-Rekursion zu laufen)
create or replace function is_adult() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where user_id = auth.uid() and rolle = 'erwachsen');
$$;

create or replace function is_master() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where user_id = auth.uid() and ist_master = true);
$$;

create or replace function my_member_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from members where user_id = auth.uid() limit 1;
$$;

-- 3. Alte pauschale Regeln entfernen (sonst gelten sie parallel weiter!)
do $$
declare t text;
begin
  foreach t in array array[
    'members','calendar_events','tasks','reminders','shopping_items',
    'documents','votes','vote_options','vote_responses','wiki_entries',
    'finance_entries','health_records','contacts','assistant_suggestions',
    'sync_log'
  ]
  loop
    execute format('drop policy if exists "authenticated_full_access" on %I;', t);
  end loop;
end $$;

-- 4. members: Login-Anzeige (vor dem Einloggen) + Verwaltung (nur Master)
grant select (id, name, farbe, avatar_pfad, rolle, login_email) on members to anon;
create policy "members_login_picker" on members for select to anon using (true);
create policy "members_select" on members for select to authenticated using (true);
create policy "members_update" on members for update to authenticated
  using (is_master() or user_id = auth.uid()) with check (is_master() or user_id = auth.uid());
create policy "members_delete" on members for delete to authenticated using (is_master());
-- Kein INSERT-Recht für authenticated — neue Personen entstehen ausschließlich
-- über die manage-member Edge Function (service_role), nie direkt aus dem Browser.

-- 5. Kalender: Kinder sehen (keine privaten Termine), nur Erwachsene bearbeiten
create policy "events_select" on calendar_events for select to authenticated
  using (not ist_privat or is_adult());
create policy "events_write" on calendar_events for insert to authenticated with check (is_adult());
create policy "events_update" on calendar_events for update to authenticated using (is_adult()) with check (is_adult());
create policy "events_delete" on calendar_events for delete to authenticated using (is_adult());

-- 6. Aufgaben: jede*r sieht alle, aber nur eigene (oder als Erwachsene*r) bearbeiten
create policy "tasks_select" on tasks for select to authenticated using (true);
create policy "tasks_insert" on tasks for insert to authenticated
  with check (is_adult() or member_id = my_member_id());
create policy "tasks_update" on tasks for update to authenticated
  using (is_adult() or member_id = my_member_id()) with check (is_adult() or member_id = my_member_id());
create policy "tasks_delete" on tasks for delete to authenticated
  using (is_adult() or member_id = my_member_id());

-- 7. Erinnerungen: Kinder sehen, nur Erwachsene pflegen
create policy "reminders_select" on reminders for select to authenticated using (true);
create policy "reminders_write" on reminders for insert to authenticated with check (is_adult());
create policy "reminders_update" on reminders for update to authenticated using (is_adult()) with check (is_adult());
create policy "reminders_delete" on reminders for delete to authenticated using (is_adult());

-- 8. Einkauf: alle dürfen mitpflegen
create policy "shopping_all" on shopping_items for all to authenticated using (true) with check (true);

-- 9. Dokumente: nur Erwachsene, komplett
create policy "documents_all" on documents for all to authenticated using (is_adult()) with check (is_adult());

-- 10. Voting: alle sehen/stimmen ab, nur Erwachsene löschen Abstimmungen
create policy "votes_select" on votes for select to authenticated using (true);
create policy "votes_insert" on votes for insert to authenticated with check (true);
create policy "votes_delete" on votes for delete to authenticated using (is_adult());
create policy "vote_options_all" on vote_options for all to authenticated using (true) with check (true);
create policy "vote_responses_all" on vote_responses for all to authenticated using (true) with check (true);

-- 11. Wissen: Kinder lesen, nur Erwachsene schreiben
create policy "wiki_select" on wiki_entries for select to authenticated using (true);
create policy "wiki_write" on wiki_entries for insert to authenticated with check (is_adult());
create policy "wiki_update" on wiki_entries for update to authenticated using (is_adult()) with check (is_adult());
create policy "wiki_delete" on wiki_entries for delete to authenticated using (is_adult());

-- 12. Finanzen & Gesundheit: nur Erwachsene, komplett unsichtbar für Kinder
create policy "finance_all" on finance_entries for all to authenticated using (is_adult()) with check (is_adult());
create policy "health_all" on health_records for all to authenticated using (is_adult()) with check (is_adult());

-- 13. Kontakte: Kinder lesen, nur Erwachsene schreiben
create policy "contacts_select" on contacts for select to authenticated using (true);
create policy "contacts_write" on contacts for insert to authenticated with check (is_adult());
create policy "contacts_update" on contacts for update to authenticated using (is_adult()) with check (is_adult());
create policy "contacts_delete" on contacts for delete to authenticated using (is_adult());

-- 14. Assistent-Vorschläge: alle sehen/bearbeiten (geringes Risiko)
create policy "assistant_all" on assistant_suggestions for all to authenticated using (true) with check (true);

-- 15. Sync-Log: nur Erwachsene dürfen reinschauen, Schreiben passiert eh nur über die Edge Function
create policy "synclog_select" on sync_log for select to authenticated using (is_adult());
