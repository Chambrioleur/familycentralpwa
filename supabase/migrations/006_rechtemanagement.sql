-- ═══════════════════════════════════════════════════════════════
-- Konfigurierbares Rechtemanagement für Kinder-Rolle.
-- Erwachsene behalten immer vollen Zugriff (kein Sperr-Risiko für
-- sich selbst). Der Master stellt über die Einstellungen ein, was
-- Kinder pro Bereich sehen ("sichtbar") und bearbeiten ("bearbeiten")
-- dürfen. Bei Kalender/Aufgaben gilt zusätzlich: eigene Einträge
-- dürfen Kinder immer bearbeiten, unabhängig vom "bearbeiten"-Schalter
-- (der regelt dort nur, ob sie auch FREMDE Einträge bearbeiten dürfen).
-- ═══════════════════════════════════════════════════════════════

create table if not exists role_permissions (
  rolle text not null check (rolle in ('kind')),
  bereich text not null,
  sichtbar boolean not null default true,
  bearbeiten boolean not null default true,
  primary key (rolle, bereich)
);

alter table role_permissions enable row level security;
create policy "role_permissions_select" on role_permissions for select to authenticated using (true);
create policy "role_permissions_write" on role_permissions for all to authenticated using (is_master()) with check (is_master());

insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'kalender', true, false),
  ('kind', 'aufgaben', true, false),
  ('kind', 'einkauf', true, true),
  ('kind', 'erinnerungen', true, false),
  ('kind', 'dokumente', false, false),
  ('kind', 'wissen', true, false),
  ('kind', 'finanzen', false, false),
  ('kind', 'gesundheit', false, false),
  ('kind', 'kontakte', true, false),
  ('kind', 'voting', true, true)
on conflict (rolle, bereich) do nothing;

