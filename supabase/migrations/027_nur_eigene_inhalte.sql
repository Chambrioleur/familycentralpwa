-- Im SQL Editor ausführen

-- Neue Spalte: nur_eigene = true bedeutet "darf nur eigene Einträge bearbeiten,
-- nicht die anderer Personen" (z.B. Kind darf eigene Aufgaben abhaken, aber
-- nicht die Aufgaben der Eltern löschen/ändern).
alter table role_permissions add column if not exists nur_eigene boolean not null default false;
alter table member_permissions add column if not exists nur_eigene boolean not null default false;

-- Standard für Kinder: nur eigene Inhalte bei Aufgaben und Kalender
update role_permissions set nur_eigene = true where rolle = 'kind' and bereich in ('aufgaben', 'kalender') and bearbeiten = true;

-- Hilfsfunktion: darf die angemeldete Person auch FREMDE Inhalte bearbeiten?
create or replace function can_edit_others(p_bereich text) returns boolean
language sql stable security definer as $$
  select case
    -- Einzelpersonen-Übersteuerung hat Vorrang
    when exists (
      select 1 from member_permissions
      where member_id = my_member_id() and bereich = p_bereich
    ) then (
      select not coalesce(nur_eigene, false) from member_permissions
      where member_id = my_member_id() and bereich = p_bereich
    )
    -- Erwachsene dürfen standardmäßig alles
    when exists (
      select 1 from members where id = my_member_id() and rolle = 'erwachsen'
    ) then true
    -- Sonst: Rollen-Vorgabe
    else coalesce(
      (select not nur_eigene from role_permissions
       where rolle = (select rolle from members where id = my_member_id())
       and bereich = p_bereich),
      true
    )
  end;
$$;
