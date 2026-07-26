-- Run in the SQL Editor

create table if not exists notification_preferences (
  member_id uuid not null references members(id) on delete cascade,
  bereich text not null,
  enabled boolean not null default true,
  primary key (member_id, bereich)
);

alter table notification_preferences enable row level security;
create policy "notification_preferences_own" on notification_preferences for all to authenticated
  using (member_id = my_member_id()) with check (member_id = my_member_id());
