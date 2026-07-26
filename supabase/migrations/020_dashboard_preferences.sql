-- Im SQL Editor ausführen

create table if not exists dashboard_preferences (
  member_id uuid not null references members(id) on delete cascade,
  widget text not null,
  enabled boolean not null default true,
  primary key (member_id, widget)
);

alter table dashboard_preferences enable row level security;
create policy "dashboard_preferences_own" on dashboard_preferences for all to authenticated
  using (member_id = my_member_id()) with check (member_id = my_member_id());