-- Hilfsfunktionen: Erwachsene dürfen immer alles; für Kinder wird in
-- role_permissions nachgeschaut (Standard: sichtbar=true, bearbeiten=false,
-- falls kein Eintrag existiert)
create or replace function can_view(p_bereich text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when is_adult() then true
    else coalesce((select sichtbar from role_permissions where rolle = 'kind' and bereich = p_bereich), true)
  end;
$$;

create or replace function can_edit(p_bereich text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when is_adult() then true
    else coalesce((select bearbeiten from role_permissions where rolle = 'kind' and bereich = p_bereich), false)
  end;
$$;

-- ── Kalender: Kinder sehen (falls sichtbar), legen eigene Termine an,
--    bearbeiten/löschen eigene immer, fremde nur falls "bearbeiten" an ist
drop policy if exists "events_select" on calendar_events;
drop policy if exists "events_write" on calendar_events;
drop policy if exists "events_update" on calendar_events;
drop policy if exists "events_delete" on calendar_events;

create policy "events_select" on calendar_events for select to authenticated
  using (can_view('kalender') and (not ist_privat or is_adult()));
create policy "events_insert" on calendar_events for insert to authenticated
  with check (can_edit('kalender') or member_id = my_member_id());
create policy "events_update" on calendar_events for update to authenticated
  using (can_edit('kalender') or member_id = my_member_id())
  with check (can_edit('kalender') or member_id = my_member_id());
create policy "events_delete" on calendar_events for delete to authenticated
  using (can_edit('kalender') or member_id = my_member_id());

-- ── Aufgaben: analog Kalender
drop policy if exists "tasks_select" on tasks;
drop policy if exists "tasks_insert" on tasks;
drop policy if exists "tasks_update" on tasks;
drop policy if exists "tasks_delete" on tasks;

create policy "tasks_select" on tasks for select to authenticated using (can_view('aufgaben'));
create policy "tasks_insert" on tasks for insert to authenticated
  with check (can_edit('aufgaben') or member_id = my_member_id());
create policy "tasks_update" on tasks for update to authenticated
  using (can_edit('aufgaben') or member_id = my_member_id())
  with check (can_edit('aufgaben') or member_id = my_member_id());
create policy "tasks_delete" on tasks for delete to authenticated
  using (can_edit('aufgaben') or member_id = my_member_id());

-- ── Erinnerungen
drop policy if exists "reminders_select" on reminders;
drop policy if exists "reminders_write" on reminders;
drop policy if exists "reminders_update" on reminders;
drop policy if exists "reminders_delete" on reminders;

create policy "reminders_select" on reminders for select to authenticated using (can_view('erinnerungen'));
create policy "reminders_write" on reminders for insert to authenticated with check (can_edit('erinnerungen'));
create policy "reminders_update" on reminders for update to authenticated using (can_edit('erinnerungen')) with check (can_edit('erinnerungen'));
create policy "reminders_delete" on reminders for delete to authenticated using (can_edit('erinnerungen'));

-- ── Einkauf (Listen + Items)
drop policy if exists "shopping_all" on shopping_items;
create policy "shopping_select" on shopping_items for select to authenticated using (can_view('einkauf'));
create policy "shopping_write" on shopping_items for insert to authenticated with check (can_edit('einkauf'));
create policy "shopping_update" on shopping_items for update to authenticated using (can_edit('einkauf')) with check (can_edit('einkauf'));
create policy "shopping_delete" on shopping_items for delete to authenticated using (can_edit('einkauf'));

drop policy if exists "shopping_lists_all" on shopping_lists;
create policy "shopping_lists_select" on shopping_lists for select to authenticated using (can_view('einkauf'));
create policy "shopping_lists_write" on shopping_lists for insert to authenticated with check (can_edit('einkauf'));
create policy "shopping_lists_update" on shopping_lists for update to authenticated using (can_edit('einkauf')) with check (can_edit('einkauf'));
create policy "shopping_lists_delete" on shopping_lists for delete to authenticated using (can_edit('einkauf'));

-- ── Dokumente
drop policy if exists "documents_all" on documents;
create policy "documents_select" on documents for select to authenticated using (can_view('dokumente'));
create policy "documents_write" on documents for insert to authenticated with check (can_edit('dokumente'));
create policy "documents_update" on documents for update to authenticated using (can_edit('dokumente')) with check (can_edit('dokumente'));
create policy "documents_delete" on documents for delete to authenticated using (can_edit('dokumente'));

-- ── Wissen
drop policy if exists "wiki_select" on wiki_entries;
drop policy if exists "wiki_write" on wiki_entries;
drop policy if exists "wiki_update" on wiki_entries;
drop policy if exists "wiki_delete" on wiki_entries;
create policy "wiki_select" on wiki_entries for select to authenticated using (can_view('wissen'));
create policy "wiki_write" on wiki_entries for insert to authenticated with check (can_edit('wissen'));
create policy "wiki_update" on wiki_entries for update to authenticated using (can_edit('wissen')) with check (can_edit('wissen'));
create policy "wiki_delete" on wiki_entries for delete to authenticated using (can_edit('wissen'));

-- ── Finanzen & Gesundheit (Standard: für Kinder unsichtbar)
drop policy if exists "finance_all" on finance_entries;
create policy "finance_select" on finance_entries for select to authenticated using (can_view('finanzen'));
create policy "finance_write" on finance_entries for insert to authenticated with check (can_edit('finanzen'));
create policy "finance_update" on finance_entries for update to authenticated using (can_edit('finanzen')) with check (can_edit('finanzen'));
create policy "finance_delete" on finance_entries for delete to authenticated using (can_edit('finanzen'));

drop policy if exists "health_all" on health_records;
create policy "health_select" on health_records for select to authenticated using (can_view('gesundheit'));
create policy "health_write" on health_records for insert to authenticated with check (can_edit('gesundheit'));
create policy "health_update" on health_records for update to authenticated using (can_edit('gesundheit')) with check (can_edit('gesundheit'));
create policy "health_delete" on health_records for delete to authenticated using (can_edit('gesundheit'));

-- ── Kontakte
drop policy if exists "contacts_select" on contacts;
drop policy if exists "contacts_write" on contacts;
drop policy if exists "contacts_update" on contacts;
drop policy if exists "contacts_delete" on contacts;
create policy "contacts_select" on contacts for select to authenticated using (can_view('kontakte'));
create policy "contacts_write" on contacts for insert to authenticated with check (can_edit('kontakte'));
create policy "contacts_update" on contacts for update to authenticated using (can_edit('kontakte')) with check (can_edit('kontakte'));
create policy "contacts_delete" on contacts for delete to authenticated using (can_edit('kontakte'));

-- ── Voting
drop policy if exists "votes_select" on votes;
drop policy if exists "votes_insert" on votes;
drop policy if exists "votes_delete" on votes;
create policy "votes_select" on votes for select to authenticated using (can_view('voting'));
create policy "votes_insert" on votes for insert to authenticated with check (can_view('voting'));
create policy "votes_delete" on votes for delete to authenticated using (can_edit('voting'));
-- vote_options/vote_responses bleiben wie bisher (alle dürfen mitstimmen, sofern Voting sichtbar ist)
