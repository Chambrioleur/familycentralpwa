-- Run in the SQL Editor

-- New column: nur_eigene = true means "may only edit their own entries,
-- not other people's" (e.g. a child may tick off their own tasks, but
-- not delete/change their parents' tasks).
alter table role_permissions add column if not exists nur_eigene boolean not null default false;
alter table member_permissions add column if not exists nur_eigene boolean not null default false;

-- Default for children: own entries only for tasks and calendar
update role_permissions set nur_eigene = true where rolle = 'kind' and bereich in ('aufgaben', 'kalender') and bearbeiten = true;

-- Helper function: may the logged-in person also edit OTHERS' entries?
create or replace function can_edit_others(p_bereich text) returns boolean
language sql stable security definer as $$
  select case
    -- Individual override takes precedence
    when exists (
      select 1 from member_permissions
      where member_id = my_member_id() and bereich = p_bereich
    ) then (
      select not coalesce(nur_eigene, false) from member_permissions
      where member_id = my_member_id() and bereich = p_bereich
    )
    -- Adults may do everything by default
    when exists (
      select 1 from members where id = my_member_id() and rolle = 'erwachsen'
    ) then true
    -- Otherwise: role default
    else coalesce(
      (select not nur_eigene from role_permissions
       where rolle = (select rolle from members where id = my_member_id())
       and bereich = p_bereich),
      true
    )
  end;
$$;
