-- Im SQL Editor ausführen

create table if not exists school_subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  farbe text not null default '#3b82f6',
  created_at timestamptz not null default now()
);

create table if not exists timetable_entries (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references members(id) on delete cascade,
  subject_id uuid not null references school_subjects(id) on delete cascade,
  wochentag integer not null check (wochentag between 1 and 5), -- 1=Montag .. 5=Freitag
  stunde integer not null check (stunde between 1 and 10),
  raum text
);

create table if not exists grades (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references members(id) on delete cascade,
  subject_id uuid not null references school_subjects(id) on delete cascade,
  note numeric not null,
  datum date not null default current_date,
  beschreibung text,
  created_at timestamptz not null default now()
);

create table if not exists exams (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references members(id) on delete cascade,
  subject_id uuid not null references school_subjects(id) on delete cascade,
  datum date not null,
  titel text,
  calendar_event_id uuid references calendar_events(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table school_subjects enable row level security;
alter table timetable_entries enable row level security;
alter table grades enable row level security;
alter table exams enable row level security;

create policy "school_subjects_select" on school_subjects for select to authenticated using (can_view('schule'));
create policy "school_subjects_write" on school_subjects for insert to authenticated with check (can_edit('schule'));
create policy "school_subjects_update" on school_subjects for update to authenticated using (can_edit('schule')) with check (can_edit('schule'));
create policy "school_subjects_delete" on school_subjects for delete to authenticated using (can_edit('schule'));

create policy "timetable_select" on timetable_entries for select to authenticated using (can_view('schule'));
create policy "timetable_write" on timetable_entries for insert to authenticated with check (can_edit('schule'));
create policy "timetable_update" on timetable_entries for update to authenticated using (can_edit('schule')) with check (can_edit('schule'));
create policy "timetable_delete" on timetable_entries for delete to authenticated using (can_edit('schule'));

create policy "grades_select" on grades for select to authenticated using (can_view('schule'));
create policy "grades_write" on grades for insert to authenticated with check (can_edit('schule'));
create policy "grades_update" on grades for update to authenticated using (can_edit('schule')) with check (can_edit('schule'));
create policy "grades_delete" on grades for delete to authenticated using (can_edit('schule'));

create policy "exams_select" on exams for select to authenticated using (can_view('schule'));
create policy "exams_write" on exams for insert to authenticated with check (can_edit('schule'));
create policy "exams_update" on exams for update to authenticated using (can_edit('schule')) with check (can_edit('schule'));
create policy "exams_delete" on exams for delete to authenticated using (can_edit('schule'));

insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'schule', true, false)
on conflict (rolle, bereich) do nothing;
