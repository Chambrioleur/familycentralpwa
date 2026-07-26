-- Run in the SQL Editor

-- Fix: missing UPDATE rule for ideas (the status dropdown therefore had
-- no effect — RLS silently blocked the update)
drop policy if exists "votes_update" on votes;
create policy "votes_update" on votes for update to authenticated using (can_edit('voting')) with check (can_edit('voting'));

-- Remember theme preference per person (instead of resetting on every reload)
alter table members add column if not exists theme_praeferenz text check (theme_praeferenz in ('dunkel', 'hell'));

-- New, granularly assignable areas for the settings sub-menus.
-- Visible only to adults by default (as before), but now individually
-- assignable to others via per-person permissions too (e.g. a child
-- helping with calendar sync without being made master outright).
insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'einstellungen_rechte', false, false),
  ('kind', 'einstellungen_personen', false, false),
  ('kind', 'einstellungen_verbindungen', false, false)
on conflict (rolle, bereich) do nothing;
