-- ═══════════════════════════════════════════════════════════════
-- PART 1: Security fixes from the audit
-- ═══════════════════════════════════════════════════════════════

-- Fix 1 (CRITICAL): prevent privilege escalation.
-- Until now, every person could change their own members row freely
-- (for "edit own profile"). Without this trigger that could also include
-- rolle/ist_master/user_id — i.e. making themselves master.
create or replace function prevent_privilege_escalation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.rolle is distinct from old.rolle
      or new.ist_master is distinct from old.ist_master
      or new.user_id is distinct from old.user_id)
     and not is_master() then
    raise exception 'Only the master may change a person''s role, master status, or access.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_privilege_escalation on members;
create trigger trg_prevent_privilege_escalation
  before update on members
  for each row execute function prevent_privilege_escalation();

-- Fix 2 (MEDIUM): caldav-sync & check-due-notifications should only be
-- triggerable with a real family login, not with the public anon key
-- alone. This is added in the code of both Edge Functions — this note
-- is just to point out that no SQL change is needed for it.

-- Fix 3 (LOW): restrict profile picture storage to one's own person.
-- Requires the filename to start with the person's own member_id (set
-- this way by the frontend on upload).
drop policy if exists "avatars_authenticated_insert" on storage.objects;
drop policy if exists "avatars_authenticated_update" on storage.objects;
drop policy if exists "avatars_authenticated_delete" on storage.objects;

create policy "avatars_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
create policy "avatars_own_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
create policy "avatars_own_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = my_member_id()::text);
-- The master may additionally manage all of them (e.g. when creating new people)
create policy "avatars_master_all" on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and is_master()) with check (bucket_id = 'avatars' and is_master());

-- ═══════════════════════════════════════════════════════════════
-- PART 2: permissions on a per-person basis (no longer just per role)
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

-- can_view/can_edit extended: check the individual override first,
-- otherwise as before (adults always yes, children per role default)
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
