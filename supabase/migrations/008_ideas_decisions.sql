-- Run in the SQL Editor

-- Extend status to 4 states
alter table votes drop constraint if exists votes_status_check;
alter table votes add constraint votes_status_check check (status in ('offen', 'in_arbeit', 'erledigt', 'verworfen'));
alter table votes alter column status set default 'offen';
update votes set status = 'offen' where status not in ('offen', 'in_arbeit', 'erledigt', 'verworfen');

-- For/neutral/against per person and idea (replaces the old multi-select)
create table if not exists idea_stances (
  idea_id uuid not null references votes(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  stance text not null check (stance in ('dafuer', 'neutral', 'dagegen')),
  updated_at timestamptz not null default now(),
  primary key (idea_id, member_id)
);

alter table idea_stances enable row level security;
create policy "idea_stances_all" on idea_stances for all to authenticated using (can_view('voting')) with check (can_view('voting'));

-- the old vote_options/vote_responses are no longer used, but are left
-- untouched (no data loss, in case you still need them)
