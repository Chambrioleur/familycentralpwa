-- ═══════════════════════════════════════════════════════════════
-- TEIL 1: Sicherheitsfixes aus dem Audit
-- ═══════════════════════════════════════════════════════════════

-- Fix 1 (KRITISCH): Rechte-Eskalation verhindern.
-- Bisher durfte jede Person ihre eigene members-Zeile beliebig ändern
-- (für "eigenes Profil bearbeiten"). Ohne diesen Trigger könnte das auch
-- rolle/ist_master/user_id einschließen — d.h. sich selbst zum Master machen.
create or replace function prevent_privilege_escalation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.rolle is distinct from old.rolle
      or new.ist_master is distinct from old.ist_master
      or new.user_id is distinct from old.user_id)
     and not is_master() then
    raise exception 'Nur der Master darf Rolle, Master-Status oder Zugang einer Person ändern.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_privilege_escalation on members;
create trigger trg_prevent_privilege_escalation
  before update on members
  for each row execute function prevent_privilege_escalation();

-- Fix 2 (MITTEL): caldav-sync & check-due-notifications sollen nur mit
-- echtem Familien-Login auslösbar sein, nicht mit dem öffentlichen anon-key
-- allein. Das wird im Code der beiden Edge Functions ergänzt (siehe Chat) —
-- hier nur der Hinweis, dass dafür keine SQL-Änderung nötig ist.

-- Fix 3 (NIEDRIG): Profilbild-Speicherplatz auf die eigene Person begrenzen.
-- Erfordert, dass der Dateiname mit der eigenen member_id beginnt (wird im
-- Frontend beim Hochladen so gesetzt — siehe Chat).
drop policy if exists "avatars_authenticated_insert" on storage.objects;
drop policy if exists "avatars_authenticated_update" on storage.objects;
drop policy if exists "avatars_authenticated_delete" on storage.objects;

create policy "avatars_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
create policy "avatars_own_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
create policy "avatars_own_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
-- Master darf zusätzlich alle verwalten (z.B. beim Anlegen neuer Personen)
create policy "avatars_master_all" on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and is_master()) with check (bucket_id = 'avatars' and is_master());

-- ═══════════════════════════════════════════════════════════════
-- TEIL 2: Rechte auf Einzelpersonen-Basis (nicht mehr nur pro Rolle)
-- ═══════════════════════════════════════════════════════════════

create table if not exists member_permissions (
  member_id uuid not null references members(id) on delete cascade,
  bereich text not null,
  sichtbar boolean not null default true,
  bearbeiten boolean not null default true,
  primary key (member_id, bereich)
);

alter table member_permissions enable row level security;
create policy "member_permissions_select" on member_permissions for select to authenticated using (true);
create policy "member_permissions_write" on member_permissions for all to authenticated using (is_master()) with check (is_master());

-- can_view/can_edit erweitert: erst individuelle Übersteuerung prüfen,
-- sonst wie bisher (Erwachsene immer ja, Kinder nach Rollen-Standard)
create or replace function can_view(p_bereich text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select sichtbar from member_permissions where member_id = my_member_id() and bereich = p_bereich),
    case
      when is_adult() then true
      else coalesce((select sichtbar from role_permissions where rolle = 'kind' and bereich = p_bereich), true)
    end
  );
$$;

create or replace function can_edit(p_bereich text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select bearbeiten from member_permissions where member_id = my_member_id() and bereich = p_bereich),
    case
      when is_adult() then true
      else coalesce((select bearbeiten from role_permissions where rolle = 'kind' and bereich = p_bereich), false)
    end
  );
$$;
