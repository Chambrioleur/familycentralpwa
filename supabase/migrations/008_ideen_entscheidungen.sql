-- Im SQL Editor ausführen

-- Status auf 4 Zustände erweitern
alter table votes drop constraint if exists votes_status_check;
alter table votes add constraint votes_status_check check (status in ('offen', 'in_arbeit', 'erledigt', 'verworfen'));
alter table votes alter column status set default 'offen';
update votes set status = 'offen' where status not in ('offen', 'in_arbeit', 'erledigt', 'verworfen');

-- Dafür/Neutral/Dagegen pro Person und Idee (ersetzt die alte Mehrfachauswahl)
create table if not exists idea_stances (
  idea_id uuid not null references votes(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  stance text not null check (stance in ('dafuer', 'neutral', 'dagegen')),
  updated_at timestamptz not null default now(),
  primary key (idea_id, member_id)
);

alter table idea_stances enable row level security;
create policy "idea_stances_all" on idea_stances for all to authenticated using (can_view('voting')) with check (can_view('voting'));

-- alte vote_options/vote_responses werden nicht mehr genutzt, bleiben aber
-- unangetastet bestehen (kein Datenverlust, falls ihr sie noch braucht)
