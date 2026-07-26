-- Im SQL Editor ausführen

create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references members(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

alter table push_subscriptions enable row level security;
create policy "push_subscriptions_own" on push_subscriptions for all to authenticated
  using (member_id = my_member_id()) with check (member_id = my_member_id());

-- Verhindert, dass dieselbe fällige Aufgabe/Erinnerung mehrfach am selben Tag benachrichtigt
alter table tasks add column if not exists benachrichtigt_am date;
alter table reminders add column if not exists benachrichtigt_am date;
