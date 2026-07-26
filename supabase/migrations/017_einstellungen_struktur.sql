-- Im SQL Editor ausführen

-- Fix: fehlende UPDATE-Regel für Ideen (Status-Dropdown hat deshalb nichts
-- bewirkt — RLS hat das Update stillschweigend blockiert)
drop policy if exists "votes_update" on votes;
create policy "votes_update" on votes for update to authenticated using (can_edit('voting')) with check (can_edit('voting'));

-- Theme-Vorliebe pro Person merken (statt bei jedem Neuladen zurückzufallen)
alter table members add column if not exists theme_praeferenz text check (theme_praeferenz in ('dunkel', 'hell'));

-- Neue, granular vergebbare Bereiche für die Einstellungen-Untermenüs.
-- Standardmäßig nur für Erwachsene sichtbar (wie bisher), aber jetzt über
-- die Einzelpersonen-Rechte gezielt auch an andere vergebbar (z.B. ein
-- Kind, das beim Kalender-Sync helfen soll, ohne gleich Master zu sein).
insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'einstellungen_rechte', false, false),
  ('kind', 'einstellungen_personen', false, false),
  ('kind', 'einstellungen_verbindungen', false, false)
on conflict (rolle, bereich) do nothing;
