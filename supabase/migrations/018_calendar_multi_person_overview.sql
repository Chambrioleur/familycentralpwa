-- Run in the SQL Editor

-- Multiple people per event (the existing member_id stays as the "primary"
-- person for backward compatibility, member_ids is the new, authoritative list)
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

-- Permission area for the family overview (individually assignable like everything else)
insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'familien_ueberblick', true, false)
on conflict (rolle, bereich) do nothing;
