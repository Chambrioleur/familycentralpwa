-- Im SQL Editor ausführen

-- Mehrere Personen pro Termin (bisherige member_id bleibt als "Haupt"-Person
-- für Abwärtskompatibilität erhalten, member_ids ist die neue, maßgebliche Liste)
alter table calendar_events add column if not exists member_ids uuid[] not null default '{}';
update calendar_events set member_ids = array[member_id] where member_id is not null and member_ids = '{}';

drop policy if exists "events_insert" on calendar_events;
drop policy if exists "events_update" on calendar_events;
drop policy if exists "events_delete" on calendar_events;

create policy "events_insert" on calendar_events for insert to authenticated
  with check (can_edit('kalender') or member_id = my_member_id() or my_member_id() = any(member_ids));
create policy "events_update" on calendar_events for update to authenticated
  using (can_edit('kalender') or member_id = my_member_id() or my_member_id() = any(member_ids))
  with check (can_edit('kalender') or member_id = my_member_id() or my_member_id() = any(member_ids));
create policy "events_delete" on calendar_events for delete to authenticated
  using (can_edit('kalender') or member_id = my_member_id() or my_member_id() = any(member_ids));

-- Rechte-Bereich für den Familien-Überblick (einzeln vergebbar wie alles andere)
insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'familien_ueberblick', true, false)
on conflict (rolle, bereich) do nothing;
